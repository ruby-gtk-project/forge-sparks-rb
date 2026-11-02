# frozen_string_literal: true

require 'adwaita'

require_relative 'util'
require_relative 'forges'
require_relative 'accounts_manager'
require_relative 'notifications_list'
require_relative 'notification_row'
require_relative 'account_dialog'
require_relative 'shortcuts_dialog'

# Window is the main application window.
#
# Ported from upstream's src/window.js and src/window.blp: a stack with the
# welcome page for when no account is configured, a spinner while the first
# fetch is in flight, and the notifications page with its "Mark all as Read"
# button, the banner that appears when an account's token stops working, and
# the list itself — or the all-done illustration when there is nothing to show.
#
# The fetch loop is upstream's subscribe(): every account is asked for its
# notifications, the results replace the model, anything new is also sent to
# the desktop, and the whole thing runs again after #interval seconds. The
# requests happen on a worker thread through Util.defer instead of upstream's
# await, so the window stays responsive while they are in flight and nothing
# but the main loop touches a widget.
#
class Window < Adwaita::ApplicationWindow
  DEFAULT_WIDTH = 500
  DEFAULT_HEIGHT = 500
  MIN_WIDTH = 360
  MIN_HEIGHT = 200

  # Interval of the notifications requests, in seconds.
  INTERVAL = 60

  EMPTY_ILLUSTRATION_WIDTH = 400
  SPINNER_SIZE = 64
  MARK_SPINNER_SIZE = 16

  AUTH_ERROR_NOTIFICATION = 'forge-sparks-error-auth'

  # @param app [Gtk::Application] the application the window belongs to
  # @param accounts [AccountsManager] the accounts model
  # @param settings [Settings] the app settings
  def initialize(app, accounts: AccountsManager.instance, settings: Util.settings)
    super(app)
    @accounts = accounts
    @settings = settings
    @forges = {}
    @interval = INTERVAL
    @fetching = false
    @re_fetch = false
    @auth_failed = nil
    @auth_error_notified = false
    @fetch_error = false
    @network_error = false
    @listed = []
    @rows = []
    @notified = @settings['notified'].dup

    self.title = 'Forge Sparks'
    self.width_request = MIN_WIDTH
    self.height_request = MIN_HEIGHT
    set_default_size(DEFAULT_WIDTH, DEFAULT_HEIGHT)
  end

  attr_reader :model

  def build
    tap do |window|
      @model = NotificationsList.new
      window.content = main_stack

      main_stack.tap do |stack|
        stack.add_named(setup_view, 'setup')
        stack.add_named(loading_view, 'loading')
        stack.add_named(notifications_view, 'notifications')
        stack.visible_child_name = 'loading'

        setup_view.tap do |view|
          view.add_top_bar(setup_header)
          view.content = setup_page

          setup_header.pack_end(setup_menu_button)

          setup_page.tap do |page|
            page.child = add_account_button

            add_account_button.signal_connect('clicked') { open_new_account }
          end
        end

        loading_view.tap do |handle|
          handle.child = loading_box

          loading_box.append(loading_spinner)
        end

        notifications_view.tap do |view|
          view.add_top_bar(header_bar)
          view.add_top_bar(account_banner)
          view.content = notifications_stack

          header_bar.tap do |bar|
            bar.pack_start(mark_as_read_button)
            bar.pack_end(menu_button)

            mark_as_read_button.tap do |button|
              button.child = mark_as_read_box

              mark_as_read_box.tap do |box|
                box.append(mark_as_read_icon)
                box.append(mark_as_read_label)

                mark_as_read_icon.tap do |stack|
                  stack.add_named(mark_as_read_image, 'icon')
                  stack.add_named(mark_as_read_spinner, 'spinner')
                  stack.visible_child_name = 'icon'
                end
              end

              button.signal_connect('clicked') { mark_all_as_read }
            end
          end

          notifications_stack.tap do |stack|
            stack.add_named(empty_clamp, 'empty')
            stack.add_named(list_scroll, 'list')
            stack.visible_child_name = 'empty'

            empty_clamp.tap do |clamp|
              clamp.child = empty_box

              empty_box.tap do |box|
                box.append(empty_picture)
                box.append(empty_label)
              end
            end

            list_scroll.tap do |scrolled|
              scrolled.child = list_clamp

              list_clamp.child = notifications_list

              notifications_list.signal_connect('row-activated') do |_list, row|
                activate_row(row.index)
              end
            end
          end
        end
      end

      @model.on_items_changed { update_notifications_view }
      @accounts.on_items_changed { show_setup_when_empty }
      setup_window_actions
      signal_connect('close-request') do
        @settings.remember(self)
        false
      end

      start
    end
  end

  # --- The fetch loop -----------------------------------------------------

  # Runs the first-run setup if it has not run, and then starts fetching.
  def start
    tap do
      unless @settings['first-run']
        first_run
      end
      subscribe
    end
  end

  # Runs the notifications getter task.
  #
  # Upstream recurses with a GLib timeout; so does this. The timeout source id
  # is kept so #reload can cancel a pending run.
  def subscribe
    @fetching = true
    @fetch_error = false
    @network_error = false

    if @retry_handler
      @accounts.off_items_changed(@retry_handler)
      @retry_handler = nil
    end

    # Resolve a token error for an account that is no longer configured.
    unless @accounts.get_accounts.include?(@auth_failed)
      resolve_token_error
    end

    if @accounts.n_items.zero?
      wait_for_an_account
    else
      Util.defer(method(:fetch_all), method(:on_fetched))
    end
  end

  # Forces a notification retrieve.
  def reload
    if @fetching
      @re_fetch = true
    else
      if @subscribe_source
        GLib::Source.remove(@subscribe_source)
        @subscribe_source = nil
      end
      subscribe
    end

    # This might be after a user interaction, so show the spinner.
    main_stack.visible_child_name = 'loading'
  end

  # Shows notifications to the user: replaces the model and sends the desktop
  # notifications for everything that is new or has changed since last time.
  def show_notifications(notifications)
    @model.clear
    notifications.each { |notification| @model.append(notification) }

    @model.sorted.each { |notification| notify_desktop(notification) }

    unless @fetch_error
      # Sanitize the notified ids before saving.
      @notified.keys.each do |id|
        unless @model.get_by_id(id)
          @notified.delete(id)
        end
      end
    end

    @settings['notified'] = @notified
    refresh_rows
    main_stack.visible_child_name = 'notifications'
  end

  # Marks one notification as read and withdraws it from the desktop inbox.
  def resolve_notification(id)
    application.withdraw_notification("fs-#{id}")

    Forges.extract_id(id).then do |(account_id, notification_id)|
      @forges[account_id].then do |forge|
        if forge
          Util.defer(
            -> { forge.mark_as_read(notification_id) },
            ->(result) { finish_resolve(id, result) },
          )
        end
      end
    end
  end

  # Marks every notification on every account as read.
  def mark_all_as_read
    mark_as_read_button.sensitive = false
    notifications_list.sensitive = false
    mark_as_read_icon.visible_child_name = 'spinner'

    Util.defer(
      -> { @forges.values.map { |forge| mark_account_read(forge) } },
      method(:finish_mark_all_as_read),
    )
  end

  # Memoized widget methods

  def main_stack
    @main_stack ||= Gtk::Stack.new.tap do |stack|
      stack.add_css_class('main-view')
    end
  end

  def setup_view = @setup_view ||= Adwaita::ToolbarView.new

  def setup_header
    @setup_header ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.show_title = false
    end
  end

  def setup_menu_button = @setup_menu_button ||= build_menu_button
  def menu_button = @menu_button ||= build_menu_button

  # Upstream names the app's own installed icon here; this port has not
  # installed one, so the ported SVG is loaded from data/ as a paintable,
  # which is the same picture without an icon theme in the way.
  def setup_page
    @setup_page ||= Adwaita::StatusPage.new.tap do |page|
      page.title = 'Welcome to Forge Sparks'
      page.description = 'Add an account to receive notifications from'
      page.paintable = app_icon
      page.vexpand = true
    end
  end

  def app_icon = @app_icon ||= Gdk::Texture.new(Gio::File.new_for_path(File.join(Util.data_dir, 'forge-sparks.svg')))

  def add_account_button
    @add_account_button ||= Gtk::Button.new.tap do |button|
      button.label = 'Add Account…'
      button.halign = :center
      button.add_css_class('suggested-action')
      button.add_css_class('pill')
    end
  end

  def loading_view = @loading_view ||= Gtk::WindowHandle.new

  def loading_box
    @loading_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.halign = :center
      box.valign = :center
      box.margin_top = 12
      box.margin_bottom = 12
      box.margin_start = 12
      box.margin_end = 12
    end
  end

  def loading_spinner
    @loading_spinner ||= Adwaita::Spinner.new.tap do |spinner|
      spinner.width_request = SPINNER_SIZE
      spinner.height_request = SPINNER_SIZE
    end
  end

  def notifications_view = @notifications_view ||= Adwaita::ToolbarView.new

  def header_bar
    @header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.show_title = false
    end
  end

  # Hidden until there is something in the list, which is upstream binding the
  # button's visibility to the model having items.
  def mark_as_read_button
    @mark_as_read_button ||= Gtk::Button.new.tap do |button|
      button.visible = false
      button.add_css_class('flat')
      button.tooltip_text = 'Mark all as Read'
    end
  end

  def mark_as_read_box = @mark_as_read_box ||= Gtk::Box.new(:horizontal, 6)
  def mark_as_read_icon = @mark_as_read_icon ||= Gtk::Stack.new
  def mark_as_read_image = @mark_as_read_image ||= Gtk::Image.new(icon_name: 'object-select-symbolic')

  def mark_as_read_spinner
    @mark_as_read_spinner ||= Adwaita::Spinner.new.tap do |spinner|
      spinner.width_request = MARK_SPINNER_SIZE
      spinner.height_request = MARK_SPINNER_SIZE
    end
  end

  def mark_as_read_label = @mark_as_read_label ||= Gtk::Label.new('Mark all as Read')

  def account_banner
    @account_banner ||= Adwaita::Banner.new('').tap do |banner|
      banner.button_label = 'Accounts'
      banner.action_name = 'app.accounts'
    end
  end

  def notifications_stack = @notifications_stack ||= Gtk::Stack.new

  def empty_clamp
    @empty_clamp ||= Adwaita::Clamp.new.tap do |clamp|
      clamp.maximum_size = EMPTY_ILLUSTRATION_WIDTH
    end
  end

  def empty_box
    @empty_box ||= Gtk::Box.new(:vertical, 24).tap do |box|
      box.valign = :center
      box.margin_start = 12
      box.margin_end = 12
      box.margin_bottom = 36
    end
  end

  # Upstream loads the illustration from its gresource bundle; here it is the
  # same SVG, ported into data/ and loaded from the file.
  def empty_picture
    @empty_picture ||= Gtk::Picture.new.tap do |picture|
      picture.can_shrink = true
      picture.filename = File.join(Util.data_dir, 'alldone.svg')
    end
  end

  def empty_label
    @empty_label ||= Gtk::Label.new('No Notifications to Show').tap do |label|
      label.wrap = true
      label.justify = :center
      label.add_css_class('title-1')
    end
  end

  def list_scroll
    @list_scroll ||= Gtk::ScrolledWindow.new.tap do |scrolled|
      scrolled.hscrollbar_policy = :never
      scrolled.vexpand = true
    end
  end

  def list_clamp = @list_clamp ||= Adwaita::Clamp.new

  def notifications_list
    @notifications_list ||= Gtk::ListBox.new.tap do |list|
      list.valign = :start
      list.selection_mode = :none
      list.add_css_class('content')
      list.add_css_class('margin-box')
    end
  end

  # The same menu upstream builds in window.blp.
  def primary_menu
    @primary_menu ||= Gio::Menu.new.tap do |menu|
      menu.append_section(
        nil,
        Gio::Menu.new.tap do |section|
                section.append('_Preferences', 'app.preferences')
                section.append('_Accounts', 'app.accounts')
                section.append('_Keyboard Shortcuts', 'win.show-help-overlay')
                section.append('About Forge Sparks', 'app.about')
              end,
      )

      menu.append_section(
        nil,
        Gio::Menu.new.tap do |section|
                section.append('Quit', 'app.quit')
              end,
      )
    end
  end

  private

    def build_menu_button
      Gtk::MenuButton.new.tap do |button|
        button.primary = true
        button.icon_name = 'open-menu-symbolic'
        button.tooltip_text = 'Main Menu'
        button.menu_model = primary_menu
      end
    end

    # Upstream's window actions: the shortcuts dialog, and the primary menu
    # that F10 opens.
    def setup_window_actions
      Gio::SimpleAction.new('show-help-overlay', nil).tap do |action|
        action.signal_connect('activate') { show_shortcuts }
        add_action(action)
      end

      Gio::SimpleAction.new('open-primary-menu', nil).tap do |action|
        action.signal_connect('activate') { menu_button.popup }
        add_action(action)
      end
    end

    def show_shortcuts
      ShortcutsDialog.new.tap do |dialog|
        dialog.build
        dialog.present(self)
      end
    end

    # --- First run ------------------------------------------------------

    # Upstream asks the portal for background permission here and saves the
    # answer as hide-on-close. Without a portal the app can simply keep
    # running, so that is the default the first run records.
    def first_run
      @settings['hide-on-close'] = true
      @settings['first-run'] = true
      self.hide_on_close = true
    end

    # --- Fetching -------------------------------------------------------

    # Shows the welcome page and re-runs #subscribe once an account appears.
    def wait_for_an_account
      main_stack.visible_child_name = 'setup'
      @fetching = false
      @retry_handler = @accounts.on_items_changed { subscribe }
    end

    def show_setup_when_empty
      if @accounts.n_items.zero?
        main_stack.visible_child_name = 'setup'
      end
    end

    # Runs on the worker thread: everything here is HTTP and secret lookups,
    # and nothing here touches a widget. The result it hands back is what the
    # main loop needs to update the UI.
    def fetch_all
      { notifications: [], failures: {}, user_ids: {}, succeeded: [] }.tap do |result|
        @accounts.accounts.each do |account|
          fetch_account(account, result)
        end
      end
    end

    def fetch_account(account, result)
      forge_for(account, result).then do |forge|
        if forge
          result[:notifications].concat(forge.get_notifications)
          result[:succeeded] << account.id
        end
      end
    rescue StandardError, GLib::Error => e
      result[:failures][account.id] = e
    end

    # The forge instance for an account, created on first use the way upstream
    # fills its this.forges map, including the user id lookup that older
    # accounts (Forge Sparks <= 0.2) never saved.
    def forge_for(account, result)
      unless @forges[account.id]
        @accounts.get_account_token(account.id).then do |token|
          Forges[account.forge].then do |forge_class|
            if forge_class && token
              @forges[account.id] = forge_class.new(
                account.url,
                token,
                account:      account.id,
                user_id:      account.user_id,
                account_name: account.display_name,
              )
            end
          end
        end
      end

      @forges[account.id].tap do |forge|
        if forge && account.user_id.to_i.zero?
          forge.get_user.then do |(user_id, _username)|
            forge.user_id = user_id
            result[:user_ids][account.id] = user_id
          end
        end
      end
    end

    # Runs back on the main loop with whatever #fetch_all produced.
    def on_fetched(result)
      @fetching = false

      if result.is_a?(Exception)
        warn "Could not fetch notifications: #{result.message}"
        main_stack.visible_child_name = 'notifications'
      else
        apply_fetched(result)
      end

      schedule_next_fetch
    end

    def apply_fetched(result)
      result[:user_ids].each do |account_id, user_id|
        @accounts.get_account_by_id(account_id).then do |account|
          if account
            @accounts.save_account_user_id(account_id, user_id)
          end
        end
      end

      result[:succeeded].each { |account_id| resolve_recovered(account_id) }
      result[:failures].each { |account_id, error| handle_failure(account_id, error) }

      if @network_error && result[:notifications].empty?
        main_stack.visible_child_name = 'notifications'
      else
        show_notifications(result[:notifications])
      end
    end

    # Upstream clears the token error as soon as the account it was reported
    # for answers a request again, which is what takes the banner back down
    # without the user having to touch the account.
    def resolve_recovered(account_id)
      if @auth_failed == account_id
        @accounts.get_account_by_id(account_id).then do |account|
          if account
            resolve_token_error(account)
          end
        end
      end
    end

    def handle_failure(account_id, error)
      @fetch_error = true

      case error
      when Forge::FailedForgeAuth
        report_auth_failure(account_id)
      else
        if network_error?(error)
          @network_error = true
        end
        warn "Account #{account_id} failed: #{error.message}"
      end
    end

    def network_error?(error)
      error.is_a?(SocketError) ||
        error.is_a?(SystemCallError) ||
        error.is_a?(Net::OpenTimeout) ||
        error.is_a?(Net::ReadTimeout) ||
        error.is_a?(IOError)
    end

    # The token was revoked or expired: say so in the banner, mark the account
    # so the accounts dialog shows its error icon, and send one desktop
    # notification about it while the window is not in front.
    def report_auth_failure(account_id)
      @accounts.get_account_by_id(account_id).then do |account|
        if account
          @auth_failed = account_id
          account.auth_failed = true
          @forges.delete(account_id)

          "Account #{account.display_name} authentication failed!".then do |title|
            'The token may have been revoked or expired.'.then do |description|
              account_banner.title = "#{title}\n#{description}"
              account_banner.revealed = true
              notify_auth_failure(title, description)
            end
          end
        end
      end
    end

    def notify_auth_failure(title, description)
      unless active? || @auth_error_notified
        Gio::Notification.new(title).tap do |notification|
          notification.body = description
          notification.set_default_action('app.activate')
          notification.add_button('Accounts', 'app.accounts')
          application.send_notification(AUTH_ERROR_NOTIFICATION, notification)
        end
        @auth_error_notified = true
      end
    end

    def resolve_token_error(account = nil)
      @auth_failed = nil
      @auth_error_notified = false
      if account
        account.auth_failed = false
      end

      account_banner.revealed = false
      if application
        application.withdraw_notification(AUTH_ERROR_NOTIFICATION)
      end
    end

    def schedule_next_fetch
      if @re_fetch
        @re_fetch = false
        subscribe
      else
        @subscribe_source = GLib::Timeout.add_seconds(@interval) do
          subscribe
          false
        end
      end
    end

    # --- Desktop notifications ------------------------------------------

    # Only sends a notification while the window is hidden or not focused, and
    # only for a notification that is new or has changed since last time.
    def notify_desktop(notification)
      if hidden?
        unless @notified[notification.id] == notification.updated_at
          application.send_notification(
            "fs-#{notification.id}",
            notification.gio_notification(hidden: !visible?),
          )
        end
      end

      @notified[notification.id] = notification.updated_at
    end

    def hidden? = !visible? || !active?

    # --- The list -------------------------------------------------------

    # Rebuilds the rows from the sorted model.
    #
    # Upstream binds the list box to a Gtk.SortListModel and lets the binding
    # build the rows; the model here sorts in Ruby, so the rows are rebuilt
    # whenever it changes. The listed array is what a row index resolves
    # through, so nothing is ever read back out of a GTK model.
    def refresh_rows
      @listed = @model.sorted
      @rows = @listed.map { |notification| notification_row(notification) }
      notifications_list.remove_all
      @rows.each { |row| notifications_list.append(row) }
    end

    def notification_row(notification)
      NotificationRow.new(
        notification,
        date:    Util.relative_date(notification.date_time),
        account: @accounts.multiple? ? notification.account_name : nil,
      ).build
    end

    # A row was activated: it goes into its progress state and the application
    # action opens the link, which is what upstream's `activated` handler does.
    #
    # The row is taken from the array built alongside the notifications rather
    # than from the list box, so nothing is read back out of GTK.
    def activate_row(index)
      @listed[index].then do |notification|
        if notification
          @rows[index].then do |row|
            row.progress = true
            row.sensitive = false
          end
          request_open(notification)
        end
      end
    end

    def request_open(notification)
      application.lookup_action('open-notification').then do |action|
        if action
          action.activate(GLib::Variant.new([notification.id.to_s, notification.url.to_s]))
        end
      end
    end

    def update_notifications_view
      if @model.n_items.positive?
        notifications_stack.visible_child_name = 'list'
      else
        notifications_stack.visible_child_name = 'empty'
      end
      mark_as_read_button.visible = @model.n_items.positive?
    end

    # --- Marking as read ------------------------------------------------

    def mark_account_read(forge)
      forge.mark_as_read
    rescue StandardError, GLib::Error => e
      warn "Could not mark notifications as read: #{e.message}"
      false
    end

    def finish_mark_all_as_read(_result)
      @model.clear
      refresh_rows

      mark_as_read_button.sensitive = true
      notifications_list.sensitive = true
      mark_as_read_icon.visible_child_name = 'icon'
    end

    def finish_resolve(id, result)
      if result == true
        @model.remove_by_id(id)
        refresh_rows
      else
        if result.is_a?(Exception)
          warn "Could not mark #{id} as read: #{result.message}"
        end
        refresh_rows
      end
    end

    # --- Window state ---------------------------------------------------

    def open_new_account
      AccountDialog.new(nil, accounts: @accounts, on_saved: method(:reload)).tap do |dialog|
        dialog.build
        dialog.present(self)
      end
    end
end
