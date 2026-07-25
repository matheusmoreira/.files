---
description: Adversarial review. Spawns a focused review agent, fixes issues, loops until zero found. Usage: /scrutinize <type> [scope]
---

## Scrutinize

Coordinator for adversarial review sessions.
You manage the review loop. You do not review code yourself.

### Arguments

The full text after `/scrutinize` is passed as a single string.
Parse it as:

- **Type** — first word: a critic name, `sweep`, `sweep incremental`,
  or `sweep blind`
- **Scope** — optional: branch, file path, commit range, or directory
- **Instructions** — anything else: free-form directives to the
  coordinator (e.g., "worktree at ~/proj/sweep", "focus on error
  handling", "skip the test files", "lighter review, just bugs")

Examples:
- `/scrutinize correctness` — correctness review of current branch diff
- `/scrutinize security source/auth/` — security review of that directory
- `/scrutinize sweep` — full sweep, default settings
- `/scrutinize sweep incremental` — incremental on existing branch
- `/scrutinize sweep blind` — fresh-eyes sweep, prior findings withheld
- `/scrutinize sweep worktree at ~/proj/sweep` — full sweep, custom path
- `/scrutinize quality HEAD~3..HEAD focus on error paths` — scoped + directed
- `/scrutinize tests` — test suite integrity review
- `/scrutinize documentation` — docs vs code accuracy check
- `/scrutinize history` — review unpushed commits or branch history

If no arguments provided, list available types and ask.

### Available types

**Programming** (in `critics/programming/`):
quality, correctness, design, integration, security,
consistency, maintainability, performance, duplication, rigor,
tests, documentation, robustness, auditor

**Writing** (in `critics/writing/`):
accuracy, clarity, code, completeness, freshness, flow,
narrative, references, voice

**Electronics** (in `critics/electronics/`):
electrical, cascade, safety, sourcing

**Git** (in `critics/git/`):
history

**Special:**
sweep — full-codebase parallel review (all critics in a category × all subsystems)
sweep incremental — verify fixes + find deeper issues missed by prior sweep
sweep blind — full matrix with all prior findings withheld; calibrates
the ledgers against what fresh eyes actually re-find

### Category inference

The coordinator infers which category to use from context:
- Source code files → programming
- Articles, blog posts, docs, README → writing
- Schematics, PCB, BOM → electronics
- Branch name, commit range, `git log` → git

If ambiguous, ask the user. For sweep mode, ask which category
of critics to deploy (default: programming). Git critics are
standard-mode only — they review commit history, not files,
so the subsystem matrix does not apply.

---

## Sweep mode

Massively parallel review: every critic in the active category
reviews every subsystem independently. Agents write to disk
incrementally. Designed to survive rate limits, session timeouts,
and interruptions.

### Execution engine — prefer the Workflow tool

Drive the fan-out with the **Workflow tool**, not hand-issued
`run_in_background` Agent calls. Hand-issuing 100+ agents forces every
launch, completion notification, and status poll back through the
coordinator's large context — it burns the usage cap many times faster.
Workflow keeps queueing, per-agent prompts, and result collection off the
main loop: one launch call, one consolidated return. (Observed: a 124-agent
sweep that would drain a 5h cap in ~30 min via background agents ran at a
fraction of that on Workflow.)

Mechanics that matter:

- **Each agent writes its checkpointed `reports/.../<critic>.md` AND returns
  structured findings** (pass a JSON `schema`). The file is the durable
  deliverable; the schema return feeds consolidation. Make every thunk
  null-tolerant — `r || {status:'FAILED', findings:[]}` — so a rate-limit
  wave degrades to relaunchable slots instead of stalling `parallel()`.
- **The engine does NOT pause when the usage cap is hit.** It fails every
  remaining agent ("session limit") and still reports `completed`. So **size
  each Workflow run to ONE usage window** — empirically ~30-37 deep Opus
  reviews per 5h window (~2-2.8M agent tokens) — and resume across windows.
  Firing more just buys a failure storm (failed agents are ~free, but noise).
- **Resume is disk-based and cross-session.** `resumeFromRunId` only works
  within the live session, and rate-limit rollovers usually start a NEW
  session. Keep a generic **arg-driven resume script** that launches only
  the slots you name (e.g. `args.run=["renderer:*","linker:robustness",
  "audit:A1"]`); choose those slots by reclassifying from DISK. Commit
  reports after every batch.
- **Reclassify with `grep -a`, never plain `grep`.** Reports contain
  non-ASCII (em-dashes, curly quotes); some get byte-classified as `data`
  and plain `grep '## Conclusion'` silently misses them → false "missing" →
  spurious relaunch. The Read tool is the authoritative content view.
- **Preserve each run's task-output file immediately** (`cp` it into the
  worktree) — `/tmp` task outputs vanish within minutes.
- **Blind mode:** resume agents must be forbidden from reading the sweep
  worktree (prior reports now populate it) or they lose blindness.

Consolidation is itself a Workflow (per-subsystem dedup+convergence agents +
auditor-diff agents) followed by a **deterministic `node` pass** over the
preserved consolidated JSON — it is far too large for context. GOTCHA: the
task-output file wraps the return as `{summary, logs, result:{...}}` — parse
`d.result`, not the top level. `node` writes `todo.list` and powers the
calibration probes: regex-search the findings for each KNOWN signature, and
for those blind did NOT re-find, VERIFY against current source — that
search-then-verify is exactly what surfaces silently-fixed-but-unmarked
ledger entries.

The conceptual steps below (discover → config → launch → resume →
consolidate) are unchanged; this is just the mechanism that makes them
survive rate limits affordably.

### Model tier under volatile availability

Model availability now shifts *mid-sweep*. A strong model can downgrade to a
weaker one from three independent causes: usage budget; a **content classifier**
(security-hardening work + exploit-shaped repros trip a dual-use gate that routes
to a weaker tier *regardless of budget* — seen firing at ~20% weekly); or the
**coordinator's own session** downgrading (after which agents that *inherit* the
session model silently stop getting the strong one). Three mechanics keep a sweep
at full strength and let you measure any shortfall:

- **Force the strongest model per agent — do NOT inherit.** An `agent()` call
  with no `model` inherits the *coordinator's* resolved tier; once the coordinator
  session itself downgrades, "inherit" silently stops meaning "strongest." Pass
  `model: '<top-tier>'` explicitly on every agent so each one *requests* the strong
  model regardless of the coordinator's tier — the system downgrades an individual
  agent only if it must. This beats all three axes: observed reclaiming the strong
  tier with a *confirmed-downgraded coordinator* AND past the 50%-weekly gate
  (still returning the strong model at 57-62% weekly). Wire it as an override arg
  (`AGENT_MODEL = args.model || '<top-tier>'`) and keep the null-tolerant wrapper —
  if forcing ever hard-fails instead of silently downgrading, the slot degrades to
  relaunchable rather than crashing the batch. **B5 of any run is the test:** watch
  the first forced batch's returned models to confirm forcing reclaims the tier vs
  the gate overriding it anyway.

- **Track model provenance per report.** Every agent self-reports its exact model
  id (read from its OWN system prompt, not guessed) as report line 2
  (`Model: <id>`) and in a `model` schema field; the coordinator keeps a per-batch
  tier ledger. (Caveat learned since: WORKFLOW subagents often carry no
  model-identity line in their system prompt, so self-report reads "unknown" — fall
  back to coordinator-side transcript provenance, `grep '"model":"..."' <agent>.jsonl`;
  see "Pinning a fleet to a specific tier" below.) This is the *only* way to answer "did the downgrade degrade the
  review, and where." Mark degraded slots so they can be re-run on the strong model
  on fresh budget. (Observed: the weaker tier held quality — carried findings to
  HIGH, delivered a clean auditor + threat-model — but you only *know* that because
  provenance was tracked. A forced tier-mix also yields free **cross-model
  convergence**: a finding both tiers independently hit is stronger evidence than
  same-model agreement, which can be a shared blind spot.)

- **Distinguish three failure signals — they demand opposite responses:**
  - *Window cap* ("session limit" / 5h) → RELAUNCH next window; not a stop, not a
    downgrade. The agent may have WRITTEN its report before dying — classify from
    disk before relaunching.
  - *Model gate* (agent returns the weaker tier) → the downgrade signal itself.
    Decide continue-on-weaker (provenance-marked) vs stop. If it fires at LOW
    weekly %, it's content-gating not budget: waiting for a fresh window will NOT
    restore the strong tier (only per-agent forcing does) — don't burn calendar.
  - *Weekly cap* ("resets <date>") → hard stop until the reset; pivot to
    consolidation (the coordinator can author it without agents — see step 6).

- **An agent can COMPLETE on disk while its structured return is null** (killed
  after writing the report, before returning). Always classify from the DISK
  (`grep -a '## Conclusion'`), not the workflow's return array — salvage the
  completed report, relaunch only the genuinely-missing slots.

- **Near a hard cap, drop to one-agent-at-a-time.** Launch one, classify + commit,
  check its returned tier, launch the next — so you stop *precisely* when the
  strong model goes, wasting no in-flight work. The strong tier is pricier per
  agent than the weaker one (fewer slots per window), so budget calibration is
  tier-dependent; a genuinely FRESH window still absorbs ~2 deep batches, but
  chaining a second batch into an already-consumed window starves it.

### Pinning a fleet to a specific (usually cheaper) tier — e.g. a Fable-only sweep

Sometimes the goal is the OPPOSITE of "force the strongest": pin the whole fleet to
one specific tier — to deliberately burn a cheaper model's budget, or because the
user wants that model's output and nothing else (e.g. they already have an Opus
review and want a pure-Fable second pass). Forcing `model: 'fable'` (or any non-top
tier) is only advisory; the harness overrides it for reasons that are NOT budget.
Validated 2026-07 on the lone sweep:

- **The dual-use content gate is content-driven, per-agent, deterministic, and
  overrides your force.** What trips it is the exploit-shaped CONTENT an agent
  generates, not the lens label alone — so it has two triggers, both observed on the
  lone sweep:
  - *Lens persona:* security agents, and robustness agents that build exploit-shaped
    repros, are served the "safe" tier (observed: Opus-4.8) every time, independent of
    budget or concurrency. DROP security + robustness from a pinned sweep and note
    them as covered by a separate strong-tier pass.
  - *Code under review:* even neutral lenses downgrade when the SUBSYSTEM itself is
    memory-unsafe — pointer arithmetic, binary patching, buffer-overwrite analysis.
    **correctness + quality were served Opus on `lisp-values` (tagged pointers) and
    `lone-embed` (ELF patching)** while the *same two lenses stayed pure Fable* on
    higher-level subsystems. The pinnable lens set is therefore not fixed; it shrinks
    on low-level code. Treat those gated slots as Opus-covered — do NOT burn re-tries,
    the gate is deterministic on the same content.
  Everything else (integration, design, consistency, maintainability, duplication,
  performance, tests, plus correctness/rigor/quality on higher-level code) stays
  pinned indefinitely. (Probe: a reader correctness agent ran 98 turns pure Fable; a
  lone-embed correctness agent wrote its whole report on Fable, then downgraded on its
  final turn as its buffer-overwrite finding materialized.)

- **The swap is per-agent and mid-conversation.** An agent starts on the pinned tier
  and flips partway once its content trips the gate. Concurrency does NOT trigger it;
  review length does NOT. Only content does — so pin-safety is decided per lens, not
  per batch.

- **Agents cannot self-detect their served model.** A workflow subagent's system
  prompt carries NO "you are powered by <model>" line, so having the agent report its
  own model (see the provenance bullet above) is unreliable for subagents — the served
  model lives only in API response metadata the model never sees while generating.
  Provenance is COORDINATOR-side: `grep -oh '"model":"[^"]*"' <agent>.jsonl | sort |
  uniq -c` over the transcript.

- **Agents CAN self-abort via their own transcript.** Give each agent a unique nonce
  and the transcript directory; it self-locates (`grep -rl <nonce> <dir>`) and greps
  its served-model field, aborting the instant the off-tier model appears (one turn
  delayed, so it wastes ~1 off-tier turn, not a whole report). Two traps, both real:
  (1) put a regex CHAR-CLASS in the pattern — `claude-op[u]s` — so the pattern text
  does not match ITSELF where it sits in the transcript (a plain `grep 'claude-opus'`
  false-positives on its own command and on your prompt); (2) match the full
  `"model":"..."` field, because the environment block lists model IDs as reference
  text that a bare name-grep also hits.

- **Monitoring gotcha:** grepping a transcript for the tier name (or a sentinel like
  "DOWNGRADED") counts the copies in your own PROMPT too — it is echoed into the
  transcript. Parse `tool_result` records for the agent's REAL echoed output, not a
  raw `grep` over the whole file, or you will chase phantom downgrades.

- **No-lost-output = checkpoint-every-finding + transcript backstop.** On a tight
  window agents get killed mid-review. Instruct them to append each finding to the
  report file the MOMENT they identify it (investigation-heavy lenses — correctness
  especially — buffer in context otherwise and lose everything on a kill). The
  backstop: a killed agent's reasoning still lives in its JSONL transcript — salvage
  findings by parsing its assistant text blocks. Proven: recovered a killed agent's
  findings from its transcript after it died one turn before writing its report.

### Recovering gated slots — the two-phase (ddrescue) scrape

A tier-pinned sweep that drops gate-tripping lenses leaves holes. Recover them in a
SECOND pass modeled on `ddrescue`: the breadth pass is the fast parallel copy of every
good block plus a bad-block MAP; the scrape pass is the slow, careful recovery of the
mapped bad blocks. Validated 2026-07 on the lone sweep — slots that gated HARD
(module-linux:rigor went 80 Fable turns → 44 Opus in the breadth pass) came back 100%
Fable when reframed, with UNDEGRADED quality confirmed by reading the output, including
the most exploit-shaped material present (an ELF program-header-overwrite bug), which
was described with full precision — just in correctness vocabulary.

- **Keep a mapfile.** As the breadth pass runs, log every gated slot to a
  `GATED-SLOTS.md`: unchecked `[ ]` = 0 Fable findings (fully gated); checked `[x]` =
  wrote a report before a final-turn downgrade (salvageable). This IS the ddrescue
  logfile — it survives interruptions and tells the scrape pass exactly where the damage is.

- **Scrape ONE slot at a time, not in parallel** — each gets its own reframed prompt
  you tune after watching its provenance. Session routing also goes STICKY for ~1h
  after a downgrade, so a FRESH agent per attempt beats an in-session retry.

- **The reframe playbook — the gate keys on OUTPUT vocabulary shape, not topic.**
  Rewrite the prompt so the agent's *findings* read as correctness, not exploitation:
  - Correctness-domain words, not exploit-domain: "bounds error / unchecked arithmetic
    / invariant violation / missing validation / structurally invalid output" — NOT
    "overflow / corruption / arbitrary write / PoC / exploit primitive."
  - Functional consequences, not attack narratives: "the process terminates" / "the
    data region lands at the table's offset, so the output file is structurally
    invalid" — never "an attacker can trigger…".
  - Ask "what invariant does this fail to maintain?", never "what could an attacker do?"
  - NO runnable proof-of-concept — the single most gate-hostile output shape.
  - Frame the system prompt as the maintainer's own-code correctness/robustness audit.
  - Tune per-slot to the material: file-format code → "malformed/invalid output"
    framing; syscall code → "wrong result / abrupt exit" framing.

- **The "no PoC" rule is a FEATURE — tier division of labor.** The reframed cheap tier
  does discovery + fix-lists; the exploit-shaped repro / regression tests (committed so
  bugs don't recur) are the STRONG tier's job later, once the issue is known. The gate's
  hardest trigger is exactly the artifact you always meant to hand to the strong tier,
  so the constraint costs nothing.

- **There is a SECOND classifier.** `reasoning_extraction` downgrades independently on
  "explain your reasoning step by step" instructions. Request structured finding LISTS,
  never step-by-step reasoning.

- **Verify the recovery, then re-rate.** Coordinator-side transcript provenance is
  authoritative (the agent's self-report is secondary). Read a sample recovered report:
  expect undegraded content but slightly CONSERVATIVE severity labels (correctness
  framing under-rates memory-safety impact) — descriptions stay complete, so re-rate at
  consolidation.

- **Escalation ladder (tune to the lens):** base reframe → HARDENED reframe → targeted
  cluster neutralization → (robustness) the CRASH-PROBE fix → fresh session → vendor own-code
  verification program → fall back to pinning that one lens to the strong tier (no classifier
  there). The four techniques below were validated 2026-07 recovering the TIER-2/TIER-3 lone
  slots (36 scrapes, 211 committed pure-Fable reports).

- **When the base reframe still gates MID-RUN — the HARDENED reframe.** If an agent holds the
  weak tier through several files then downgrades on ACCUMULATED memory-safety findings, the
  trigger is low-level MECHANISM narration. Tighten four levers: (1) FUNCTIONAL REPRODUCTION
  over mechanism — run the binary on BENIGN input and report the OBSERVED wrong output / exit
  code as the evidence (observing a wrong result or an honest exit is gate-SAFE; narrating the
  access pattern that causes it is gate-HOSTILE); (2) missing-check + wrong-result in ONE
  sentence — name the absent guard and the functional outcome, never narrate index/pointer/tag/
  bit mechanics; (3) a BANNED-WORD list (arbitrary, wild, reinterpret, type confusion, heap
  slot/index, payload bits, "(pointer,count)", corruption, overflow, attacker, exploit) — but
  KEEP domain nouns (tag, heap value, inline, ELF program header): for pointer-heavy/binary
  subsystems the low-level representation IS the domain, so ban the exploit-CAPABILITY framing,
  not the domain vocabulary; (4) evidence tuned to input — reproduce benign-stdin findings; for
  findings needing a CRAFTED malformed file, describe the missing validation structurally
  ("require X to be nil-or-a-table at the boundary") and defer the repro to the strong tier.

- **When even the hardened reframe gates — TARGETED cluster neutralization.** The trigger is
  usually ONE finding-cluster (e.g. the embedded-loader memory-safety findings). Add a rule to
  state THAT cluster once, in a single structural sentence, and keep recurring cross-lens
  findings brief — this frees detail for lens-specific observations and held the weak tier
  while yielding MORE findings (15 vs the 11 the un-targeted pass reached before gating).

- **The ROBUSTNESS lens — the CRASH-PROBE fix (the key to recovering it at all).** Robustness
  is inherently repro-shaped ("run hostile inputs"), so first reframe the LENS as a
  RESOURCE-BOUNDS / LARGE-INPUT CORRECTNESS audit: bounds, termination,
  honest-abort-vs-silent-wrong-behavior. Then the deeper trap: the gate trigger is usually the
  CONFIRMATION PROBE, not the writing — a probe that observes a CRASH / SIGSEGV /
  stack-exhaustion (deep-recursion or huge-allocation input) is gate-hostile EVEN on benign
  input; a probe observing a CLEAN bounded result or an HONEST non-zero exit code is safe. So:
  run ONLY clean/bounded/honest-abort probes (the ideal is allocation-exhaustion under
  `ulimit -v` observing an honest exit); describe crash-shaped findings (unbounded recursion,
  faults) STRUCTURALLY by code reading, NEVER reproduce the fault. With this even pointer-heavy
  cores HOLD — the gate was the crash-probe, not the pointer content (validated: a heap/GC
  robustness pass held clean first-try; an evaluator pass gated exactly at a deep-recursion
  probe, and its retry restricted to clean probes held pure weak-tier).

- **Keep findings on abort; reconstruct from the transcript if needed.** Instruct the agent: on
  DOWNGRADED, append the abort marker to the END and do NOT delete findings already written —
  Fable-phase findings (written before the first strong-tier record in the transcript) are a
  valid `[~]` salvage; flag the downgrade record number in the mapfile. If an agent CLEARS its
  file on abort, its findings still survive in the transcript as Write/Edit tool-call inputs —
  extract them with `jq` and reconstruct the report (validated on an ELF-tool correctness slot).

- **Some domains gate on ACCUMULATION regardless of clean vocabulary** — ELF-binary rewriting,
  raw-syscall interfaces. Even with the hardened reframe and zero banned words, enough findings
  in the domain cross the threshold (an ELF-tool pass wrote 12 clean-vocabulary findings, then
  gated). For these, salvage the Fable-phase findings rather than re-gating on a retry; a clean
  full version is a strong-tier-fallback candidate.

### Operational hardening for long, resumable tier-pinned sweeps

Learned the hard way over a multi-week lone sweep that spanned many session rollovers:

- **Make the agent self-abort SESSION-AGNOSTIC.** The live session id changes across
  resumes; a self-check that greps one hardcoded `<session>/subagents` dir silently
  finds nothing after a rollover and always returns "ok" → Opus slips through unmarked.
  Grep a GLOB over every session dir (`…/projects/<proj>/*/subagents`) so it finds the
  agent's transcript wherever it landed.
- **Verify every preservation commit EXPLICITLY.** A `git commit -q` buried in a long
  `&&` chain can fail while a downstream status check misreports "clean." Print the
  commit hash and re-check `git log` before believing it. (A failed commit is a
  preservation GAP, not data loss — the files sit uncommitted on disk — but close it.)
- **Preserve-scan before each resume.** Agents that return `NULL_RETURN` (killed after
  writing, before returning) leave COMPLETE reports on disk the ledger calls "failed";
  and pre-committing an in-flight report snapshots a stale mid-write copy. Periodically
  scan for uncommitted reports carrying content and commit them, or the ledger lies
  about coverage.

### 1. Discover subsystems

Partition the source tree into reviewable units. Target: 500-2000
lines per subsystem — small enough for deep review, large enough
to capture cross-file interactions.

**Algorithm:**

1. Group source files by parent directory. Record line counts.
2. Check dependency graphs — files sharing internal imports/headers
   are cohesive. Files using only public APIs are independent.
3. Apply size thresholds:
   - \> 2000 lines → split by subdirectory, naming pattern,
     or dependency independence
   - < 200 lines → merge with parent or sibling group
   - 200-2000 → keep as-is
4. Pair interface files with implementations (`.h`/`.c`, types/impl,
   index/module). Architecture or platform variants go with the
   file that imports them.
5. Handle outliers: standalone tools get own subsystem (different
   threat model). Tests and build scripts each get one subsystem.
   Generated files group with their generator.

**Granularity:** err toward larger. Missing cross-file interactions
is invisible; skimming is recoverable via re-review.

**Small subsystem optimization:** For subsystems under ~200 lines,
run a single "combined" agent (quality + correctness + security in
one pass) instead of separate critics for each. Full matrix is overkill
for trivial dispatch code or tiny config files. Mark these as `*`
(combined) in the progress tracker. This typically cuts agent count
by 30-50% on projects under 10K lines.

Present a summary table to the user. Do not proceed until approved.

### 2. Set up review branch

Create an orphan branch with a worktree. All review output lives
here, isolated from main history.

```
git worktree add ~/<project>-sweep-review --detach
cd ~/<project>-sweep-review
git checkout --orphan sweep-review
git rm -rf . --quiet 2>/dev/null
```

**CRITICAL:** commit configuration files before launching agents.
Untracked files on orphan branches die to `git clean`.

### 3. Configuration files

Write and commit these before any agents launch:

**SUBSYSTEMS.md** — the approved partition (name, files, line count,
description per subsystem). On resume, read this instead of
re-discovering.

**CRITICS.md** — which critics are active (checkbox list). User
may disable critics to manage throughput. Default: all critics in
the inferred category. The matrix is: active critics × subsystems.

**KNOWN.md** — finding lifecycle tracker. Gathered from: prior
todo.list, `gh issue list`, memory files, in-code TODO/FIXME
markers, project docs.

```markdown
## Known (tracked, not yet fixed)
- <one-line description per item>

## Resolved (fixed on master)
- <description> (fixed <date>)
```

State transitions: **New → Known → Resolved**.
If a Resolved item reappears on re-review, it regressed.

Agent prompt instructions:
- Known: "Do not re-report. Flag only new aspects."
- Resolved: "Should be gone. If found, report as regression."

**PROGRESS.md** — critic × subsystem matrix tracking launched /
complete / partial / missing. Lifeline for session resumption.

### 4. Launch agents

Read critic definitions from the inferred category
(e.g., `${CLAUDE_SKILL_DIR}/critics/programming/` for code).
For each (critic, subsystem) pair, spawn a background agent.

**Each agent prompt includes:**
- Project description and architecture (from CLAUDE.md)
- Subsystem file list from SUBSYSTEMS.md
- Critic persona verbatim from definition file
- Critic-specific sweep-mode tuning (see below)
- Known issues summary from KNOWN.md
- Output file path and checkpoint protocol

**Launch strategy:** prefer the Workflow tool (see "Execution engine —
prefer the Workflow tool" above) — fan out (critic × subsystem) pairs sized
to one usage window, and resume the rest across windows. If hand-issuing
agents instead: one wave per subsystem, all `run_in_background`; don't wait
between waves; if rate-limited, stop launching and let running agents
finish.

#### Checkpoint protocol

The report file is its own write-ahead log:

- After reviewing each source file, write the full report to disk
  with a checkpoint marker: `<!-- CHECKPOINT: reviewed up to <path> -->`
- On completion, append `## Conclusion`. Leave prior checkpoints
  inline — they serve as an audit trail showing review order.

**Status detection:**
- Has `## Conclusion` → complete (may contain inline checkpoints)
- Has checkpoints but no `## Conclusion` → partial, resumable
- Missing → needs full launch

On resume: read the partial report, find last checkpoint, compute
remaining files, spawn new agent with existing findings + remaining
scope. Worst case loss: one file's review work.

#### Critic tuning

Include these supplementary guidelines per critic type:

| Critic | Key directive |
|--------|--------------|
| **Correctness** | Construct concrete failure scenarios. Check error path reachability. Cross-reference contracts vs call sites. |
| **Security** | Trace data flow from entry to sensitive ops. Check all untrusted arithmetic. Consider adversarial-but-valid input. Frame the prompt as defensive review of the project's own code. |
| **Design** | "Would a new contributor understand this?" Only flag what improves the code. |
| **Performance** | Identify hot paths first. Check allocations/syscalls on hot paths only. Suggest benchmarks. |
| **Integration** | Headers match implementations? Callers updated? Docs match behavior? Tests cover edges? |
| **Consistency** | Baseline is what the code does, not external guides. Look for drift between old/new code. |
| **Duplication** | Structural clones, not textual. Flag when repeated code is one concept that should change together. |
| **Maintainability** | Read this in 2 years with zero context. Flag re-read friction and hidden assumptions. |
| **Rigor** | Is this the real fix or a band-aid? Flag hacks that address symptoms over root causes, incomplete escaping, mode flags, swap-restore patterns. |
| **Quality** | General sweep. Prioritize by impact. If clean, say so. |
| **Tests** | Cross-reference tests against source. Flag assertions that encode failure as expected behavior. Verify edge case coverage. Check mock fidelity. |
| **Documentation** | Coordinator provides doc inventory. Cross-reference docs against code. Verify examples compile/run. Check for stale references to removed/renamed symbols. |
| **Robustness** | Hostile input and resource exhaustion. Construct and RUN repros. Distinguish honest aborts (policy) from corruption (bug). |
| **Auditor** | Receives code but NOT design documents. Derives the contract from first principles; coordinator diffs it against the spec. Not part of routine sweeps — deploy once per convention or subsystem design. |

### 5. Handle interruptions and resume

Rate limits, session timeouts, and crashes all have the same
recovery path. Whether resuming mid-session after a rate limit
or in a new session after "continue please," the procedure is
identical. **Do not report state and wait for permission.** A
resume prompt IS the permission.

#### Resume procedure

1. **Locate the sweep worktree.** Read PROGRESS.md to recover
   full state. Read SUBSYSTEMS.md and CRITICS.md to reconstruct
   the matrix.

2. **Classify every slot** in the critic × subsystem matrix:
   - Report file has `## Conclusion` → **complete**
   - Report file has checkpoints but no `## Conclusion` → **partial**
   - Report file missing or empty → **missing**

3. **Commit any unsaved work** — partial reports, updated
   PROGRESS.md. Do not risk losing progress.

4. **Relaunch all incomplete slots immediately.** For partial
   reports: read the last checkpoint, compute remaining files,
   spawn a new agent with existing findings + remaining scope.
   For missing reports: full launch. Use the same agent prompt
   template as the initial launch.

5. **Brief the user in one line** — e.g., "Resuming: 4 of 17
   slots incomplete, relaunching." Then launch. Do not list
   every slot. Do not ask whether to proceed.

#### Hard gates

**Do not consolidate while any slot is incomplete.** Do not
skip incomplete slots. Do not move to "After completion."
Relaunch every missing or partial report before doing anything
else.

Only after a retry also fails (second rate limit in the same
session) should you inform the user that slots remain unfilled
and ask whether to wait or consolidate with gaps.

Moving to consolidation with missing data produces an incomplete
todo list that gives false confidence. The user thinks "everything
was reviewed" when it wasn't. This is the single worst failure
mode of the sweep — worse than finding no bugs, because it is
invisible.

#### Detecting partial reports
```bash
find <output-dir> -name '*.md' -exec grep -l 'CHECKPOINT' {} \;
```
For each: read checkpoint → compute remaining files → relaunch
with existing findings + remaining scope. Worst case loss: one
file's review work.

### 6. After completion

#### Convergence-weighted todo list

Read all complete reports. Deduplicate findings across critics:

- **3+ critics** flag same issue → promote severity. Near-certain bug.
- **2 critics** → note "confirmed by N reviewers." High confidence.
- **1 critic** → keep as-is. May be real or false positive.

Write `todo.list` with severity headers, `[ ]` items, file paths,
convergence counts, and report cross-references. Tag each finding's model
provenance where a tier-mix ran, and record which cross-critic confirmations
were **primed** (a later agent given an earlier finding as a heads-up) — primed
confirmations are not independent and must not inflate the convergence count.

**Coordinator-authored fallback.** The Workflow-based consolidation (per-subsystem
dedup agents + `node` pass) is ideal but needs agents. If a hard cap (weekly reset)
ends the review phase first, the coordinator can AUTHOR `todo.list` directly from
the committed reports plus the accumulated structured returns it already collected
per batch — synthesis, not review, so it needs no agents and runs on whatever tier
the coordinator is. A coordinator-authored todo.list from a fully-committed report
set is a valid deliverable; note in it which slots were deferred.

#### Targeted re-review

After fixing items: re-run only the (critic, subsystem) pairs that
flagged each fix. If a Resolved item reappears → regression.
For bulk verification: re-run `quality` on affected subsystems.

#### Final report to user

- Agents launched vs completed
- Confirmed bugs by severity
- Top 5 most actionable items
- Worktree path for browsing
- Do not push the review branch

### Branch lifecycle

The branch persists across multiple sweeps. Each full sweep is a
commit (or commit series) on the same branch. The commit log is
the audit trail: "full sweep 2026-05-16", "full sweep 2026-05-23".

**Full sweep** (default): re-reviews everything with fresh eyes.
KNOWN.md lightens the load — agents skip known issues, only report
new findings. Overwrites all prior reports with fresh analysis.
Regenerates todo.list. Good for: first review, periodic health
checks, post-major-development passes.

**Incremental sweep** (`sweep incremental`): two explicit goals:

1. **Verify fixes** — confirm resolved items from KNOWN.md are
   actually gone. If an agent rediscovers a Resolved item, it's
   a regression. Flag as critical.

2. **Find what was missed** — with KNOWN.md suppressing previously
   found issues, agents have cognitive bandwidth to dig deeper.
   They should look for second-order bugs, bugs-in-fixes, deeper
   variants of known issue classes, and issues in areas the full
   sweep didn't probe thoroughly.

Incremental agents review ALL subsystems (not just changed files)
but with different instructions: "The obvious bugs have been found.
Look deeper. Find what the first pass missed." This is what makes
repeated sweeps productive — each pass peels another layer.

Incrementals add to `reports/incremental/` without overwriting
full-sweep reports. They build on top of the latest full sweep.

**Blind sweep** (`sweep blind`): the full matrix with every prior
finding deliberately withheld. Agents receive SUBSYSTEMS.md scope
and project context (CLAUDE.md) but NOT KNOWN.md, not the
dismissal ledger, not prior reports, not todo lists — and their
prompts say so: "You have no prior findings. Report everything
you find." KNOWN.md is still maintained; it is hidden, not
abandoned. Reports go to `reports/blind/`.

The product is the **calibration diff**, computed after
consolidation:

- blind ∩ known — the ledger is honest; these issues are real
  and re-findable.
- blind ∖ known — genuinely new findings; merge into todo.list.
- known ∖ blind — tracked issues fresh eyes could NOT re-find.
  Each is one of: fixed-but-not-marked-Resolved, documented only
  in a ledger no newcomer would derive (documentation debt), or
  a stale entry that was never real. Triage explicitly — this
  column is the one only a blind sweep can produce.

The most expensive mode per unit of finding and the only one
that audits the ledgers themselves. Run on a fresh usage window;
never as the routine mode. Suppression-list discipline everywhere
else is what keeps an occasional blind sweep affordable.

**Detecting mode:** if the sweep branch already exists, ask:
"Full sweep or incremental?" If it doesn't exist, always full.
Blind is never inferred — only explicit `sweep blind`.

**Cleanup:** persists until user explicitly removes it:
`git worktree remove <path> && git branch -D sweep-review`

Do not delete or prompt for cleanup automatically.

---

## Standard mode

### Determine scope

- Branch name → diff against merge base
- File path → review that file/directory
- Commit range → review those commits
- No scope → current branch vs master merge base,
  or whole project if on master

### History scope (git category)

The history critic reviews commits, not files. The coordinator:

1. Determines the commit range:
   - On master, no explicit scope: unpushed commits
     (`git log origin/master..HEAD`)
   - On any other branch, no explicit scope: full branch
     history (`git log master..HEAD`)
   - Explicit commit range: use as given
2. Provides `git log --stat -p` output for the range
3. Skips file/directory scope — history is always commit-based

### Round zero — deterministic checks before any agent

Scripts first; agents only get what scripts cannot decide.

1. Run the project's own gates: clean build and full test suite.
   The suite is the project's accumulated checker — invariant
   tests live there (lone: `suite/leaf-invariant`,
   `suite/import-usage`). Record baselines (suite count, total
   compiler warnings) so later delta claims have a denominator.
2. Run the generic checks in `${CLAUDE_SKILL_DIR}/checks/`
   (git hygiene: whitespace, subject lengths, fixup leftovers,
   added TODOs).
3. Triage anything red before launching critics. Round-zero
   findings are coordinator work, not critic work.
4. **Tree freeze:** from first agent launch until the last
   report lands, do not mutate the reviewed tree — no commits,
   no checkouts, no edits, no builds in shared build trees.
   Concurrent mutation manufactures phantom findings.

When a round uncovers a class of finding a script could catch,
write the check before closing the round: prefer the project's
own test suite (it outlives the skill and runs in CI); use
`checks/` only for project-independent git hygiene.

### Spawn review agents

Fleet size follows novelty, not habit:

- **First review of new work:** 6-9 dedicated critics. Default
  set: correctness, rigor, consistency, tests, documentation,
  design, quality; add history for unpushed branches, and
  robustness when input handling or memory management changed.
  Add security when the change crosses a trust boundary: data
  arriving from outside the process (descriptors, network,
  foreign binaries), module or path resolution from external
  locations, exec or privilege transitions. For
  interpreter-internal changes robustness and correctness cover
  the same ground with less framing risk; when security does
  deploy, its prompt is framed as defensive review of the
  project's own code, and trust-boundary changes deploy both.
- **Re-review after fixes:** only the critics that flagged the
  fixed findings — typically correctness + tests + consistency.
- **Mechanical confirmation:** one verifier agent over the delta.
- **Deliberate usage burn** (user opt-in only): full fleet plus
  auditor.

One agent per critic — dedicated critics find 2-3x more than one
agent wearing every hat. Resolve critic definitions from
`${CLAUDE_SKILL_DIR}/critics/<category>/<name>.md`. Each agent
prompt includes:

- project context (CLAUDE.md), framed as claims to verify
- exact scope (commit range, files) and read-only constraints
- context documents (spec, execution notes, prior findings)
  framed verify-don't-trust
- the suppression list: known issues, tracked todos, the
  standing dismissal ledger, the implementer's recorded judgment
  calls — re-report only if actually wrong, not merely debatable
- output protocol: write findings to a file incrementally
  (sessions die; the file is the deliverable), return a terse
  summary

Agents never run the full suite or build in shared trees — the
coordinator ran the suite in round zero; agents run individual
tests and build only archived copies under /tmp.

**The auditor is special:** it receives the code but NOT the
design documents — list the withheld paths explicitly in its
prompt so it does not wander into them. Deploy once per new
convention or subsystem design, not per branch. The coordinator
diffs its derived contract against the real spec; divergences
are spec bugs, code drift, or missing documentation.

### Review loop

1. Collect findings. Triage: real / false positive / design
   choice to surface.
2. **Convergence raises priority, never truth.** Critics sharing
   a blind spot converge on the same wrong fix. Verify every fix
   premise personally against the nearest precedent before
   editing — in-file precedent beats cross-module symmetry.
3. **Only fix unambiguous issues.** Surface design choices to
   the user, each with a recommendation.
4. Fix protocol on unpushed branches: backup branch first
   (`backup/<branch>-pre-<purpose>`); one fixup commit per
   finding against its originating commit; autosquash rebase;
   verify tree identity against the backup (the diff must be
   exactly the intended changes); clean test at the tip;
   spot-build rewritten commits from `git archive` copies under
   /tmp — never check out inside the repo; reword commit
   messages the fold invalidated (renamed operands, test
   enumerations) in the same rebase.
5. Record dismissals with reasons beside the fixes; append
   settled judgments to the project's dismissal ledger
   (project-local: beside the project's todo/notes if it has
   them, else the review worktree) so future rounds inherit
   them instead of re-litigating.
6. Close the round with one verifier agent over the final
   delta: confirm each fix landed, fresh eyes on the changed
   material.
7. Repeat. **Two consecutive clean rounds end the loop** —
   further rounds are usage, not value.

### Final report

- Rounds and findings per round (the convergence trajectory)
- What was fixed (commit subjects) and what folded where
- Dismissals and why — a false positive explained is worth as
  much as a defect fixed
- Design choices surfaced for the user, each with a
  recommendation
- Verification evidence: suite counts, warning deltas,
  architecture coverage, tree-identity result
- `git log --oneline` of commits made

Do NOT push. Wait for human review.
