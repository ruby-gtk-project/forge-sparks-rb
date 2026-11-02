# frozen_string_literal: true

require 'adwaita'

# NotificationRow is the row for one notification.
#
# Ported from upstream's src/widgets/notificationRow.js and
# src/widgets/notificationRow.blp: an icon that swaps for a spinner while the
# row is opening, the notification title with its relative date on the right,
# and the repository with the account name under it.
#
# Upstream cannot derive from Adw.ActionRow because it needs that two-line
# layout, so it builds a Gtk.ListBoxRow and reconnects its parent's
# row-activated signal to an `activated` signal of its own. The window here
# owns the one row-activated handler and holds the rows it built, so that
# bookkeeping is gone; the behaviour on screen is the same.
#
class NotificationRow < Gtk::ListBoxRow
  type_register

  ICON_SIZE = 16

  # The css class the icon gets for each notification state.
  STATE_CLASSES = {
    'open'   => 'accent',
    'opened' => 'accent',
    'closed' => 'closed',
    'draft'  => 'dim-label',
    'denied' => 'error',
  }.freeze

  # @param notification [Notification] the notification this row shows
  # @param date [String] the relative date, already formatted
  # @param account [String, nil] the account name, shown when there are several
  def initialize(notification, date:, account: nil)
    super()
    @notification = notification
    @date = date
    @account = account
    self.activatable = true
    self.tooltip_text = notification.title.to_s
  end

  attr_reader :notification

  def build
    tap do |row|
      row.child = content_box

      content_box.tap do |box|
        box.append(icon_stack)
        box.append(text_box)

        icon_stack.tap do |stack|
          stack.add_named(icon, 'icon')
          stack.add_named(spinner, 'spinner')
          stack.visible_child_name = 'icon'
        end

        text_box.tap do |texts|
          texts.append(title_line)
          texts.append(repository_line)

          title_line.tap do |line|
            line.start_widget = title_label
            line.end_widget = date_label
          end

          repository_line.tap do |line|
            line.start_widget = repository_label
            line.end_widget = account_label
          end
        end
      end
    end
  end

  # While true the icon is a spinner, which is how the row says it is opening
  # the notification.
  def progress=(value)
    if value
      icon_stack.visible_child_name = 'spinner'
    else
      icon_stack.visible_child_name = 'icon'
    end
    @progress = value
  end

  def progress? = @progress == true

  # Memoized widget methods

  def content_box
    @content_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
      box.valign = :center
      box.add_css_class('header')
    end
  end

  def icon_stack = @icon_stack ||= Gtk::Stack.new

  # The icon is the ported SVG when there is one for this notification type,
  # and a themed icon name otherwise — upstream resolves both through the icon
  # theme, which this port does not have to install into.
  def icon
    @icon ||= Gtk::Image.new.tap do |image|
      image.pixel_size = ICON_SIZE
      @notification.icon_path.then do |path|
        if path
          image.file = path
        else
          image.icon_name = @notification.icon_name
        end
      end

      STATE_CLASSES[@notification.state.to_s].then do |css_class|
        if css_class
          image.add_css_class(css_class)
        end
      end
    end
  end

  def spinner
    @spinner ||= Adwaita::Spinner.new.tap do |spinner|
      spinner.width_request = ICON_SIZE
      spinner.height_request = ICON_SIZE
    end
  end

  def text_box
    @text_box ||= Gtk::Box.new(:vertical, 3).tap do |box|
      box.valign = :center
    end
  end

  def title_line
    @title_line ||= Gtk::CenterBox.new.tap do |line|
      line.orientation = :horizontal
      line.hexpand = true
    end
  end

  def repository_line
    @repository_line ||= Gtk::CenterBox.new.tap do |line|
      line.orientation = :horizontal
      line.hexpand = true
    end
  end

  def title_label
    @title_label ||= Gtk::Label.new(@notification.title.to_s).tap do |label|
      label.xalign = 0
      label.hexpand = true
      label.ellipsize = :end
    end
  end

  def date_label
    @date_label ||= Gtk::Label.new(@date.to_s).tap do |label|
      label.xalign = 0
      label.margin_start = 6
      label.add_css_class('caption')
      label.add_css_class('dim-label')
    end
  end

  def repository_label
    @repository_label ||= Gtk::Label.new(@notification.repository.to_s).tap do |label|
      label.xalign = 0
      label.ellipsize = :end
      label.add_css_class('caption')
      label.add_css_class('dim-label')
    end
  end

  # The account name only has something to say when more than one account is
  # configured; the label still occupies its slot so every row is the same
  # height either way.
  def account_label
    @account_label ||= Gtk::Label.new(@account.to_s).tap do |label|
      label.xalign = 0
      label.halign = :end
      label.ellipsize = :start
      label.add_css_class('caption')
      label.add_css_class('dim-label')
    end
  end
end
