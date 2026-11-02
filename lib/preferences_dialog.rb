# frozen_string_literal: true

require 'adwaita'

require_relative 'util'

# PreferencesDialog holds the three desktop-integration preferences.
#
# Ported from upstream's src/widgets/preferences.js and
# src/widgets/preferences.blp: an expander row with its own enable switch for
# "Keep Running in Background", and inside it "Run on Startup" and "Start
# Hidden", the second only sensitive while the first is on.
#
# Upstream asks the XDG background portal to grant each of these and saves
# whatever the portal answered, so a refused request switches the row back
# off and raises a toast. There is no portal binding for Ruby, and a portal
# only exists inside a sandbox, so here "keep running in the background" is
# the window's own hide-on-close and the two autostart switches write the XDG
# autostart desktop file the portal would have written. The flow is the same:
# the request can fail, and the row follows what actually happened.
#
class PreferencesDialog < Adwaita::PreferencesDialog
  # @param settings [Settings] the app settings
  # @param on_hide_on_close_changed [Proc, nil] called with the new value so the
  #   window can follow it, as upstream sets window.hide_on_close
  def initialize(settings: Util.settings, on_hide_on_close_changed: nil)
    super()
    @settings = settings
    @on_hide_on_close_changed = on_hide_on_close_changed
  end

  def build
    tap do |dialog|
      dialog.add(page)

      page.tap do |prefs|
        prefs.add(group)

        group.tap do |prefs_group|
          prefs_group.add(background_row)

          background_row.tap do |row|
            row.add_row(startup_row)
            row.add_row(hidden_row)

            row.signal_connect('notify::enable-expansion') { on_background_changed }
          end

          startup_row.tap do |row|
            row.add_suffix(startup_switch)
            row.activatable_widget = startup_switch

            # Connected through the memoized handler id, so the handler can be
            # blocked again when the switch is put back programmatically.
            startup_handler_id
          end

          hidden_row.tap do |row|
            row.add_suffix(hidden_switch)
            row.activatable_widget = hidden_switch

            hidden_switch.signal_connect('notify::active') { on_startup_hidden_changed }
          end
        end
      end

      load_saved_settings
    end
  end

  # Memoized widget methods

  def page = @page ||= Adwaita::PreferencesPage.new
  def group = @group ||= Adwaita::PreferencesGroup.new

  def background_row
    @background_row ||= Adwaita::ExpanderRow.new.tap do |row|
      row.title = 'Keep Running in Background'
      row.show_enable_switch = true
      row.expanded = true
    end
  end

  def startup_row
    @startup_row ||= Adwaita::ActionRow.new.tap do |row|
      row.title = 'Run on Startup'
    end
  end

  def startup_switch
    @startup_switch ||= Gtk::Switch.new.tap do |toggle|
      toggle.valign = :center
    end
  end

  # Starting hidden only means anything when the app starts by itself, so the
  # row follows the autostart switch — upstream binds its sensitivity to it.
  def hidden_row
    @hidden_row ||= Adwaita::ActionRow.new.tap do |row|
      row.title = 'Start Hidden'
      row.sensitive = false
    end
  end

  def hidden_switch
    @hidden_switch ||= Gtk::Switch.new.tap do |toggle|
      toggle.valign = :center
    end
  end

  private

    def load_saved_settings
      background_row.enable_expansion = @settings['hide-on-close']
      startup_switch.active = @settings['autostart']
      hidden_switch.active = @settings['autostart-hidden']
      hidden_row.sensitive = startup_switch.active?
    end

    # Keeping the app running in the background is the window not closing when
    # the user closes it, which nothing can refuse — so this saves the new
    # value, hands it to the window, and re-requests autostart with it,
    # because an autostart that cannot keep running has nothing to start.
    def on_background_changed
      background_row.enable_expansion.then do |enabled|
        unless enabled == @settings['hide-on-close']
          @settings['hide-on-close'] = enabled
          if @on_hide_on_close_changed
            @on_hide_on_close_changed.call(enabled)
          end

          autostart = @settings['autostart'] && enabled
          apply_autostart(autostart, hidden: autostart && @settings['autostart-hidden'])
        end
      end
    end

    def on_startup_changed
      startup_switch.active?.then do |active|
        unless active == @settings['autostart']
          hidden_row.sensitive = active
          apply_autostart(active, hidden: @settings['autostart-hidden'])
        end
      end
    end

    def on_startup_hidden_changed
      hidden_switch.active?.then do |active|
        unless active == @settings['autostart-hidden']
          @settings['autostart-hidden'] = active
          apply_autostart(@settings['autostart'], hidden: active)
        end
      end
    end

    # Writes or removes the autostart entry, saves what actually happened, and
    # puts the switch back where reality left it.
    def apply_autostart(enabled, hidden:)
      Util.request_autostart(enabled, hidden: hidden).then do |success|
        @settings['autostart'] = enabled && success
        update_startup_switch(@settings['autostart'])

        unless success
          add_toast(Adwaita::Toast.new('The autostart request failed.'))
        end
      end
    end

    # The switch is set from the saved value without re-entering the handler,
    # which is what upstream freezes and thaws notifications for.
    def update_startup_switch(value)
      unless startup_switch.active? == value
        startup_switch.signal_handler_block(startup_handler_id) do
          startup_switch.active = value
        end
        hidden_row.sensitive = value
      end
    end

    def startup_handler_id
      @startup_handler_id ||= startup_switch.signal_connect('notify::active') { on_startup_changed }
    end
end
