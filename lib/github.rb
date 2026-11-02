# frozen_string_literal: true

require 'time'

require_relative 'forge'
require_relative 'notification'
require_relative 'translation'

# GitHub is the GitHub backend.
#
# Ported from upstream's src/forges/github.js: the token help text, the three
# operations, the subject lookup that turns a notification into the URL and
# state the row shows, and the notification referrer id that makes GitHub's
# web UI open the notification shelf.
#
class GitHub < Forge
  extend Translation

  TOKEN_URL = 'https://github.com/settings/tokens'
  TOKEN_HELP_URL = 'https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/' \
                   'managing-your-personal-access-tokens#creating-a-personal-access-token-classic'

  # The subject types whose notification has no API subject to look up, and
  # the repository-relative page to open instead.
  SUBJECT_FALLBACKS = {
    'RepositoryInvitation'             => 'invitations',
    'RepositoryVulnerabilityAlert'     => 'network/dependencies',
    'RepositoryDependabotAlertsThread' => 'security/dependabot',
    'CheckSuite'                       => 'actions',
    # https://github.com/orgs/community/discussions/15252
    'Discussion'                       => 'discussions',
  }.freeze

  # The subject types that have no subject url to request at all.
  NO_SUBJECT_TYPES = %w[RepositoryInvitation RepositoryVulnerabilityAlert].freeze

  class << self
    def forge_name = 'github'
    def pretty_name = 'GitHub'
    def allow_instances? = true
    def default_url = 'github.com'
    def scopes = %w[notifications read:user].freeze

    def token_text
      [
        format(
          _(
            'You can generate a new personal access token from <a href="%s">GitHub developer ' \
            'settings</a>. For more information, see "<a href="%s">Creating a personal access ' \
            'token</a>".',
          ),
          TOKEN_URL,
          TOKEN_HELP_URL,
        ),
        "\n\n",
        # Translators: GitHub access token help
        _(
          'Forge Sparks requires a <b>classic</b> access token (for general use) with the ' \
          '<i>notifications</i> and <i>read:user</i> scopes granted.',
        ),
        ' ',
        # Translators: GitHub access token help
        _(
          'If you’re working with private repositories, you’ll also need to grant the full ' \
          '<i>repo</i> scope.',
        ),
      ].join
    end
  end

  def get_user
    request('GET', build_uri('user')).then do |status, contents|
      check_user_status(status, contents)

      # Test notifications capabilities.
      request('GET', build_uri('notifications')).then do |notifications_status, _|
        if notifications_status == 403
          raise FailedTokenScopes, 'The token cannot read notifications'
        end
      end

      [contents['id'], contents['login']]
    end
  end

  def get_notifications
    request('GET', build_uri('notifications')).then do |status, contents|
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
      mark_all_as_read
    else
      request('PATCH', build_uri("/notifications/threads/#{id}")).then do |status, _|
        # If Reset-Content.
        status == 205
      end
    end
  end

  # Build a request URI with the GitHub API url as host.
  def build_uri(path, query = {}) = Forge.build_uri("api.#{@url}", path, query)

  private

    def check_user_status(status, contents)
      case status
      when 401
        raise FailedForgeAuth, 'The access token is not valid'
      when 403
        raise FailedTokenScopes, 'The access token is missing a scope'
      when 200
        unless contents.is_a?(Hash) && contents.key?('login') && contents.key?('id')
          raise Unexpected, 'Could not find the username in the response'
        end
      else
        raise Unexpected, "Unexpected status #{status}"
      end
    end

    def mark_all_as_read
      request(
        'PUT',
        build_uri('notifications'),
        data: { 'last_read_at' => Time.now.utc.iso8601, 'read' => true },
      ).then do |status, _|
        # If Accepted or Reset-Content.
        [202, 205].include?(status)
      end
    end

    # One notification from one response item, or nil when the subject lookup
    # failed — upstream logs and skips the item for the same reason.
    def build_notification(item)
      subject_info(item).then do |info|
        Notification.new(
          id:           format_id(item['id']),
          type:         item.dig('subject', 'type'),
          unread:       item['unread'],
          updated_at:   info['updated_at'] || item['updated_at'],
          state:        info['state'].to_s.empty? ? nil : info['state'],
          title:        item.dig('subject', 'title'),
          repository:   item.dig('repository', 'full_name'),
          url:          info['url'],
          account_name: @account_name,
        )
      end
    rescue StandardError => e
      warn "Could not read notification #{item['id']}: #{e.message}"
      nil
    end

    # Get extra info from the notification subject: the URL to open and the
    # state the row's icon colours itself by.
    def subject_info(item)
      { 'url' => item.dig('repository', 'html_url'), 'state' => '' }.then do |info|
        if skip_subject?(item)
          fallback_subject_info(item, info)
        else
          request_subject_info(item, info)
        end
      end
    end

    def skip_subject?(item)
      NO_SUBJECT_TYPES.include?(item.dig('subject', 'type')) ||
        item.dig('subject', 'url').to_s.empty?
    end

    def fallback_subject_info(item, info)
      SUBJECT_FALLBACKS[item.dig('subject', 'type')].then do |page|
        if page
          info.merge('url' => "#{item.dig('repository', 'html_url')}/#{page}")
        else
          info
        end
      end
    end

    def request_subject_info(item, info)
      request('GET', item.dig('subject', 'url')).then do |status, contents|
        if status == 200
          subject_info_from_contents(item, info, contents)
        else
          # Fallback URL if the request failed, probably a private repo.
          info.merge('url' => private_repo_url(item))
        end
      end
    end

    def subject_info_from_contents(item, info, contents)
      info.merge(
        'state' => subject_state(item, contents),
        'url'   => referrer_url(item, comment_url(item, contents['html_url'])),
      )
    end

    # A pull request's state is more than the API's own state field: a draft
    # and a closed-but-never-merged request each read differently.
    def subject_state(item, contents)
      contents['state'].then do |state|
        if item.dig('subject', 'type') == 'PullRequest'
          pull_request_state(contents, state)
        else
          state
        end
      end
    end

    def pull_request_state(contents, state)
      if contents['draft']
        'draft'
      elsif state == 'closed' && contents['merged_at'].nil?
        'denied'
      else
        state
      end
    end

    def private_repo_url(item)
      case item.dig('subject', 'type')
      when 'PullRequest'
        "#{item.dig('repository', 'html_url')}/pulls"
      when 'Issue'
        "#{item.dig('repository', 'html_url')}/issues"
      else
        item.dig('repository', 'url')
      end
    end

    # The comment the notification is about, when it is about one: a mention
    # or a review request points at the latest comment, not the thread.
    def comment_url(item, default_url)
      if commentable?(item)
        latest_comment_url(item.dig('subject', 'latest_comment_url')) || default_url
      else
        default_url
      end
    end

    def commentable?(item)
      item['reason'] != 'subscribed' &&
        %w[Issue PullRequest].include?(item.dig('subject', 'type'))
    end

    # Get the HTML url of the latest comment, e.g.
    # https://github.com/user/repo/issues/1#issuecomment-1529954726
    def latest_comment_url(url)
      if url.to_s.empty?
        nil
      else
        request('GET', url).then do |_status, contents|
          contents.is_a?(Hash) ? contents['html_url'] : nil
        end
      end
    end

    # Add the notification referrer to the url, which is what makes GitHub's
    # web UI show the notification shelf. Only GitHub itself understands it,
    # so the Gitea and Forgejo subclasses leave the url alone.
    def referrer_url(item, url)
      if self.class.forge_name == 'github'
        append_referrer(url, notification_referrer_id(item['id']))
      else
        url
      end
    end

    def append_referrer(url, referrer)
      url.to_s.rindex('#').then do |hash_position|
        if hash_position.nil?
          "#{url}?notification_referrer_id=#{referrer}"
        else
          "#{url[0, hash_position]}?notification_referrer_id=#{referrer}#{url[hash_position..]}"
        end
      end
    end

    # Based on Daniel Lamando's snippet
    # https://github.com/sindresorhus/notifier-for-github/issues/268
    # pack('m0') is strict base64 without a trailing newline, which is what
    # GLib.base64_encode produces; the base64 library is no longer a default
    # gem in Ruby 3.4.
    def notification_referrer_id(id)
      ["018:NotificationThread#{id}:#{@user_id}"].pack('m0')
    end
end
