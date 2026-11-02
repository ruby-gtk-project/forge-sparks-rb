# frozen_string_literal: true

require 'adwaita'

# ShortcutsDialog lists the keyboard shortcuts.
#
# Ported from upstream's src/gtk/help-overlay.blp, a Gtk.ShortcutsWindow with
# one "General" group holding the three shortcuts it advertises. Gtk
# ShortcutsWindow is deprecated in GTK 4.18 and Adwaita's dialog replaces it,
# so the same group is an Adwaita::ShortcutsSection here, reached through the
# same win.show-help-overlay action.
#
class ShortcutsDialog < Adwaita::ShortcutsDialog
  SECTIONS = {
    'General' => [
      ['Open menu', 'F10'],
      ['Keyboard shortcuts', '<Control>question'],
      ['Quit', '<Control>q'],
    ],
  }.freeze

  def initialize
    super()
    self.title = 'Keyboard Shortcuts'
  end

  def build
    tap do |dialog|
      SECTIONS.each do |title, items|
        dialog.add(section(title, items))
      end
    end
  end

  private

    def section(title, items)
      Adwaita::ShortcutsSection.new.tap do |section|
        section.title = title
        items.each { |label, accelerator| section.add(item(label, accelerator)) }
      end
    end

  # Positional, not keyword, arguments — even though the error a no-argument
  # new raises advertises the signatures as "title: utf8, accelerator: utf8".
    def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)
end
