# frozen_string_literal: true

require 'gtk4'
require 'adwaita'

# Style installs the app stylesheet.
#
# Ported from upstream's src/style.css and src/style-dark.css, which the
# application imports and GJS registers for the default display — the light
# sheet always, the dark one on top of it when the dark colour scheme is
# active.
#
# ruby-gnome has no equivalent of that import, so the two sheets are the
# strings below and this class adds them as providers, keeping the dark one
# attached only while Adwaita reports a dark scheme.
#
class Style
  # src/style.css
  LIGHT = <<~CSS
    .margin-box {
        margin: 24px 12px;
    }

    .closed {
        color: @purple_3;
    }
  CSS

  # src/style-dark.css
  DARK = <<~CSS
    .closed {
        color: @purple_1;
    }
  CSS

  # Upstream's light sheet is registered as an application stylesheet and the
  # dark one has to win over it, so the dark provider sits one step higher.
  LIGHT_PRIORITY = Gtk::StyleProvider::PRIORITY_APPLICATION
  DARK_PRIORITY = Gtk::StyleProvider::PRIORITY_APPLICATION + 1

  # Adds the providers to the display and follows the colour scheme from then
  # on. Called once, from the application's startup.
  def install
    tap do
      Gdk::Display.default.then do |display|
        if display
          Gtk::StyleContext.add_provider_for_display(display, light_provider, LIGHT_PRIORITY)
          apply_color_scheme(display)

          style_manager.signal_connect('notify::dark') { apply_color_scheme(display) }
        end
      end
    end
  end

  def light_provider = @light_provider ||= Gtk::CssProvider.new.tap { |provider| provider.load_from_data(LIGHT) }
  def dark_provider = @dark_provider ||= Gtk::CssProvider.new.tap { |provider| provider.load_from_data(DARK) }
  def style_manager = @style_manager ||= Adwaita::StyleManager.default

  private

    def apply_color_scheme(display)
      if style_manager.dark?
        Gtk::StyleContext.add_provider_for_display(display, dark_provider, DARK_PRIORITY)
      else
        Gtk::StyleContext.remove_provider_for_display(display, dark_provider)
      end
    end
end
