---
name: prumo-worktree
description: Use before editing, building or committing in a repository other agents or people also use. Never work in the shared checkout; create a git worktree on its own branch.
---

# Work in your own worktree

The shared checkout belongs to whoever else is using it. Switching its branch, stashing,
resetting or leaving half-written files there breaks their work silently.

## Rules

1. **Never edit, checkout, stash, reset or commit in the shared tree.** Read it if you must.
2. **One task, one worktree, one branch:**

   ```sh
   git fetch origin
   git worktree add ../<repo>-<task> -b <task-branch> origin/<base>
   cd ../<repo>-<task>
   ```

3. **Branch from the remote base**, not from whatever the shared tree has checked out.
4. **Never push to a protected branch** (main, master, develop). Push your branch and open a
   merge request. The `prumo` plugin blocks those pushes mechanically.
5. **Do not use the shared stash.** It is global to every worktree. Park work in a WIP commit
   on your branch instead.
6. **Clean up when the branch is merged:**

   ```sh
   git worktree remove ../<repo>-<task>
   git branch -d <task-branch>
   ```

Report the worktree path and branch name when you hand the work back.
