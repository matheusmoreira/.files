## Session resilience

Long sessions risk context loss from token limits or API errors.
During extended work (design sessions, multi-file reviews, spec writing):

- Write progress to a scratch file at each major milestone.
  Use a project-local file (e.g., NOTES.md, scratch.md).
  Don't hold large intermediate results only in context.
- If a response needs to cover many topics, write the details
  to a file and summarize in-context.
- When spawning subagents for research, have them write findings
  to disk rather than returning everything in the final message.
- Always think and reason deeply; never limit your own performance
  due to rate limits or errors, find ways to cope with them

## Verification

- Verify facts before making claims.
- Verify branch and worktree state
  before and after making changes;
  user may have edited or rebased.

## Git workflow

Commit freely and often. Prefer small logical commits.
Easy to rebase and restructure. Easy to drop unwanted commits.
This protects against accidental data loss.

Never push commits without explicit permission.
It's trivial to manipulate commits while they're local.
That is not the case once they're out there.

Never use globbing commands like `git add -A` or `git add .`
ALWAYS explicitly add specific files. Capturing untracked
files and having to uncommit them later is a recurring problem.

Before editing, amending, or restructuring any commit,
check its current state with `git show`. The user may have
reworded the message or edited the diff during a review pass.
Preserve both message and content, make only additive changes.
Try to reconcile your plans with the user's plans and intent.
If in doubt, don't proceed, simply ask the user.

Never credit Claude or AI in commits, code, or documentation.

### Destructive operations on a dirty tree

Never run `git checkout -- <file>`, `git restore <file>`,
`git reset --hard`, or `git clean` on a file with uncommitted
changes you care about. These overwrite the working tree from
the index or HEAD and silently destroy unstaged work.

If you need a clean working tree mid-operation, use the stash:
`git stash push`. Stashed changes are recoverable via `git stash pop`.
Plain `restore` and `checkout --` are not. Dropping unwanted stashes
is trivial to do later if necessary.

### Commit ugly, rebase pretty

Avoid partial staging via `git add -p` with piped input.
Hunk numbering shifts when hunks split, and you cannot see
what is actually staged until the operation completes.

Prefer two approaches:

  - Make edits incrementally and commit each logical chunk
    before starting the next. This keeps the working tree
    close to the index.

  - If a commit ended up mixed, leave it for the `git review`
    pass where commits can be split interactively.

Do not do history surgery on a dirty working tree. Clean
state first (commit or stash), then reset/rebase, then
re-apply changes one at a time, committing each.

### Branch review flow

The user reviews branches using custom git commands
in a separate terminal. These scripts are in ~/.local/bin/.

**Review cycle:**

1. `git review` — interactive rebase with every commit set to `edit`.
   Shows the current commit's message and diff.
   `git review -N` limits to the first N commits.
   `git review <upstream>` rebases onto a specific ref.
2. `git next` — `git rebase --continue` to the next commit, show it.
3. `git review --finish` — accept all remaining commits at once.
   Rewrites the remaining `edit` marks to `pick` via sed,
   then does `rebase --continue`. Changes are kept.
   Use after restructuring commits (splits, fixups, reorders).

During this process, the user may return to the Claude session
to discuss or fix individual commits. When asked to fix something
during a review, always verify current git status before acting.
Amend the current commit if appropriate and tell the user to continue
with `git next` or restart with `git review --finish`.
Reviews are cheap to start, finish and restart.
It is common for many review rounds to take place
before a branch or feature is declared done.

**Inspecting without advancing:**

`git peek` — show the current commit during a review.
`git peek -N` — show the next N commits.
`git peek --oneline` — one-line summary of all remaining.

Outside a rebase, `git peek` shows unpushed commits.
`git peek -5` shows the first 5 unpushes commits lying
on top of the master branch.

**Shipping:**

`git ship` — push N commits to the remote.
`git ship -N` — push exactly N commits (default 1).

During a rebase, pushes the current commit(s) and advances.
Outside a rebase, pushes the oldest unpushed commit(s).

Never run `git ship` without explicit instruction.
