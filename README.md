# worktree-tool

A small shell function that makes `git worktree` practical for everyday feature work.

Create a worktree, commit, open a PR, delete the worktree — four commands, with guardrails so you cannot throw away work by accident.

## Installation

`wt` is a shell function, so it must be **sourced**, not executed. Running it as a script would not work: `wt base` moves your shell into the new worktree, and a subprocess cannot do that.

```bash
git clone https://github.com/reki2000/worktree-tool.git ~/.config/worktree-tool
```

Then add this to `~/.bashrc` or `~/.zshrc`:

```bash
source ~/.config/worktree-tool/wt.sh
```

Open a new shell, or `source` the file once in your current one.

**Requirements**

- bash or zsh
- git 2.31 or later (for `git rev-parse --path-format`)
- [GitHub CLI](https://cli.github.com/) (`gh`) — only for `wt pr`

## Usage

```bash
wt base       # new worktree from origin/develop, or origin/main if that is absent
wt current    # new worktree from the current HEAD

wt push       # push the current branch to origin
wt pr         # rebase onto the base branch if needed, push, and open a PR
wt remove     # delete the current worktree, if it is safe to do so

wt            # help
```

`wt base` and `wt current` take no arguments. `wt pr --base BRANCH` overrides the PR base.
Short aliases exist: `b`, `c`, `rm`.

## Typical flow

```bash
wt base                       # you are now inside a fresh worktree

git switch -c feature/foo      # new worktrees start on a detached HEAD
# ... work ...
git add .
git commit -m "Implement foo"

wt pr                         # rebase if needed, push, open the PR
wt remove                     # once the PR is merged
```

New worktrees are created on a **detached HEAD** on purpose — you pick the branch name yourself with `git switch -c` when you are ready to commit.

## Why use it

**Worktrees stop being a chore.** They live in `<repo>/.worktree/` under generated names, and `.worktree/` is added to your `.gitignore` automatically. You never invent a directory name, never pick a path, and never leave stray checkouts sitting beside your repository. `wt base` fetches first, so a new worktree starts from the real tip of `develop` or `main` — not from whatever your clone happened to know last week.

**It refuses to lose your work.** `wt remove` is the reason this exists. It will not delete a worktree with uncommitted changes, and it will not delete one whose HEAD is unreachable from every remote branch — it fetches, checks, and tells you to `wt push` first. It also only ever touches worktrees under `.worktree/`, so aiming it at your main checkout is an error rather than a disaster.

**`wt pr` handles the awkward parts.** It verifies the tree is clean, fetches, notices when your branch is behind the base, and offers to rebase. If that rebase rewrote commits you had already pushed, it uses `--force-with-lease` — but only after confirming the remote branch holds nothing you lack locally. A missing base branch, a branch equal to its own base, a missing `gh`: each is caught up front with a clear message instead of halfway through.

**Short enough to actually use.** One command per step, no flags to remember, and readable output at every stage.

## License

MIT. See [LICENSE](LICENSE).
