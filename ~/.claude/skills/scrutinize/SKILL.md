---
description: Adversarial review. Spawns a focused review agent, fixes issues, loops until zero found. Usage: /scrutinize <type> [scope]
---

## Scrutinize

Coordinator for adversarial review sessions.
You manage the review loop. You do not review code yourself.

### Arguments

The full text after `/scrutinize` is passed as a single string.
Parse it as:

- **Type** — first word: a critic name, `sweep`, or `sweep incremental`
- **Scope** — optional: branch, file path, commit range, or directory
- **Instructions** — anything else: free-form directives to the
  coordinator (e.g., "worktree at ~/proj/sweep", "focus on error
  handling", "skip the test files", "lighter review, just bugs")

Examples:
- `/scrutinize correctness` — correctness review of current branch diff
- `/scrutinize security source/auth/` — security review of that directory
- `/scrutinize sweep` — full sweep, default settings
- `/scrutinize sweep incremental` — incremental on existing branch
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
tests, documentation

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

**Launch strategy:** one wave per subsystem, all `run_in_background`.
Don't wait between waves. If rate-limited, stop launching and
let running agents finish.

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
| **Security** | Trace data flow from entry to sensitive ops. Check all untrusted arithmetic. Consider adversarial-but-valid input. |
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
convergence counts, and report cross-references.

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

**Detecting mode:** if the sweep branch already exists, ask:
"Full sweep or incremental?" If it doesn't exist, always full.

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

### Spawn review agent

1. Resolve critic definition: search `${CLAUDE_SKILL_DIR}/critics/programming/$0.md`,
   then `critics/writing/$0.md`, then `critics/electronics/$0.md`,
   then `critics/git/$0.md`
2. Read project conventions from CLAUDE.md (frame as claims to verify)
3. Spawn one opus agent with: diff/files + critic persona + conventions

### Review loop

1. Collect findings. Triage real issues vs false positives.
2. Report false positives honestly.
3. Real issues exist:
   a. **Only fix unambiguous issues.** Surface design choices to user.
   b. Fix with discrete logical commits.
   c. Re-spawn agent on updated code.
   d. Repeat until zero issues found.
4. Zero issues → final report.

### Final report

- Round count and findings per round
- What was fixed (commit subjects)
- False positives and why dismissed
- Test results if available
- Observations worth human consideration
- `git log --oneline` of commits made

Do NOT push. Wait for human review.
