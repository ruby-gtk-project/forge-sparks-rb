# frozen_string_literal: true

require 'time'

require_relative 'forge'
require_relative 'github'

# Gitea is the Gitea backend.
#
# Ported from upstream's src/forges/gitea.js. Gitea has a GitHub compatible
# API, so this derives from the GitHub backend and tweaks the two places they
# differ: the API path, and marking everything as read, which Gitea takes as
# url queries rather than a request body.
#
class Gitea < GitHub
  class << self
    def forge_name = 'gitea'
    def pretty_name = 'Gitea'
    def allow_instances? = true
    def default_url = 'gitea.com'
    def scopes = %w[read:issue write:notification read:user].freeze

    def token_text
      [
        'To generate a new access token from your instance, go to Settings → Applications and ' \
        'generate a new token.',
        "\n\n",
        'Forge Sparks requires the <i>read:issue</i>, <i>write:notification</i> and ' \
        '<i>read:user</i> scopes granted.',
      ].join
    end
  end

  def mark_as_read(id = nil)
    if id.nil?
      mark_all_as_read
    else
      request('PATCH', build_uri("/notifications/threads/#{id}")).then do |status, _|
        # If Reset-Content.
        status == 205
      end
    end
  end

  # Build a request URI with the instance url as host and api v1 prepended.
  #
  # The leading slash is dropped from the path first: upstream concatenates
  # '/api/v1/' with a path that sometimes starts with its own slash, and the
  # doubled slash it produces is not something an instance has to accept.
  def build_uri(path, query = {}) = Forge.build_uri(@url, "/api/v1/#{path.delete_prefix('/')}", query)

  private

    # Gitea differs from GitHub here: the parameters are url queries, and a
    # successful call answers Reset-Content rather than Accepted.
    def mark_all_as_read
      request(
        'PUT',
        build_uri('notifications', 'last_read_at' => Time.now.utc.iso8601, 'all' => true),
      ).then do |status, _|
        status == 205
      end
    end
end
