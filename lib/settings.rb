# frozen_string_literal: true

require 'json'
require 'fileutils'

# Settings holds the same keys as upstream's com.mardojai.ForgeSparks
# GSettings schema (data/com.mardojai.ForgeSparks.gschema.xml).
#
# Upstream declares two schemas: the application one, keyed by first-run,
# hide-on-close, autostart, autostart-hidden, window-size, accounts and
# notified; and a per-account one (forge, url, username, user-id) that it
# instantiates at a relocatable path below the app path, one subpath per
# account id.
#
# GSettings needs a compiled schema installed into the system's
# glib-2.0/schemas directory, and requiring an install step before the app can
# run from a checkout is worse than the alternative, so the same keys, defaults
# and semantics are backed by a small JSON file under XDG_CONFIG_HOME instead.
# The per-account schema becomes the nested "account-settings" object, reached
# through #account, which returns a view with the same four keys.
#
class Settings
  DEFAULTS = {
    'first-run'        => false,
    'hide-on-close'    => false,
    'autostart'        => false,
    'autostart-hidden' => false,
    'window-size'      => [780, 480],
    'accounts'         => [],
    'notified'         => {},
  }.freeze

  # Upstream's com.mardojai.ForgeSparks.account schema.
  ACCOUNT_DEFAULTS = {
    'forge'    => 'github',
    'url'      => 'github.com',
    'username' => '',
    'user-id'  => 0,
  }.freeze

  ACCOUNT_SETTINGS_KEY = 'account-settings'

  # AccountSettings is one account's relocated copy of the account schema.
  #
  # It reads and writes through the owning Settings so every change hits the
  # same JSON file, which is what upstream gets from a relocatable GSettings
  # path under the app's own path.
  class AccountSettings
    def initialize(settings, id)
      @settings = settings
      @id = id
    end

    def id = @id

    def [](key) = values.fetch(key.to_s, ACCOUNT_DEFAULTS[key.to_s])

    def []=(key, value)
      @settings.write_account_value(@id, key.to_s, value)
      value
    end

    ACCOUNT_DEFAULTS.each_key do |key|
      method_name = key.tr('-', '_')
      define_method(method_name) { self[key] }
      define_method(:"#{method_name}=") { |value| self[key] = value }
    end

    def to_h = ACCOUNT_DEFAULTS.merge(values)

    private

      def values = @settings.account_values(@id)
  end

  def initialize(path: nil)
    @path = path || default_path
    @values = DEFAULTS.merge(read)
    @account_views = {}
  end

  def location = @path

  def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

  def []=(key, value)
    @values[key.to_s] = value
    write
    value
  end

  # Named accessors for every key, so callers do not repeat the string keys.
  DEFAULTS.each_key do |key|
    method_name = key.tr('-', '_')
    define_method(method_name) { self[key] }
    define_method(:"#{method_name}=") { |value| self[key] = value }
    if DEFAULTS[key] == false
      define_method(:"#{method_name}?") { self[key] == true }
    end
  end

  # The account schema instance for one account id, memoized per id the same
  # way upstream's AccountsManager memoizes its Gio.Settings instances.
  def account(id) = @account_views[id.to_s] ||= AccountSettings.new(self, id.to_s)

  # Drops an account's stored keys. Upstream leaves the relocated GSettings
  # path behind when an account is removed; here the whole subtree goes, which
  # keeps the file from growing a tail of dead accounts.
  def forget_account(id)
    account_store.delete(id.to_s)
    @account_views.delete(id.to_s)
    write
  end

  def account_values(id) = account_store.fetch(id.to_s, {})

  def write_account_value(id, key, value)
    (account_store[id.to_s] ||= {})[key] = value
    write
    value
  end

  # Restores the window geometry recorded by the previous run.
  def apply_to(window)
    self['window-size'].then do |(width, height)|
      window.set_default_size(width, height)
    end
  end

  # Records the window geometry, which is upstream's window-size key: a pair
  # of integers rather than separate width and height keys.
  def remember(window)
    self['window-size'] = [window.default_width, window.default_height]
  end

  private

    def account_store = @values[ACCOUNT_SETTINGS_KEY] ||= {}

    def default_path
      File.join(
        ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config')),
        'forge-sparks-rb',
        'settings.json',
      )
    end

    def read
      File.exist?(@path) ? JSON.parse(File.read(@path)) : {}
    rescue JSON::ParserError => e
      warn "Error parsing #{@path}: #{e.message}"
      {}
    end

    def write
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(@values))
    end
end
