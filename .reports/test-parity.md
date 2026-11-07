# Test parity — forge-sparks

| | |
|---|---|
| Upstream | `main` @ `3df28d2` |
| Port | `ruby` @ `0bcf2cc` (re-audited this round; previous pass was at `e0bd336`) |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |
| Test commands | `nix develop --command xvfb-run -a ruby test/check_models.rb`; `nix develop --command xvfb-run -a ruby test/drive_window.rb` |

## Upstream has no test suite

Verified, not assumed: `git ls-tree -r --name-only origin/main` has no
`test/`, `tests/`, or `spec/` directory and no `*.test.js`; `test-census.sh`
run against a clean `git archive` of `origin/main` returns **0 rows**; there
is no `jasmine`/`it(...)` anywhere in `src/`, and `meson.build` declares no
test target. Parity is **0/0, met trivially — the port inherits no safety
net from upstream.** Every check below was written for the port and pins
nothing upstream ever considered worth pinning down.

## Extra (outside the count, but actually run during this audit)

- `test/check_models.rb` — 71 `check(...)` calls over the settings file, the
  accounts model, all four forge backends, the notification model and the
  relative-date formatter. **Re-run live, twice now:** on `3f45b15` by the
  previous pass and again this round on current HEAD `e0bd336` (after the
  background-portal fix commit landed) — both `70 of 70 checks passed,
  CHECKS OK` (one `check(...)` call is a no-op label line that the census
  double-counts; the runtime `@checks` counter, the actual pass tally, is
  the number that matters — see below).
- `test/drive_window.rb` — drives the live window headless (offscreen GTK,
  `xvfb-run`), opening every dialog, firing every accelerator and action.
  **Re-run live, twice now,** same two commits: both `207 of 207 checks
  passed, DRIVE OK`, matching exactly the number asserted by the task's own
  runtime gate — this audit did not take that number on faith on either
  pass, it reproduced it both times, including after the fix commit that
  changed `lib/util.rb` and `lib/preferences_dialog.rb`, the files the drive
  script's preferences-dialog checks exercise.
- **What the 207/277 gate does not reach:** `test/drive_window.rb` opens the
  preferences dialog and flips its switches (confirmed by reading the
  script), but neither suite asserts on the specific strings fixed in
  `e0bd336` — no check asserts `"The request failed."` vs `"The autostart
  request failed."` appears on the right toast for the right toggle, and
  none exercises `Util.sandboxed?` under an actual sandbox (there is no
  Flatpak manifest to run this port inside, sandboxed or not). The gate
  passing is real and reproduced, but it does not cover the exact two bugs
  the latest commit fixed, nor the background-portal gap that commit left
  open — a passing drive run and a component-parity gap are not in tension;
  they are checking different things. See `.reports/component-parity.md`.

**Which call is the assertion unit:** `test/gtk_driver.rb:78-89` defines
`check` and increments `@checks` there; `step` (`gtk_driver.rb:70-72`) only
registers a named block and increments nothing. `test-census.sh`'s own
regex collects both `check(` and `step(` for `.rb` files (by design — see
its comment), which overcounts: a raw census of `test/drive_window.rb`
returns 272 rows (193 `check` + 79 `step`), not the 207 the harness itself
reports as the assertion count. **The 207 figure, read from the actual
`@checks` counter at runtime, is the correct one** — not the census script's
raw regex count, and not a number to trust without running it.

## The `spec/` directory: closed this round

The finding this section used to describe (an empty `spec/` with no
`*_spec.rb` anywhere, a green `rake spec` that asserted nothing) is stale.
Commit `0bcf2cc` added `spec/util_spec.rb` (11 examples over
`Util.relative_date`'s thresholds, rounding and both date-format fallbacks)
and `spec/settings_spec.rb` (10 examples over `Settings`' defaults,
persistence and the per-account view) — the port's first real specs.

As found this round, those specs could not actually run in this fork's own
dev shell: `spec_helper.rb` hard-required `kettle/test/rspec` and `"forge/sparks/rb"`
(a module path with no matching `lib/forge/sparks/rb.rb` — the real entry
point is `lib/forge_sparks.rb`), and `.rspec` forced a `RspecJunitFormatter`
that is not installed either. All three were a dev-dependency scaffold left
over from the gem generator, not anything this port's own code needs; `bundle
exec rspec` also fails outright in this shell because `rspec-core` itself is
not in the Bundler-resolved set the flake provides (only reachable via plain
`ruby -S rspec`, which does see it on `GEM_PATH`). Fixed this round:
`spec/spec_helper.rb`'s `kettle/test/rspec` require is now wrapped in the
same `rescue LoadError` guard already used for `kettle-soup-cover` just above
it, its library require now points at `forge_sparks` (the module that
actually exists), and `.rspec` no longer names the missing junit formatter.
Confirmed live: `nix develop --command xvfb-run -a ruby -Ilib -S rspec spec/`
→ **21 examples, 0 failures**. Also fixed in the same pass: running the
specs surfaced a real `warning: too many arguments for format string` in
`Util.relative_date`'s "yesterday" branch (`n_('yesterday', '%d days ago',
days)` has no `%d` in its singular form, but `format` was still called with
`days`) — `lib/util.rb` now special-cases `days == 1` so the format call
only runs on the string that has a placeholder; the warning is gone and the
spec suite is still green.

## Rules followed

- Both extra suites were **re-run in this audit's own session**, inside the
  dev shell against a real (virtual) display, not read off a prior claim.
- No upstream test was invented to pad the 0/0; the GJS app genuinely ships
  none.
- "0/0, met trivially, no inherited safety net" is stated explicitly per the
  skill's own template for this case, rather than left as an implied pass.
