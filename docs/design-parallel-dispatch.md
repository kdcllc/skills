# Design: Bounded-Concurrency Dispatch for the Autonomous Loop

**Status**: DESIGN ONLY for everything below still marked *Proposed* — a proposal, not
shipped behavior. **Exceptions**: §3.2 parts 1–3 (write-temp-then-rename, the terminator
check, and torn-retry/fail-safe-OPEN) shipped in STORY-009 (kit v0.10.0); §1 (slot
accounting), §2 (worktree lifecycle), and §5 (per-slot failure/rollback) shipped in
STORY-010 (kit v0.11.0) — each marked **Shipped — STORY-010, v0.11.0** in place below,
with two argued deviations recorded where the relevant section text sits: (i) a
**double dark launch** — §1's `LOOP_SLOTS` ships guarded to `1` regardless of its
default-2 value, and §2's worktree isolation ships STAGED behind `LOOP_WORKTREE`
defaulting to `0` (main-tree iteration unchanged) — both held back until STORY-011's
driver-owned dispatch, goal-judged because no backlog story yet declares a `writes:`
set (§6 is unimplemented, so nothing prevents two slots double-dispatching the same
story) and because worktree execution is inoperable in gitignored-instance repos
without the preflight this story added *(STORY-011 shipped, v0.12.0: the double-dark-launch
hold is resolved — see the STORY-011 additions below)*; (ii) §5's closing note that the kill-0 poll
loop "must be reflected in the parity heuristic at `.claude/checks.sh:26-35`" was
deliberately **not** done — `.claude/checks.sh` is untracked instance tooling, not the
parity home; the tracked harness (`tests/loop-harness/run.sh`, assertion 53 and others)
carries this parity instead. §3.2 part 4, §3.3, §4, §6, §7, and everything else marked
*Proposed* remain unimplemented *(as of STORY-010; see STORY-011 scope below)*;
STORY-010 also ships quarantine-lite only (branch
retained, not integrated, and reported at exit — no marker file) — full quarantine
remains STORY-012. No other file under
`skills/setup/templates/` or `_loop/` changed beyond what STORY-010 required
*(STORY-011 also changed `loop/SKILL.md`, `PROMPT.md`, and `backlog.md`)*.

**STORY-011 scope (kit v0.12.0)**: §4 (driver-owned story selection/dispatch), §6
(write-set admission and single-writer integration), §3.2 part 4 (single-ownership
breaker — breaker moves entirely into driver process), §3.3 (per-slot CB1/CB2 counters
with driver-table state under N>1 dispatch), and §7.1/§7.2 partially (see the in-place
deviation notes at the relevant sections below) — §4, §6, §3.2 part 4 and §3.3 each
marked **Shipped — STORY-011, v0.12.0** in place; §7.1/§7.2 carry in-place deviation
notes only. Recorded deviations from the design: (i) **dual-mode auto-loop
skill** — `auto-loop` now handles both manual and dispatched invocations; (ii)
**protected-path writes REFUSED** at dispatch, not deferred (admission test runs before
the slot runs, not after); (iii) **N>1-iff-worktree guard** replaces STORY-010's
dark-launch: `LOOP_SLOTS>1` is honored iff `LOOP_WORKTREE=1`; at `LOOP_WORKTREE=0`
`EFFECTIVE_SLOTS` clamps to 1, with a one-line stderr note fired only when `LOOP_SLOTS>1`
was explicitly requested (supersedes the
double-dark-launch); (iv) **compaction/archival deferred to manual**, with a driver-side
slot prohibition — the driver does not compact or archive; manual compaction must not
run while slots are live. **PRECONDITION note** (§6's fast-forward narrative and §2's
discussion at :253): same-round sibling branches diverge after the first integration
commit, so the integrator rebases then ff-merges; a rebase conflict aborts → exit 5
with artifacts retained. This is recorded near the §6 fold-back summary at :807-818
rather than as a deviation, because `:253` already permits "fast-forward-or-rebase". §7.3
(exit-code aggregation) and all remaining *Proposed* items remain design-only; full
quarantine remains STORY-012. *(Resolved by STORY-012, kit v0.13.0: §7.3's exit-code
aggregation and §5's full quarantine (slot retirement + quarantine markers) both
shipped — see the in-place "Shipped — STORY-012" notes at §5 :567-606 and §7.1/§7.2/§7.3
below.)*

**Pattern source**: squad's WIP-limited self-refilling dispatch —
`available-slots = max(0, 3 - active PRs)`, refill on merge
(`docs/research-squad-ideas.md:125-127`). That line is the seed; almost none of this
document is about slot arithmetic, because slot arithmetic is the easy part.

**Citation convention (read this once)**: where a quoted current-behavior line contains
a kit template placeholder, this document renders that placeholder with inner spaces —
`{{ IDE_DIR }}`, `{{ PROJECT_NAME }}`, `{{ LOOP_MODEL_CHAIN }}` — so the kit's
unresolved-placeholder scan never flags a design note that merely *quotes* the
templates. This mirrors the precedent at `.claude/checks.sh:11-14`, where the checks
script excludes itself from its own patterns because it necessarily contains them.
Every quotation in this document is otherwise byte-faithful to the cited line.

**Anti-invention rule applied here**: every "currently" claim below carries a
`file:line` anchor that was read before it was cited. Where the design proposes
something new, it says *Proposed*.

---

### The counter-position this design must answer

`docs/research-designing-conflict-free-multi-agents.md` is not background for this
design — it is a direct argument against the obvious implementation. Its decisive
claims:

- *":65"* — file locks / leases / CAS are "Overkill for a design-time-partitioned
  system; keep as a last-resort fallback only."
- *":67"* — "prevention lives in the planning layer (write-sets) and the prompt layer
  (fences)… **You do not need locks, CRDTs, or worktrees if the plan guarantees
  disjointness.**"
- *":23"* — worktree-per-agent isolation (Copilot `/fleet`, Claude Code
  `isolation: worktree`) is "precisely the after-the-fact reconciliation the user wants
  to avoid."
- *":113-118"* — Stage 5 sketches write-set admission aimed at *this* loop: story
  sizing = one ownership boundary; a claimed-paths ledger where "the loop refuses to
  dispatch a task whose `writes` intersect an unfinished task's claim."

**Where this design lands (stated up front, argued in Rejected alternatives).** The
counter-position is *adopted* for what it actually covers — write–write conflicts on
source files — and *rebutted* on its sufficiency claim for this specific system. The
rebuttal is one sentence long: **git's HEAD, index, and working tree are a shared
non-file surface, and the loop's own rollback primitive operates on it globally.**
`loop.sh:111-114` diffs `"$head_before" HEAD` and, on a violation, runs
`git reset --hard "$head_before"` against the whole tree. Two iterations sharing one
working tree do not need to touch the same *file* to destroy each other; slot B's commit
merely has to land between slot A's `head_before` capture (`loop.sh:79`) and slot A's
CB0 check. Disjoint write-sets do not make HEAD disjoint. The research doc's own
vocabulary already names this case: ATM's rule that "physical disjointness remains
necessary but not sufficient" — two intents writing physically disjoint regions are
still blocked when they touch "a shared non-file surface"
(`docs/research-designing-conflict-free-multi-agents.md:18`).

So the chosen design is a **three-layer hybrid**, each layer justified separately:

| Layer | Mechanism | Justification |
|---|---|---|
| Source files | Declared write-sets, checked at dispatch (planning-layer admission) | Adopted directly from `:59` / `:113-118`. |
| Git state (HEAD, index, worktree) | One git worktree per slot | *Not* isolate-and-merge repair — it is the only way the existing `git reset --hard` rollback stays scoped to one slot. |
| Shared loop memory (backlog / LEARNINGS / ESCALATIONS) | Single serialized integrator; slots never write these files | Adopted from the single-writer principle at `:4` and `:37`. |

Locks appear exactly once, as `:65` permits: nowhere in the steady-state path. There is
no backlog lockfile, no claim lease, no breaker mutex. Exclusivity is achieved by
*single ownership of the resource* (`:64`) — the driver owns dispatch, the integrator
owns shared memory, the driver owns breaker state.

---

## 1. Slot accounting

**Shipped — STORY-010, v0.11.0.** `LOOP_SLOTS` (default 2, clamped `[1, 3]`,
`loop.sh:57-58`; twin `loop.ps1:87-88`), the startup banner (`loop.sh:94`; twin
`loop.ps1:131`), and the `available_slots = max(0, EFFECTIVE_SLOTS - active_slots)`
formula (`loop.sh:196-201`; twin `loop.ps1:277-282`) all shipped as designed. One argued
deviation: a dark-launch guard holds *effective* concurrency at 1 regardless of the
configured value, warning on stderr when `LOOP_SLOTS>1` is explicitly requested, until
STORY-011's driver-owned dispatch (§4/§6) exists — running two live slots today would
double-dispatch the same backlog story with no admission rule (§6) to stop it, since no
story yet declares a `writes:` set. See the Status block above for the full argument.
*(Superseded by STORY-011, v0.12.0: the dark-launch guard is replaced by the
N>1-iff-worktree rule — `LOOP_SLOTS>1` is honored iff `LOOP_WORKTREE=1`; see the
guard replacement comment at `loop.sh:93-112`.)*

**(c) Current behavior.** The driver is a strictly serial `for` loop:
`for ((i = 1; i <= MAX_ITER; i++))` with `MAX_ITER="${1:-10}"` (`loop.sh:23,66`; twin at
`loop.ps1:25,113`). One CLI invocation per iteration (`loop.sh:91`), one story per
invocation — "You perform **exactly one iteration**: one story, one commit, then stop…
Never start a second story" (`templates/loop/SKILL.md:8-9`). There is no concept of a
slot anywhere in either driver.

**(a) Proposed artifact.** A `LOOP_SLOTS` environment variable read by both drivers,
default `2`, clamped to `[1, 3]`, echoed at startup next to the existing iteration
banner (`loop.sh:67`):

```
available_slots = max(0, LOOP_SLOTS - active_slots)
```

`active_slots` = the number of live slot child processes the driver is supervising.
**Refill trigger**: slot exit, not merge. squad refills "on merge"
(`docs/research-squad-ideas.md:125-127`) because squad's WIP unit is an open PR; this
loop has no merge event to key on — it "never pushes" (`loop.sh:12`;
`templates/loop/SKILL.md:123`) and Phase 7 is "deferred to the end of the whole run"
(`templates/loop/SKILL.md:96-97`). The kit's equivalent completion event is the slot
child process exiting, so a slot is refilled the moment its integration (§6) is applied.
`MAX_ITER` keeps its meaning as *total iterations dispatched across all slots*, so a
default run is still 10 units of work — it just finishes sooner.

**Why the default is 2, not 3 — capacity contention is a design input, not an open
question.** Three independent contention facts bound N:

1. **Subagent fan-out multiplies, not adds.** One iteration is not one agent. It runs
   the seven-phase flow with "implementer/test-writer execute, `judge` verifies every
   task and the final audit, fixes are always re-judged, 3 judge cycles max per task"
   (`templates/loop/SKILL.md:101-103`), plus Phase 6 `align-docs` per story
   (`templates/loop/SKILL.md:104-105`). The harness ceiling on orchestrator spawning is
   documented as `tools: Agent(worker, judge)` spawn allowlists with a
   **20 concurrent default** (`docs/research-multi-harness-upgrade.md:53`) — that row is
   about *judge/agent* spawn capacity, which N slots share. The binding budget is therefore
   `N × peak_concurrent_subagents_per_iteration ≤ 20`, and the slot count must be
   *chosen in fan-out units, not story units*. At an **estimated** peak of 5–8 concurrent
   subagents per iteration (an estimate — no file in the kit records a measured
   per-iteration fan-out), N=2 sits comfortably inside the ceiling and N=3 begins to
   crowd it.
2. **One provider account, one rate-limit budget.** All N slots authenticate as the same
   account through the same `LOOP_CLI` (`loop.sh:24`). Doubling N roughly doubles the
   request rate against an unchanged quota, so throughput does *not* scale linearly with
   N — past the quota knee, extra slots buy rate-limit errors rather than stories.
3. **The breaker is provider-global, and its cooldown is global too.** There is exactly
   one state file, `STATE_FILE="_goals/breaker-state.json"` (`loop.sh:28`), and its
   cooldown is 600s (`breaker.sh:14`). A single OPEN trip stalls *all* N slots, and the
   worst-case fully-rate-limited run already occupies "up to `MAX_ITER × 600s` (~100
   minutes at the defaults of 10 iterations × 600s)"
   (`templates/loop/SKILL.md:59-60`). Raising N raises the
   probability of hitting that stall without shortening it.

**(b) Failure mode prevented.** Unbounded fan-out that converts a bounded-cost serial
run into a quota-exhausting stampede: N slots each spawning a full judge/worker tree
against one account, tripping the shared breaker OPEN, and then all N sleeping the same
600s cooldown — a run that is simultaneously more expensive and slower than the serial
loop it replaced. Bounding N at the *fan-out* layer rather than the story layer is what
prevents it.

*Twin note*: `LOOP_SLOTS` is a plain environment variable, read identically as
`${LOOP_SLOTS:-2}` (bash) and `$env:LOOP_SLOTS` (PowerShell), matching how `LOOP_CLI`
and `LOOP_MODEL_FLAG` are already handled on both sides (`loop.sh:24-25`;
`loop.ps1:41-51`). No twin divergence.

---

## 2. Isolation and integration of concurrent work

**Shipped — STORY-010, v0.11.0.** The worktree-per-slot lifecycle below shipped, gated
behind a new `LOOP_WORKTREE` env var: `0` (default) is today's main-tree iteration,
unchanged; `1` runs each iteration under `.loop-worktrees/` per the mechanics below,
guarded by a tracked-instance preflight (`loop.sh:11,29-34,213-234`; twin
`loop.ps1:14,34,133-137,295-331`) — a worktree checks out tracked files only, so a
gitignored `_loop`/`_goals`/`{{ IDE_DIR }}` instance fails the preflight loudly (exit
5) rather than silently falling back to the main tree. **Deviation**: `LOOP_WORKTREE`
defaults to `0`, staging worktree isolation as opt-in rather than making it the live
default this design originally argued for — the same double-dark-launch reasoning as
§1 (no `writes:` admission yet, and worktree execution is inoperable in
gitignored-instance repos like this one's self-install without the preflight this
story added) until STORY-011's driver-owned dispatch. See the Status block above.
*(STORY-011 shipped, v0.12.0: this hold is resolved; the N>1-iff-worktree rule
replaced the double-dark-launch.)*

**(c) Current behavior.** Every iteration runs in the driver's own working tree.
`head_before="$(git rev-parse HEAD)"` (`loop.sh:79`; twin `loop.ps1:127`) captures a
single global HEAD; CB0 diffs that range and, on a violation, executes
`git reset --hard "$head_before"` (`loop.sh:111-114`; twin `loop.ps1:177-182`); CB1
compares `"$(git rev-parse HEAD)" == "$head_before"` to decide whether progress happened
(`loop.sh:121`; twin `loop.ps1:189-190`). All three assume HEAD moves only because of
*this* iteration. The kit already advises running the loop "in a worktree/container with
minimal credentials" (`skills/setup/templates/ORCHESTRATION.md:486`;
`loop.sh:11`) — but as a *sandbox for the whole run*, not as per-slot isolation.

**(a) Proposed artifact.** One git worktree per slot, created and destroyed by the
driver:

```
git worktree add -b loop/<story-id> .loop-worktrees/slot-<n> HEAD
  # … slot runs its whole iteration with cwd = .loop-worktrees/slot-<n> …
git worktree remove .loop-worktrees/slot-<n>
```

Three constraints on the path, each load-bearing:

- **Not under `_loop/`.** `_loop/**` is a protected path
  (`templates/loop/SKILL.md:13-14`; enforced at `loop.sh:111-114`), so a worktree there
  would make every slot's own scratch state look like a protected-path modification and
  trip CB0 (exit 4) on the first iteration.
- **Gitignored.** `.loop-worktrees/` must be appended to the project's `.gitignore` by
  the emitter, following the existing precedent for `_goals/breaker-state.json`
  (`skills/setup/SKILL.md:127-129`).
- **Forward slashes, no colons.** Required by the kit's Windows rules —
  "Generated filenames never contain colons… Paths in stories/tasks use forward slashes
  (git and pwsh both accept them)" (`templates/loop/SKILL.md:27-30`). `slot-<n>` and
  `loop/<story-id>` satisfy both.

**Integration** is a fast-forward-or-rebase of `loop/<story-id>` onto the run branch,
performed by the single integrator described in §6 — never by a slot, and never
concurrently.

**(b) Failure mode prevented.** Cross-slot destruction of committed work. Concretely:
slot A captures `head_before` (`loop.sh:79`); slot B commits its story; slot A finishes
and evaluates CB0 over `head_before..HEAD`, which now *contains slot B's diff*. If slot
B legitimately touched nothing protected, slot A's CB1 also misreads B's commit as A's
own progress and resets `no_progress=0` (`loop.sh:133`). If anything in the combined
range trips CB0, slot A runs `git reset --hard "$head_before"` (`loop.sh:113`) and
**silently deletes slot B's commit** before exiting 4. Neither failure is a write–write
conflict on any file, so no write-set discipline prevents either; only giving each slot
its own HEAD and index does.

**A second failure mode, cheaper to state**: `git` serializes index mutations with
`index.lock`, so two concurrent `git commit` calls in one tree do not corrupt the object
store — they fail one of the two with a lock error, which the loop would surface as an
opaque non-zero `status` (`loop.sh:92`) feeding CB2's error-signature counter
(`loop.sh:137-152`). Isolation removes the contention rather than teaching the loop to
interpret it.

**Why this is not the "isolate-and-merge" pattern the research doc rejects.**
`docs/research-designing-conflict-free-multi-agents.md:23` rejects worktrees *as the
primary conflict-resolution mechanism* — as a substitute for planning-layer
disjointness, where colliding edits are reconciled after the fact. This design does not
use them that way: source-file collisions are prevented up front by §6's admission rule,
and the worktree exists to isolate a resource that is not a file at all. If §6 admission
is doing its job, integration is a fast-forward with **zero** merge conflicts, and the
worktree never performs any reconciliation. Its job is to keep `git reset --hard`
scoped. Stated plainly: this design agrees with `:67` that you do not need worktrees to
solve *file* disjointness, and disagrees that file disjointness is the whole problem
here.

*Twin note*: `git worktree add/remove` is git, not shell — identical invocation on both
twins. The only PowerShell-specific concern is worktree removal while a child process
still holds a handle inside it (Windows locks open files); the twin must `Wait-Job`/wait
for the slot process to exit before `git worktree remove`, and fall back to
`git worktree remove --force` plus `git worktree prune`. Recorded as an implementation
requirement, not an open question.

---

## 3. Breaker and counters under concurrency

### 3.1 The verified race, named exactly

Two independently verified facts combine into a silent-cooldown-erasure bug:

1. **The write was a non-atomic truncate — fixed by STORY-009 (v0.10.0).** Before
   STORY-009, `_breaker_write` — "The ONE place that serializes the schema" — wrote a
   brace group redirected with `>` directly into the state file: ten `printf` calls
   between `{` and `} > "$file"`. The `>` truncated the file to zero length *before* the
   first `printf` ran, and there was no rename, no `fsync`, no temp file. Between
   truncation and the final `printf '}\n'` there was a window in which the on-disk file
   was a zero-length or partially-written prefix of a valid state. The PowerShell twin
   had the same shape — a single `[System.IO.File]::WriteAllText(...)`, which also
   truncated before writing. **Shipped fix**: `_breaker_write` (`breaker.sh:143-161`)
   now writes the same ten `printf` calls (`breaker.sh:148-158`) to a sibling temp file
   `"$file.tmp.$$"` (`breaker.sh:159`) and then `mv -f`s it onto the target
   (`breaker.sh:160`) — POSIX `rename(2)` on the same filesystem is atomic, so no reader
   can ever observe a partial file. The twin writes to `"$Path.tmp.$PID"` via
   `[System.IO.File]::WriteAllText` (`breaker.ps1:142-172`, write call `breaker.ps1:170`)
   and then atomically `[System.IO.File]::Move($tmp, $Path, $true)` (`breaker.ps1:171`).
2. **An unparseable read reseeded a fresh CLOSED state — fixed by STORY-009 (v0.10.0).**
   Before STORY-009, `breaker_load`'s contract was "Unparseable file -> rewrite fresh
   CLOSED (same seeding) + one stderr warning", implemented as `echo "breaker:
   $state_file is unparseable — resetting to fresh CLOSED state" >&2` followed by
   `_breaker_seed "$state_file" "$chain"` — neither string exists in the shipped file;
   both are quoted here as the pre-fix text. `_breaker_seed` writes `CLOSED`,
   `fallbackIndex` 0, `currentModel` = the *first* chain entry, `openedAt` 0
   (`breaker.sh:165-169`, unchanged by this story). The validity gate it failed is now
   split into two helpers: `_breaker_valid_fields` (`breaker.sh:89-108`), which requires
   all nine keys to be present and typed, and `_breaker_terminator_ok`
   (`breaker.sh:116-123`), combined by `_breaker_valid` (`breaker.sh:128-133`) — a
   truncated file still fails trivially. The twin was identical: `Test-BreakerStateValid`
   false ⇒ `New-BreakerSeed`; today `Test-BreakerStateValid` (`breaker.ps1:127-132`)
   combines `Test-BreakerFieldsValid` (`breaker.ps1:88-105`) and
   `Test-BreakerTerminatorOk` (`breaker.ps1:113-122`).

**The race (as it stood before STORY-009)**: with two drivers (or, before this design,
any second process) touching `_goals/breaker-state.json` (`loop.sh:28`), a reader that
grepped the file (`_breaker_get`'s `grep -m1`, `breaker.sh:70`) *during* another
process's truncate-write observed a torn file, declared it unparseable, and **reseeded a
fresh CLOSED state that erased an OPEN cooldown**. The damage was not a lost counter: it
reset `state` to CLOSED (so the loop immediately resumed full-rate calls against a
provider that had just rate-limited it), reset `openedAt` to 0 (so the 600s cooldown at
`breaker.sh:14` never elapsed because it never started), and reset `fallbackIndex` to 0
and `currentModel` to the chain's *preferred* entry — the exact model that had just been
rate-limited, undoing the fallback that `breaker_record` had just performed
(`breaker.sh:353-362`). The observable symptom was a loop that hammered a limited
provider on its most expensive model while printing a warning that looked like benign
corruption recovery.

**Shipped fix (STORY-009, v0.10.0)**: `breaker_load` no longer reseeds CLOSED on an
unparseable read. A torn read (fields fine, terminator missing) gets up to three
retries with a ~50ms backoff (`breaker.sh:279-286`; twin `breaker.ps1:301-306`); a read
that is still invalid after that fails SAFE to OPEN — `echo "breaker: $state_file is
unreadable — failing SAFE to OPEN" >&2` (`breaker.sh:287`) followed by
`_breaker_failsafe_open` (`breaker.sh:217-249`, called at `breaker.sh:288`), which seeds
`OPEN` with `openedAt = now` and the full cooldown while preserving any
`chain`/`fallbackIndex`/`currentModel`/`totalFallbacks`/`totalRecoveries` fields that do
parse (deriving `currentModel` as `chain[fallbackIndex]` rather than blindly `chain[0]`
when it does not parse). The twin is identical:
`[Console]::Error.WriteLine(...)` (`breaker.ps1:307`) followed by
`New-BreakerFailsafeOpen` (`breaker.ps1:233-266`, called at `breaker.ps1:308`).

**Therefore a write-side lock is insufficient.** Serializing writers still leaves the
reader free to observe a torn file, because the torn file is a legal intermediate state
that no writer-side mutual exclusion removes from the reader's view.

### 3.2 Proposed mechanic — closing the READ side

Four parts. Parts 2 and 3 are the read-side closure; part 1 alone is the tempting
half-fix.

1. *(write side, necessary but not sufficient)* **Write-temp-then-rename — Shipped,
   STORY-009 (v0.10.0).** `_breaker_write` writes to `"$file.tmp.$$"` and then `mv -f`
   onto the target. POSIX `rename(2)` on the same filesystem is atomic, so no reader can
   ever observe a partial file. Twin: `[System.IO.File]::WriteAllText` to the temp path,
   then `[System.IO.File]::Move($tmp, $path, $true)` (overwrite variant, PowerShell 7+ /
   .NET Core) — atomic on NTFS via `ReplaceFile` semantics. The temp name stays
   colon-free per `templates/loop/SKILL.md:27`.
2. **A terminator-line integrity check on read — Shipped, STORY-009 (v0.10.0).** The
   schema's last line is `}` (the write's final `printf '}\n'`, `breaker.sh:158`; twin
   the `'}'` element, `breaker.ps1:166`). `_breaker_valid` (`breaker.sh:128-133`) gains
   this exact condition via `_breaker_terminator_ok` (`breaker.sh:116-123`): the file's
   final non-empty line must be exactly `}`, compared after stripping a trailing CR. A
   reader that does not see the terminator knows it read a *torn* file rather than a
   *corrupt* one. This costs one `tail -n1`-equivalent and adds no dependency, honoring
   the helper's standing rule of "Zero runtime deps: no jq/python/other JSON library"
   (`breaker.sh:41-49`).
3. **Torn ⇒ retry; still-unparseable ⇒ fail SAFE, not fail OPEN-erasing — Shipped,
   STORY-009 (v0.10.0).** `breaker_load` (`breaker.sh:270-289`) splits the old single
   unparseable branch into three:
   - file absent ⇒ seed fresh CLOSED (unchanged, `breaker.sh:272-275`);
   - present but failing only the terminator check ⇒ re-read up to 3 times with a
     ~50 ms backoff (`breaker.sh:279-286`), then fall through;
   - present and *still* invalid ⇒ **does not seed CLOSED**. Seeds `OPEN` with
     `openedAt = now` and the full cooldown via `_breaker_failsafe_open`
     (`breaker.sh:217-249`, called at `breaker.sh:288`), keeping any
     `chain`/`fallbackIndex`/`currentModel`/`totalFallbacks`/`totalRecoveries` values
     that did parse. This inverts the failure default: a lost read now costs one
     cooldown, where before it erased one. Reseeding to CLOSED was the only branch of
     the whole state machine that could *weaken* protection, and it was the branch a
     race could force.
4. **Single ownership makes the race unreachable in the steady state — Shipped,
   STORY-011 (v0.12.0).** The breaker moves entirely into the driver process. Only the
   driver calls `breaker_load` / `breaker_should_skip` / `breaker_record`
   (`loop.sh:32,72-77,101`);
   slot children never open the state file. Because the driver is one process, the
   breaker is single-writer *by construction* — the research doc's "Actor model / single
   owner of a resource" row (`docs/research-designing-conflict-free-multi-agents.md:64`)
   rather than its last-resort lock row (`:65`). Parts 1–3 remain as defense-in-depth
   for the case a user runs two drivers against one repo.

**(b) Failure mode prevented.** A cooldown-erasing torn read that silently returns the
loop to full rate on its most expensive model mid-rate-limit — and, more generally, the
class where a concurrency bug degrades safety *silently* because the recovery path looks
like normal corruption handling.

### 3.3 The iteration counters, which are a different problem

**Shipped — STORY-011, v0.12.0** (extends the per-slot CB1/CB2 counters shipped in
STORY-010, see the §5 marker at :511-513, with driver-table state under N>1 dispatch).

`no_progress`, `same_error`, and `last_error_sig` are plain shell locals initialized once
before the loop (`loop.sh:62-64`; twin `loop.ps1:77-79`). They are per-*driver*, and
under N slots they are meaningless as written: CB1's `no_progress` increments on
`"$(git rev-parse HEAD)" == "$head_before"` (`loop.sh:121`), which under a shared tree is
answered by *other* slots' commits, and CB2 hashes "the last 5 lines of output"
(`loop.sh:138`) from a single capture. *Proposed*: both become per-slot state carried in
the driver's slot table, evaluated against that slot's own worktree HEAD and that slot's
own captured output; the CB1 rate-limit carve-out (`loop.sh:122-125`) is likewise
evaluated per slot against that slot's `detected` flag. Aggregation to a driver exit code
is §7's job.

*Twin note*: bash keeps the slot table as parallel indexed arrays keyed by slot number;
PowerShell keeps an array of hashtables. Both are language-native; no new primitive.

---

## 4. Story admission and claiming

**Shipped — STORY-011, v0.12.0.**

**Delineation from §6 — the two sections share a word and must not share a meaning.**
**This section (§4) answers: *which* story a given slot takes, and how exclusive
ownership of that story is won** — a one-story-to-one-slot assignment question. **§6
answers a strictly later question: given two stories that have already been claimed by
different slots, may they be permitted to run *at the same time*** — a pairwise
compatibility question. A story can pass §4 (it is free, eligible, unclaimed) and still
be refused by §6 (its write-set collides with an in-flight story), in which case it stays
unclaimed and the slot idles or takes the next candidate.

**(c) Current behavior.** Story selection lives *inside* the iteration, not in the
driver. The driver passes an unparameterized prompt — "Invoke the `auto-loop` skill and
follow it for exactly ONE iteration: pick one story from `_goals/backlog.md`"
(`templates/loop/PROMPT.md:1-2`), read fresh each iteration (`loop.sh:91`;
`loop.ps1:144`) — and the skill instructs every iteration to "Pick the highest-priority
story with `passes: false` and `attempts < 3`" (`templates/loop/SKILL.md:83-84`) and to
"Increment the story's `attempts` counter in the backlog **now** (so a crashed iteration
still counts)" (`templates/loop/SKILL.md:89-90`). The parsed fields are pinned by the
backlog's format comment: `priority`, `passes`, `attempts`, `blocked`
(`_goals/backlog.md:3-6`).

That rule is *deterministic*, which is exactly what breaks under concurrency: N slots
following it simultaneously all compute the same highest-priority story and all take it.

**(a) Proposed artifact.** **Selection moves up into the driver, and the story id moves
down into the prompt.** The driver:

1. parses `_goals/backlog.md` for eligible stories using the pinned fields
   (`_goals/backlog.md:3-6`): `blocked: false`, `passes: false`, `attempts < 3`, ordered
   by `priority` ascending;
2. filters that list through §6's pairwise admission test against currently in-flight
   stories;
3. takes the first survivor, records it in an in-memory claim table
   `slot → story-id`, and increments that story's `attempts` **itself** (moving the
   `templates/loop/SKILL.md:89-90` responsibility from the iteration to the driver, since
   the driver is now the single writer of the backlog per §6);
4. dispatches with the story pinned: `_loop/PROMPT.md` gains a substitution point so the
   slot receives *"run story `<story-id>`"* rather than *"pick a story."*

**No lockfile, no lease, no claim directory.** Steps 1–3 execute inside one
single-threaded driver process, so mutual exclusion is a property of the program's
control flow, not of a filesystem primitive. This is the research doc's "single owner of
a resource" (`:64`) and is precisely why `:65`'s "locks are overkill / last-resort" verdict
is honored rather than overridden.

The corresponding change on the skill side is a guard, not a mechanism: `auto-loop` must
refuse to select a story when one was supplied, and its existing "Never touch stories
other than the one you picked" rule (`templates/loop/SKILL.md:123`) becomes
enforceable — the driver validates that the `ITERATION: <story-id> …` line it receives
(`templates/loop/SKILL.md:141-143`) names the story it dispatched, and quarantines the
slot on a mismatch.

**(b) Failure mode prevented.** Duplicate claim: N slots each selecting the same
highest-priority story, each incrementing `attempts` on it (burning the 3-attempt cap in
one round — `templates/loop/SKILL.md:131-132`), each producing a commit for it, and each
racing to set `passes: true` (`templates/loop/SKILL.md:113`). Under today's rules this is
not a rare interleaving; it is the *guaranteed* outcome of running two iterations at
once.

*Twin note*: the claim table is an in-process associative structure — a bash associative
array (bash 4+) or parallel indexed arrays (bash 3.2-safe, matching the constraint the
breaker already documents at `breaker.sh:172-173`), and a `[hashtable]` in PowerShell,
consistent with `Read-BreakerState`'s existing use of one (`breaker.ps1:190-203`).
**If** a future story ever permits two concurrent *drivers* (explicitly not this design),
in-memory claims are insufficient and an on-disk claim becomes necessary; the twin
primitives would be `set -o noclobber` with `> "$claim"` for bash and
`[System.IO.File]::Open($claim, 'CreateNew', 'Write')` for PowerShell — both
exclusive-create, both failing loudly on contention. Listed in Open questions, not
adopted here.

---

## 5. Per-slot failure and rollback

**Shipped — STORY-010, v0.11.0** (supervision/circuit-breaker scoping, quarantine-lite).
Worktree-local rollback, CB0-stays-fatal, and per-slot CB1/CB2 counters shipped as
designed (`loop.sh:213-445`; twin `loop.ps1:295-586`); slot *retirement*
(retire-without-ending-the-run) did **not** ship — CB1/CB2 remain run-fatal `exit
2`/`exit 3` at the dark-launched N=1 (`loop.sh:440-445`) *(the dark-launch guard was
replaced by the N>1-iff-worktree rule in STORY-011, v0.12.0)*, retirement bookkeeping
deferred to STORY-012 alongside full quarantine (`loop.sh:415-418`) *(shipped in
STORY-012, v0.13.0 — see the CB1/CB2-retirement and quarantine bullets below,
:567-606)*. The quarantine
mechanic shipped as **quarantine-lite**: an abnormally-exiting slot's branch is
retained rather than integrated (the `retainedBranches` bookkeeping; its worktree is
removed — only the non-fast-forward integration stop retains the worktree,
`loop.sh:166`) but without the fuller escalation/re-dispatch machinery this section
originally sketched —
full quarantine (`_goals/ESCALATIONS.md` integration, re-dispatch at a new path) remains
STORY-012 *(shipped in STORY-012, v0.13.0, as ARGUED-DEVIATION quarantine markers rather
than the sketched ESCALATIONS-integration/re-dispatch machinery — see the quarantine
bullet below, :578-606)*. See the twin note at the end of this section for a second, deliberate
deviation on the `.claude/checks.sh` parity requirement.

**(c) Current behavior.** Failure handling is entirely global. The driver's exit-code
contract is "0 = backlog complete (sentinel found); 1 = max iterations reached without
completion; 2 = circuit breaker — no commit for 3 consecutive iterations; 3 = circuit
breaker — same failure signature 5 times consecutively; 4 = protected-path modification
detected (iteration reverted)" (`loop.sh:17-20`; identical text at `loop.ps1:18-21`)
*(pre-STORY-012 text; the shipped contract block now reads "0 = backlog complete --
the driver's own backlog re-scan …" — see loop.sh's header, `loop.sh:22-50`; twin
`loop.ps1:24-52`)*.
CB0 reverts with `git reset --hard "$head_before"` and exits 4 (`loop.sh:111-115`); CB1
exits 2 (`loop.sh:127-130`); CB2 exits 3 (`loop.sh:141-144`). Inside the iteration, the
skill's own failure path is "Do NOT commit implementation work; leave the tree clean
(`git checkout .` / `git clean -fd` limited to files you created for this story)"
(`templates/loop/SKILL.md:129-130`).

**(a) Proposed artifacts and disposition rules.**

- **Rollback becomes worktree-local.** `git reset --hard "$head_before"` and the skill's
  `git checkout . / git clean -fd` both execute with the slot's worktree as cwd, so
  their blast radius is one slot's checkout. Note what this buys beyond safety: the
  skill's "limited to files you created for this story" clause
  (`templates/loop/SKILL.md:130`) is today a *prompt-level* fence — the research doc's
  "allowed-paths write fence" row (`docs/research-designing-conflict-free-multi-agents.md:60`),
  which it rates an excellent fit but explicitly "defense-in-depth, not the primary
  guarantee" (`:61`). Under per-slot worktrees the fence acquires a filesystem boundary
  behind it, which is the promotion `:61` describes as unavailable at the tool layer
  today.
- **CB0 stays fatal to the entire run.** *Proposed and argued*: a protected-path
  modification means an iteration tried to edit the loop's own machinery —
  `_loop/**`, `{{ IDE_DIR }}/agents/**`, `{{ IDE_DIR }}/skills/**`,
  `orchestration-kit.manifest.json`, `.gitattributes` (`templates/loop/SKILL.md:13-14`;
  enforced at `loop.sh:111-114`). That is a *global integrity* failure, not a per-story one:
  the machinery is shared by every slot, so a slot that attempted to rewrite it has
  invalidated the assumptions the other slots are running under. The driver kills all
  slots, integrates nothing that has not already been integrated, and exits 4 —
  preserving the meaning of exit 4 at `loop.sh:19-20` and the guard's stated behavior at
  `skills/setup/templates/ORCHESTRATION.md:483`.
- **CB1 and CB2 become per-slot with slot retirement.** A slot that hits 3 no-progress
  iterations or 5 identical error signatures is *retired*, not run-fatal: the driver
  stops refilling it and logs the reason. Other slots continue. Aggregation to a driver
  exit code is §7.
  *(Shipped — STORY-012, v0.13.0: CB1 retires at `loop.sh:1101-1106`, CB2 retires at
  `loop.sh:1124-1129` (twin `loop.ps1:1272-1277` / `loop.ps1:1301-1306`), both inside
  `_loop_reap_slot`; a retired slot is skipped forever by FILL, with no un-retire path.
  Aggregation is the single `_loop_aggregate_exit` funnel (`loop.sh:1240-1301`; twin
  `Invoke-LoopAggregateExit`, `loop.ps1:1434-1509`), which decides 3-vs-2 from
  retirement reasons alone — any `cb2` retirement anywhere in the run wins over an
  all-`cb1` run (`loop.sh:1251-1261`; twin `loop.ps1:1447-1457`).)*
- **Quarantine instead of silent cleanup.** *Proposed*: a slot that exits abnormally
  leaves its worktree in place with a `.loop-worktrees/slot-<n>/QUARANTINE` marker file
  naming the story id and the exit code, and its branch `loop/<story-id>` is **not**
  integrated. The driver refills the slot at a *new* path (`slot-<n+k>`). This converts
  an invisible loss into a diagnosable artifact and matches the escalation posture the
  skill already takes for exhausted attempts — "append an entry to
  `_goals/ESCALATIONS.md` (story id, what failed, judge verdicts, what a human must
  decide)" (`templates/loop/SKILL.md:131-133`), except the escalation append is
  performed by the integrator (§6), never by the dying slot.
  *(Shipped — STORY-012, v0.13.0, with an ARGUED DEVIATION (D4) on marker location:
  markers are `.loop-worktrees/QUARANTINE-<branch-with-slashes-replaced-by-dashes>.md`
  siblings, not in-worktree files — the worktree is still removed and slot paths stay
  fixed 1-based (no `slot-<n+k>` re-pathing), preserving the shipped v0.11.0/v0.12.0
  lifecycle (harness 43-46/49 pin the fixed slot paths) rather than rewriting it.
  ACCEPTED LOSS, recorded rather than hidden: on the dirty-abnormal path
  `git worktree remove --force` destroys uncommitted worktree state the design's
  retained worktree would have preserved; the branch carries committed work only.
  Mitigation shipped instead of worktree retention: the marker's `dirty_paths` field
  records the `git status --porcelain` list (`none` when clean), naming the loss
  per-file even though the bytes are gone. Markers also embed the dispatched prompt
  verbatim (closing the addendum-1/§7.2 durable-evidence gap, D5) and cover every
  quarantine-lite disposal reason — `mismatch`/`abnormal`/`subset` — plus CB0-killed
  slots (`reason: killed`), flag=1 only (at flag=0 there is no worktree/branch to
  mark). Retirement reasons (`cb1`/`cb2`) decide the run's 3-vs-2 exit precedence — see
  §7.3. Implementation: `_loop_write_quarantine_marker`, `loop.sh:672-689`; callers
  `_loop_reap_slot`'s disposal, `loop.sh:1172-1197`, and `_loop_kill_other_slots`,
  `loop.sh:709-733`; twin `Write-LoopQuarantineMarker`, `loop.ps1:751-777`; twin
  callers `Invoke-LoopReapSlot`'s disposal, `loop.ps1:1346-1393`, and
  `Stop-LoopOtherSlots`, `loop.ps1:796-824`.)*

**(b) Failure mode prevented.** Two distinct ones. First, a *global* revert triggered by
one slot's misbehavior wiping other slots' healthy committed work — today's
`git reset --hard "$head_before"` at `loop.sh:113` does exactly that if the tree is
shared. Second, the inverse: one unhealthy slot (a story that cannot converge and burns
5 identical failures) terminating an otherwise productive run, which is what
per-slot-then-aggregate CB1/CB2 avoids.

*Twin note — process supervision is the one place the twins genuinely diverge.* bash
supervises with background jobs and `wait -n`; PowerShell uses `Start-ThreadJob` /
`Start-Process` with `Wait-Job -Any`. The concrete portability hazard: `wait -n` requires
bash 4.3+, and the kit already commits to bash 3.2 compatibility elsewhere — the breaker
avoids `local -n` explicitly because "bash 3.2 on stock macOS has no `local -n`"
(`breaker.sh:172-173`). *Proposed portable primitive*: a poll loop over recorded child
PIDs using `kill -0 "$pid"` plus a short `sleep`, which is POSIX and works on bash 3.2;
`wait -n` may be used as a fast path when `${BASH_VERSINFO[0]}` permits. The PowerShell
twin's `Wait-Job -Any` has no such constraint, so parity is achieved by the bash side
adopting the poll loop as its floor. This must be reflected in the parity heuristic at
`.claude/checks.sh:26-35`, which today keys on the sentinel, the five exit codes, and the
default iteration count.

**Deviation, recorded rather than silently skipped**: that last sentence's prescription
was **deliberately not done**. `.claude/checks.sh` is this repository's own untracked,
gitignored instance tooling (a self-install artifact, not shipped kit content), so it is
not the parity home for a kit feature — the tracked behavioral harness
(`tests/loop-harness/run.sh`, assertion 53 and others covering §1–§2's shipped surface)
is. `.claude/checks.sh`'s check G still only asserts the sentinel, the original five exit
codes (0–4), and the default iteration count; it was not extended to assert `LOOP_SLOTS`,
`LOOP_WORKTREE`, or exit code 5.
*(check G was extended to exit codes 0-5 in STORY-012, v0.13.0 — `for n in 0 1 2 3 4 5`,
`.claude/checks.sh:309`; the deviation's substance is unchanged: `.claude/checks.sh` is
still untracked instance tooling and still not the parity home, and it still asserts
neither `LOOP_SLOTS` nor `LOOP_WORKTREE`.)*

---

## 6. Inter-story conflict admission and shared memory

**Shipped — STORY-011, v0.12.0.**

**Scope of this section (contrast with §4).** §4 assigned each slot a distinct story.
This section decides whether two *already-claimed, distinct* stories are permitted to be
in flight simultaneously, and how the state both of them must touch is written without
conflict.

### 6.1 Admission: how the dispatcher decides two claimed stories may run concurrently

**(c) Current behavior.** Stories declare no write-set. The pinned parsed fields are
`priority`, `passes`, `attempts`, `blocked` (`_goals/backlog.md:3-6`); the only
ownership-adjacent guidance is prose — "Size every story to fit ONE context window:
small, self-contained" (`_goals/backlog.md:7-8`) — and story descriptions carry an
informal "Affected layer" note (e.g. `_goals/backlog.md:97-99`). Nothing is checkable.

**(a) Proposed artifact.** A `writes:` field in the backlog story format, listed
alongside the existing parsed fields in the format comment at `_goals/backlog.md:3-10`:

```
- priority: 4
- passes: false
- attempts: 1
- blocked: false
- writes: skills/setup/templates/loop/**, docs/design-parallel-dispatch.md
```

**Admission rule** (evaluated by the driver at step 2 of §4): two stories may be in
flight concurrently iff their `writes:` globs do not intersect, **and** neither
intersects the hotspot set defined in §6.3 while the other holds it. A story whose
`writes:` is absent or empty is treated as intersecting everything — it runs alone.
Failing admission does **not** block the story; it defers it until the conflicting story
integrates, which is exactly the "refuses to dispatch a task whose `writes` intersect an
unfinished task's claim" rule sketched at
`docs/research-designing-conflict-free-multi-agents.md:116`, lifted from the task layer
to the story layer.

**Honest limitation, stated rather than hidden.** A story's true write-set is not fully
known at dispatch time, because the goal — and its per-task write-sets — is *derived
inside* the iteration by the seven-phase flow (`templates/loop/SKILL.md:94-97`). The
declared `writes:` is therefore a human/authoring-time *upper bound*, not a computed
fact. Two mitigations, both *proposed*: (i) the slot escalates loudly rather than
silently widening if the derived goal needs a path outside the declared set — the
fail-loud rule at `docs/research-designing-conflict-free-multi-agents.md:105`; and (ii)
the integrator verifies at fold-back time that the branch's actual changed paths are a
subset of the declared `writes:`, quarantining the branch (§5) if not. This is
verification-after-the-fact for a *declaration*, not conflict repair for a *collision* —
the collision itself was prevented at admission.

**(b) Failure mode prevented.** Two concurrently running stories editing the same source
file, where the second commit either loses the first's changes or produces a semantic
mismatch that no test catches — the empirically large cost the research doc documents at
`:14` ("a conflict rate of 27.67%" across 142K+ agentic PRs).

### 6.2 Shared loop memory: the tracked-vs-gitignored split comes first

This split is not a footnote — it determines which mechanism is even *available*, and
getting it wrong means proposing git merge drivers for files git never sees.

**In THIS repository**, `.gitignore:8` ignores `_goals/` wholesale (alongside `.claude/`
at `:5` and `_loop/` at `:9`, all under the header "Self-install (dogfooding)
instance — NEVER commit", `.gitignore:1`). `git ls-files` confirms neither
`_goals/backlog.md` nor `_goals/LEARNINGS.md` is tracked. Consequences:

- These files **cannot** collide as git merges here. There is no merge to drive and no
  `.gitattributes` entry that would ever fire: a root `.gitattributes` does now exist in
  this repository, but it carries only `*.sh text eol=lf` and `*.ps1 text eol=lf`
  (`.gitattributes:2-3`) — no `merge=union` entries at all — so no merge driver applies
  to anything under `_goals/` here.
- They **can and do** collide as concurrent *filesystem* writes: two slots doing
  read-modify-write on `_goals/backlog.md` last-writer-wins each other's field updates,
  which is precisely Copilot `/fleet`'s failure mode — "If two agents write to the same
  file, the last one to finish silently wins — no merge, no error"
  (`docs/research-designing-conflict-free-multi-agents.md:23`).
- `_goals/LEARNINGS.md` does not currently exist in this tree at all, though
  `templates/loop/SKILL.md:114` requires appending to it every passing iteration.

**In an EMITTED install**, `_goals/` is typically tracked, and the setup skill already
appends merge drivers for exactly this reason: `_goals/LEARNINGS.md merge=union`,
`_goals/ESCALATIONS.md merge=union`, `_goals/*/orchestration-log.md merge=union`
(`skills/setup/SKILL.md:120-122`, under the rationale "so parallel/append-only state
merges cleanly", `:115-117`). There, git *does* see these files and merge=union *is* a
live mechanism — for appends only. Note that `_goals/backlog.md` is deliberately **not**
in that merge=union list, even in installs.

**Design consequence**: because merge=union is available in some installs and absent in
others, this design does **not** depend on it. It makes the integrator the single writer
so that union never has to fire in either environment, and treats the emitted
`.gitattributes` lines as a safety net for hand-editing humans, not as the loop's
mechanism.

### 6.3 Per-file resolution rules

The four files, each with its own rule — not one rule for the set.

**`_goals/backlog.md`** — *gitignored here* (`.gitignore:8`); *not* merge=union even in
installs. Currently mutated by every iteration in two places: `attempts` incremented at
iteration start (`templates/loop/SKILL.md:89-90`) and `passes: true` set on success
(`templates/loop/SKILL.md:113`). **Rule: slots never write it.** The driver already owns
selection and the `attempts` increment (§4 step 3); the integrator applies the
`passes`/`blocked` transitions from the slot's `ITERATION:` line
(`templates/loop/SKILL.md:141-143`). Because writes are field-level transitions applied
by one process, there is no merge and no last-writer-wins window. *Fold-back is
unnecessary for this file: it is never modified on a slot branch.*

**`_goals/LEARNINGS.md`** — *gitignored here* (`.gitignore:8`), absent from this tree;
merge=union in installs (`skills/setup/SKILL.md:120`). Two distinct problems:
- *Concurrent appends*: "Append one line to `_goals/LEARNINGS.md`… Keep it one line per
  learning" (`templates/loop/SKILL.md:114-115`). **Rule**: the slot writes its learning
  line to a per-slot outbox inside its own worktree
  (`.loop-worktrees/slot-<n>/outbox/learnings.md`, gitignored, never committed); the
  integrator appends outboxes to `_goals/LEARNINGS.md` in integration order. Single
  writer ⇒ no interleaved append, in tracked and untracked installs alike.
- *The compaction rewrite, which merge=union cannot survive*: "**Memory size gates**
  (hard, check after appending): `_goals/LEARNINGS.md` ≥ 15 KB → compact now (merge
  duplicates, summarize older entries; keep it one-read useful)"
  (`templates/loop/SKILL.md:116-118`; restated at
  `skills/setup/templates/ORCHESTRATION.md:484`). Compaction is a **wholesale rewrite**:
  it deletes and rephrases existing lines. `merge=union` concatenates both sides' added
  lines and resolves no deletions — so a branch that compacted 15 KB down to 4 KB and a
  branch that appended one line to the original 15 KB union back into 15 KB *plus* the
  new line *plus* the 4 KB summary. Union does not merely fail to help here; it actively
  resurrects the content compaction removed. **Rule**: compaction is *forbidden inside a
  slot* and is performed only by the integrator, after appends are applied, as a
  single-threaded step. A whole-file rewrite is safe precisely when there is exactly one
  writer — the same reasoning the research doc gives for whole-file rewrites under
  single ownership (`docs/research-designing-conflict-free-multi-agents.md:47`).

**`_goals/ESCALATIONS.md`** (in scope with LEARNINGS by the same gate) — *gitignored
here*; merge=union in installs (`skills/setup/SKILL.md:121`). Appended on block —
"append an entry to `_goals/ESCALATIONS.md`" (`templates/loop/SKILL.md:131-133`) — and
gated at "≥ 20 KB → move resolved entries to `_goals/archive/`"
(`templates/loop/SKILL.md:118`). **Rule**: identical to LEARNINGS — per-slot outbox,
integrator-applied append, archival move performed only by the integrator. The archival
move has the same whole-file/whole-tree character as compaction and the same
single-writer answer.

**`ORCHESTRATION.md`** (repository root) — **tracked** (`git ls-files`), 35 lines, a
pointer to the canonical template ("Edit the template in the skill's `templates/`
directory only; this file is just a pointer", `ORCHESTRATION.md:34-35`). It *does*
collide as a real git merge, because Phase 6 `align-docs` "runs **per story**, so its doc
updates land in the story's commit" (`templates/loop/SKILL.md:104-105`) and two stories
can both have doc-alignment reasons to touch it. **Rule: hotspot serialization.** It is
placed in the driver's hotspot set; at most one in-flight story may declare it in
`writes:`, and a second story declaring it is deferred rather than run concurrently.
This is the research doc's explicit prescription for hotspot files: "the answer is
**serialization, not concurrency**" (`:39-41`). Serializing it is nearly free because it
is a rarely-edited pointer file.

**`skills/setup/emitters/*.md`** — **tracked** (four files: `claude-code.md`,
`codex.md`, `copilot.md`, `cursor.md`). Also real merge collisions, and also touched by
per-story doc alignment; they are additionally coupled by the checks suite, which
requires `loop.ps1` and `breaker.ps1` to be mentioned in *all four*
(`.claude/checks.sh:36-40`). **Rule: per-file hotspot serialization, not per-directory.**
Each emitter file is independently ownable, so a story declaring
`skills/setup/emitters/claude-code.md` and one declaring
`skills/setup/emitters/codex.md` both admit and run concurrently; two stories declaring
the same emitter file serialize. The coupling caveat is stated explicitly: a change to
the *shared* emit contract (the row at `skills/setup/emitters/claude-code.md:14` and its
three siblings) necessarily touches all four, so such a story declares all four and
therefore runs alone — correctly, since a partial cross-emitter change fails
`.claude/checks.sh` check H anyway.

**Summary of what fold-back actually has to do.** For the two gitignored files, nothing:
they are never on a branch. For the two tracked surfaces, nothing either, in the normal
case: admission guarantees no two in-flight branches touched the same one, so
integration is a fast-forward. Fold-back's only real job is the subset verification
described in §6.1 and the sequencing of outbox appends.

**PRECONDITION note (shipped, STORY-011; cross-ref :280 and :253)**: same-round sibling
branches diverge after the first integration commit lands on the target branch, so the
integrator rebases the next slot's branch then ff-merges it — the design at :253 already
permits "fast-forward-or-rebase". A rebase conflict aborts with exit 5 and artifacts
retained (the branch is quarantine-lite rather than integrated). Admission keeps the
normal case conflict-free, so rebase is a safety net, not the expected path.

*Twin note*: outboxes are ordinary files and appends are ordinary redirects (`>>` /
`Add-Content`); the integrator is a function inside the driver, so it is the same
single-process construct on both twins. No new primitive, hence no twin divergence and
no open question.

---

## 7. Completion and exit protocol

### 7.1 Sentinel semantics: per-slot signal, global decision

**(c) Current behavior.** The sentinel is a single pinned string,
`SENTINEL='<promise>COMPLETE</promise>'` (`loop.sh:27`; twin `loop.ps1:47`), and finding
it anywhere in one iteration's captured output terminates the entire driver:

```
if grep -qF "$SENTINEL" <<< "$output"; then
  echo "=== backlog complete after $i iteration(s) ==="
  exit 0
fi
```

(`loop.sh:105-108`; twin `loop.ps1:169-172`). The skill emits it under one condition —
"If none exists (all passed or blocked): print `<promise>COMPLETE</promise>` as your
final output and stop" (`templates/loop/SKILL.md:84-85`) — and its output contract makes
it one of four mutually exclusive terminal lines (`templates/loop/SKILL.md:137-144`).
The guard table calls it an "Exit condition — explicit `<promise>COMPLETE</promise>`
sentinel — never inferred from prose"
(`skills/setup/templates/ORCHESTRATION.md:480`).

**Why that becomes wrong under N slots.** The sentinel asserts *"no eligible story
existed when I looked."* Under concurrency that is both **partial** (slot A cannot see
that slot B is mid-story) and **non-monotonic** (a story slot B is running may fail and
return to `passes: false, attempts < 3` — eligible again). One slot's true observation
would therefore terminate a run with work still in flight and work still to do.

**(a) Proposed artifact.** The sentinel is demoted from a **decision** to a **per-slot
advisory signal**, and the exit decision moves to the driver:

- A slot printing the sentinel is marked `drained` and is not refilled.
  **Deviation (STORY-011, v0.12.0)**: in dispatched runs, a sentinel-emitting slot is
  treated as an ITERATION-mismatch and quarantined rather than marked `drained`
  (`loop.sh:905-906`) — the sentinel-from-dispatched-slot rule, because a correctly
  dispatched slot runs its pinned story, not an eligibility re-scan.
  *(RATIFIED, STORY-012: under §4 driver-owned dispatch a slot-level `drained` mark is
  meaningless; the driver's own backlog re-scan (§7.1(b)(ii), shipped) is strictly
  stronger — the deviation is now the designed behavior, not an interim gap. Shipped
  at `loop.sh:980-982`; twin `loop.ps1:1128-1130`.)*
- The driver exits 0 only when **all three** hold: (i) every slot is `drained` or idle;
  (ii) the driver's *own* re-scan of `_goals/backlog.md` finds no eligible story under
  the pinned fields (`_goals/backlog.md:3-6`); (iii) every integration has been applied
  and no branch remains quarantined (§5).
  **Deviation (STORY-011, v0.12.0)**: condition (iii) did not ship — exit 0 is NOT
  gated on quarantined branches. `retained_branches` is reported-only via an EXIT trap
  that fires after the literal `exit` statement and cannot alter the pending exit status
  (`loop.sh:243-256, :1145-1151`). Full quarantine gating deferred to STORY-012.
  *(RESOLVED, STORY-012: condition (iii) implemented — the drained completion exits 1
  when quarantined branches were retained this run (`loop.sh:1283-1286`; twin
  `loop.ps1:1490-1493`), inside the single `_loop_aggregate_exit` funnel
  (`loop.sh:1240-1301`; twin `Invoke-LoopAggregateExit`, `loop.ps1:1434-1509`). Two
  related shipped changes recorded here rather than restated per row: the funnel also
  gained a fifth, loud `exit 5` site (orchestrator-ratified) for a backlog readable at
  the last FILL gate but missing/unreadable by completion time — a mid-run destruction
  that would otherwise silently report "backlog complete" (`loop.sh:1266-1275`; twin
  `loop.ps1:1470-1482`); and, per §7.3's own row-1 "with eligible stories remaining"
  qualifier, the MAX_ITER-exhausted path now exits 0, not 1, when the backlog is
  genuinely drained and nothing was quarantined (`loop.sh:1279-1296`; twin
  `loop.ps1:1486-1503`) — an intentional N=1 behavior change from today's unconditional
  exit 1 there.)*
- The sentinel string itself does not change — it is checked by both twins and by the
  parity heuristic at `.claude/checks.sh:26-28`, so changing it would be a gratuitous
  compatibility break. Only its *interpretation* moves.

**(b) Failure mode prevented.** Premature exit 0 — a run reporting "backlog complete"
while N−1 slots still hold claimed stories, leaving committed-but-unintegrated branches
and a backlog whose `passes` fields were never updated. Equally, the mirror failure: a
driver that never exits because it waits for a sentinel that a drained slot already
emitted and nobody recorded.

### 7.2 Attribution of interleaved `ITERATION:` lines

**(c) Current behavior.** One capture per iteration, `output="$($LOOP_CLI $model_arg
"$(cat "$PROMPT_FILE")" 2>&1)"` (`loop.sh:91`; twin `loop.ps1:154`), tailed 25 lines to
the console (`loop.sh:94`; `loop.ps1:164`). Because exactly one child runs at a time,
every line in that capture unambiguously belongs to the current iteration. The output
contract's terminal lines already carry a story id — `ITERATION: <story-id> passed`,
`… failed (attempt N/3)`, `… blocked` (`templates/loop/SKILL.md:141-143`).

**(a) Proposed artifact.** Attribution by **capture separation first, story id second**:

- Each slot's stdout+stderr is captured to its own file,
  `.loop-worktrees/slot-<n>/iteration-<i>.log`, and parsed independently — so
  attribution never depends on parsing an interleaved stream at all. Console output is
  a tee with a `[slot <n>]` prefix per line, for humans only.
  **Deviation (STORY-011, v0.12.0)**: captures are per-slot `mktemp` files
  (`loop.sh:827`), not `.loop-worktrees/slot-<n>/iteration-<i>.log`; there is no
  prefixed tee — the slot's last 25 lines are printed to the console without a
  `[slot <n>]` prefix.
  *(RATIFIED, STORY-012: capture separation — the attribution authority this section
  needs — already shipped; mktemp works identically at `LOOP_WORKTREE=0` (no worktree
  exists yet) and has zero gitignore surface, so the design's in-worktree log path buys
  nothing the mktemp capture does not already provide. Shipped at `loop.sh:899-901`;
  twin `loop.ps1:1016-1023`.)*
- The driver then **cross-checks** the story id on the `ITERATION:` line against the id
  it dispatched to that slot (§4). A match is authoritative. A mismatch means the slot
  ignored its pinned story — a contract violation — and the slot is quarantined (§5)
  rather than believed.
- A slot whose capture contains *no* terminal line (crash, kill, truncated output) is
  recorded as `failed` for its dispatched story, matching the intent behind incrementing
  `attempts` up front so "a crashed iteration still counts"
  (`templates/loop/SKILL.md:89-90`).
  **Deviation (STORY-011, v0.12.0)**: a capture with no terminal `ITERATION:` line
  becomes an ITERATION-mismatch (`loop.sh:895-896`) with no backlog transition
  (`loop.sh:925-926`), rather than a `failed` record — the `attempts` counter was
  already incremented at dispatch, so the story is correctly charged without a
  separate transition.
  *(RATIFIED, STORY-012: a `failed` record would differ from mismatch only in
  *integrating* the crashed slot's branch — quarantining a branch whose producer
  crashed is strictly safer than integrating it, and the story is already charged
  (attempts incremented at claim; a `failed` verdict causes no field change anyway, so
  nothing distinguishes the two outcomes on the backlog side). Shipped at
  `loop.sh:970-982`; twin `loop.ps1:1120-1130`.)*

**Shipped addition (STORY-012, v0.13.0, addendum-1 closure)**: the driver now writes the
exact dispatched prompt to `<outbox>/dispatch-prompt.md` immediately before spawning
each slot's child, after both `%%STORY_ID%%`/`%%OUTBOX_DIR%%` substitutions
(`loop.sh:879-885`; twin `loop.ps1:995-1001`); reads it back at reap, before the outbox
is removed (`loop.sh:1021-1029`; twin `loop.ps1:1173-1183`); and embeds it verbatim in
the D4 quarantine marker (§5) on every non-clean disposal/kill path — the durable
delivery evidence this section's attribution problem needed. It is discarded with the
outbox on a clean integration, where the integrated commit is itself the evidence.

**(b) Failure mode prevented.** Misattributed outcomes: marking story X `passed` because
slot 2's success line was read while parsing slot 1's stream — which would set
`passes: true` on unfinished work and permanently retire a story that never ran.
Prefix-tagging alone is insufficient (a subagent can emit a line containing a literal
`[slot 1]`), which is why separate captures, not prefixes, carry the authority.

### 7.3 Reducing N slot exit codes to one driver exit code

**Shipped — STORY-012, v0.13.0.** The aggregation table below ships with one
implementable reading, argued once here rather than restated per row (D3): the table's
exit-3 conjunct "No slot made progress" is read as *every slot has stopped progressing
(all retired)*, not "zero commits ever happened this run" — this preserves the N=1
circuit-breaker codes exactly (a lone slot that committed earlier and only later trips
CB2 still exits 3, as before) and keeps CB2's per-lineage meaning, the rationale the
table itself gives. 3-vs-2 precedence is decided from retirement reasons alone: any
`cb2` retirement anywhere in the run's lineage wins over an all-`cb1` run
(`loop.sh:1251-1261`; twin `loop.ps1:1447-1457`). Row 1's own "with eligible stories
remaining" qualifier is now load-bearing: the MAX_ITER-exhausted path exits 0, not 1,
when the backlog is genuinely drained and nothing was quarantined — an intentional N=1
behavior change from today's unconditional exit 1 there (`loop.sh:1279-1296`; twin
`loop.ps1:1486-1503`). All literal `exit N` statements except CB0's `exit 4` and the
five loud `exit 5` stops route through one driver-level funnel, `_loop_aggregate_exit`
(`loop.sh:1240-1301`; twin `Invoke-LoopAggregateExit`, `loop.ps1:1434-1509`), evaluated
strictly top-down: rows 3/2 (all-retired) before rows 0/1 (drained/quarantine) on every
terminal route — see §7.1(b)(iii)'s resolution note above for the exit-0
quarantine gate and the fifth `exit 5` site this same funnel carries.

**(c) Current behavior.** Five codes, one producer: "0 = backlog complete (sentinel
found); 1 = max iterations reached without completion; 2 = circuit breaker — no commit
for 3 consecutive iterations; 3 = circuit breaker — same failure signature 5 times
consecutively; 4 = protected-path modification detected (iteration reverted)"
(`loop.sh:17-20`; verbatim twin at `loop.ps1:18-21`). All five are `exit` statements in
the single driver process (`loop.sh:107,114,129,143,156`). The parity heuristic asserts
"all five exit codes (0-4)" are present in both twins (`.claude/checks.sh:26-28`), so
the *set* must not change.
*(pre-STORY-012 text; the shipped contract block now reads "0 = backlog complete --
the driver's own backlog re-scan …" — see loop.sh's header, `loop.sh:22-50`; twin
`loop.ps1:24-52`)*

**(a) Proposed artifact — an aggregation rule with a fixed precedence, preserving all
five meanings.** Evaluated by the driver after all slots have terminated:

| Driver exit | Aggregation condition | Rationale |
|---|---|---|
| **4** | ANY slot detected a protected-path modification | Integrity dominates (§5): the machinery is shared, so one violation invalidates the whole run. Short-circuits — the driver kills remaining slots immediately rather than waiting. |
| **3** | No slot made progress AND the same error signature repeated 5× **within any single slot's** history | Preserves CB2's per-lineage meaning (`loop.sh:137-152`); a *global* 5-identical-errors rule would be a different, weaker assertion. |
| **2** | Every slot has retired on no-progress, i.e. no slot has produced an integrated commit for 3 consecutive dispatch rounds | Generalizes CB1 (`loop.sh:121-134`) from "3 consecutive iterations" to "3 consecutive rounds across all slots" — a single stuck slot must not stop a productive run, but a wholly stuck *run* must still stop. |
| **1** | Total iterations dispatched across all slots reached `MAX_ITER` with eligible stories remaining | Keeps `MAX_ITER` a budget over work units, not over rounds (`loop.sh:23,155-156`). |
| **0** | The three-part drained condition in §7.1 | Strictly stronger than today's first-sentinel-wins. |

Precedence is 4 > 3 > 2 > 1 > 0, checked in that order, so the most severe cause is
always the one reported. Codes 2 and 3 are the only ones whose *definition* widens
(iteration → round); 4, 1, and 0 keep their exact meanings, which is what keeps the
documented contract at `loop.sh:17-20` honest rather than silently redefined.

**(b) Failure mode prevented.** An unattended run whose exit code no longer means
anything — the classic "aggregate the last child's status" bug, where a run that
suffered a protected-path violation in slot 1 exits 0 because slot 3 happened to finish
cleanly, and CI (or a human reading the exit code) treats a machinery-integrity breach
as success.

*Twin note*: both twins already `exit` with these codes from a single process
(`loop.sh:107-156`; `loop.ps1:171-238`), and PowerShell's `exit <int>` maps to the same
process exit status, so the aggregation table is expressible identically on both sides.
The parity heuristic (`.claude/checks.sh:26-35`) continues to see all five literals in
both twins.
*(check G asserts 0-5 as of STORY-012 — the loop extended to `for n in 0 1 2 3 4 5`,
`.claude/checks.sh:309`; a `kitVersion==VERSION` join tripwire was also added as a
third, independently-gated check-J report line, `.claude/checks.sh:521-542`, unrelated
to exit-code parity but shipped in the same story, D8.)*

---

## Open questions

1. **bash 3.2 supervision floor.** Is the `kill -0` poll loop (§5) acceptable as the
   bash primitive, or should the kit raise its bash floor to 4.3 and use `wait -n`? The
   breaker currently accommodates 3.2 explicitly (`breaker.sh:172-173`), so raising the
   floor is a kit-wide policy decision, not a loop-local one.
2. **Windows worktree removal under a live handle.** `git worktree remove` can fail on
   Windows when a child process still holds a file open. The §2 mitigation
   (wait-then-`--force`-then-`prune`) is proposed but unvalidated on a real Windows
   host; the checks suite's pwsh coverage is parse-only and skip-aware
   (`.claude/checks.sh:22-25`), so it cannot verify this.
3. **Multi-driver operation is explicitly out of this design.** All exclusivity here
   rests on there being exactly one driver process (§4, §6). If two drivers on one repo
   is ever wanted, on-disk exclusive-create claims and the full breaker hardening of
   §3.2 parts 1–3 become load-bearing rather than defense-in-depth. Not designed here.
4. **Accuracy of declared `writes:` sets.** §6.1 states the limitation; unresolved is
   what the integrator should do on a *small* overrun (a story that also touched one
   README). Quarantine may be too blunt; an escalation-and-admit path may be better.
5. **Should `_goals/` become tracked in this repository?** Today it is ignored
   (`.gitignore:8`) as a dogfooding artifact. Tracking it would make the install-side
   merge=union guidance (`skills/setup/SKILL.md:120-122`) apply here too, changing which
   of §6.3's rules are belt and which are braces. Orthogonal to this design, but it
   changes the test surface for the follow-up stories.
6. **Cross-loop cooperative rate limiting** — the shared token pool and predictive
   breaker pattern at `docs/research-squad-ideas.md:122-124` — is the natural companion
   to §1's capacity analysis but is explicitly out of scope for this story.
7. **Where the integrator's own commit lands.** The integrator writes backlog/LEARNINGS/
   ESCALATIONS transitions; whether those become one commit per story or one batched
   commit per round affects `ship-pr`'s eventual summary
   (`templates/loop/SKILL.md:96-97`) and is undecided.

---

## Rejected alternatives

### A. Planning-layer write-set admission alone (the counter-position's position)

*Verdict: adopted as a layer, rejected as sufficient.*

`docs/research-designing-conflict-free-multi-agents.md:67` states it plainly: "You do not
need locks, CRDTs, or worktrees if the plan guarantees disjointness", supported by the
mechanism table at `:59` (declared disjoint write-sets = "Best fit… This is the primary
recommendation") and the loop-specific Stage 5 sketch at `:113-118`. Taken seriously,
this design would consist of §6.1 and nothing else: declare `writes:` per story, refuse
to co-dispatch intersecting stories, run both slots in the one shared working tree.

Argued on its merits, it is right about a great deal. It is cheaper than anything else
here, it needs no runtime infrastructure, it travels in the prompt (which suits
fresh-context subagents, `:59`), and it prevents the failure the empirical data actually
measures — a 27.67% conflict rate over 142K+ agentic PRs (`:14`). §6.1 adopts it
verbatim, including its escalate-don't-widen rule (`:105`) and its claimed-paths ledger
idea (`:116`).

It is rejected as a *complete* answer for three specific reasons:

1. **Git state is a shared non-file surface.** HEAD, the index, and the working tree are
   written by every iteration and owned by none. The research doc's own ATM summary
   supplies the counterexample class: "physical disjointness remains necessary but not
   sufficient" — disjoint writers are still blocked when they "touch a shared non-file
   surface (a registry, generated artifact, or validator)" (`:18`). Here the shared
   surface is git itself.
2. **The loop's rollback primitive is global and destructive.** `git reset --hard
   "$head_before"` (`loop.sh:113`) does not respect write-sets; it reverts *the tree*.
   No plan-time property constrains what it deletes. A design that keeps a shared tree
   must either remove this primitive (losing CB0's revert semantics,
   `skills/setup/templates/ORCHESTRATION.md:483`) or accept that one slot can erase
   another's commit.
3. **Story write-sets are not knowable at dispatch.** The goal and its task write-sets
   are derived *inside* the iteration (`templates/loop/SKILL.md:94-97`), so the declared
   set is an authoring-time upper bound, not the computed disjointness proof CodeTeam's
   plan-time check assumes (`:31`). Admission on an estimate is worth having; it is not
   worth betting the working tree on.

The reconciliation is therefore: `:67` is accepted for the layer it addresses (files) and
declined for the layer it does not (git state), and `:65`'s judgment that locks are a
last resort is honored literally — this design contains no locks.

### B. Serialized writes with parallel reads (single writer; concurrent read-only planning and judging)

*Verdict: rejected as the dispatch architecture, adopted as the shared-memory rule.*

This is the pattern with the strongest empirical backing in the research doc: Cognition's
"multi-agent systems work best today when writes stay single-threaded and the additional
agents contribute intelligence rather than actions" (`:10`), Anthropic's read-heavy
orchestrator-worker design where subagents "never talk to each other" (`:12`), and the
underlying law that "read operations are naturally parallelizable, while write operations
that must maintain consistency require sequential coordination" (`:37`). Applied here it
would mean: N slots run Phases 1–3 (alignment, goal creation, goal judgment) and all
judging concurrently in read-only worktrees, while a single writer applies Phase 4 edits
serially.

Argued seriously, this is attractive: it needs no admission rule at all, it makes §6
almost vacuous, and it is the pattern the strongest primary sources validate.

It is rejected as the dispatch architecture because **the kit's iteration has no short
write tail to serialize.** Phase 4 is not a brief apply-step following a long planning
step; execution and judging are interleaved — "implementer/test-writer execute, `judge`
verifies every task and the final audit, fixes are always re-judged, 3 judge cycles max
per task, tests climb ladder rungs 1–2 mid-story with rung 3 after the audit"
(`templates/loop/SKILL.md:101-104`), plus per-story Phase 6 doc alignment
(`:104-105`). The write-bearing portion is most of the wall clock, so serializing it
serializes most of the run and the remaining parallelism is planning overhead. The
research doc supplies the quantitative warning for exactly this shape: Co-Coder found
naive parallelism gave "negligible" gains over sequential (57.7% vs 56.8%) at +44% cost
(`:19`). Paying N× the tokens for a fraction of the wall-clock is a worse trade than the
serial loop we already have.

What *is* adopted is its principle, applied where the write tail genuinely is short:
§6.3 makes the integrator the single writer for `_goals/backlog.md`,
`_goals/LEARNINGS.md`, and `_goals/ESCALATIONS.md`. Those writes take milliseconds, so
serializing them costs nothing and buys the whole-file-rewrite safety that compaction
requires.

### C. Branch-per-story with merge-conflict repair at fold-back

*Verdict: rejected.* This is the dominant commercial answer — Copilot's `/fleet` and
Claude Code's `isolation: worktree` (`:23`) — and it is the design a naive reading of
"worktree-per-story" (the phrasing in this story's own backlog entry,
`_goals/backlog.md:99`) would produce: let slots collide freely, resolve at merge. It is
rejected on the research doc's terms, which this design accepts without reservation: it
is "precisely the after-the-fact reconciliation the user wants to avoid" (`:23`) and it
imports the measured 27.67% conflict rate (`:14`). The distinction from §2 matters and is
worth restating: §2 uses worktrees so that admission-guaranteed-disjoint work integrates
by **fast-forward with zero conflicts**, not so that conflicting work can be merged.

### D. `merge=union` as the shared-memory mechanism

*Verdict: rejected as a mechanism; retained as a safety net in installs.* The setup skill
already emits `merge=union` for `_goals/LEARNINGS.md`, `_goals/ESCALATIONS.md`, and
`_goals/*/orchestration-log.md` (`skills/setup/SKILL.md:120-122`), so building on it is
tempting. Three reasons not to: (i) it does not exist in this repository, where `_goals/`
is untracked (`.gitignore:8`) and the root `.gitattributes` carries only the two
`text eol=lf` lines with no `merge=union` entry (`.gitattributes:2-3`), so a design
resting on it would work in installs and silently not work here; (ii) it cannot survive
the mandatory compaction rewrite at `templates/loop/SKILL.md:116-118` — union resolves
additions, not deletions, so it would resurrect exactly the content compaction removed
(§6.3); (iii) union merges are *unordered* concatenations, so interleaved learnings lose
their sequence. The integrator (§6.3) makes union unnecessary in both environments; the
emitted lines stay as protection against hand edits.

### E. A global write lock on the shared working tree

*Verdict: rejected.* Keep one tree, guard every commit with a lockfile. This is the
minimal-change option and it does prevent index contention. It is rejected because it
does not address the actual §2 failure — `head_before` is captured *outside* any
plausible critical section (`loop.sh:79`) and the CB0 diff range spans the entire
iteration, so a lock held only around `git commit` still lets slot B's commit fall inside
slot A's diff window. Holding the lock for the whole iteration is just the serial loop
with extra machinery. It is also the mechanism the research doc rates lowest — locks are
"Overkill for a design-time-partitioned system; keep as a last-resort fallback only"
(`:65`).

### F. Per-slot breaker state files

*Verdict: rejected.* Giving each slot its own `breaker-state.json` would sidestep §3's
torn-read race entirely. It is rejected because it is semantically wrong: rate limits are
a property of the *provider account*, not of a slot (§1), so N independent breakers would
each need to observe N× fewer signals before tripping, and a slot in CLOSED would keep
hammering a provider that another slot's breaker had already found OPEN. The breaker must
stay global; §3.2 part 4 makes it single-owner instead.

---

## Scope

**This story ships design only.** No change to `skills/setup/templates/` or `_loop/`
(`_goals/backlog.md:109`). The verification for this story is structural: the
placeholder-safe rendering check over this file, plus `bash .claude/checks.sh` as a
**no-regression signal only** — no check in that suite reads `docs/` (its checks A–I
cover templates, the emitted instance, frontmatter, model IDs, twin parity, and emitter
reference coverage, `.claude/checks.sh:6-40`), so a green suite proves this document
broke nothing, not that this document is correct.

**Accepted consequence**: root `ORCHESTRATION.md` indexes `docs/`
(`ORCHESTRATION.md:29-32` *(stale — after v0.12.0 docs alignment the index line is at
`:45-50`)* ) and is out of scope here, so this design note ships unindexed until a
follow-up links it. *(Now resolved: `ORCHESTRATION.md:45-50` indexes this design as of
STORY-011 (v0.12.0) docs alignment.)*

### Implementation follow-up: plausibly 3–4 stories

Sized honestly, and deliberately ordered so each story is independently shippable and
independently revertible. Story 2 is the one most likely to split, which is where the
"3–4" range comes from.

**Follow-up story 1 — Breaker hardening (independent of dispatch, ship first).**
Atomic temp-plus-rename write, terminator-line integrity check, torn-read retry, and the
fail-safe reseed inversion (§3.2 parts 1–3). Surfaces: `templates/loop/breaker.sh`,
`templates/loop/breaker.ps1`, `templates/loop/SKILL.md` (the corrupted-state paragraph at
`:69-70`), `.claude/checks.sh` (check G's parity assertions,
`.claude/checks.sh:26-35`). This story has standalone value even if parallel dispatch is
never built — the reseed-to-CLOSED weakening is reachable today by any second process
touching the state file.

**Follow-up story 2 — Slot supervision and per-slot isolation.** `LOOP_SLOTS`, the slot
table, worktree lifecycle, per-slot CB1/CB2, quarantine, and the process-supervision
primitives (§1, §2, §5). Surfaces: `templates/loop/loop.sh`, `templates/loop/loop.ps1`,
`templates/loop/SKILL.md` (Windows-compatibility section, `:24-32`),
`skills/setup/SKILL.md` (the `.gitignore` append for `.loop-worktrees/`, extending the
precedent at `:127-129`), all four `skills/setup/emitters/*.md` (loop-extras rows, e.g.
`skills/setup/emitters/claude-code.md:14`), `.claude/checks.sh`. **This is the story most
likely to split in two** — bash and PowerShell supervision diverge more than any other
part of the twin contract (§5), so "supervision (bash)" and "supervision (PowerShell
twin + parity checks)" may need to be separate stories to each fit one context window per
`_goals/backlog.md:7-8`.

**Follow-up story 3 — Driver-owned dispatch and the integrator.** Story selection moved
into the driver, `writes:` field and admission rule, hotspot set, per-slot outboxes, and
the single-writer integrator including compaction/archival (§4, §6). Surfaces:
`templates/loop/loop.sh`, `templates/loop/loop.ps1`, `templates/loop/PROMPT.md` (story
pinning, `:1-5`), `templates/loop/SKILL.md` (sections 1, 3 and 4 — `:81-90`, `:110-123`,
`:126-135`), `templates/loop/backlog.md` (the format comment gains `writes:`),
`_goals/backlog.md`'s live format comment (`:3-10`) by way of a re-emit.

**Follow-up story 4 — Completion and exit aggregation.** Sentinel demotion, per-slot log
capture and `ITERATION:` cross-checking, and the exit-code aggregation table (§7).
Surfaces: `templates/loop/loop.sh`, `templates/loop/loop.ps1`,
`templates/loop/SKILL.md` (output contract, `:137-144`),
`skills/setup/templates/ORCHESTRATION.md` (guard table rows at `:474-486`),
`.claude/checks.sh` (check G's five-exit-code assertion, `:26-28`).

**Surfaces touched across the whole follow-up**, consolidated:
`skills/setup/templates/loop/loop.sh`, `skills/setup/templates/loop/loop.ps1`,
`skills/setup/templates/loop/breaker.sh`, `skills/setup/templates/loop/breaker.ps1`,
`skills/setup/templates/loop/SKILL.md` (the `auto-loop` skill),
`skills/setup/templates/loop/PROMPT.md`, `skills/setup/templates/loop/backlog.md`,
`skills/setup/templates/ORCHESTRATION.md`, `skills/setup/SKILL.md`, all four
`skills/setup/emitters/*.md`, and `.claude/checks.sh`.

**Out of scope for the entire follow-up**: multi-driver operation (Open question 3),
cross-loop cooperative rate limiting (`docs/research-squad-ideas.md:122-124`), and any
change to `ship-pr`'s one-PR-per-run model (`templates/loop/SKILL.md:96-97`).
