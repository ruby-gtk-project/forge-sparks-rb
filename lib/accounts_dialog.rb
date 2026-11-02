# frozen_string_literal: true

require 'adwaita'

require_relative 'accounts_manager'
require_relative 'account_dialog'

# AccountsDialog lists the configured accounts.
#
# Ported from upstream's src/widgets/accountsDialog.js and
# src/widgets/accountsDialog.blp: an "Add…" button in the header, a status
# page while there are no accounts, and one activatable row per account
# carrying the error icon that appears when its token stopped working.
#
# Upstream binds the list box to the accounts model and each row's title to
# the account's display-name property. There is no property to bind to here,
# so the rows are rebuilt whenever the model changes, which is also what
# redraws a row after its account was edited.
#
class AccountsDialog < Adwaita::Dialog
  CONTENT_WIDTH = 360

  # @param accounts [AccountsManager] the accounts model
  # @param on_changed [Proc, nil] called after an account was added or changed
  def initialize(accounts: AccountsManager.instance, on_changed: nil)
    super()
    @accounts = accounts
    @on_changed = on_changed
    @listed = []
    @error_icons = {}
    @watched = []

    self.title = 'Accounts'
    self.content_width = CONTENT_WIDTH
  end

  def build
    tap do |dialog|
      dialog.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = scrolled_window

        header_bar.tap do |bar|
          bar.pack_start(add_button)

          add_button.signal_connect('clicked') { open_add_account }
        end

        scrolled_window.tap do |scrolled|
          scrolled.child = clamp

          clamp.tap do |clamped|
            clamped.child = accounts_stack

            accounts_stack.tap do |stack|
              stack.add_named(empty_page, 'empty')
              stack.add_named(accounts_list, 'accounts')
            end
          end
        end
      end

      @accounts.on_items_changed { refresh }
      refresh
    end
  end

  # Rebuilds the rows and picks the page that has something to show.
  def refresh
    @listed = @accounts.accounts
    accounts_list.remove_all
    @listed.each { |account| accounts_list.append(account_row(account)) }

    if @listed.empty?
      accounts_stack.visible_child_name = 'empty'
    else
      accounts_stack.visible_child_name = 'accounts'
    end
  end

  # Memoized widget methods

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def add_button
    @add_button ||= Gtk::Button.new.tap do |button|
      button.add_css_class('flat')
      button.child = add_button_content
    end
  end

  def add_button_content
    @add_button_content ||= Adwaita::ButtonContent.new.tap do |content|
      content.label = 'Add…'
      content.icon_name = 'list-add-symbolic'
    end
  end

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |scrolled|
      scrolled.propagate_natural_height = true
      scrolled.propagate_natural_width = true
    end
  end

  def clamp
    @clamp ||= Adwaita::Clamp.new.tap do |clamp|
      clamp.add_css_class('margin-box')
    end
  end

  def accounts_stack
    @accounts_stack ||= Gtk::Stack.new.tap do |stack|
      stack.vhomogeneous = false
    end
  end

  def empty_page
    @empty_page ||= Adwaita::StatusPage.new.tap do |page|
      page.title = 'No Accounts'
      page.description = 'Add an account to receive notifications from'
      page.add_css_class('compact')
    end
  end

  def accounts_list
    @accounts_list ||= Gtk::ListBox.new.tap do |list|
      list.selection_mode = :none
      list.valign = :start
      list.add_css_class('content')
    end
  end

  private

    # One row per account: its display name, the error icon that shows only
    # while the account's token is failing, and the chevron saying the row
    # opens something.
    def account_row(account)
      Adwaita::ActionRow.new.tap do |row|
        row.title = account.display_name
        row.activatable = true
        row.add_suffix(auth_error_icon(account))
        row.add_suffix(Gtk::Image.new(icon_name: 'go-next-symbolic'))

        # Upstream connects the row's own "activated" signal, and that is the
        # signal an AdwActionRow emits: its activate_signal is "activated", so
        # activating the row never reaches the list box's "row-activated".
        row.signal_connect('activated') { open_edit_account(account) }
      end
    end

    def auth_error_icon(account)
      Gtk::Image.new(icon_name: 'dialog-error-symbolic').tap do |image|
        image.tooltip_text = 'Account authentication failed!'
        image.add_css_class('error')
        image.visible = account.auth_failed?
        watch_auth_failed(account, image)
      end
    end

    # Upstream binds the icon's visibility to the account's auth-failed
    # property, so a dialog that is already open shows the error the moment a
    # fetch fails and loses it again when the account recovers. There is no
    # property to bind here, so the account's change callback moves it — once
    # per account, through the icon the latest #refresh built.
    def watch_auth_failed(account, image)
      @error_icons[account.id] = image

      unless @watched.include?(account.id)
        @watched << account.id
        account.on_change { |changed| update_auth_error_icon(changed) }
      end
    end

    def update_auth_error_icon(account)
      @error_icons[account.id].then do |image|
        if image
          image.visible = account.auth_failed?
        end
      end
    end

    def open_add_account
      AccountDialog.new(nil, accounts: @accounts, on_saved: method(:account_saved)).tap do |dialog|
        dialog.build
        dialog.present(self)
      end
    end

    def open_edit_account(account)
      AccountDialog.new(account, accounts: @accounts, on_saved: method(:account_saved)).tap do |dialog|
        dialog.build
        dialog.present(self)
      end
    end

    def account_saved
      refresh
      if @on_changed
        @on_changed.call
      end
    end
end
