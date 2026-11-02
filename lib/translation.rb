# frozen_string_literal: true

require 'gettext'

# Translation is where every string the app shows is looked up.
#
# Ported from the `import { gettext as _, ngettext } from 'gettext'` line
# upstream repeats at the top of each file that shows text, from the
# `i18n.gettext(application_id, preset: 'glib')` in upstream's po/meson.build
# and from the text domain GJS binds for pkg.name: one catalogue, named after
# the app, holding the strings of the window, the dialogs, the preferences,
# the forge help texts and the desktop notifications.
#
# `include Translation` in a class, or `extend Translation` in a module, and
# the two lookups upstream imports are in scope:
#
#   _('Accounts')                                   # gettext
#   n_('%d minute ago', '%d minutes ago', minutes)  # ngettext
#   p_('shortcut window', 'Quit')                   # pgettext
#
# All three are delegated to the one Catalogue below instead of being mixed in
# from GetText directly, because the gettext gem resolves a text domain
# through the ancestors of whatever object called `_`, and a module that is
# only ever extended into other modules has no such ancestry to resolve
# through.
#
# With no catalogue compiled for the current locale — the C locale of a
# development run, or a language nobody has translated yet — every lookup
# hands back the string it was given, which is the English the port is
# written in.
#
module Translation
  # The text domain, which is also the basename of the compiled catalogue:
  # po/es.po becomes <locale dir>/es/LC_MESSAGES/forge-sparks.mo.
  DOMAIN = 'forge-sparks'

  # The fallback XDG_DATA_DIRS, straight from the Base Directory spec.
  DEFAULT_DATA_DIRS = '/usr/local/share:/usr/share'

  # Catalogue owns the binding between the text domain and the directory the
  # compiled catalogues are in, and is the object the lookups run as, so that
  # the domain is found on its class.
  class Catalogue
    include GetText

    def initialize(path)
      bindtextdomain(DOMAIN, path: path)
    end

    def singular(message) = _(message)

    def plural(one, many, count) = n_(one, many, count)

    def particular(context, message) = p_(context, message)
  end

  module_function

  # Where a compiled catalogue may be. The tree the app runs from comes
  # first, so `po/update-catalogue.sh` in a checkout is what a development run
  # picks up; an installed app finds its catalogues through XDG_DATA_DIRS,
  # which is where the install step puts them.
  def locale_paths
    [
      File.expand_path('../data/locale', __dir__),
      *ENV.fetch('XDG_DATA_DIRS', DEFAULT_DATA_DIRS)
          .split(':')
          .reject(&:empty?)
          .map { |dir| File.join(dir, 'locale') },
    ]
  end

  # The first of those that actually holds a catalogue of this app's, and not
  # merely the first that exists: XDG_DATA_DIRS carries the share directory of
  # every library in the closure, and GTK's own one is full of locale
  # directories with nothing of ours in them.
  #
  # Binding a directory with no catalogue in it is not an error — every lookup
  # then returns its msgid — so when there is no catalogue anywhere the last
  # candidate is handed over and the app stays English.
  def locale_path = locale_paths.find { |path| catalogue_in?(path) } || locale_paths.last

  # Whether `path` is a locale directory with a catalogue of this domain's
  # compiled into it, for any language at all.
  def catalogue_in?(path)
    Dir.glob(
      File.join(
        path,
        '*',
        'LC_MESSAGES',
        "#{DOMAIN}.mo",
      ),
    ).any?
  end

  def catalogue = @catalogue ||= Catalogue.new(locale_path)

  # gettext: the translation of `message`, or `message` itself.
  def _(message) = Translation.catalogue.singular(message)

  # ngettext: the translation of `one` or `many` that the catalogue's plural
  # rule picks for `count`, or the English of the two that `count == 1` picks.
  def n_(one, many, count) = Translation.catalogue.plural(one, many, count)

  # pgettext: the translation of `message` as it reads in `context`, for the
  # strings whose English is too short to translate the same way everywhere.
  def p_(context, message) = Translation.catalogue.particular(context, message)
end
