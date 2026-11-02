# frozen_string_literal: true

require 'adwaita'

require_relative 'translation'

# ShortcutsDialog lists the keyboard shortcuts.
#
# Ported from upstream's src/gtk/help-overlay.blp, a Gtk.ShortcutsWindow with
# one "General" group holding the three shortcuts it advertises. Gtk
# ShortcutsWindow is deprecated in GTK 4.18 and Adwaita's dialog replaces it,
# so the same group is an Adwaita::ShortcutsSection here, reached through the
# same win.show-help-overlay action.
#
class ShortcutsDialog < Adwaita::ShortcutsDialog
  # Both ways round: the section titles below are looked up as the class body
  # is read, the dialog title as an instance is built.
  include Translation
  extend Translation

  # The four titles carry upstream's "shortcut window" context, which is what
  # C_("shortcut window", …) in its Blueprint gives them: a shortcut window's
  # labels are short enough that a language may want them worded differently
  # here than in the menu.
  SECTIONS = {
    p_('shortcut window', 'General') => [
      [p_('shortcut window', 'Open menu'), 'F10'],
      [p_('shortcut window', 'Keyboard shortcuts'), '<Control>question'],
      [p_('shortcut window', 'Quit'), '<Control>q'],
    ],
  }.freeze

  def initialize
    super()
    self.title = _('Keyboard Shortcuts')
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
