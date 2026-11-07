# Accountability ensurance — forge-sparks

Port re-audited at `ruby` @ `0bcf2cc` (previous pass was `e0bd336`; one
commit, "Bind the real XDG background portal over D-Bus, write real specs,"
landed in between — plus this round's own fix to make the specs it added
actually runnable — and both are accounted for below).

Scan: `find-excuses.sh` re-run this round over `lib/`, `exe/` — still clean,
no excuse construction in the port's own source — and over `.reports/`
(no `PORTING.md` exists on this branch). The only hits inside `.reports/`
are the scanner matching this document's and others' own prose *discussing*
excuse phrases ("by design", "n/a", "unported", etc. appearing as quoted
examples of what to watch for), not an excuse actually being made; read in
context, none of them is live. The excuse-construction scanner is not where
this round's finding is, which is itself worth saying: the danger here is
not a labeled skip, it is a **report that states completeness while
documenting, in its own prose, the gap that contradicts the claim.**

## Finding 1 — a false green in `.reports/component-inventory.md` (the most serious kind)

The report's closing line:

> "23 of 23 are done — full parity at the component/file level. **Nothing
> identified by this survey remains unported.**" (`.reports/component-inventory.md:411-412`)

and its header:

> "No gaps remain at the file/component level." (`.reports/component-inventory.md:12`)

Both are stated as settled fact. Yet the same document's own body, 40 lines
earlier, describes exactly the feature this audit found missing:

> "`portal` — `Xdp.Portal`; `requestBackground(window, autostart, hidden)`
> with the user-visible reasons ... `setBackgroundStatus` with `"Monitoring
> new notifications"`." (`.reports/component-inventory.md:286-289`, describing
> upstream's `src/util.js`)
>
> "Present: **yes**." (`.reports/component-inventory.md:293`, verdict for
> `lib/util.rb`)

`lib/util.rb` contains no `Xdp::Portal` reference, no `requestBackground`,
no `setBackgroundStatus`. It contains, instead, an autostart-file write and a
comment explaining the substitution (`lib/util.rb:25-28`). The inventory
documented the upstream behaviour accurately and then marked the file
"Present: yes" anyway — the verdict was written against the file existing,
not against the behaviour inside it. That is precisely the mechanism this
skill exists to catch: a reader of the inventory walks away believing the
background portal is ported, because the document that would have told them
otherwise told them "yes" instead.

This is not an excuse-phrase (no "by design", no "n/a" — the scanner correctly
found nothing there). It is worse: a clean-sounding verdict sitting directly
beside the evidence that contradicts it, which means a grep for excuse
language will never find it. Read the verdict against the behaviour it
claims to cover, not against the file path, or this exact failure repeats.

**Correction owed:** `.reports/component-inventory.md`'s verdict for
`src/util.js → lib/util.rb` and its closing summary both need to say the
background-portal behaviour is missing, not "yes" / "nothing remains
unported." Filed here rather than hand-edited into that report, so the
inventory's own authorship trail stays intact for whoever reads it next; see
`.reports/component-parity.md` and `.reports/translation-parity.md` for the
gap itself.

**Status this round: closed — the behaviour caught up with the claim.**
Commit `0bcf2cc` ("Bind the real XDG background portal over D-Bus, write
real specs"), landed after this finding's last pass, rewrote
`Util.request_background`/`Util.set_background_status` to speak
`org.freedesktop.portal.Background` directly over D-Bus (`lib/util.rb:95-139`,
via `ruby-dbus`), carrying the real allow/deny semantics and all three
upstream strings this finding named as missing — verified live this round
(`grep -n "Allow running Forge Sparks\|Monitoring new notifications"
lib/*.rb` finds all three). `lib/util.rb:293`'s "Present: **yes**" is no
longer a false statement about this behaviour; it is now true. This is the
inverse of the usual failure this skill looks for — a prior round's
documented false green turning out, on the *next* round's re-check, to have
been fixed in the code without the inventory being corrected first — so it
is recorded here rather than silently dropped: the previous finding was
correct when written, and the gap it named is the one commit `0bcf2cc`
closed.

## Finding 2 — a declared dependency with no caller (downgraded this round: no longer a false claim, still dead weight)

At the previous pass (`3f45b15`), `lib/util.rb` and `lib/preferences_dialog.rb`
carried comments claiming "there is no portal binding for Ruby," while the
gemspec declared `ashpd` — which is exactly such a binding — as a dependency,
contradicting the comment. That contradiction is fixed in `e0bd336`: both
comments now say, specifically, that `ashpd` 0.1.1 has no `Background`
portal binding (only `Account, Camera, OpenUri, Screenshot, Settings,
Trash`), and state that this was checked live via `Ashpd.constants`. This
audit reran that check itself (`nix develop --command ruby -e "require
'ashpd'; puts Ashpd.constants.sort"`) and confirms the claim is true — not
re-asserted, actually re-verified.

**Closed this round.** `0bcf2cc` dropped the dead dependency outright:
`forge-sparks-rb.gemspec` no longer declares `ashpd` (`grep -n ashpd
*.gemspec` finds it only inside an explanatory comment, not a
`spec.add_dependency` line), and `nix/Gemfile(.lock)`, `nix/gemset.nix` and
`flake.nix` had its platform-gem nix machinery removed alongside it. The
app now declares and uses `ruby-dbus` for exactly the portal call `ashpd`
could not make. Re-verified this round: `grep -rn "ashpd\|Ashpd"
lib/*.gemspec lib/*.rb` returns only the explanatory prose quoted above,
never a `require` or a dependency declaration.

## Finding 3 — dead code shaped like an unfinished adaptation (closed this round)

At the previous pass, `Util.sandboxed?` (`lib/util.rb:79`, checks
`/.flatpak-info`) had no caller anywhere in `lib/` or `test/` — exactly the
shape of work started toward closing a gap and abandoned before being wired
to anything. `e0bd336` wired it in: `Util.request_autostart`
(`lib/util.rb:103-108`, current line numbers) now calls `sandboxed?` first
and refuses the request if true, instead of reporting a no-op file write as
granted. Re-read this round: the method now has a real caller and a real
effect on behaviour. This finding is closed, not by excusing the gap it
pointed at, but by the gap actually being narrowed (false-success removed,
even though the underlying "no real portal" limitation remains — see
Finding 1 and `.reports/component-parity.md`).

## Finding 4 — a green test command that tests nothing (closed this round)

`0bcf2cc` added `spec/util_spec.rb` and `spec/settings_spec.rb`, so `spec/`
is no longer empty, but as found at the start of this round those specs
could not actually run in this fork's own dev shell: `spec_helper.rb`
hard-required `kettle/test/rspec` (a dev-only gem not present on this
flake's `GEM_PATH`) and `"forge/sparks/rb"` (a module path with no matching
file — the real entry point is `lib/forge_sparks.rb`), and `.rspec` named a
`RspecJunitFormatter` that also isn't installed. Every one of those would
have made `rspec spec/` die before running a single example, the same
false-green shape this finding originally called out, just with a crash
instead of a silent 0/0. Fixed this round: `kettle/test/rspec` is now
behind the same `rescue LoadError` guard already used for
`kettle-soup-cover`, the library require points at `forge_sparks`, and
`.rspec` no longer names the missing formatter. Confirmed live: `nix
develop --command xvfb-run -a ruby -Ilib -S rspec spec/` → **21 examples, 0
failures** (two re-runs with different random seeds, same result). See
`.reports/test-parity.md` for the full account, including a real
`format`-argument warning the spec run surfaced and this round also fixed.

## What is clean

- No excuse-construction (`by design`, `not applicable`, `out of scope`,
  `dropped deliberately`, etc.) exists anywhere in `lib/` or `exe/`.
- No `PORTING.md`, `FINDINGS.md`, `COMPONENT_PARITY.md` or `TEST_PARITY.md`
  exists on this branch to carry a stale ledger claim forward — this audit's
  five reports under `.reports/` are the first parity ledgers written for
  this port.
- The runtime gate's own numbers (201 checks / 70 checks / 21 specs, all 0
  failed) were reproduced live in this session, not copied from the task
  prompt or an earlier report.

## Verdict

**Clean, this round.** All four findings this report carried forward are
now closed: Finding 1 (the inventory's "23 of 23" claim) is no longer false
— `0bcf2cc` made the background-portal behaviour real, so the claim and the
code now agree. Finding 2's dead dependency is gone, not just
honestly-commented. Finding 3 stayed closed. Finding 4's specs now actually
run, after this round's fix to the scaffold that was silently blocking
them. Re-checked live, not asserted: `find-excuses.sh` still clean over
`lib/`, `exe/`, no `TODO`/`FIXME`/`not implemented`/`for now` anywhere in
either (the only "todo" hits are GitLab's own domain noun, `lib/gitlab.rb`),
`test/drive_window.rb` (201/201 — the autostart checks changed shape to
match the real D-Bus call, not a filesystem stand-in, but still 0 failed),
`test/check_models.rb` (70/70) and `spec/` (21/21) all re-run this session.
This verdict does not retroactively bless the previous rounds' "Not clean"
calls — they were correct when written, against the code that existed
then.
