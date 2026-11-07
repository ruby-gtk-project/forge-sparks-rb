# Accountability ensurance — forge-sparks

Port re-audited at `ruby` @ `e0bd336` (previous pass was `3f45b15`; one
commit, "Fix the background-portal toast text and the sandboxed autostart
lie," landed in between and is accounted for below).

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

**Status this round: still open.** One commit (`e0bd336`) landed on the
branch between the previous pass and this one, and it fixed two real bugs
in the code (see Finding 3 and `.reports/component-parity.md`), but it did
not touch `.reports/component-inventory.md`. Re-read this round, line
411-412 still reads "23 of 23 are done ... Nothing identified by this survey
remains unported," and line 12 still reads "No gaps remain at the
file/component level," and line 293 still reads "Present: **yes**" for
`lib/util.rb`. All three are still false: the background-portal permission
request and its "Monitoring new notifications" status message are still not
ported, for a reason now well-documented (`ashpd` 0.1.1 cannot bind that
portal) but still not ported. A false green that survives one commit cycle
unnoticed is exactly the risk this finding is for.

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

What remains, and is worth recording even though it is no longer a false
claim: `forge-sparks-rb.gemspec:110` still declares `ashpd` as a runtime
dependency, and `grep -rn "ashpd\|Ashpd" lib/ exe/` still returns nothing —
`require 'ashpd'` appears nowhere in the app. The gem is dead weight: an
honestly-documented reason it isn't used is not the same as it being used,
and every install still pulls in a gem the app never loads. Either drop the
dependency (and say in the comment that it was tried and found not to
cover this portal, rather than keeping it installed) or find a use for it
elsewhere the app actually needs a portal (e.g. `Screenshot` or `OpenUri`,
both of which are things forge-sparks arguably could use and does not yet).

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

**Not clean.** Two of the previous pass's four findings are genuinely
closed this round (Finding 3, the dead `sandboxed?` guard, now wired in;
and half of Finding 2, the comment that used to contradict the gemspec,
now doesn't). Finding 1 — `.reports/component-inventory.md`'s "23 of 23,
nothing remains unported" standing uncorrected next to the behaviour it
itself describes as missing — is unchanged and still the most serious item
here: it is a false green that survived an entire commit cycle that fixed
two real bugs in the exact feature it claims is done, without anyone
touching the report. Finding 4 (the empty `spec/` suite reading as a green
test command) is also unchanged. Fixing code without correcting the
document that claims the code was already fine is itself worth flagging:
it is evidence the inventory is not being read as a live ledger by whoever
is doing the fixing.
