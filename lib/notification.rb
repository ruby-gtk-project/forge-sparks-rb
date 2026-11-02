# frozen_string_literal: true

require 'time'
require 'gtk4'

require_relative 'util'

# Notification is one notification from a forge.
#
# Ported from upstream's src/model/notification.js, including its icon map
# (src/icons/*.svg, reachable as data/icons/*.svg here) and the Gio.Notification
# it hands the desktop.
#
# Upstream declares every field as a GObject property so its Blueprint
# templates can bind to them; the rows in this port are built in Ruby, so the
# fields are plain attributes on a GLib::Object subclass. It still has to be a
# GLib::Object: Gio::ListStore only stores GObjects, and that is the model the
# window sorts and the list box renders.
#
class Notification < GLib::Object
  type_register

  DEFAULT_ICON = 'preferences-system-details-symbolic'

  # Upstream's iconName getter, as data: notification type, then state.
  ICONS = {
    'Issue'      => {
      'closed' => 'issue-done-symbolic',
      :default => 'issue-symbolic',
    },
    'Pull'       => {
      'closed' => 'merge-merged-symbolic',
      'draft'  => 'merge-draft-symbolic',
      'denied' => 'merge-denied-symbolic',
      :default => 'merge-symbolic',
    },
    'Discussion' => { :default => 'discussion-symbolic' },
    'Release'    => { :default => 'tag-symbolic' },
    'Commit'     => { :default => 'commit-symbolic' },
  }.freeze

  # The three names the forges use for the same thing.
  PULL_TYPES = %w[Pull PullRequest MergeRequest].freeze

  attr_accessor :id, :type, :unread, :updated_at, :state, :title, :repository, :url, :account_name

  def initialize(id: nil, type: nil, unread: false, updated_at: nil, state: nil,
                 title: nil, repository: nil, url: nil, account_name: nil)
    super()
    @id = id
    @type = type
    @unread = unread
    @updated_at = updated_at
    @state = state
    @title = title
    @repository = repository
    @url = url
    @account_name = account_name
  end

  def unread? = @unread == true

  # Notification datetime, parsed from the ISO 8601 string the forge sent.
  #
  # Upstream memoizes the GLib.DateTime it parses once; an unparseable or
  # missing date falls back to the epoch so a bad field cannot take the whole
  # list down, which is also why the row still renders.
  def date_time = @date_time ||= parse_updated_at

  # Notification timestamp — what the window sorts on.
  def timestamp = date_time.to_i

  # Icon name for the notification.
  def icon_name
    ICONS.fetch(icon_type, nil).then do |states|
      if states
        states.fetch(@state.to_s, states[:default])
      else
        DEFAULT_ICON
      end
    end
  end

  # The ported SVG for #icon_name, or nil when the icon is a themed one.
  #
  # Upstream imports the SVGs as icon resources and lets the icon theme
  # resolve them by name; here they are files next to the code, so the row and
  # the desktop notification both point straight at the file.
  def icon_path
    File.join(Util.data_dir, 'icons', "#{icon_name}.svg").then do |path|
      File.exist?(path) ? path : nil
    end
  end

  def icon
    icon_path.then do |path|
      if path
        Gio::FileIcon.new(Gio::File.new_for_path(path))
      else
        Gio::ThemedIcon.new(icon_name)
      end
    end
  end

  # The Gio::Notification for this notification.
  #
  # @param hidden [Boolean] whether the window is currently out of sight, which
  #   is when upstream adds the button that brings the app back
  def gio_notification(hidden: false)
    Gio::Notification.new(@title.to_s).tap do |notification|
      notification.body = @repository.to_s
      notification.icon = icon

      notification.set_default_action_and_target(
        'app.open-notification',
        GLib::Variant.new([@id.to_s, @url.to_s]),
      )

      notification.add_button_with_target(
        'Mark as Read',
        'app.mark-read',
        GLib::Variant.new(@id.to_s),
      )

      if hidden
        notification.add_button('Show Forge Sparks', 'app.activate')
      end
    end
  end

  private

    def parse_updated_at
      Time.iso8601(@updated_at.to_s).utc
    rescue ArgumentError, TypeError
      Time.at(0).utc
    end

    # Pull requests arrive under three different type names; everything else
    # keys the icon map directly.
    def icon_type = PULL_TYPES.include?(@type.to_s) ? 'Pull' : @type.to_s
end
