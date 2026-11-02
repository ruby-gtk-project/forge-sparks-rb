# frozen_string_literal: true

require 'adwaita'

require_relative 'util'
require_relative 'translation'
require_relative 'style'
require_relative 'window'
require_relative 'accounts_manager'
require_relative 'accounts_dialog'
require_relative 'preferences_dialog'

# Application is the app itself.
#
# Ported from upstream's src/application.js: the nine application actions, the
# accelerators for them, the --version and --hidden command line options, the
# About dialog, and the single-instance preferences and accounts dialogs.
#
# Adwaita::Application is broken in the Ruby bindings, so the application
# object is a Gtk::Application; Adwaita is initialised explicitly instead, and
# the window is an Adwaita::ApplicationWindow, which works.
#
class Application
  include Translation

  APP_ID = Util::APP_ID

  # Upstream's _initAppActions, as data. Each action is either parameterless
  # or carries the GVariant type of the parameter it takes.
  ACTIONS = {
    'activate'          => nil,
    'about'             => nil,
    'preferences'       => nil,
    'accounts'          => nil,
    'quit'              => nil,
    'close'             => nil,
    'open-notification' => 'as',
    'mark-read'         => 's',
    'reload'            => nil,
  }.freeze

  # Upstream's set_accels_for_action calls, including the two window actions.
  ACCELS = {
    'app.quit'              => ['<Primary>q'],
    'app.close'             => ['<Primary>w'],
    'app.preferences'       => ['<Primary>comma'],
    'app.accounts'          => ['<Primary><Shift>a'],
    'app.reload'            => ['<Primary>r'],
    'win.open-primary-menu' => ['F10'],
    'win.show-help-overlay' => ['<Primary>question'],
  }.freeze

  # @param hidden [Boolean] whether the window should start out of sight
  # @param present [Boolean] whether the window is shown at all, which a
  #   driver script turns off to inspect the widgets without a display
  def initialize(hidden: false, present: true, settings: Util.settings)
    @hidden = hidden
    @present = present
    @settings = settings
  end

  attr_reader :window

  def build
    app.tap do
      app.signal_connect('startup') { on_startup }
      app.signal_connect('activate') { on_activate }
      app.signal_connect('handle-local-options') { |_app, options| on_handle_local_options(options) }

      setup_main_options
      setup_actions
    end
  end

  def run(argv = []) = app.run(argv)

  # Adwaita::Application is broken in the bindings, so the application object
  # is a Gtk::Application and Adwaita is initialised by hand.
  def app
    @app ||= begin
      Adwaita.init
      Gtk::Application.new(APP_ID, :default_flags)
    end
  end

  def style = @style ||= Style.new
  def accounts = @accounts ||= AccountsManager.instance

  def about_dialog
    @about_dialog ||= Adwaita::AboutDialog.new.tap do |about|
      about.application_name = Util::APP_NAME
      about.application_icon = APP_ID
      about.developer_name = 'Rafael Mardojai CM'
      about.developers = ['Rafael Mardojai CM']
      about.version = Util::VERSION
      about.comments = _('Get Git forges notifications')
      # Translators: Replace "translator-credits" with your names, one name per line
      about.translator_credits = _('translator-credits')
      about.copyright = 'Copyright 2022 Rafael Mardojai CM'
      about.license_type = Gtk::License::MIT_X11
      about.website = 'https://github.com/ruby-gtk-project/forge-sparks-rb'
      about.issue_url = 'https://github.com/ruby-gtk-project/forge-sparks-rb/issues'
    end
  end

  private

    # Upstream's add_main_option calls. GLib owns -h for --help, so --hidden
    # keeps its long form only; upstream's short -h never reaches the app.
    def setup_main_options
      app.add_main_option(
        'version',
        'v'.ord,
        :none,
        :none,
        _('Print version information and exit'),
        nil,
      )

      app.add_main_option(
        'hidden',
        0,
        :none,
        :none,
        _('Start hidden'),
        nil,
      )
    end

    def setup_actions
      ACTIONS.each { |name, parameter_type| add_action(name, parameter_type) }
      ACCELS.each { |action, accels| app.set_accels_for_action(action, accels) }
    end

    def add_action(name, parameter_type)
      Gio::SimpleAction.new(name, parameter_type && GLib::VariantType.new(parameter_type)).tap do |action|
        action.signal_connect('activate') do |_action, parameter|
          send(:"action_#{name.tr('-', '_')}", parameter)
        end
        app.add_action(action)
      end
    end

    # --- Lifecycle ------------------------------------------------------

    def on_startup
      warn "Forge Sparks: #{APP_ID}"
      warn "Version: #{Util::VERSION}"
      style.install
    end

    def on_activate
      unless @window
        @window = Window.new(app, accounts: accounts, settings: @settings).tap do |win|
          win.hide_on_close = @settings['hide-on-close']
          win.build
        end
      end

      show_window
    end

    # Starting hidden means the window is built and fetching, but never
    # presented — upstream sets visible = false and reports the background
    # status it has no counterpart for here.
    def show_window
      if @hidden
        @window.visible = false
        @hidden = false
      else
        if @present
          @window.present
        end
      end
    end

    # Returns -1 to continue execution, which is what upstream's
    # vfunc_handle_local_options does, and 0 after printing the version.
    def on_handle_local_options(options)
      if options.contains?('version')
        puts Util::VERSION
        0
      else
        if options.contains?('hidden') && @window.nil?
          @hidden = true
        end
        -1
      end
    end

    # --- Actions --------------------------------------------------------

    def action_activate(_parameter) = app.activate

    def action_quit(_parameter) = app.quit

    def action_close(_parameter)
      app.active_window.then do |active|
        if active
          active.close
        end
      end
    end

    def action_reload(_parameter)
      @window.then do |win|
        if win
          win.reload
        end
      end
    end

    def action_about(_parameter) = about_dialog.present(@window)

    # The dialogs are single-instance: upstream keeps the one it opened until
    # it closes, so a second activation does not stack two of them.
    def action_preferences(_parameter)
      unless @preferences_dialog
        @preferences_dialog = PreferencesDialog.new(
          settings:                 @settings,
          on_hide_on_close_changed: method(:on_hide_on_close_changed),
        ).tap do |dialog|
          dialog.build
          dialog.signal_connect('closed') { @preferences_dialog = nil }
          dialog.present(@window)
        end
      end
    end

    def action_accounts(_parameter)
      unless @accounts_dialog
        @accounts_dialog = AccountsDialog.new(
          accounts:   accounts,
          on_changed: method(:on_accounts_changed),
        ).tap do |dialog|
          dialog.build
          dialog.signal_connect('closed') { @accounts_dialog = nil }
          dialog.present(@window)
        end
      end
    end

    # ruby-gnome hands an action parameter over already unwrapped, so a GVariant
    # of type "as" arrives as a Ruby Array and one of type "s" as a String;
    # both are read through these two helpers so neither assumption is spread
    # through the actions.
    def string_array(parameter)
      if parameter.respond_to?(:get_strv)
        parameter.get_strv
      else
        Array(parameter)
      end
    end

    def string_value(parameter)
      if parameter.respond_to?(:value)
        parameter.value.to_s
      else
        parameter.to_s
      end
    end

    # The notification's default action: open the link, and mark it as read
    # once the browser actually took it.
    def action_open_notification(parameter)
      string_array(parameter).then do |(id, url)|
        Gtk::UriLauncher.new(url.to_s).tap do |launcher|
          launcher.launch(launch_parent, nil) do |_source, result|
            finish_launch(launcher, result, id)
          end
        end
      end
    end

    def finish_launch(launcher, result, id)
      if launcher.launch_finish(result)
        @window.resolve_notification(id)
      end
    # A handler-less URI comes back as Gtk::DialogError::Failed, which carries
    # GLib::ErrorInfo but does not descend from GLib::Error, and an exception
    # that escapes a Gio async callback takes the process down with it — so
    # this catches the whole StandardError family and not just GLib::Error.
    rescue StandardError, GLib::Error => e
      warn "Could not open the notification: #{e.message}"
    end

    # A window that hides on close is not a window the launcher should block,
    # which is upstream passing null in that case.
    def launch_parent
      if @settings['hide-on-close']
        nil
      else
        @window
      end
    end

    def action_mark_read(parameter) = @window.resolve_notification(string_value(parameter))

    # --- Callbacks ------------------------------------------------------

    def on_hide_on_close_changed(value)
      @window.then do |win|
        if win
          win.hide_on_close = value
        end
      end
    end

    def on_accounts_changed
      @window.then do |win|
        if win
          win.reload
        end
      end
    end
end
