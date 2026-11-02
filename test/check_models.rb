# frozen_string_literal: true

# Checks the parts of the port that need no widget: the settings file, the
# accounts model, the forge backends and the notification model.
#
# Run it:
#   xvfb-run -a ruby test/check_models.rb
#
# (Requiring the port loads gtk4, which wants a display even for the models.)

require 'tmpdir'
require 'json'

scratch = Dir.mktmpdir('forge-sparks-checks')
ENV['XDG_CONFIG_HOME'] = File.join(scratch, 'config')
ENV['XDG_DATA_HOME'] = File.join(scratch, 'data')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'main'

@checks = 0
@failures = []

def check(description)
  @checks += 1
  yield.then do |ok|
    puts(ok ? "  ok   #{description}" : "  FAIL #{description}")
    unless ok
      @failures << description
    end
  end
rescue StandardError => e
  puts "  FAIL #{description} (#{e.class}: #{e.message})"
  @failures << description
end

def section(name) = puts("\n#{name}")

# A session that answers from a script of [status, body] pairs, keyed by the
# url it is asked for, so the backends can be driven without a network.
class FakeSession
  def initialize(responses)
    @responses = responses
    @requests = []
  end

  attr_reader :requests

  def send_and_read(method, url, data: nil, headers: {})
    @requests << { method: method, url: url, data: data, headers: headers }
    @responses.fetch(url, [404, '']).then do |(status, body)|
      [status, body.is_a?(String) ? body : JSON.generate(body)]
    end
  end

  def read_contents(body) = body.to_s.empty? ? [] : JSON.parse(body)
end

def with_session(responses)
  FakeSession.new(responses).tap do |session|
    Util.instance_variable_set(:@session, session)
    yield session
  ensure
    Util.instance_variable_set(:@session, nil)
  end
end

# A token store that keeps the tokens in memory, so the checks never touch
# the user's secret service.
class MemoryTokens
  def initialize = @tokens = {}
  def store(id, token, label: nil) = @tokens[id] = token
  def lookup(id) = @tokens[id]
  def clear(id) = @tokens.delete(id) || true
end

section 'Settings'

Settings.new(path: File.join(scratch, 'settings.json')).tap do |settings|
  check('defaults come from the schema') { settings['window-size'] == [780, 480] }
  check('accounts start empty') { settings['accounts'] == [] }
  settings['hide-on-close'] = true
  check('values round-trip through the file') do
    Settings.new(path: settings.location)['hide-on-close'] == true
  end

  settings.account('abc').tap do |account|
    check('account defaults come from the account schema') { account.forge == 'github' }
    account.url = 'codeberg.org'
    account.username = 'octocat'
    account.user_id = 7
  end

  check('account values round-trip') do
    Settings.new(path: settings.location).account('abc').url == 'codeberg.org'
  end

  settings.forget_account('abc')
  check('forgetting an account clears its keys') { settings.account_values('abc').empty? }
end

section 'AccountsManager'

Settings.new(path: File.join(scratch, 'accounts.json')).then do |settings|
  AccountsManager.new(settings: settings, tokens: MemoryTokens.new).tap do |accounts|
    check('starts empty') { accounts.n_items.zero? }

    accounts.save_account(
      forge: 'github', url: 'github.com', user_id: 1, username: 'octocat', token: 'secret',
    ).then do |id|
      check('the account is in the model') { accounts.n_items == 1 }
      check('the id is in the settings') { settings['accounts'] == [id] }
      check('the display name is username@instance') do
        accounts.get_account_by_id(id).display_name == 'octocat@github.com'
      end
      check('the token went to the store') { accounts.get_account_token(id) == 'secret' }
      check('one account is not multiple') { !accounts.multiple? }

      accounts.update_account(id, url: 'github.com', user_id: 2, username: 'monalisa', token: 'other')
      check('updating changes the display name') do
        accounts.get_account_by_id(id).display_name == 'monalisa@github.com'
      end
      check('updating replaces the token') { accounts.get_account_token(id) == 'other' }
      check('updating saves the user id') { settings.account(id).user_id == 2 }

      accounts.save_account_user_id(id, 42)
      check('a late user id is saved') { settings.account(id).user_id == 42 }

      check('removing reports success') { accounts.remove_account(id) == true }
      check('removing empties the model') { accounts.n_items.zero? }
      check('removing clears the settings') { settings['accounts'] == [] }
      check('removing clears the token') { accounts.get_account_token(id).nil? }
    end

    accounts.on_items_changed { @notified_of_change = true }
    accounts.save_account(forge: 'gitea', url: 'gitea.com', user_id: 3, username: 'tea', token: 't')
    check('listeners hear about changes') { @notified_of_change == true }
  end
end

section 'Forges registry'

check('four forges are registered') { Forges.all.length == 4 }
check('a forge is found by name') { Forges['gitlab'] == GitLab }
check('an unknown forge is nil') { Forges['svn'].nil? }
check('an id splits into account and notification') do
  Forges.extract_id('123e4567-e89b-12d3-a456-426614174000-987') ==
    ['123e4567-e89b-12d3-a456-426614174000', '987']
end

section 'Forge URLs and classes'

check('github builds an api host') do
  GitHub.new('github.com', 't').build_uri('notifications') == 'https://api.github.com/notifications'
end
check('github adds a query') do
  GitHub.new('github.com', 't').build_uri('notifications', 'all' => true) ==
    'https://api.github.com/notifications?all=true'
end
check('gitea prepends api v1') do
  Gitea.new('codeberg.org', 't').build_uri('/notifications/threads/4') ==
    'https://codeberg.org/api/v1/notifications/threads/4'
end
check('gitlab prepends api v4') do
  GitLab.new('gitlab.com', 't').build_uri('todos') == 'https://gitlab.com/api/v4/todos'
end
check('forgejo defaults to codeberg') { Forgejo.default_url == 'codeberg.org' }
check('forgejo inherits the gitea api') do
  Forgejo.new('codeberg.org', 't').build_uri('notifications') ==
    'https://codeberg.org/api/v1/notifications'
end
check('github authorizes with a token header') do
  GitHub.new('github.com', 'abc').authorization == 'token abc'
end
check('gitlab authorizes with a bearer token') do
  GitLab.new('gitlab.com', 'abc').authorization == 'Bearer abc'
end
check('every forge has help text') do
  Forges.all.all? { |forge| forge.token_text.length > 40 }
end
check('github asks for the notifications scope') { GitHub.scopes.include?('notifications') }
check('gitea asks for write:notification') { Gitea.scopes.include?('write:notification') }

section 'GitHub backend'

with_session(
  'https://api.github.com/user'          => [200, { 'id' => 9, 'login' => 'octocat' }],
  'https://api.github.com/notifications' => [200, []],
) do
  check('get_user returns the id and login') do
    GitHub.new('github.com', 't').get_user == [9, 'octocat']
  end
end

with_session('https://api.github.com/user' => [401, '']) do
  check('a 401 is an auth failure') do
    begin
      GitHub.new('github.com', 't').get_user
      false
    rescue Forge::FailedForgeAuth
      true
    end
  end
end

with_session('https://api.github.com/user' => [403, '']) do
  check('a 403 is a scope failure') do
    begin
      GitHub.new('github.com', 't').get_user
      false
    rescue Forge::FailedTokenScopes
      true
    end
  end
end

with_session(
  'https://api.github.com/notifications'               => [
    200,
    [
      {
        'id'         => '101',
        'unread'     => true,
        'updated_at' => '2024-05-01T10:00:00Z',
        'reason'     => 'subscribed',
        'subject'    => {
          'type'  => 'PullRequest',
          'title' => 'Add a thing',
          'url'   => 'https://api.github.com/repos/octocat/hello/pulls/3',
        },
        'repository' => {
          'full_name' => 'octocat/hello',
          'html_url'  => 'https://github.com/octocat/hello',
          'url'       => 'https://api.github.com/repos/octocat/hello',
        },
      },
    ],
  ],
  'https://api.github.com/repos/octocat/hello/pulls/3' => [
    200,
    {
      'state'     => 'closed',
      'merged_at' => nil,
      'draft'     => false,
      'html_url'  => 'https://github.com/octocat/hello/pull/3',
    },
  ],
) do
  GitHub.new('github.com', 't', account: 'acct', user_id: 5).get_notifications.then do |notifications|
    check('one notification was built') { notifications.length == 1 }
    check('the id carries the account') { notifications.first.id == 'acct-101' }
    check('a closed unmerged pull is denied') { notifications.first.state == 'denied' }
    check('the icon follows the state') { notifications.first.icon_name == 'merge-denied-symbolic' }
    check('the url carries the referrer') do
      notifications.first.url.include?('notification_referrer_id=')
    end
    check('the repository is the full name') { notifications.first.repository == 'octocat/hello' }
  end
end

with_session(
  'https://api.github.com/notifications' => [
    200,
    [
      {
        'id'         => '202',
        'unread'     => true,
        'updated_at' => '2024-05-01T10:00:00Z',
        'subject'    => { 'type' => 'RepositoryInvitation', 'title' => 'You are invited' },
        'repository' => {
          'full_name' => 'octocat/hello',
          'html_url'  => 'https://github.com/octocat/hello',
        },
      },
    ],
  ],
) do
  GitHub.new('github.com', 't', account: 'acct').get_notifications.first.then do |notification|
    check('an invitation points at the invitations page') do
      notification.url == 'https://github.com/octocat/hello/invitations'
    end
    check('an unknown type falls back to the default icon') do
      notification.icon_name == Notification::DEFAULT_ICON
    end
  end
end

section 'GitLab backend'

with_session(
  'https://gitlab.com/api/v4/todos' => [
    200,
    [
      {
        'id'          => 7,
        'target_type' => 'MergeRequest',
        'state'       => 'pending',
        'updated_at'  => '2024-05-01T10:00:00Z',
        'target'      => { 'state' => 'opened', 'title' => 'Ship it' },
        'project'     => { 'path_with_namespace' => 'group/project' },
        'target_url'  => 'https://gitlab.com/group/project/-/merge_requests/1',
      },
    ],
  ],
) do
  GitLab.new('gitlab.com', 't', account: 'acct').get_notifications.first.then do |notification|
    check('a todo becomes a notification') { notification.title == 'Ship it' }
    check('a pending todo is unread') { notification.unread? }
    check('the project is the repository') { notification.repository == 'group/project' }
    check('an open merge request keeps the merge icon') do
      notification.icon_name == 'merge-symbolic'
    end
  end
end

section 'Notification model'

Notification.new(
  id:         'a-1',
  type:       'Issue',
  state:      'closed',
  title:      'Done',
  repository: 'octocat/hello',
  url:        'https://example.com',
  updated_at: '2024-05-01T10:00:00Z',
).tap do |notification|
  check('a closed issue is done') { notification.icon_name == 'issue-done-symbolic' }
  check('the icon file is on disk') { File.exist?(notification.icon_path) }
  check('the timestamp comes from the date') { notification.timestamp == 1_714_557_600 }
  check('a desktop notification is built') do
    !notification.gio_notification(hidden: true).nil?
  end
end

check('an unparseable date does not raise') do
  Notification.new(id: 'x', updated_at: 'not a date').timestamp.zero?
end

section 'NotificationsList'

NotificationsList.new.tap do |list|
  list.append(Notification.new(id: 'a', updated_at: '2024-05-01T10:00:00Z', title: 'older'))
  list.append(Notification.new(id: 'b', updated_at: '2024-06-01T10:00:00Z', title: 'newer'))

  check('both are in the list') { list.n_items == 2 }
  check('sorted puts the newest first') { list.sorted.first.title == 'newer' }
  check('an item is found by id') { list.get_by_id('a').title == 'older' }
  list.remove_by_id('a')
  check('removing by id drops it') { list.n_items == 1 }
  list.clear
  check('clearing empties the list') { list.n_items.zero? }
end

section 'Relative dates'

Time.utc(
  2024,
  5,
  1,
  12,
  0,
  0,
).then do |now|
  check('seconds read as now') { Util.relative_date(now - 10, now: now) == 'now' }
  check('one minute is singular') { Util.relative_date(now - 60, now: now) == '1 minute ago' }
  check('minutes are plural') { Util.relative_date(now - (300), now: now) == '5 minutes ago' }
  check('hours') { Util.relative_date(now - (3 * 3600), now: now) == '3 hours ago' }
  check('one day reads as yesterday') { Util.relative_date(now - (24 * 3600), now: now) == 'yesterday' }
  check('days') { Util.relative_date(now - (3 * 24 * 3600), now: now) == '3 days ago' }
  check('weeks') { Util.relative_date(now - (14 * 24 * 3600), now: now) == '2 weeks ago' }
  check('this year falls back to a date') do
    Util.relative_date(now - (60 * 24 * 3600), now: now) == 'on Mar 02'
  end
  check('another year carries the year') do
    Util.relative_date(now - (400 * 24 * 3600), now: now) == 'on 28 Mar, 2023'
  end
end

puts
puts "#{@checks - @failures.length} of #{@checks} checks passed"
@failures.each { |failure| puts "  failed: #{failure}" }
puts(@failures.empty? ? 'CHECKS OK' : "CHECKS FAILED (#{@failures.length})")
exit(@failures.empty? ? 0 : 1)
