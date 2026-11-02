# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'gtk4'

require_relative 'settings'

# Util holds the process-wide singletons and the small helpers upstream keeps
# in src/util.js: the settings instance, the HTTP session every request goes
# through, the desktop-integration helpers behind the preferences switches and
# the relative date formatter used by the notification rows.
#
# Three things differ from upstream and are deliberate:
#
# * The session is Ruby's Net::HTTP rather than libsoup. There is no Soup
#   binding in ruby-gnome, and the forges only need "send this request, give
#   me the status and the body", which Net::HTTP does with the same semantics.
# * Requests run on a worker thread handed back to the main loop by #defer,
#   which is this port's stand-in for upstream's async/await: GTK is only ever
#   touched from the main loop.
# * Upstream asks the XDG background portal (libportal) for permission to keep
#   running and to autostart. There is no portal binding either, and a portal
#   is only present inside a sandbox, so "keep running in the background" is
#   the window's own hide-on-close, and "run on startup" writes the XDG
#   autostart desktop file that the portal would have written on our behalf.
#
module Util
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

  # True when the app is running from a Flatpak sandbox, where the autostart
  # file below has no effect and the portal upstream uses would be the only
  # way to ask for the same thing.
  def sandboxed? = File.exist?('/.flatpak-info')

  def autostart_file
    File.join(
      ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')),
      'autostart',
      "#{APP_ID}.desktop",
    )
  end

  def autostart? = File.exist?(autostart_file)

  # Writes or removes the autostart desktop entry, and reports whether the
  # state asked for is the state on disk afterwards — the same boolean
  # upstream gets back from the portal request.
  def request_autostart(enabled, hidden: false)
    if enabled
      write_autostart_file(hidden: hidden)
    else
      remove_autostart_file
    end
    autostart? == enabled
  rescue SystemCallError => e
    warn "Could not update #{autostart_file}: #{e.message}"
    false
  end

  def write_autostart_file(hidden: false)
    command = [AUTOSTART_COMMAND]
    if hidden
      command << HIDDEN_FLAG
    end

    FileUtils.mkdir_p(File.dirname(autostart_file))
    File.write(autostart_file, <<~DESKTOP)
      [Desktop Entry]
      Type=Application
      Name=#{APP_NAME}
      Comment=Get Git forges notifications
      Exec=#{command.join(' ')}
      Icon=#{APP_ID}
      Terminal=false
      X-GNOME-Autostart-enabled=true
    DESKTOP
  end

  def remove_autostart_file
    if File.exist?(autostart_file)
      File.delete(autostart_file)
    end
  end

  # Get relative date string from a Time.
  #
  # The thresholds, the rounding and the two fallback date formats are
  # upstream's relativeDate().
  def relative_date(date, now: Time.now)
    difference = now.to_f - date.to_f

    if difference <= 0
      warn 'Date is in the future!'
      'now'
    else
      minutes = (difference / 60.0).round

      if minutes < 1
        'now'
      elsif minutes < 60
        plural(minutes, '%d minute ago', '%d minutes ago')
      elsif minutes < 1440
        (minutes / 60.0).round.then { |hours| plural(hours, '%d hour ago', '%d hours ago') }
      elsif minutes < 10_080
        (minutes / 1440.0).round.then { |days| plural(days, 'yesterday', '%d days ago') }
      elsif minutes < 40_320
        (minutes / 10_080.0).round.then { |weeks| plural(weeks, '%d week ago', '%d weeks ago') }
      elsif now.year == date.year
        format('on %s', date.strftime('%b %d'))
      else
        format('on %s', date.strftime('%d %b, %Y'))
      end
    end
  end

  # Upstream reaches for ngettext here; without a catalogue the port picks the
  # same two forms by the same rule.
  def plural(count, singular, plural_form)
    format(count == 1 ? singular : plural_form, count)
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
