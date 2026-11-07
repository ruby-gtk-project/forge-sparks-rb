# Test parity — forge-sparks

| | |
|---|---|
| Upstream | `main` @ `3df28d2` |
| Port | `ruby` @ `5570f99` (re-audited this round; previous pass was at `0bcf2cc`) |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |
| Test commands | `nix develop --command xvfb-run -a ruby test/check_models.rb`; `nix develop --command xvfb-run -a ruby test/drive_window.rb`; `nix develop --command xvfb-run -a ruby -Ilib -S rspec spec/` |

## Upstream has no test suite

Verified, not assumed: `git ls-tree -r --name-only origin/main` has no
`test/`, `tests/`, or `spec/` directory and no `*.test.js`; no
`jasmine`/`it(...)` anywhere in `src/`; `meson.build` declares no test
target. Parity is **0/0, met trivially** — the port inherits no safety net
from upstream. Every check below was written for the port.

## Runtime gate, reproduced live this round (not taken on faith)

```
$ nix develop --command xvfb-run -a ruby test/drive_window.rb
201 of 201 checks passed
DRIVE OK

$ nix develop --command xvfb-run -a ruby test/check_models.rb
70 of 70 checks passed
CHECKS OK

$ nix develop --command xvfb-run -a ruby -Ilib -S rspec spec/
Finished in 0.08167 seconds
21 examples, 0 failures
```

These numbers match the task's stated runtime gate (201 checks, 0 failed)
and the commit message of `0bcf2cc` itself ("DRIVE OK, 201/201 checks
passed"), and `5570f99`'s own message ("201/201, DRIVE OK").

## Correction to the previous pass of this report: the "207/207" claim was wrong

The previous pass of this file (written at `0bcf2cc`) stated twice that
`test/drive_window.rb` was "re-run live, twice now" and both times returned
**"207 of 207 checks passed, DRIVE OK"**, and called that "the number
asserted by the task's own runtime gate." That is incorrect on two counts:

1. The task's runtime gate at every point this round has stated **201**
   checks, not 207 — including in the commit message of the very commit
   (`0bcf2cc`) that report was auditing.
2. This round's own live run, on the current HEAD, returns **201**, not
   207. There is no commit between `0bcf2cc` and `5570f99` that changes the
   check count.

207 was a real number at an earlier point in this port's history —
`.reports/component-inventory.md` traces it to the drive script being
"extended... to 207 checks" around commit `18f35e9`, before the
autostart-check rewrite in `0bcf2cc` changed the script's shape (and,
incidentally, its count) to 201. The previous test-parity pass appears to
have carried that older number forward without re-running the script
against the commit it was actually auditing. `.reports/component-parity.md`
and `.reports/component-inventory.md` both also quote 207 for the same
(now-stale) point in time. See `.reports/accountability-ensurance.md` for
this as a standalone finding — a report asserting it had re-run a check
live, with a specific number, that does not match either the real tool
output or the commit's own stated result.

## What the gate does not reach

`test/drive_window.rb` opens the preferences dialog and flips its switches,
but neither suite asserts on the specific toast strings (`"The request
failed."` vs `"The autostart request failed."`) or checks that
`po/forge-sparks.pot` actually contains every string a given code path
`_()`-wraps. The translation-catalogue staleness this round's
`.reports/translation-parity.md` and `.reports/component-parity.md` found
(three strings used in `lib/util.rb` but absent from the `.pot`) passes the
runtime gate cleanly, because the gate drives behaviour, not the `.pot`
file — a passing drive run and a translation gap are not in tension; they
check different things.

## The `spec/` directory

`spec/util_spec.rb` (11 examples, `Util.relative_date`) and
`spec/settings_spec.rb` (10 examples, `Settings`) exist and run: confirmed
again this round, 21 examples total, 0 failures, inside the dev shell
against a virtual display. `spec_helper.rb`'s guarded requires
(`kettle/test/rspec`, `kettle-soup-cover`) and `.rspec`'s formatter line were
fixed in `5570f99`, re-verified this round by running the suite rather than
re-reading the fix.

## Rules followed

- Both extra suites and the spec suite were **re-run in this audit's own
  session**, inside the dev shell against a real (virtual) display, not
  read off a prior claim.
- No upstream test was invented to pad the 0/0; the GJS app genuinely ships
  none.
- A number quoted by a previous pass of this exact report was checked
  against a live re-run rather than carried forward, which is what caught
  the 207-vs-201 discrepancy above.
