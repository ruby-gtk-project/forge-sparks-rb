# Test parity — forge-sparks

| | |
|---|---|
| Upstream | `main` @ `3df28d2` |
| Port | `ruby` @ `2e0c16d` (re-audited this round; previous pass was at `5570f99`, two commits behind — `180f802`/`b609a74`/`2e0c16d` only touched `po/` and `.reports/`, no test code) |
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

## Re-verification this round (`2e0c16d`)

Re-run live again, independently, against current HEAD rather than trusting
the previous pass's transcript:

```
$ nix develop --command xvfb-run -a ruby test/drive_window.rb
201 of 201 checks passed
DRIVE OK

$ nix develop --command xvfb-run -a ruby test/check_models.rb
70 of 70 checks passed
CHECKS OK

$ nix develop --command xvfb-run -a ruby -Ilib -S rspec spec/
21 examples, 0 failures
```

Identical to the task's stated runtime gate (201 checks, 0 failed) and to
the previous pass's numbers. No test file changed since `5570f99`, so an
identical result is expected, not merely assumed — it was executed again
this round to confirm that "nothing changed" is actually true rather than
inferred from the diff.

On the task's framing of the gate as "covering 15 components": this
report's unit of account is the 23-row inventory in
`.reports/component-inventory.md`, not 15. The two numbers are not in
tension — "15" is not a count this repository's own scripts, commit
messages, or inventory use anywhere (checked: `grep -rn "15 component"
lib/ test/ .reports/` finds nothing), so it reads as the harness's own
approximate figure rather than a port-specific claim to reconcile. Flagged
here rather than silently ignored, per this skill's instruction to treat a
component no check exercises as unverified: every one of the 23 inventoried units has at least one drive/check_models/
rspec step that touches it, but the depth of that coverage is not uniform
across the four forge backends. `test/drive_window.rb`'s `FakeSession`
(line 55) scripts canned HTTP responses so "the real GitHub backend, the
real fetch loop and the real notification rows are all exercised with no
network" (the file's own comment, line 12) — and that is accurate: the
notification-fetch steps around line 480 set `forge: 'github'` and the
whole account-creation-to-notification-on-screen path runs through
`lib/github.rb`'s real request/parsing code against the fake session.
`lib/gitea.rb`, `lib/forgejo.rb` and `lib/gitlab.rb` get only the combo-row
swap steps ("choosing Gitea/GitLab swaps the help text and the instance" —
UI text and default-URL prefill only, confirmed by reading those three
steps and `grep -n "forge:" test/drive_window.rb`, which returns only the
one `'github'` literal). Their `request`/notification-parsing methods are
never driven by any suite — not the drive script, not `check_models.rb`,
not `spec/`. That is a real, three-of-four-backends gap in what the
runtime gate actually reaches, not closed by any suite today; it predates
this round (the `FakeSession` comment has said "GitHub backend" since it
was written) but no previous pass of this report named it. See
`.reports/accountability-ensurance.md` for this recorded as a finding.

## Rules followed

- Both extra suites and the spec suite were **re-run in this audit's own
  session**, inside the dev shell against a real (virtual) display, not
  read off a prior claim.
- No upstream test was invented to pad the 0/0; the GJS app genuinely ships
  none.
- A number quoted by a previous pass of this exact report was checked
  against a live re-run rather than carried forward, which is what caught
  the 207-vs-201 discrepancy above.
