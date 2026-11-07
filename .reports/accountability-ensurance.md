# Accountability ensurance — forge-sparks

Scan: `find-excuses.sh` over `lib/`, `exe/` (clean — no excuse construction
found in the port's own source) and over `.reports/`, `PORTING.md` (no
`PORTING.md` exists on this branch). The excuse-construction scanner is not
where this round's finding is, which is itself worth saying: the danger here
is not a labeled skip, it is a **report that states completeness while
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

## Finding 2 — a declared dependency with no caller

`forge-sparks-rb.gemspec:110` adds `ashpd` as a runtime dependency, by a
commit titled "Wire in the gemspec's missing runtime dependencies and
ashpd." `ashpd` is a Ruby binding to the XDG Desktop Portal — the exact
thing `lib/util.rb:26` and `lib/preferences_dialog.rb:17` both say, in
comments, does not exist ("There is no portal binding for Ruby" /
"There is no portal binding either"). `grep -rn "ashpd\|Ashpd" lib/ exe/`
returns nothing. Either the comment is stale and the gem was added to use
later and never was, or the gem was added without checking what it does.
Either way the gemspec now ships a dependency the app never loads, and the
comment beside the feature it would implement asserts something the
gemspec contradicts. One of the two is wrong and nobody reconciled them.

## Finding 3 — dead code shaped like an unfinished adaptation

`Util.sandboxed?` (`lib/util.rb:79`, checks `/.flatpak-info`) has no caller
anywhere in `lib/` or `test/`. It reads as a half-finished attempt to gate
the autostart-file substitute on sandbox state — exactly the gate that
Finding 1's gap needs — abandoned before it was wired to anything. Not
reported as an excuse (there is no comment claiming it is unused on
purpose), but it is the shape of exactly what this skill warns about: work
started toward closing a gap, stopped, and left silent rather than recorded
as an owed behaviour.

## Finding 4 — a green test command that tests nothing

`rake spec` and the dev shell's advertised "run the specs" command both
execute RSpec against `spec/`, which holds only `spec_helper.rb` and
`README.md` — zero `*_spec.rb` files. Both commands exit 0 with "0
examples, 0 failures." Nobody has yet mistaken this for a passing suite in
any report reviewed for this audit, so it is not (yet) a false claim
anywhere written down — it is flagged here because it is loaded exactly like
one: a command that reads as "the tests pass" and has never run a single
assertion. See `.reports/test-parity.md` for the suites that are real
(`test/check_models.rb`, `test/drive_window.rb`, both re-run live this
audit) and are not this.

## What is clean

- No excuse-construction (`by design`, `not applicable`, `out of scope`,
  `dropped deliberately`, etc.) exists anywhere in `lib/` or `exe/`.
- No `PORTING.md`, `FINDINGS.md`, `COMPONENT_PARITY.md` or `TEST_PARITY.md`
  exists on this branch to carry a stale ledger claim forward — this audit's
  five reports under `.reports/` are the first parity ledgers written for
  this port.
- The runtime gate's own numbers (207 checks / 70 checks, both 0 failed)
  were reproduced live in this session, not copied from the task prompt.

## Verdict

**Not clean.** The most serious finding — a report's own verdict
contradicting the behaviour its own prose documented three paragraphs
earlier — is exactly the failure mode this skill is for, and it was found in
the one document this org already trusted as settled.
