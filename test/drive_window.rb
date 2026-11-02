# frozen_string_literal: true

# Drives the main window and the dialogs it opens.
#
# Run it:
#   xvfb-run -a ruby test/drive_window.rb
#
# Set DRIVE_SHOTS to keep the screenshots somewhere you can look at them.

require 'tmpdir'
require 'fileutils'

scratch = Dir.mktmpdir('forge-sparks-drive')
ENV['XDG_CONFIG_HOME'] = File.join(scratch, 'config')
ENV['XDG_DATA_HOME'] = File.join(scratch, 'data')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'main'
require_relative 'gtk_driver'

def fake_notification(id:, title:, type:, state:, repository:, minutes_ago:)
  Notification.new(
    id:           id,
    type:         type,
    unread:       true,
    updated_at:   (Time.now.utc - (minutes_ago * 60)).iso8601,
    state:        state,
    title:        title,
    repository:   repository,
    url:          "https://example.com/#{id}",
    account_name: 'octocat@github.com',
  )
end

application = Application.new

shots = ENV.fetch('DRIVE_SHOTS', File.join(scratch, 'shots'))

GtkDriver.drive(application, shots: shots) do |d, app|
  d.window { app.window }

  d.step('the window comes up on the setup page') do
    d.check('window exists') { !app.window.nil? }
    d.check('no accounts configured') { app.accounts.n_items.zero? }
    d.check('setup page showing') { app.window.main_stack.visible_child_name == 'setup' }
    d.check('welcome title set') { app.window.setup_page.title == 'Welcome to Forge Sparks' }
    d.check('add button is a pill') { app.window.add_account_button.css_classes.include?('pill') }
    d.check('app icon loaded') { !app.window.setup_page.paintable.nil? }
    d.shot('01-setup')
  end

  d.step('notifications render in the list') do
    app.window.show_notifications(
      [
        fake_notification(
          id:          'acct-1',
          title:       'Fix the thing',
          type:        'Issue',
          state:       'open',
          repository:  'octocat/hello',
          minutes_ago: 5,
        ),
        fake_notification(
          id:          'acct-2',
          title:       'Merge the other thing',
          type:        'PullRequest',
          state:       'draft',
          repository:  'octocat/world',
          minutes_ago: 1500,
        ),
        fake_notification(
          id:          'acct-3',
          title:       'Release v2',
          type:        'Release',
          state:       nil,
          repository:  'octocat/world',
          minutes_ago: 20_000,
        ),
      ],
    )
  end

  d.step('the list page shows three rows, newest first') do
    d.check('model holds three') { app.window.model.n_items == 3 }
    d.check('notifications page showing') { app.window.main_stack.visible_child_name == 'notifications' }
    d.check('list page showing') { app.window.notifications_stack.visible_child_name == 'list' }
    d.check('mark all as read is visible') { app.window.mark_as_read_button.visible? }
    d.check('newest first') { app.window.model.sorted.first.title == 'Fix the thing' }
    d.check('a row was built') { !app.window.notifications_list.get_row_at_index(0).nil? }
    d.shot('02-notifications')
  end

  d.step('icons and dates come from the model') do
    app.window.model.sorted.then do |sorted|
      d.check('issue icon') { sorted[0].icon_name == 'issue-symbolic' }
      d.check('draft merge icon') { sorted[1].icon_name == 'merge-draft-symbolic' }
      d.check('release icon') { sorted[2].icon_name == 'tag-symbolic' }
      d.check('issue icon file exists') { !sorted[0].icon_path.nil? }
      d.check('relative date reads as minutes') { Util.relative_date(sorted[0].date_time) == '5 minutes ago' }
    end
  end

  d.step('the empty page comes back when the list is cleared') do
    app.window.show_notifications([])
  end

  d.step('the all-done illustration is showing') do
    d.check('empty page showing') { app.window.notifications_stack.visible_child_name == 'empty' }
    d.check('mark all as read is hidden') { !app.window.mark_as_read_button.visible? }
    d.check('illustration loaded') { !app.window.empty_picture.paintable.nil? }
    d.shot('03-empty')
  end

  d.step('the add account dialog opens') do
    app.window.add_account_button.activate
  end

  d.step('the account dialog is filled in for a new account') do
    AccountDialog.new(nil, accounts: app.accounts).tap do |dialog|
      dialog.build
      dialog.present(app.window)
      @dialog = dialog
    end
  end

  d.step('the account dialog validates as the user types') do
    d.check('forge row is visible for a new account') { @dialog.forge_row.visible? }
    d.check('four forges listed') { @dialog.forge_row.model.n_items == 4 }
    d.check('instance row visible for forgejo') { @dialog.instance_row.visible? }
    d.check('instance defaults to codeberg.org') { @dialog.instance_row.text == 'codeberg.org' }
    d.check('help text is set') { @dialog.help_label.label.include?('access token') }
    d.check('save starts insensitive') { !@dialog.save_button.sensitive? }
    @dialog.access_token_row.text = 'a-token'
    d.shot('04-account-dialog', @dialog.child)
  end

  d.step('a token makes the dialog saveable') do
    d.check('save is now sensitive') { @dialog.save_button.sensitive? }
    d.check('remove group hidden while adding') { !@dialog.remove_group.visible? }
    @dialog.forge_row.selected = 2
  end

  d.step('choosing GitHub swaps the help text and the instance') do
    d.check('instance now github.com') { @dialog.instance_row.text == 'github.com' }
    d.check('help text mentions classic tokens') { @dialog.help_label.label.include?('classic') }
    d.shot('05-account-dialog-github', @dialog.child)
    @dialog.close
  end

  d.step('the preferences dialog opens') do
    PreferencesDialog.new(settings: Util.settings).tap do |dialog|
      dialog.build
      dialog.present(app.window)
      @prefs = dialog
    end
  end

  d.step('the preferences reflect the settings') do
    d.check('background row titled') { @prefs.background_row.title == 'Keep Running in Background' }
    d.check('startup switch off') { !@prefs.startup_switch.active? }
    d.check('start hidden row insensitive') { !@prefs.hidden_row.sensitive? }
    @prefs.startup_switch.active = true
  end

  d.step('turning on autostart writes the desktop file') do
    d.check('autostart saved') { Util.settings['autostart'] == true }
    d.check('desktop file written') { File.exist?(Util.autostart_file) }
    d.check('start hidden row now sensitive') { @prefs.hidden_row.sensitive? }
    d.shot('06-preferences', @prefs.child)
    @prefs.startup_switch.active = false
  end

  d.step('turning it off removes the desktop file') do
    d.check('autostart cleared') { Util.settings['autostart'] == false }
    d.check('desktop file gone') { !File.exist?(Util.autostart_file) }
    @prefs.close
  end

  d.step('the accounts dialog opens') do
    AccountsDialog.new(accounts: app.accounts).tap do |dialog|
      dialog.build
      dialog.present(app.window)
      @accounts_dialog = dialog
    end
  end

  d.step('the accounts dialog shows its empty page') do
    d.check('empty page showing') { @accounts_dialog.accounts_stack.visible_child_name == 'empty' }
    d.check('empty page titled') { @accounts_dialog.empty_page.title == 'No Accounts' }
    d.shot('07-accounts', @accounts_dialog.child)
    @accounts_dialog.close
  end

  d.step('the shortcuts dialog opens') do
    app.window.activate_action('show-help-overlay', nil)
  end

  d.step('the about dialog opens') do
    app.about_dialog.then do |about|
      d.check('about names the app') { about.application_name == 'Forge Sparks' }
      d.check('about carries a version') { !about.version.to_s.empty? }
    end
    app.app.activate_action('about', nil)
  end

  d.step('the app still has its actions and accelerators') do
    Application::ACTIONS.each_key do |name|
      d.check("app.#{name} exists") { !app.app.lookup_action(name).nil? }
    end
    Application::ACCELS.each_key do |action|
      d.check("#{action} has an accelerator") { !app.app.get_accels_for_action(action).empty? }
    end
  end

  d.step('the window settings round-trip') do
    Util.settings.remember(app.window)
    d.check('window size saved') { Util.settings['window-size'].length == 2 }
    d.check('settings file written') { File.exist?(Util.settings.location) }
  end
end

FileUtils.remove_entry(scratch)
