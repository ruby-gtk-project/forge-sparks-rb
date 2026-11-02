#!/usr/bin/env bash
#
# Regenerates the translation catalogue.
#
# This is the port of upstream's po/meson.build, whose one
# `i18n.gettext(application_id, preset: 'glib')` line gives meson the three
# jobs done here: extract the template from the sources listed in POTFILES,
# merge every locale's catalogue against it, and compile the catalogues the
# app reads at runtime.
#
# Run it from the dev shell, which carries rxgettext (the Ruby extractor) and
# the GNU gettext tools:
#
#   nix develop --command po/update-catalogue.sh
#
# The compiled catalogues land in data/locale, where Translation looks first,
# so a development run picks up a translation as soon as this has run. The
# install step compiles them again, into the prefix's share/locale.
#
set -euo pipefail

cd "$(dirname "$0")/.."

domain=forge-sparks
pot="po/$domain.pot"
version=$(ruby -e 'require "./lib/forge/sparks/rb/version"; print Forge::Sparks::Rb::VERSION')

# The ITS rules that teach xgettext which elements of an AppStream metainfo
# file hold text. They ship with gettext itself, in a directory named after
# its version, so the lookup is a glob over the installation msgfmt is in.
find_metainfo_its() {
  local prefix
  prefix=$(dirname "$(dirname "$(readlink -f "$(command -v msgfmt)")")")
  local candidate
  for candidate in "$prefix"/share/gettext*/its/metainfo.its /usr/share/gettext*/its/metainfo.its; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "po/update-catalogue.sh: no metainfo.its found next to $(command -v msgfmt)" >&2
  return 1
}

# POTFILES names every file with a translatable string in it, and the three
# kinds of file in it need three extractors.
sources_of() {
  grep -v '^[[:space:]]*\(#.*\)\?$' po/POTFILES | grep -- "$1" || true
}

mapfile -t ruby_sources < <(sources_of '\.rb$')
mapfile -t desktop_sources < <(sources_of '\.desktop\.in$')
mapfile -t metainfo_sources < <(sources_of '\.metainfo\.xml\.in$')

# The working directory is under po/, because rxgettext writes each source
# reference relative to the file it is writing: from po/ that is ../lib/..., and
# the sed below drops the ../ so a reference reads from the project root, the
# way xgettext already writes the data/ ones.
work=$(mktemp -d -p po)
trap 'rm -rf "$work"' EXIT

# The Ruby sources come first, so the header the catalogue keeps is this one.
rxgettext \
  --add-comments=Translators: \
  --package-name="$domain" \
  --package-version="$version" \
  --msgid-bugs-address='https://github.com/ruby-gtk-project/forge-sparks-rb/issues' \
  --output="$work/ruby.pot" \
  "${ruby_sources[@]}"

xgettext \
  --language=Desktop \
  --add-comments=TRANSLATORS: \
  --from-code=UTF-8 \
  --output="$work/desktop.pot" \
  "${desktop_sources[@]}"

xgettext \
  --its="$(find_metainfo_its)" \
  --from-code=UTF-8 \
  --output="$work/metainfo.pot" \
  "${metainfo_sources[@]}"

msgcat --use-first --output-file="$work/merged.pot" \
  "$work/ruby.pot" "$work/desktop.pot" "$work/metainfo.pot"

sed -e '/^#:/s|\.\./||g' "$work/merged.pot" > "$pot"

echo "wrote $pot ($(grep -c '^msgid ' "$pot") messages, header included)"

while read -r lang; do
  case "$lang" in
    '' | \#*) continue ;;
  esac

  po="po/$lang.po"
  if [ -f "$po" ]; then
    msgmerge --quiet --previous --update --backup=none "$po" "$pot"
  else
    msginit --no-translator --locale="$lang" --input="$pot" --output-file="$po"
  fi

  mkdir -p "data/locale/$lang/LC_MESSAGES"
  msgfmt --output-file="data/locale/$lang/LC_MESSAGES/$domain.mo" "$po"
  printf '%-8s %s\n' "$lang" "$(msgfmt --statistics --output-file=/dev/null "$po" 2>&1)"
done < po/LINGUAS
