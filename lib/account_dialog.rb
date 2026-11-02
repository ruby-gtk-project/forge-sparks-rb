# frozen_string_literal: true

require 'uri'
require 'adwaita'

require_relative 'forges'
require_relative 'accounts_manager'
require_relative 'util'
require_relative 'translation'

# AccountDialog adds an account, or edits one that exists.
#
# Ported from upstream's src/widgets/accountDialog.js and
# src/widgets/accountDialog.blp: a forge chooser, the instance url for the
# forges that have instances, the access token, the forge's own help text on
# getting one, and — only while editing — the button that removes the account.
#
# The save button stays insensitive until the form validates, which for a new
# account means a token and a parseable instance url, and while editing means
# that one of the two actually changed. Validating the token itself is a
# request, so saving runs off the main loop through Util.defer and the form is
# insensitive while it is in flight, exactly as upstream makes the page
# insensitive while it awaits getUser().
#
class AccountDialog < Adwaita::Dialog
  include Translation

  CONTENT_WIDTH = 360
  HELP_MARGIN = 24

  # @param account [Account, nil] the account to edit, or nil to add one
  # @param accounts [AccountsManager] the accounts model
  # @param on_saved [Proc, nil] called after an account is added, changed or removed
  def initialize(account = nil, accounts: AccountsManager.instance, on_saved: nil)
    super()
    @account = account
    @accounts = accounts
    @on_saved = on_saved
    @editing = !account.nil?
    @user_changed_instance = false
    @saved_token = nil

    self.content_width = CONTENT_WIDTH
    self.follows_content_size = true
    if @editing
      self.title = _('Edit Account')
    else
      self.title = _('Add Account')
    end
  end

  def editing? = @editing

  def build
    tap do |dialog|
      dialog.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = toast_overlay

        header_bar.tap do |bar|
          bar.title_widget = title_widget
          bar.pack_start(cancel_button)
          bar.pack_end(save_button)

          cancel_button.signal_connect('clicked') { close }
          save_button.signal_connect('clicked') { on_save }
        end

        toast_overlay.tap do |overlay|
          overlay.child = page

          page.tap do |prefs|
            prefs.add(form_group)
            prefs.add(remove_group)

            form_group.tap do |group|
              group.add(forge_row)
              group.add(instance_row)
              group.add(access_token_row)
              group.add(help_row)

              forge_row.signal_connect('notify::selected') { on_forge_changed }
              instance_row.signal_connect('notify::text') { on_instance_changed }
              access_token_row.signal_connect('notify::text') { on_entry_changed }
            end

            remove_group.tap do |group|
              group.add(remove_button)

              remove_button.signal_connect('clicked') { on_remove_account }
            end
          end
        end
      end

      if @editing
        load_saved_account
      else
        on_forge_changed
      end
    end
  end

  # --- Form state ---------------------------------------------------------

  # The forge classes, in the order the combo row lists them.
  def forge_classes = Forges.all

  # The forge class the form is about: the saved one while editing, the
  # selected one while adding.
  def selected_forge_class
    if @editing
      Forges[@account.forge]
    else
      forge_classes[forge_row.selected]
    end
  end

  def allow_instances? = selected_forge_class.allow_instances?

  # Memoized widget methods

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

  def header_bar
    @header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.show_start_title_buttons = false
      bar.show_end_title_buttons = false
    end
  end

  def title_widget = @title_widget ||= Adwaita::WindowTitle.new(title.to_s, '')

  def cancel_button
    @cancel_button ||= Gtk::Button.new.tap do |button|
      button.label = _('Cancel')
    end
  end

  def save_button
    @save_button ||= Gtk::Button.new.tap do |button|
      if @editing
        button.label = _('Save')
      else
        button.label = _('Add')
      end
      button.sensitive = false
      button.add_css_class('suggested-action')
    end
  end

  def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new
  def page = @page ||= Adwaita::PreferencesPage.new

  def form_group
    @form_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.hexpand = true
    end
  end

  # The forge chooser has nothing to offer while editing: the forge an account
  # is on cannot change, so upstream hides the row.
  def forge_row
    @forge_row ||= Adwaita::ComboRow.new.tap do |row|
      row.title = _('Forge')
      row.visible = !@editing
      row.model = Gtk::StringList.new(forge_classes.map(&:pretty_name))
    end
  end

  def instance_row
    @instance_row ||= Adwaita::EntryRow.new.tap do |row|
      row.title = _('Instance URL')
      row.visible = false
    end
  end

  def access_token_row
    @access_token_row ||= Adwaita::PasswordEntryRow.new.tap do |row|
      row.title = _('Access Token')
    end
  end

  # The help text is a plain label inside the group, which is how upstream's
  # Blueprint has it; a PreferencesGroup only takes rows, so the label travels
  # in a non-activatable row of its own.
  def help_row
    @help_row ||= Adwaita::PreferencesRow.new.tap do |row|
      row.activatable = false
      row.child = help_label
    end
  end

  def help_label
    @help_label ||= Gtk::Label.new.tap do |label|
      label.use_markup = true
      label.wrap = true
      label.xalign = 0
      label.margin_top = HELP_MARGIN
    end
  end

  def remove_group
    @remove_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.visible = @editing
    end
  end

  def remove_button
    @remove_button ||= Gtk::Button.new.tap do |button|
      button.label = _('Remove Account')
      button.halign = :center
      button.add_css_class('destructive-action')
      button.add_css_class('pill')
    end
  end

  private

    # Loads the saved values of the account being edited. The token lookup
    # talks to the secret service, so it runs off the main loop.
    def load_saved_account
      title_widget.subtitle = @account.display_name

      if allow_instances?
        instance_row.visible = true
        instance_row.text = @account.url.to_s
      end

      help_label.label = selected_forge_class.token_text

      Util.defer(
        -> { @accounts.get_account_token(@account.id) },
        method(:on_token_loaded),
      )
    end

    def on_token_loaded(token)
      if token.is_a?(Exception)
        warn "Could not read the saved token: #{token.message}"
        add_toast(Adwaita::Toast.new(_('Could not read the saved access token')))
      else
        @saved_token = token.to_s
        access_token_row.text = @saved_token
      end
      on_entry_changed
    end

    # --- Callbacks ------------------------------------------------------

    def on_forge_changed
      instance_row.visible = allow_instances?
      help_label.label = selected_forge_class.token_text

      # Entries may be different now, so validate again.
      on_entry_changed

      unless @user_changed_instance || @editing
        instance_row.text = selected_forge_class.default_url
      end
    end

    # Remembers that the instance url is the user's own, so changing the forge
    # does not overwrite what they typed.
    def on_instance_changed
      @user_changed_instance = !@editing && instance_row.text != selected_forge_class.default_url
      on_entry_changed
    end

    def on_entry_changed
      save_button.sensitive = form_valid?
    end

    def on_save
      if @editing
        update_account
      else
        add_account
      end
    end

    # --- Validation -----------------------------------------------------

    def form_valid?
      if allow_instances?
        instance_valid? && token_filled? && something_changed?
      else
        token_filled? && something_changed?
      end
    end

    def token_filled? = !access_token_row.text.to_s.empty?

    # A new account is a change by definition; an edit has to differ from
    # what is saved, which is upstream's urlChanged || tokenChanged.
    def something_changed?
      if @editing
        instance_row.text != @account.url.to_s || access_token_row.text != @saved_token.to_s
      else
        true
      end
    end

    # Validates the instance url, marking the entry and raising a toast when
    # it cannot be parsed — upstream does both from the same place.
    #
    # An empty entry is not yet a bad url: it is a form the user has not
    # finished, so it only leaves the save button insensitive. Upstream gets
    # the same behaviour from GLib.Uri accepting a bare "https://".
    def instance_valid?
      if instance_row.text.to_s.empty?
        instance_row.remove_css_class('error')
        false
      else
        check_instance_url
      end
    end

    def check_instance_url
      instance_url.then do |uri|
        if uri
          instance_row.remove_css_class('error')
          true
        else
          instance_row.add_css_class('error')
          add_toast(Adwaita::Toast.new(_('Invalid instance url.')))
          false
        end
      end
    end

    # The parsed instance url, or nil when it does not parse. https is forced
    # on, as upstream does before handing the string to GLib.Uri.
    def instance_url
      instance_row.text.to_s.then do |text|
        URI.parse(text.match?(%r{\Ahttps?://}i) ? text : "https://#{text}").then do |uri|
          uri.host.to_s.empty? ? nil : uri
        end
      end
    rescue URI::InvalidURIError
      nil
    end

    # The host the account is saved with: the forge's default when it has no
    # instances, and the typed host with any leading www. removed when it has.
    def account_url
      if allow_instances?
        instance_url.then { |uri| uri ? uri.host.delete_prefix('www.') : nil }
      else
        selected_forge_class.default_url
      end
    end

    # --- Saving ---------------------------------------------------------

    def add_account
      account_url.then do |url|
        if url
          page.sensitive = false
          selected_forge_class.new(url, access_token_row.text).then do |forge|
            Util.defer(
              -> { forge.get_user },
              ->(result) { finish_add(result, url) },
            )
          end
        end
      end
    end

    def finish_add(result, url)
      page.sensitive = true

      if result.is_a?(Exception)
        add_toast(Adwaita::Toast.new(error_text(result)))
      else
        save_new_account(result, url)
      end
    end

    def save_new_account(user, url)
      user.then do |(user_id, username)|
        @accounts.save_account(
          forge:    selected_forge_class.forge_name,
          url:      url,
          user_id:  user_id,
          username: username,
          token:    access_token_row.text,
        )
      end
      finish_and_close
    rescue AccountsManager::TokenStore::Error => e
      add_toast(Adwaita::Toast.new(e.message))
    end

    def update_account
      account_url.then do |url|
        if url && something_changed?
          page.sensitive = false
          selected_forge_class.new(url, access_token_row.text).then do |forge|
            Util.defer(
              -> { forge.get_user },
              ->(result) { finish_update(result, url) },
            )
          end
        end
      end
    end

    def finish_update(result, url)
      page.sensitive = true

      if result.is_a?(Exception)
        add_toast(Adwaita::Toast.new(error_text(result)))
      else
        save_updated_account(result, url)
      end
    end

    def save_updated_account(user, url)
      user.then do |(user_id, username)|
        @accounts.update_account(
          @account.id,
          url:      url,
          user_id:  user_id,
          username: username,
          token:    access_token_row.text,
        )
      end
      finish_and_close
    rescue AccountsManager::TokenStore::Error => e
      add_toast(Adwaita::Toast.new(e.message))
    end

    def on_remove_account
      if @editing
        Util.defer(
          -> { @accounts.remove_account(@account.id) },
          method(:finish_remove),
        )
      end
    end

    def finish_remove(result)
      if result == true
        finish_and_close
      else
        add_toast(Adwaita::Toast.new(_('Unexpected error removing the account')))
      end
    end

    def finish_and_close
      close
      if @on_saved
        @on_saved.call
      end
    end

    def add_toast(toast) = toast_overlay.add_toast(toast)

    # Upstream's _errorText, keyed by error class rather than by the strings
    # it throws.
    def error_text(error)
      case error
      when Forge::FailedForgeAuth
        _('Couldn’t authenticate the account')
      when Forge::FailedTokenScopes
        _('The access token doesn’t have the needed scopes')
      else
        _('Unexpected error when creating the account')
      end
    end
end
