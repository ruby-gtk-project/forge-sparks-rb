# Test parity — forge-sparks

| | |
|---|---|
| Upstream | `main` @ `3df28d2` |
| Port | `ruby` @ `e0bd336` (re-audited; previous pass was at `3f45b15`) |
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

## The `spec/` directory: a scaffold with no tests in it, and the real finding

`spec/` contains exactly two files: `spec_helper.rb` and `README.md`. There
is not one `*_spec.rb` anywhere in the repository. `Rakefile` still declares
`rake spec` (RSpec via `kettle-dev`), and the dev shell banner advertises
`ruby -e 'require "rspec/core"; ...RSpec::Core::Runner.run(...)'` as "run the
specs." **Running either command executes zero examples and exits 0** — a
green result that asserts nothing. This is not a test-parity gap in the
bijection sense (upstream has 0 tests to map), but it is a real risk flagged
here because it is exactly the shape of false-green the `accountability-ensurance`
skill looks for: a command that reads as "tests pass" and has never tested
anything. See `.reports/accountability-ensurance.md`.

## Rules followed

- Both extra suites were **re-run in this audit's own session**, inside the
  dev shell against a real (virtual) display, not read off a prior claim.
- No upstream test was invented to pad the 0/0; the GJS app genuinely ships
  none.
- "0/0, met trivially, no inherited safety net" is stated explicitly per the
  skill's own template for this case, rather than left as an implied pass.
