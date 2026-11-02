# forge-sparks — Ruby port

This branch is an empty `ruby` orphan branch. The upstream code (the original
implementation of forge-sparks) lives on the fork's other branches; this branch is
where the Ruby GTK4 / Libadwaita port is written.

## Skills — use them

Two skills are installed in `.claude/skills/`. They are not optional reading.

- **ruby-gtk** — the house style for Ruby GTK4/Libadwaita: the declarative
  memoized-widget pattern, Adwaita binding quirks, worked examples. Load it
  before writing or reviewing ANY Ruby GTK code, including single widgets, and
  before planning a port. The bindings are quirky enough that code written from
  memory is unreliable.
- **ruby-gtk-testing** — run the app headlessly and drive its UI: click through
  dialogs, assert widget state, capture screenshots. Use it before claiming any
  GTK change works. `ruby -c` and a successful `require` prove nothing about a
  UI.

## Setup

`direnv allow` (or `nix develop`) gets Ruby, GTK4, Libadwaita and the
introspection typelibs. Then `bundle install`.

## Style

`.rubocop.yml` plus the custom cops in `cops/` are enforced: no `return`, no
modifier `if`, no conditional assignment, `tap` where it applies, and fixed
multi-line argument/hash layout. Run `bundle exec rubocop` before committing.

## Translations

Every string the app shows goes through `lib/translation.rb`: `_()` for one
string, `n_()` for a count, `p_()` for one that needs a context. After adding
or changing one, regenerate the catalogue from the dev shell:

```
nix develop --command po/update-catalogue.sh
```

That rewrites `po/forge-sparks.pot` from the files listed in `po/POTFILES`,
merges every locale in `po/LINGUAS` against it, and compiles the catalogues
into `data/locale`, which is where a development run reads them from and which
is not committed. `nix build` compiles them again into the package's
`share/locale`, and merges each locale's strings into the installed desktop
entry and AppStream metainfo.

To see the app in another language: `LANGUAGE=de nix develop --command xvfb-run
-a ruby exe/forge-sparks`. The drive scripts pin themselves to the C locale,
because their checks read the English the port is written in.
