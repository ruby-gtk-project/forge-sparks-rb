# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'securerandom'
require 'shellwords'
require 'open3'
require 'gtk4'

require_relative 'util'
require_relative 'account'

# AccountsManager owns the configured accounts.
#
# Ported from upstream's src/model/accountsManager.js: a singleton list model
# over the account ids in the app settings, with the access tokens kept out of
# the settings and in the secret service, keyed by the account id.
#
# Two things differ from upstream and are deliberate:
#
# * It wraps a Gio::ListStore rather than implementing Gio.ListModel, because
#   ruby-gnome cannot implement the interface from Ruby. Reads go through the
#   Ruby Array it keeps alongside, for the same memory-safety reason as
#   NotificationsList.
# * There is no libsecret binding for Ruby, so the tokens go through
#   TokenStore below, which talks to the same secret service through
#   secret-tool when it is installed and falls back to a file only the user
#   can read when it is not.
#
class AccountsManager
  # Upstream's AccountsManager is a singleton every widget constructs a copy
  # of and gets the one instance back; here that is explicit.
  def self.instance = @instance ||= new

  # Replaces the singleton, which is what a test needs and nothing else does.
  class << self
    attr_writer :instance
  end

  def initialize(settings: Util.settings, tokens: nil)
    @settings = settings
    @tokens = tokens || TokenStore.new
    @accounts = []
    @list_store = Gio::ListStore.new(Account)
    @listeners = {}
    @next_handler_id = 0

    load_saved_accounts
  end

  attr_reader :list_store

  # --- The list model -----------------------------------------------------

  def n_items = @accounts.length

  # Every account, in the order the settings list them.
  def accounts = @accounts.dup

  def get_item(position) = @accounts[position]

  # Gets an account from the list model by its ID.
  def get_account_by_id(id) = @accounts.find { |account| account.id == id }

  # The saved account ids.
  def get_accounts = @settings['accounts'].dup

  # If the user has more than one account.
  def multiple? = @accounts.length > 1

  # Registers a block to run after the model changes, and returns the handler
  # id to pass to #off_items_changed — upstream connects and disconnects the
  # items-changed signal the same way to arm a one-shot retry.
  def on_items_changed(&listener)
    @next_handler_id += 1
    @listeners[@next_handler_id] = listener
    @next_handler_id
  end

  def off_items_changed(handler_id) = @listeners.delete(handler_id)

  # --- Writing ------------------------------------------------------------

  # Saves a new account in the secret service and the app settings.
  #
  # @return [String] the id of the new account
  # @raise [TokenStore::Error] if the token could not be stored
  def save_account(forge:, url:, user_id:, username:, token:)
    SecureRandom.uuid.then do |id|
      @tokens.store(id, token, label: "Access token for #{url}")

      @settings['accounts'] = @settings['accounts'] + [id]
      @settings.account(id).tap do |account_settings|
        account_settings.forge = forge
        account_settings.url = url
        account_settings.username = username
        account_settings.user_id = user_id
      end

      @accounts << Account.from_settings(id, @settings.account(id))
      @list_store.append(@accounts.last)
      notify_items_changed

      id
    end
  end

  # Updates an account in the secret service and the app settings.
  #
  # @return [Boolean] whether the account was updated
  def update_account(id, url:, user_id:, username:, token:)
    get_account_by_id(id).then do |account|
      if account
        @tokens.clear(id)
        @tokens.store(id, token, label: "Access token for #{url}")

        @settings.account(id).tap do |account_settings|
          account_settings.url = url
          account_settings.username = username
          account_settings.user_id = user_id
        end

        account.url = url
        account.username = username
        account.user_id = user_id
        notify_items_changed

        true
      else
        false
      end
    end
  end

  # Removes an account from the secret service, the settings and the model.
  #
  # @return [Boolean] whether the account was removed
  def remove_account(id)
    @settings['accounts'].index(id).then do |index|
      if index
        @tokens.clear(id)
        @settings['accounts'] = @settings['accounts'].reject { |saved| saved == id }
        @settings.forget_account(id)

        @accounts.delete_at(index)
        @list_store.remove(index)
        notify_items_changed

        true
      else
        false
      end
    end
  end

  # Saves the user id an older account never recorded.
  #
  # Upstream binds account.user-id to its GSettings key, so assigning it on
  # the account persists it; here the write is explicit.
  def save_account_user_id(id, user_id)
    get_account_by_id(id).then do |account|
      if account
        @settings.account(id).user_id = user_id
        account.user_id = user_id
        true
      else
        false
      end
    end
  end

  # --- Reading ------------------------------------------------------------

  # Gets one account setting value.
  def get_account_setting(id, setting) = @settings.account(id)[setting]

  # Gets the account access token from the secret service.
  def get_account_token(id) = @tokens.lookup(id)

  private

    def load_saved_accounts
      @settings['accounts'].each do |id|
        Account.from_settings(id, @settings.account(id)).tap do |account|
          @accounts << account
          @list_store.append(account)
        end
      end
    end

    def notify_items_changed = @listeners.values.each(&:call)

  # TokenStore keeps the access tokens, keyed by account id.
  #
  # Upstream stores them with libsecret under a schema whose single attribute
  # is the account id. secret-tool, from the same project, writes into the
  # same collection with the same attribute, so a token stored here is the one
  # upstream would have stored. When secret-tool is not installed — no secret
  # service on the machine, or a stripped-down container — the tokens go to a
  # file in the user's data directory with 0600 permissions, because the
  # alternative is an app that cannot hold an account at all.
    class TokenStore
      Error = Class.new(StandardError)

      ATTRIBUTE = 'id'
      LABEL = 'Forge Sparks access token'
      SCHEMA = 'org.rubygtkproject.ForgeSparks'

      def initialize(path: nil)
        @path = path || default_path
      end

      # Whether the secret service can be reached. Asking secret-tool for its
      # version is cheaper than a lookup and tells us both that the tool is
      # installed and that it runs.
      def secret_tool?
        unless defined?(@secret_tool)
          @secret_tool = detect_secret_tool
        end
        @secret_tool
      end

      def store(id, token, label: LABEL)
        if secret_tool?
          store_in_secret_service(id, token, label)
        else
          write_file(read_file.merge(id.to_s => token.to_s))
        end
      end

      def lookup(id)
        if secret_tool?
          Open3.capture2(

            'secret-tool',
            'lookup',
            ATTRIBUTE,
            id.to_s,
            'xdg:schema',
            SCHEMA,

          ).then { |output, status| status.success? && !output.empty? ? output.chomp : nil }
        else
          read_file[id.to_s]
        end
      end

      def clear(id)
        if secret_tool?
          system(
            'secret-tool',
            'clear',
            ATTRIBUTE,
            id.to_s,
            'xdg:schema',
            SCHEMA,
            out: File::NULL,
            err: File::NULL,
          )
        else
          write_file(read_file.reject { |key, _| key == id.to_s })
        end
        true
      end

      private

        def detect_secret_tool
          system('secret-tool', '--version', out: File::NULL, err: File::NULL) || false
        rescue SystemCallError
          false
        end

        def store_in_secret_service(id, token, label)
          Open3.capture2e(
            'secret-tool',
            'store',
            '--label',
            label,
            ATTRIBUTE,
            id.to_s,
            'xdg:schema',
            SCHEMA,
            stdin_data: "#{token}\n",
          ).then do |output, status|
            unless status.success?
              raise Error, "Couldn't save the token: #{output.strip}"
            end
          end
          true
        end

        def default_path
          File.join(
            ENV.fetch('XDG_DATA_HOME', File.expand_path('~/.local/share')),
            'forge-sparks-rb',
            'tokens.json',
          )
        end

        def read_file
          File.exist?(@path) ? JSON.parse(File.read(@path)) : {}
        rescue JSON::ParserError => e
          warn "Error parsing #{@path}: #{e.message}"
          {}
        end

        def write_file(tokens)
          FileUtils.mkdir_p(File.dirname(@path))
          File.write(@path, JSON.pretty_generate(tokens))
          File.chmod(0o600, @path)
          true
        end
    end
end
