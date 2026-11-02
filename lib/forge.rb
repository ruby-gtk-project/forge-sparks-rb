# frozen_string_literal: true

require 'uri'

require_relative 'util'

# Forge is the base class every forge backend derives from.
#
# Ported from upstream's src/forges/forge.js: the class-level description of a
# forge (its name, whether it has instances, its default instance, the token
# scopes it needs and the help text for getting a token), the three operations
# a backend performs, and the request/response plumbing the subclasses share.
#
# Upstream signals failures by throwing the strings 'FailedForgeAuth',
# 'FailedTokenScopes' and 'Unexpected', which its dialogs switch on. Here they
# are the three error classes below, so a failure carries its own type and a
# rescue cannot mistake it for a successful string result.
#
class Forge
  Error = Class.new(StandardError)

  # The access token is not valid (401).
  FailedForgeAuth = Class.new(Error)
  # The access token is missing a scope the app needs (403).
  FailedTokenScopes = Class.new(Error)
  # A response arrived, but not one we can use.
  Unexpected = Class.new(Error)
  # A subclass did not implement one of the three operations.
  Abstract = Class.new(Error)

  class << self
    # Name (identifier) of the forge.
    def forge_name = 'github'

    # Name of the forge for display.
    def pretty_name = 'Github'

    # If the forge allows setting an instance url.
    def allow_instances? = false

    # Default URL (instance) for provider.
    def default_url = 'example.com'

    # Scopes needed.
    def scopes = []

    # Help text on how to get an access token for this forge.
    def token_text = ''
  end

  attr_reader :url, :token, :account, :account_name
  attr_accessor :user_id

  # @param url [String] the url of the forge
  # @param token [String] the access token
  # @param account [String, nil] account ID associated to the instance
  # @param user_id [Integer, nil] account user ID associated to the instance
  # @param account_name [String] account name (username@instance.tld)
  def initialize(url, token, account: nil, user_id: nil, account_name: '')
    @url = url
    @token = token
    @account = account
    @user_id = user_id
    @account_name = account_name
    @modified_since = ''
  end

  # Authorization header value.
  def authorization = "token #{@token}"

  # Get the username of the logged in user, which is how a token is validated
  # when an account is added.
  #
  # @return [Array(Integer, String)] the id and username
  def get_user = raise(Abstract, "#{self.class} must define #get_user")

  # Get all unread notifications for the logged in user.
  #
  # @return [Array<Notification>]
  def get_notifications = raise(Abstract, "#{self.class} must define #get_notifications")

  # Mark notifications as read.
  #
  # @param id [String, Integer, nil] the notification to mark, or nil for all
  # @return [Boolean] whether the operation succeeded
  def mark_as_read(id = nil) = raise(Abstract, "#{self.class} must define #mark_as_read")

  # Sends a request and reads the response.
  #
  # This is upstream's createMessage and readContents in one call: it encodes
  # the body as JSON, adds the authorization and Time-Zone headers, and hands
  # back the status alongside the parsed body.
  #
  # @return [Array(Integer, Object)] the HTTP status and the parsed body
  def request(method, url, data: nil, headers: {})
    Util.session.send_and_read(
      method,
      url,
      data:    data,
      headers: headers.merge('Authorization' => authorization, 'Time-Zone' => 'UTC'),
    ).then do |status, body|
      warn "#{url} response resulted in #{status}"
      [status, read_contents(body)]
    end
  end

  # Reads the contents of a response, as upstream's readContents does: an
  # empty body is an empty list, not an error.
  def read_contents(body) = Util.session.read_contents(body)

  # Create a more unique ID using the forge account ID.
  def format_id(id) = "#{@account}-#{id}"

  # Build a request URI from multiple parts.
  #
  # @param host [String] the URI host
  # @param path [String] the URI path
  # @param query [Hash] the URI query
  # @return [String] the resulting URI
  def self.build_uri(host, path, query = {})
    (path.start_with?('/') ? path : "/#{path}").then do |full_path|
      URI::HTTPS.build(host: host, path: full_path).tap do |uri|
        unless query.empty?
          uri.query = query.map { |key, value| "#{key}=#{value}" }.join('&').tr(' ', '+')
        end
      end.to_s
    end
  end
end
