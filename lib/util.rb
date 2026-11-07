# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'timeout'
require 'dbus'
require 'gtk4'

require_relative 'settings'
require_relative 'translation'

# Util holds the process-wide singletons and the small helpers upstream keeps
# in src/util.js: the settings instance, the HTTP session every request goes
# through, the desktop-integration helpers behind the preferences switches and
# the relative date formatter used by the notification rows.
#
# Two things differ from upstream and are deliberate:
#
# * The session is Ruby's Net::HTTP rather than libsoup. There is no Soup
#   binding in ruby-gnome, and the forges only need "send this request, give
#   me the status and the body", which Net::HTTP does with the same semantics.
# * Requests run on a worker thread handed back to the main loop by #defer,
#   which is this port's stand-in for upstream's async/await: GTK is only ever
#   touched from the main loop.
#
# Upstream asks the XDG background portal (libportal's Xdp.Portal) for
# permission to keep running and to autostart, and to set a status message
# while it does. `ashpd` 0.1.1, the binding gem this fork's policy named,
# does not cover the Background portal (only Account, Camera, OpenUri,
# Screenshot, Settings and Trash — checked live: `Ashpd.constants` has no
# `Background`), so this talks to org.freedesktop.portal.Background
# directly over D-Bus through `ruby-dbus`, which is pure Ruby and needs no
# typelib. #request_background and #set_background_status below are
# RequestBackground and SetStatus on that interface — the same two calls
# Xdp.Portal#request_background and #set_background_status make underneath.
#
module Util
  extend Translation

  APP_ID = 'org.rubygtkproject.ForgeSparks'
  APP_NAME = 'Forge Sparks'
  VERSION = '0.1.0'

  # The command the autostart entry runs, and the flag upstream appends when
  # the window should come up hidden.
  AUTOSTART_COMMAND = 'forge-sparks'
  HIDDEN_FLAG = '--hidden'

  module_function

  # App Settings instance.
  def settings = @settings ||= Settings.new

  # HTTP session instance for all app requests.
  def session = @session ||= HttpSession.new("#{APP_NAME} v#{VERSION}")

  # Where the ported assets (status icons, the all-done illustration) live.
  def data_dir = @data_dir ||= File.expand_path('../data', __dir__)

  # Runs `work` on a worker thread and calls `finish` with its value back on
  # the main loop. An exception inside `work` is handed to `finish` as the
  # value, so callers decide what a failure looks like instead of losing it.
  #
  # This is the port's equivalent of upstream awaiting a Gio promise: the HTTP
  # request must not block the main loop, and nothing but the main loop may
  # touch a widget.
  def defer(work, finish)
    Thread.new do
      begin
        result = work.call
      rescue StandardError, GLib::Error => e
        result = e
      end

      GLib::Idle.add do
        finish.call(result)
        false
      end
    end
  end

  PORTAL_BUS_NAME = 'org.freedesktop.portal.Desktop'
  PORTAL_OBJECT_PATH = '/org/freedesktop/portal/desktop'
  PORTAL_BACKGROUND_INTERFACE = 'org.freedesktop.portal.Background'
  PORTAL_REQUEST_INTERFACE = 'org.freedesktop.portal.Request'

  # How long to wait for the user to answer the portal's permission dialog
  # before giving up, same shape as upstream waiting on the portal's async
  # result forever but bounded, since nothing here is cancellable.
  PORTAL_REQUEST_TIMEOUT = 120

  # True when the app is running from a Flatpak sandbox. Upstream only
  # bothers setting the background status message (below) in this case,
  # since that is the one thing a sandboxed, hidden app can still surface to
  # the user.
  def sandboxed? = File.exist?('/.flatpak-info')

  # Requests background and, optionally, autostart permission from the real
  # XDG background portal.
  #
  # Ported from upstream's requestBackground(window, autostart, hidden):
  # the reason shown to the user depends on which permission is being asked
  # for (exactly as upstream picks it — autostart gets the "on background"
  # reason, plain background gets "on startup"), and the command line only
  # gets --hidden when both autostart and hidden are requested. Success is
  # the portal's Request.Response signal reporting its "success" code, the
  # same thing libportal's request_background_finish checks.
  #
  # @return [Boolean] whether the request was granted
  def request_background(autostart: false, hidden: false)
    reason = autostart ? _('Allow running Forge Sparks on background.') : _('Allow running Forge Sparks on startup.')
    command = [AUTOSTART_COMMAND]
    if autostart && hidden
      command << HIDDEN_FLAG
    end

    response_code, = portal_request(
      'RequestBackground',
      'reason'      => reason,
      'autostart'   => autostart,
      'commandline' => command,
    )
    response_code.zero?
  rescue DBus::Error, SystemCallError, Timeout::Error => e
    warn "Background portal request failed: #{e.message}"
    false
  end

  # Sets the status message the background portal shows for this app while
  # it runs hidden, e.g. in a shell's background-apps indicator.
  #
  # Ported from upstream's setBackgroundStatus(message): upstream only calls
  # it under Xdp.Portal.running_under_sandbox(), so this does the same.
  # Unlike #request_background this is a plain method call with no Request
  # object or user dialog behind it, so it is fire-and-forget.
  def set_background_status(message = _('Monitoring new notifications'))
    if sandboxed?
      portal_mutex.synchronize { portal_background_interface.SetStatus('message' => message) }
    end
  rescue DBus::Error, SystemCallError => e
    warn "Could not set the background status: #{e.message}"
  end

  def portal_background_interface
    @portal_background_interface ||= DBus::SessionBus.instance
      .service(PORTAL_BUS_NAME)
      .object(PORTAL_OBJECT_PATH)
      .tap(&:introspect)[PORTAL_BACKGROUND_INTERFACE]
  end

  def portal_mutex = @portal_mutex ||= Mutex.new

  # Calls `method_name` (RequestBackground) on the background portal and
  # blocks until its Request object emits the Response signal, which is how
  # every "request" method on an XDG portal reports its result: the method
  # call itself only returns a handle to watch.
  #
  # @return [Array(Integer, Hash)] the response code and results dict
  def portal_request(method_name, options)
    bus = DBus::SessionBus.instance
    response = nil

    portal_mutex.synchronize do
      handle_path = portal_background_interface.send(method_name, '', options)
      request = bus.service(PORTAL_BUS_NAME).object(handle_path).tap(&:introspect)
      request[PORTAL_REQUEST_INTERFACE].on_signal('Response') do |code, results|
        response = [code, results]
      end

      Timeout.timeout(PORTAL_REQUEST_TIMEOUT) do
        bus.wait_for_message until response
      end
    end

    response
  end

  # Get relative date string from a Time.
  #
  # The thresholds, the rounding and the two fallback date formats are
  # upstream's relativeDate().
  def relative_date(date, now: Time.now)
    difference = now.to_f - date.to_f

    if difference <= 0
      warn 'Date is in the future!'
      _('now')
    else
      minutes = (difference / 60.0).round

      if minutes < 1
        _('now')
      elsif minutes < 60
        # Translators: relative date
        format(n_('%d minute ago', '%d minutes ago', minutes), minutes)
      elsif minutes < 1440
        (minutes / 60.0).round.then do |hours|
          # Translators: relative date
          format(n_('%d hour ago', '%d hours ago', hours), hours)
        end
      elsif minutes < 10_080
        (minutes / 1440.0).round.then do |days|
          # Translators: relative date
          format(n_('yesterday', '%d days ago', days), days)
        end
      elsif minutes < 40_320
        (minutes / 10_080.0).round.then do |weeks|
          # Translators: relative date
          format(n_('%d week ago', '%d weeks ago', weeks), weeks)
        end
      elsif now.year == date.year
        # Translators: relative date, %s is date formatted as "May 01"
        format(_('on %s'), date.strftime('%b %d'))
      else
        # Translators: relative date, %s is date formatted as "01 May, 2022"
        format(_('on %s'), date.strftime('%d %b, %Y'))
      end
    end
  end

  # HttpSession is the single session every forge request goes through.
  #
  # Upstream's Soup.Session carries the user agent for the whole app and is
  # shared by all the backends; this does the same, and adds the JSON body
  # encoding and the response reading that upstream spreads across
  # Forge.createMessage and Forge.readContents.
  class HttpSession
    METHODS = {
      'GET'    => Net::HTTP::Get,
      'POST'   => Net::HTTP::Post,
      'PATCH'  => Net::HTTP::Patch,
      'PUT'    => Net::HTTP::Put,
      'DELETE' => Net::HTTP::Delete,
    }.freeze

    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30

    def initialize(user_agent)
      @user_agent = user_agent
    end

    attr_reader :user_agent

    # Sends a request and reads the whole response.
    #
    # @return [Array(Integer, String)] the HTTP status and the response body
    def send_and_read(method, url, data: nil, headers: {})
      URI.parse(url).then do |uri|
        request = build_request(
          method,
          uri,
          data,
          headers,
        )
        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl:      uri.scheme == 'https',
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT,
        ) { |http| http.request(request) }

        [response.code.to_i, response.body.to_s]
      end
    end

    # Parses a response body the way upstream's Forge.readContents does: an
    # empty body is an empty list rather than an error.
    def read_contents(body)
      body.to_s.empty? ? [] : JSON.parse(body)
    end

    private

      def build_request(method, uri, data, headers)
        METHODS.fetch(method.to_s.upcase).new(uri).tap do |request|
          request['User-Agent'] = @user_agent
          headers.each { |key, value| request[key.to_s] = value.to_s }

          if data
            request['Content-Type'] = 'application/json'
            request.body = JSON.generate(data)
          end
        end
      end
  end
end
