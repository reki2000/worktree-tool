# ~/.config/wt.sh
#
# Usage:
#   wt
#   wt b | base
#   wt c | current
#   wt push
#   wt pr [--base BRANCH]
#   wt remove


wt() {
    local cmd="${1:-help}"

    if [ $# -gt 0 ]; then
        shift
    fi

    case "$cmd" in
        help|-h|--help)
            _wt_help
            ;;

        b|base)
            _wt_create_base "$@"
            ;;

        c|current)
            _wt_create_current "$@"
            ;;

        push)
            _wt_push "$@"
            ;;

        pr)
            _wt_pr "$@"
            ;;

        remove|rm)
            _wt_remove "$@"
            ;;

        *)
            echo "Unknown command: $cmd" >&2
            echo >&2
            _wt_help >&2
            return 1
            ;;
    esac
}


_wt_help() {
    cat <<'EOF'
Usage:
  wt                  show this help

  wt b | base         create worktree from:
                        origin/develop
                        or origin/main if develop does not exist

  wt c | current      create worktree from current HEAD

  wt push             push current branch to origin

  wt pr               rebase onto PR base if needed,
                      push current branch and create PR

  wt pr --base NAME   explicitly specify PR base branch

  wt remove           safely remove current worktree

Typical flow:

  wt b

  # work...
  git switch -c feature/foo
  git add .
  git commit -m "Implement foo"

  wt pr

  wt remove
EOF
}


_wt_require_repo() {
    git rev-parse --git-dir >/dev/null 2>&1 || {
        echo "Not inside a git repository." >&2
        return 1
    }
}


# Return the root of the main worktree.
_wt_main_root() {
    local common

    common="$(git rev-parse --path-format=absolute --git-common-dir)" ||
        return 1

    dirname "$common"
}


# Ensure /.worktree/ exists in the repository root .gitignore.
_wt_ensure_gitignore() {
    local root gitignore

    root="$(_wt_main_root)" || return 1
    gitignore="$root/.gitignore"

    touch "$gitignore" || return 1

    # Accept these existing forms:
    #
    #   .worktree
    #   .worktree/
    #   /.worktree
    #   /.worktree/
    #
    if grep -Eq \
        '^[[:space:]]*/?\.worktree/?[[:space:]]*$' \
        "$gitignore"
    then
        return 0
    fi

    # Ensure the new rule starts on its own line.
    if [ -s "$gitignore" ]; then
        printf '\n' >> "$gitignore"
    fi

    printf '/.worktree/\n' >> "$gitignore"

    echo "Added /.worktree/ to:"
    echo "  $gitignore"
}


_wt_setup_directory() {
    local root

    root="$(_wt_main_root)" || return 1

    _wt_ensure_gitignore || return 1

    mkdir -p "$root/.worktree" || return 1
}


_wt_new_path() {
    local root name

    root="$(_wt_main_root)" || return 1

    name="wt-$(date +%Y%m%d-%H%M%S)-$$-${RANDOM:-0}"

    echo "$root/.worktree/$name"
}


_wt_create_base() {
    _wt_require_repo || return 1
    _wt_setup_directory || return 1

    if [ $# -ne 0 ]; then
        echo "Usage: wt b" >&2
        return 1
    fi

    echo "Fetching origin..."
    git fetch origin --prune || return 1

    local start

    if git show-ref --verify --quiet refs/remotes/origin/develop; then
        start="origin/develop"

    elif git show-ref --verify --quiet refs/remotes/origin/main; then
        start="origin/main"

    else
        echo "Neither origin/develop nor origin/main exists." >&2
        return 1
    fi

    local dir
    dir="$(_wt_new_path)" || return 1

    echo "Creating worktree from $start"
    echo "  $dir"

    git worktree add --detach "$dir" "$start" || return 1

    cd "$dir" || return 1

    echo
    echo "Worktree created."
    echo "HEAD: $(git rev-parse --short HEAD)"
    echo "Base: $start"
}


_wt_create_current() {
    _wt_require_repo || return 1
    _wt_setup_directory || return 1

    if [ $# -ne 0 ]; then
        echo "Usage: wt c" >&2
        return 1
    fi

    local commit
    commit="$(git rev-parse HEAD)" || return 1

    local dir
    dir="$(_wt_new_path)" || return 1

    echo "Creating worktree from current HEAD"
    echo "  $dir"

    git worktree add --detach "$dir" "$commit" || return 1

    cd "$dir" || return 1

    echo
    echo "Worktree created."
    echo "HEAD: $(git rev-parse --short HEAD)"
}


_wt_current_branch() {
    local branch

    branch="$(git symbolic-ref --quiet --short HEAD)" || {
        echo "Current worktree is on detached HEAD." >&2
        echo >&2
        echo "Create a branch first, for example:" >&2
        echo "  git switch -c feature/foo" >&2
        return 1
    }

    echo "$branch"
}


_wt_push() {
    _wt_require_repo || return 1

    if [ $# -ne 0 ]; then
        echo "Usage: wt push" >&2
        return 1
    fi

    local branch
    branch="$(_wt_current_branch)" || return 1

    if [ -n "$(git status --porcelain)" ]; then
        echo "Warning: uncommitted changes exist:"
        git status --short
        echo
    fi

    echo "Pushing:"
    echo "  $branch -> origin/$branch"
    echo

    git push -u origin "$branch"
}


_wt_default_pr_base() {
    if git show-ref --verify --quiet refs/remotes/origin/develop; then
        echo "develop"

    elif git show-ref --verify --quiet refs/remotes/origin/main; then
        echo "main"

    else
        echo "Neither origin/develop nor origin/main exists." >&2
        return 1
    fi
}


_wt_confirm_rebase() {
    local base="$1"
    local answer

    echo
    echo "Current branch does not contain the latest origin/$base."
    echo

    printf "Rebase onto origin/%s before creating PR? [y/N] " "$base"

    IFS= read -r answer

    case "$answer" in
        y|Y|yes|YES|Yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}


_wt_pr() {
    _wt_require_repo || return 1

    local base=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --base)
                if [ $# -lt 2 ]; then
                    echo "--base requires a branch name." >&2
                    return 1
                fi

                base="$2"
                shift 2
                ;;

            *)
                echo "Unknown option: $1" >&2
                echo "Usage: wt pr [--base BRANCH]" >&2
                return 1
                ;;
        esac
    done

    command -v gh >/dev/null 2>&1 || {
        echo "GitHub CLI (gh) is required for 'wt pr'." >&2
        return 1
    }

    local branch
    branch="$(_wt_current_branch)" || return 1

    #
    # Rebase requires a clean worktree.
    #
    if [ -n "$(git status --porcelain)" ]; then
        echo "Refusing to create PR: uncommitted changes exist." >&2
        echo >&2
        git status --short >&2
        return 1
    fi

    echo "Fetching origin..."
    git fetch origin --prune || return 1

    #
    # Determine PR base.
    #
    if [ -z "$base" ]; then
        base="$(_wt_default_pr_base)" || return 1
    fi

    if ! git show-ref \
        --verify \
        --quiet \
        "refs/remotes/origin/$base"
    then
        echo "origin/$base does not exist." >&2
        return 1
    fi

    if [ "$branch" = "$base" ]; then
        echo "Current branch and PR base are both '$base'." >&2
        return 1
    fi

    #
    # If origin/<current branch> already exists, make sure it
    # contains no commits that are absent locally.
    #
    # This is important because a subsequent rebase may require
    # force-with-lease.
    #
    local remote_branch_exists=false

    if git show-ref \
        --verify \
        --quiet \
        "refs/remotes/origin/$branch"
    then
        remote_branch_exists=true

        if ! git merge-base \
            --is-ancestor \
            "origin/$branch" \
            HEAD
        then
            echo "Refusing to continue." >&2
            echo >&2
            echo "origin/$branch contains commits that are not in the local branch." >&2
            echo "Synchronize/reconcile the branch first." >&2
            return 1
        fi
    fi

    #
    # Check whether the current branch already contains
    # the latest PR base.
    #
    local rebased=false

    if git merge-base \
        --is-ancestor \
        "origin/$base" \
        HEAD
    then
        echo "Already up to date with origin/$base."

    else
        if _wt_confirm_rebase "$base"; then
            echo
            echo "Rebasing onto origin/$base..."

            git rebase "origin/$base" || {
                echo >&2
                echo "Rebase stopped." >&2
                echo "Resolve conflicts and continue with:" >&2
                echo "  git rebase --continue" >&2
                echo >&2
                echo "Or abort with:" >&2
                echo "  git rebase --abort" >&2
                return 1
            }

            rebased=true

        else
            echo
            echo "Skipping rebase."
        fi
    fi

    #
    # Push.
    #
    # If the branch had already been pushed and we rebased it,
    # commit IDs may have changed. Because we verified above that
    # origin/<branch> had no remote-only commits, force-with-lease
    # is safe here.
    #
    echo
    echo "Pushing:"
    echo "  $branch -> origin/$branch"
    echo

    if [ "$rebased" = true ] &&
       [ "$remote_branch_exists" = true ] &&
       ! git merge-base \
           --is-ancestor \
           "origin/$branch" \
           HEAD
    then
        echo "History changed by rebase; using --force-with-lease."
        echo

        git push \
            --force-with-lease \
            -u origin "$branch" ||
            return 1
    else
        git push -u origin "$branch" || return 1
    fi

    #
    # Create PR.
    #
    echo
    echo "Creating PR:"
    echo "  $branch -> $base"
    echo

    gh pr create \
        --head "$branch" \
        --base "$base" \
        --fill
}


_wt_remove() {
    _wt_require_repo || return 1

    if [ $# -ne 0 ]; then
        echo "Usage: wt remove" >&2
        return 1
    fi

    local current root managed_root

    current="$(git rev-parse --show-toplevel)" || return 1
    root="$(_wt_main_root)" || return 1
    managed_root="$root/.worktree"

    #
    # Only remove worktrees under <repo>/.worktree/.
    #
    case "$current" in
        "$managed_root"/*)
            ;;
        *)
            echo "Refusing to remove this worktree." >&2
            echo >&2
            echo "wt remove only removes worktrees under:" >&2
            echo "  $managed_root" >&2
            echo >&2
            echo "Current:" >&2
            echo "  $current" >&2
            return 1
            ;;
    esac

    #
    # Do not lose working-tree/index changes.
    #
    if [ -n "$(git status --porcelain)" ]; then
        echo "Refusing to remove: uncommitted changes exist." >&2
        echo >&2
        git status --short >&2
        return 1
    fi

    local head
    head="$(git rev-parse HEAD)" || return 1

    #
    # Refresh remote refs before checking safety.
    #
    echo "Fetching remotes..."

    git fetch --all --prune || {
        echo "Fetch failed; refusing to remove." >&2
        return 1
    }

    #
    # HEAD must be reachable from at least one remote branch.
    #
    local refs

    refs="$(
        git for-each-ref \
            --format='%(refname:short)' \
            --contains="$head" \
            refs/remotes/
    )"

    if [ -z "$refs" ]; then
        echo >&2
        echo "Refusing to remove." >&2
        echo "Current HEAD is not reachable from any remote branch." >&2
        echo >&2
        echo "HEAD:" >&2
        echo "  $(git rev-parse --short HEAD)" >&2
        echo >&2

        local branch
        branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)"

        if [ -n "$branch" ]; then
            echo "Push it first:" >&2
            echo "  wt push" >&2
        else
            echo "Create a branch and push it first:" >&2
            echo "  git switch -c feature/foo" >&2
            echo "  wt push" >&2
        fi

        return 1
    fi

    echo
    echo "HEAD is safely reachable from:"
    echo "$refs" | sed 's/^/  /'
    echo

    #
    # Leave the directory before deleting it.
    #
    cd "$root" || return 1

    echo "Removing:"
    echo "  $current"

    git worktree remove "$current" || return 1

    echo
    echo "Removed."
}
