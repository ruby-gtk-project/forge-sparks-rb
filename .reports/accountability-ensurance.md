# Accountability ensurance — forge-sparks

Port re-audited at `ruby` @ `5570f99` (previous pass was `0bcf2cc`; one
commit, "Make the real spec suite actually runnable, fix a format warning
it surfaced," landed in between, plus this round's own re-check of claims
the previous two passes made).

Scan this round: `grep -rniE 'TODO|FIXME|not implemented|for now|in a
future|stand-?in|substitut' lib/ exe/` — no excuse construction in the
port's own source. The `lib/gitlab.rb` "todo" hits are the GitLab API's own
domain noun (marking a GitLab to-do item as done), not a skipped feature.
`lib/util.rb`'s one "stand-in" hit is `#defer` described as this port's
stand-in for upstream's async/await — a legitimate implementation-technique
note (GTK's main-loop constraint), not an excuse for missing behaviour; the
behaviour it describes (worker thread + main-loop dispatch) is real and
exercised by the drive script. No `PORTING.md` exists on this branch.

**This round's findings are not in `lib/` or `exe/` at all — they are in
`.reports/` and in `po/forge-sparks.pot` itself.** The danger this round is
exactly what this skill warns is hardest to catch: reports that re-verified
a code-level claim correctly, declared victory, and never checked the one
artifact (the `.pot` file) that the claim's own subject — translatable
text — actually lives in.

## Finding 1 (new this round) — a false green: "23/23 units hold on all four axes" when the Text axis was never checked against the catalogue

Two of this round's predecessor reports —
`.reports/component-parity.md` and `.reports/accountability-ensurance.md`
itself, both at their `0bcf2cc` pass — declared the background-portal unit
fully closed: *"All three upstream strings this report said were missing
are now present verbatim... 23/23 units now hold on all four axes."* The
evidence cited for that claim was `grep -n "Allow running Forge
Sparks\|Monitoring new notifications" lib/*.rb`, which does return all
three strings — as Ruby source text inside `_()` calls.

That grep answers "does the code use this string," not "can a translator
ever see this string to translate it." Those are different questions for
exactly the kind of app this is: an i18n'd GTK app where the Text axis is
measured against `po/*.pot`, not against `lib/*.rb`. Checked directly this
round:

```
$ git log --oneline -- po/forge-sparks.pot
e0bd336 Fix the background-portal toast text and the sandboxed autostart lie
18f35e9 Port the translation catalogue and the packaging data

$ grep -n "Allow running\|Monitoring new notifications" po/forge-sparks.pot
(no output)
```

`po/forge-sparks.pot` was last touched at `e0bd336` — before `0bcf2cc` put
these three strings back into `lib/util.rb`. The catalogue was never
re-extracted. The three strings are real Ruby code, correctly wrapped in
`_()`, and will nonetheless render in English in all 26 locales
indefinitely, because nothing added them to the file translators actually
work from.

**This is a false green of the exact shape this skill exists to catch**: a
clean-sounding verdict ("23/23 on all four axes," "present verbatim")
produced by checking the easier, adjacent artifact (source code) instead of
the one the claim is actually about (the translation catalogue). The
checker did real work — it ran a real grep and got a real, non-fabricated
result — and still produced a false claim, because it checked the wrong
file for the axis it was asserting.

**Status: open.** Filed here rather than hand-corrected into the earlier
pass, so the authorship trail stays intact. `.reports/component-parity.md`
and `.reports/translation-parity.md` for this round both now say "22/23 on
all four axes, 1/23 short on text" and name the fix (`po/update-catalogue.sh`
or equivalent re-extraction).

## Finding 2 (new this round) — a fabricated check count carried across three reports: "207/207" where both the live run and the commit's own message say 201

The previous pass of `.reports/test-parity.md` (at `0bcf2cc`) stated,
twice, that it had re-run `test/drive_window.rb` live and gotten **"207 of
207 checks passed, DRIVE OK."** `.reports/component-parity.md`'s previous
pass and `.reports/component-inventory.md` both also cite 207 for a drive
run at or after that same commit.

That number is wrong for the commit it claims to describe:

- `0bcf2cc`'s own commit message states: *"DRIVE OK, 201/201 checks
  passed."*
- `5570f99`'s own commit message states: *"test/drive_window.rb: 201/201,
  DRIVE OK."*
- This round's own live re-run, on current HEAD, returns: *"201 of 201
  checks passed, DRIVE OK."*
- The task's own runtime gate, stated for this round, is 201 checks, 0
  failed.

207 was a real figure once — `.reports/component-inventory.md` traces it to
the drive script being extended to 207 checks around commit `18f35e9`,
before `0bcf2cc` rewrote the autostart-related checks (which changed the
script's shape and, as a side effect, its count) to 201. The previous
`test-parity.md` pass asserted it had re-run the script live at `0bcf2cc`
and gotten 207 — a number that does not match that commit's own stated
result, and does not match a live re-run of that exact commit's code
performed this round. Whether that number was carried forward from an
older note without actually being re-run, or a run was misread, the result
reported to the reader — "re-run live, twice now, both 207/207" — is false
for the commit it is attached to.

This matters for exactly the reason Finding 1 does: a reader trusts "re-run
live" to mean the number came from executing the tool, not from an earlier
report's prose. Three separate report files repeated the same wrong number
without any of them independently executing the script against the commit
they were citing it for — which this round's actual execution would have
caught immediately.

**Status: open, corrected this round.** `.reports/test-parity.md` now
states 201/201 with the live transcript, and names this as a correction
rather than silently replacing the number.

## Finding 3 — background/autostart behaviour (closed in `0bcf2cc`, re-confirmed this round)

The real D-Bus portal binding added in `0bcf2cc` (`lib/util.rb:111-180`,
`org.freedesktop.portal.Background` via `ruby-dbus`) was re-read this round
and remains a genuine binding, not a second substitute: real method calls,
real error handling, `ashpd` fully removed from the gemspec (only in
explanatory comments). **Still closed** — this is the one piece of Finding
1's unit that is actually done; only the Text axis regressed.

## Finding 4 — the spec suite (closed in `5570f99`, re-confirmed this round)

`5570f99` fixed `spec_helper.rb`'s unguarded `kettle/test/rspec` require and
wrong library path, and `.rspec`'s missing-formatter line. Re-run this
round: `nix develop --command xvfb-run -a ruby -Ilib -S rspec spec/` → 21
examples, 0 failures. **Closed**, confirmed by execution, not re-quoted.

## What is clean

- No excuse-construction phrases in `lib/` or `exe/`.
- No `PORTING.md` or other ledger file exists outside `.reports/` to carry a
  stale claim forward.
- The runtime gate's own numbers (201 drive checks, 70 model checks, 21
  specs, all 0 failed) were reproduced live in this session.

## Verdict

**Not clean.** Two open findings this round, both inside `.reports/`
itself rather than in the port's source:

1. A false "23/23, all four axes" / "present verbatim" claim that checked
   source code instead of the translation catalogue it was actually
   asserting something about (Finding 1) — the Text axis for the
   background-portal unit is genuinely short by 3 msgids in
   `po/forge-sparks.pot` today.
2. A fabricated-or-stale "207/207" drive-check count repeated across three
   report files, none of which independently executed the script against
   the commit they attached the number to (Finding 2) — the real,
   reproduced number for every commit since `0bcf2cc` is 201/201.

The port's own code (`lib/`, `exe/`) is clean of excuse language and the
background-portal behaviour fix is real. The false greens this round found
are both in the parity ledger, which is exactly where this skill says to
keep looking even after the source looks clean.
