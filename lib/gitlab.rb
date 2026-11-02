# frozen_string_literal: true

require_relative 'forge'
require_relative 'notification'
require_relative 'translation'

# GitLab is the GitLab backend.
#
# Ported from upstream's src/forges/gitlab.js. GitLab has no notifications
# endpoint; its todos are the equivalent, and marking one as read is marking a
# todo as done. The token is a Bearer token rather than GitHub's "token".
#
class GitLab < Forge
  extend Translation

  class << self
    def forge_name = 'gitlab'
    def pretty_name = 'GitLab'
    def allow_instances? = true
    def default_url = 'gitlab.com'
    def scopes = %w[api].freeze

    def token_text
      [
        # Translators: GitLab access token help
        _(
          'To generate a new access token from your instance, go to Preferences → Access ' \
          'Tokens and generate a new token.',
        ),
        "\n\n",
        # Translators: GitLab access token help
        _(
          'Forge Sparks needs <i>read_api</i> scope to read notifications or full <i>api</i> ' \
          'scope to also mark todos as done.',
        ),
      ].join
    end
  end

  def authorization = "Bearer #{@token}"

  def get_user
    request('GET', build_uri('user')).then do |status, contents|
      case status
      when 401
        raise FailedForgeAuth, 'The access token is not valid'
      when 403
        raise FailedTokenScopes, 'The access token is missing a scope'
      when 200
        unless contents.is_a?(Hash) && contents.key?('username') && contents.key?('id')
          raise Unexpected, 'Could not find the username in the response'
        end
      else
        raise Unexpected, "Unexpected status #{status}"
      end

      [contents['id'], contents['username']]
    end
  end

  def get_notifications
    request('GET', build_uri('todos')).then do |status, contents|
      case status
      when 200
        contents.filter_map { |item| build_notification(item) }
      when 401
        raise FailedForgeAuth, 'The access token was revoked or expired'
      when 403
        raise FailedTokenScopes, 'The access token is missing a scope'
      else
        raise Unexpected, "Unexpected status #{status}"
      end
    end
  end

  def mark_as_read(id = nil)
    if id.nil?
      request('POST', build_uri('todos/mark_as_done')).then do |status, _|
        # If No Content.
        status == 204
      end
    else
      request('POST', build_uri("todos/#{id}/mark_as_done")).then do |status, _|
        # If OK.
        status == 200
      end
    end
  end

  # Build a request URI with the instance url as host and api v4 prepended.
  def build_uri(path, query = {}) = Forge.build_uri(@url, "/api/v4/#{path.delete_prefix('/')}", query)

  private

    def build_notification(item)
      Notification.new(
        id:           format_id(item['id']),
        type:         item['target_type'],
        unread:       item['state'] == 'pending',
        updated_at:   item['updated_at'],
        state:        item.dig('target', 'state'),
        title:        item.dig('target', 'title'),
        repository:   repository_name(item),
        url:          item['target_url'],
        account_name: @account_name,
      )
    rescue StandardError => e
      warn "Could not read todo #{item['id']}: #{e.message}"
      nil
    end

    # A todo on a project names the project; one that is not — a todo on a
    # snippet or a personal mention — names its author instead.
    def repository_name(item)
      if item.key?('project')
        item.dig('project', 'path_with_namespace')
      else
        item.dig('author', 'name')
      end
    end
end
