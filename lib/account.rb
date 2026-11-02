# frozen_string_literal: true

require 'gtk4'

# Account is one configured forge account.
#
# Ported from upstream's src/model/account.js: the id the account is known by
# in the app settings, which forge it is on, the instance url, the username
# and user id the token resolved to, and whether that token has since stopped
# authenticating.
#
# Upstream declares these as GObject properties so the accounts dialog can
# bind a row's title to display-name and the error icon's visibility to
# auth-failed. The rows here are built in Ruby, so the fields are plain
# attributes and the two bindings become the #on_change callback the dialog
# registers. It is still a GLib::Object because Gio::ListStore holds GObjects.
#
class Account < GLib::Object
  type_register

  attr_reader :id
  attr_accessor :user_id

  def initialize(id:, forge: 'github', url: '', username: '', user_id: 0)
    super()
    @id = id
    @forge = forge
    @url = url
    @username = username
    @user_id = user_id
    @auth_failed = false
    @listeners = []
  end

  # Registers a block called with this account whenever a field that the UI
  # shows changes — upstream's notify::display-name and notify::auth-failed.
  def on_change(&listener) = @listeners << listener

  # Account display name (username@instance.tld).
  def display_name = "#{@username}@#{@url}"

  attr_reader :forge, :url, :username, :auth_failed

  def forge=(value)
    assign(:@forge, value)
  end

  def url=(value)
    assign(:@url, value)
  end

  def username=(value)
    assign(:@username, value)
  end

  def auth_failed=(value)
    assign(:@auth_failed, value)
  end

  def auth_failed? = @auth_failed == true

  # Builds an account from one id and the per-account settings view that holds
  # its saved keys, which is where upstream binds the four GSettings keys to
  # the account object.
  def self.from_settings(id, account_settings)
    new(
      id:       id,
      forge:    account_settings.forge,
      url:      account_settings.url,
      username: account_settings.username,
      user_id:  account_settings.user_id,
    )
  end

  private

    # Upstream's setters each return early when the value has not changed and
    # notify otherwise; this is the same, once.
    def assign(ivar, value)
      instance_variable_get(ivar).then do |current|
        unless current == value
          instance_variable_set(ivar, value)
          @listeners.each { |listener| listener.call(self) }
        end
      end
      value
    end
end
