#!/usr/bin/env zsh
# git-jira-shortcuts — Git + Jira workflow shortcuts for zsh
# https://github.com/chipallen2/git-jira-shortcuts
#
# Configuration (set in ~/.git-jira-shortcuts.env):
#   GJS_TICKET_PREFIX      — Jira project key (e.g. MYPROJ, ACME)
#   GJS_JIRA_DOMAIN        — Jira domain (e.g. yourco.atlassian.net)
#   GJS_JIRA_API_TOKEN     — Base64 Jira API token
#   GJS_BRANCH_WEBHOOK_URL — Optional webhook for branch name generation
#   GJS_REPOS              — Optional array of repo paths for grepos

# Store path to this script for self-reference (used by ghelp)
GJS_SHELL_SCRIPT_PATH="${0:A}"

# Current installed version (read from package.json next to this script)
GJS_VERSION=$(node -p "require('$(dirname "$GJS_SHELL_SCRIPT_PATH")/../package.json').version" 2>/dev/null)

# Background version check — runs once per day, never blocks the shell
_gjs_version_cache="$HOME/.gjs-version-cache"
(
  # Skip if cache is less than 24 hours old
  if [[ -f "$_gjs_version_cache" ]]; then
    local cache_age=$(( $(date +%s) - $(stat -f%m "$_gjs_version_cache" 2>/dev/null || echo 0) ))
    [[ $cache_age -lt 86400 ]] && exit 0
  fi
  # Fetch latest version from npm registry (silent, no error output)
  local latest=$(curl -sf --max-time 3 "https://registry.npmjs.org/git-jira-shortcuts/latest" | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
  [[ -n "$latest" ]] && echo "$latest" > "$_gjs_version_cache"
) &>/dev/null &!

# Show upgrade notice if a newer version is available (reads local cache only — instant)
_gjs_check_upgrade() {
  [[ ! -f "$_gjs_version_cache" ]] && return
  local latest=$(cat "$_gjs_version_cache" 2>/dev/null)
  [[ -z "$latest" || "$latest" == "$GJS_VERSION" ]] && return
  # Compare versions: if latest is different and greater, show notice
  if [[ "$(printf '%s\n%s' "$GJS_VERSION" "$latest" | sort -V | tail -1)" == "$latest" && "$latest" != "$GJS_VERSION" ]]; then
    echo "\033[33m⬆  git-jira-shortcuts $latest is available (you have $GJS_VERSION)\033[0m" >&2
    echo "\033[33m   Run: npm install -g git-jira-shortcuts@$latest\033[0m" >&2
    echo "" >&2
  fi
}

###
### INTERNAL HELPERS
###

_gjs_get_recent_branches() {
  local reflog=$(git reflog --all --format='%gd:%gs' 2>/dev/null)
  [[ -z "$reflog" ]] && return 1
  local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  echo "$reflog" | grep "checkout:" | cut -d':' -f3- | \
    sed 's/.*moving from .* to //' | \
    awk -v cur="$current_branch" '!seen[$0]++ && $0 != cur' | \
    head -10
}

_gjs_interactive_menu() {
  local -a options=("$@")
  local selected=1
  local total=${#options[@]}

  [[ $total -eq 0 ]] && return 1

  tput civis >&2 2>/dev/null

  for i in {1..$total}; do
    if [[ $i -eq $selected ]]; then
      printf "  \033[36m● %s\033[0m\n" "${options[$i]}" >&2
    else
      printf "  ○ %s\n" "${options[$i]}" >&2
    fi
  done

  while true; do
    read -rsk1 key
    case "$key" in
      $'\e')
        read -rsk1 key2
        read -rsk1 key3
        case "$key3" in
          A) ((selected > 1)) && ((selected--)) ;;
          B) ((selected < total)) && ((selected++)) ;;
        esac
        ;;
      $'\n')
        break
        ;;
      q)
        printf "\033[%dB" "$((total - selected))" >&2
        tput cnorm >&2 2>/dev/null
        return 1
        ;;
    esac

    printf "\033[%dA" "$total" >&2
    for i in {1..$total}; do
      printf "\r\033[K" >&2
      if [[ $i -eq $selected ]]; then
        printf "  \033[36m● %s\033[0m\n" "${options[$i]}" >&2
      else
        printf "  ○ %s\n" "${options[$i]}" >&2
      fi
    done
  done

  tput cnorm >&2 2>/dev/null
  echo "${options[$selected]}"
}

_gjs_is_ticket_number() {
  [[ -n "$GJS_TICKET_PREFIX" ]] && [[ $1 =~ ^[0-9]{3,6}$ ]]
}

_gjs_branch_exists_local() {
  git show-ref --verify --quiet "refs/heads/$1"
}

_gjs_branch_exists_remote() {
  [[ -n "$(git ls-remote --heads origin "$1" 2>/dev/null)" ]]
}

_gjs_resolve_branch_input() {
  local raw_input="$1"
  local scope="${2:-any}"

  if [[ -z "$raw_input" ]]; then
    echo "$raw_input"
    return 0
  fi

  if [[ "$raw_input" == "m" ]]; then
    echo "master"
    return 0
  elif [[ "$raw_input" == "d" ]]; then
    echo "develop"
    return 0
  fi

  if ! _gjs_is_ticket_number "$raw_input"; then
    echo "$raw_input"
    return 0
  fi

  local prefix="${GJS_TICKET_PREFIX}-$raw_input"
  local -a matches=()

  if [[ "$scope" == "local" || "$scope" == "any" ]]; then
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      if [[ "$branch" == ${prefix}* && -z ${matches[(r)$branch]} ]]; then
        matches+=("$branch")
      fi
    done < <(git branch --format="%(refname:short)")
  fi

  if [[ "$scope" == "remote" || "$scope" == "any" ]]; then
    while IFS= read -r branch; do
      [[ -z "$branch" || "$branch" == *"->"* ]] && continue
      if [[ "$branch" == origin/${prefix}* ]]; then
        local short_branch="${branch#origin/}"
        if [[ -z ${matches[(r)$short_branch]} ]]; then
          matches+=("$short_branch")
        fi
      fi
    done < <(git branch -r --format="%(refname:short)")
  fi

  if (( ${#matches[@]} == 0 )); then
    echo "❌ No branches found matching $prefix" >&2
    return 1
  fi

  if (( ${#matches[@]} == 1 )); then
    echo "${matches[1]}"
    return 0
  fi

  echo "🔢 Multiple branches found for $prefix:" >&2
  local i=1
  for branch in "${matches[@]}"; do
    echo "  $i) $branch" >&2
    ((i++))
  done

  local choice
  while true; do
    read "choice?Select branch [1-${#matches[@]}]: "
    if [[ "$choice" =~ '^[0-9]+$' ]] && (( choice >= 1 && choice <= ${#matches[@]} )); then
      echo "${matches[$choice]}"
      return 0
    fi
    echo "❌ Invalid selection." >&2
  done
}

_gjs_sanitize_branch_name() {
  local title="$1"
  echo "$title" | tr '[:upper:]' '[:lower:]' | \
    sed 's/[^a-z0-9]/-/g' | \
    sed 's/--*/-/g' | \
    sed 's/^-//' | \
    sed 's/-$//' | \
    cut -c1-50
}

_gjs_get_jira_story_title() {
  local story_number="$1"

  if [[ -z "$GJS_JIRA_API_TOKEN" ]]; then
    echo "❌ GJS_JIRA_API_TOKEN not set. Run: git-jira-shortcuts init" >&2
    return 1
  fi
  if [[ -z "$GJS_JIRA_DOMAIN" ]]; then
    echo "❌ GJS_JIRA_DOMAIN not set. Run: git-jira-shortcuts init" >&2
    return 1
  fi
  if [[ -z "$story_number" ]]; then
    echo "❌ Story number is required" >&2
    return 1
  fi

  local response
  response=$(curl -sS \
    -H "Authorization: Basic $GJS_JIRA_API_TOKEN" \
    -H "Accept: application/json" \
    "https://$GJS_JIRA_DOMAIN/rest/api/3/issue/${GJS_TICKET_PREFIX}-$story_number?fields=summary")

  if [[ $? -ne 0 ]]; then
    echo "❌ Jira API call failed." >&2
    return 1
  fi

  local summary
  summary=$(echo "$response" | jq -r '.fields.summary // empty')

  if [[ -z "$summary" ]]; then
    echo "❌ Could not find ${GJS_TICKET_PREFIX}-$story_number or extract title" >&2
    return 1
  fi

  echo "$summary"
}

###
### PUBLIC COMMANDS
###

grecent() { # grecent | Show recently checked out branches (last 10)
  local reflog=$(git reflog --all --format='%gd:%gs' 2>/dev/null)
  [[ -z "$reflog" ]] && echo "No git history found" && return 1
  local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  echo "$reflog" | grep "checkout:" | cut -d':' -f3- | \
    sed 's/.*moving from .* to //' | \
    awk -v cur="$current_branch" '!seen[$0]++ && $0 != cur' | \
    head -10 | \
    nl -nln | \
    sed 's/^/  /'
}

unalias gs 2>/dev/null
gs() { # gs | Clean git status with remote sync info
  local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  [[ -z "$branch" ]] && echo "Not a git repo" && return 1
  echo "\033[1m$branch\033[0m"
  local staged=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  local unstaged=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
  local untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  local pending=$((staged + unstaged + untracked))
  git fetch --quiet 2>/dev/null
  local behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
  local ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  if [[ $pending -gt 0 || $ahead -gt 0 ]]; then
    echo "🔴 \033[31mFiles Pending\033[0m"
  elif [[ $behind -gt 0 ]]; then
    echo "🔵 \033[34mBehind\033[0m"
  else
    echo "✅ \033[32mUp to Date\033[0m"
  fi
}
alias gstatus='gs' # gstatus | Alias for gs
alias gp='git pull --no-rebase --no-edit' # gp | Pull without rebase or editor

grepos() { # grepos | Show all repo clones and their current branch
  [[ -z "${GJS_REPOS+x}" ]] && echo "GJS_REPOS not defined. Run: git-jira-shortcuts init" && return 1
  local max_len=0
  for entry in "${GJS_REPOS[@]}"; do
    local label="${entry##*:}"
    (( ${#label} > max_len )) && max_len=${#label}
  done
  for entry in "${GJS_REPOS[@]}"; do
    local dir="${entry%:*}"
    local label="${entry##*:}"
    if [[ -d "$dir/.git" ]]; then
      local branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
      printf "%-${max_len}s  %s\n" "$label" "${branch:-???}"
    else
      printf "%-${max_len}s  %s\n" "$label" "\033[31m(not found)\033[0m"
    fi
  done
}
alias repos='grepos' # grepos | Alias for grepos

ghelp() { # ghelp | Show all git-jira-shortcuts commands
  _gjs_check_upgrade
  cat >&2 <<'EOF'
🧠 GIT-JIRA-SHORTCUTS

── Status ─────────────────────────────────────────────────────
  gs                  Quick git status — branch, sync info, pending files
  gl / glist          List all pending files (staged, unstaged, untracked)
  grecent             Show last 10 branches you checked out

── Branching ──────────────────────────────────────────────────
  gw [branch]         Switch branches — arrow-key picker if no branch given
    gswitch             (same, also accepts --force / -f)
  gt <branch|ticket#> Create or switch to a branch — auto-names from Jira
    gstart, gcreate     (same)
  gdel [branch]       Delete a branch — interactive picker, safety checks
    gdelete             (same)

── Committing & Pushing ───────────────────────────────────────
  gf <message>        Stage all → commit (skip hooks) → push
    gcfast              (same)  Auto-prefixes ticket ID from branch name.
  gc <message>        Stage all → commit (with hooks) → push
    gcommit             (same)  Auto-prefixes ticket ID from branch name.
  gpu [branch]        Push current branch with upstream tracking
    gpush               (same)
  gp                  Pull (no rebase, no editor)

── Merge & Diff ───────────────────────────────────────────────
  gm [branch]         Merge another branch INTO your current branch
    gmerge              (same)
  gdiff [branch]      Files changed vs target branch + GitHub compare link

── File Operations ────────────────────────────────────────────
  gr [file]           Reset a file with confirmation — picker if no file
    greset              (same)

── Utilities ──────────────────────────────────────────────────
  grepos / repos      Show all repo clones and their current branch
  testJira / tj       Test your Jira API connection
  ghelp               This help screen

── Tips ───────────────────────────────────────────────────────
  Ticket numbers:
    Just type the number — no need to type the full branch name.
    Example: gw 1234  →  switches to PROJ-1234-whatever-the-branch-is
             gt 1234  →  creates a branch named from the Jira story title

  Interactive picker:
    Leave the branch empty on gw, gdel, or gm and you'll get an
    arrow-key menu of your recent branches to pick from.

  Merge workflow (gm):
    Stay on YOUR branch, then tell it which branch to merge in.
    It pulls latest on that branch first, then merges it into yours.
    Example: (on feature branch) gm develop
             → pulls latest develop → merges develop into your branch

  Auto-prefixed commits:
    On a ticket branch like PROJ-1234-fix-bug, your commit messages
    are automatically prefixed:  gf "fixed it"  →  "PROJ-1234: fixed it"

  Branch shorthand:
    m → master    d → develop
EOF
}

gdiff() { # gdiff [*branch=m] | List files changed for PR to target branch + GitHub compare link
  local target_input="${1:-m}"
  local target
  if ! target=$(_gjs_resolve_branch_input "$target_input" "any"); then
    return 1
  fi

  local diff_ref="$target"
  if _gjs_branch_exists_remote "$target" && ! _gjs_branch_exists_local "$target"; then
    diff_ref="origin/$target"
  fi

  local current_branch=$(git rev-parse --abbrev-ref HEAD)
  local changed_files=$(git --no-pager diff --name-only "$diff_ref"...HEAD)

  if [[ -z "$changed_files" ]]; then
    echo "No files changed vs $target"
  else
    local file_count=$(echo "$changed_files" | wc -l | tr -d ' ')
    echo "$file_count files changed vs $target"
    echo ""
    echo "$changed_files"
  fi

  local remote_url=$(git remote get-url origin 2>/dev/null)
  if [[ -n "$remote_url" ]]; then
    local repo_path
    if [[ "$remote_url" == git@github.com:* ]]; then
      repo_path="${remote_url#git@github.com:}"
    elif [[ "$remote_url" == https://github.com/* ]]; then
      repo_path="${remote_url#https://github.com/}"
    fi
    repo_path="${repo_path%.git}"
    if [[ -n "$repo_path" ]]; then
      echo ""
      echo "View full diff at:"
      echo "https://github.com/${repo_path}/compare/${target}...${current_branch}?expand=1"
    fi
  fi
}

glist() { # glist | List files pending in this branch
  git --no-pager status --short --untracked-files=all
}
alias gl='glist' # glist | Alias for glist

greset() { # greset [*file] | Reset a specific file with confirmation (interactive if no file given)
  local file="$1"
  
  _greset_file() {
    local f="$1"
    local file_status=$(git status --porcelain -- "$f" 2>/dev/null | head -1)
    local index_status="${file_status:0:1}"
    local worktree_status="${file_status:1:1}"
    if [[ "$index_status" == "?" ]]; then
      rm -rf "$f"
    elif [[ "$index_status" == "A" ]]; then
      git restore --staged "$f" 2>/dev/null
      rm -rf "$f"
    else
      git restore --staged --worktree "$f" 2>/dev/null || git checkout HEAD -- "$f" 2>/dev/null
    fi
  }
  
  if [[ -z "$file" ]]; then
    local files=()
    local statuses=()
    while IFS= read -r line; do
      local fname="${line:3}"
      if [[ "$fname" == *" -> "* ]]; then
        fname="${fname##* -> }"
      fi
      files+=("$fname")
      statuses+=("${line:0:2}")
    done < <(git status --porcelain)
    
    if [[ ${#files[@]} -eq 0 ]]; then
      echo "No modified files to reset."
      return 0
    fi
    
    echo "Select a file to reset:"
    echo "  1) ALL (reset all files)"
    local i=2
    for f in "${files[@]}"; do
      echo "  $i) $f"
      ((i++))
    done
    
    echo -n "Enter number: "
    read choice
    
    if [[ "$choice" == "1" ]]; then
      echo "Are you sure you want to reset ALL files? (Y/N)"
      read -k user_input
      echo
      if [[ $user_input == "y" || $user_input == "Y" ]]; then
        git restore --staged --worktree . 2>/dev/null
        git clean -fd 2>/dev/null
        echo "✅ Reset all files"
      else
        echo "❌ Cancelled"
      fi
      return 0
    fi
    
    local idx=$((choice - 1))
    if [[ $idx -lt 1 || $idx -gt ${#files[@]} ]]; then
      echo "❌ Invalid selection"
      return 1
    fi
    file="${files[$idx]}"
  fi
  
  echo "Are you sure you want to reset $file? (Y/N)"
  read -k user_input
  echo
  if [[ $user_input == "y" || $user_input == "Y" ]]; then
    _greset_file "$file"
    echo "✅ Reset $file"
  else
    echo "❌ Cancelled"
  fi
}
alias gr='greset' # greset [*file] | Alias for greset

gswitch() { # gswitch [*branch] [--force|-f] | Switch branches (optionally bypass local-dirty guard)
  local force_switch=0
  local -a positional=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      --force|-f)
        force_switch=1
        ;;
      *)
        positional+=("$arg")
        ;;
    esac
  done
  set -- "${positional[@]}"

  if [[ $force_switch -eq 0 && -n "$(git status --porcelain)" ]]; then
    echo "⚠️  You have uncommitted changes. Commit or stash before switching."
    echo "   Use 'gw --force [branch]' to bypass this check."
    return 1
  fi

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  local unpushed
  unpushed=$(git log origin/"$branch"..HEAD --oneline 2>/dev/null)

  if [[ -n "$unpushed" ]]; then
    echo "🚫 You have commits on '$branch' not pushed to origin. Push them first."
    return 1
  fi

  if [[ -z "$1" ]]; then
    local -a branches=()
    while IFS= read -r b; do
      branches+=("$b")
    done < <(_gjs_get_recent_branches)

    if [[ ${#branches[@]} -eq 0 ]]; then
      echo "No recent branches found."
      return 1
    fi

    echo "Switch to branch (↑/↓ select, Enter confirm, q cancel):"
    local picked
    if ! picked=$(_gjs_interactive_menu "${branches[@]}"); then
      echo "Cancelled."
      return 1
    fi
    set -- "$picked"
  fi

  local target_branch
  if ! target_branch=$(_gjs_resolve_branch_input "$1" "any"); then
    return 1
  fi
  
  if git show-ref --verify --quiet refs/heads/"$target_branch"; then
    git switch "$target_branch" || return 1
  else
    echo "📡 Branch not found locally, checking out from remote..."
    git checkout -t origin/"$target_branch" || {
      echo "❌ Failed to checkout branch '$target_branch' from remote."
      return 1
    }
  fi
  echo "⬇️  Pulling latest changes..."
  git pull
}
alias gw='gswitch' # gswitch [*branch] | Alias for gswitch

gcfast() { # gcfast [message] | Commit all, skip hooks, push (auto-prefix if ticket branch)
  if [[ -z "$1" ]]; then
    echo "Usage: gcfast \"commit message\""
    return 1
  fi

  local message="$*"
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)

  if [[ -n "$GJS_TICKET_PREFIX" ]]; then
    local pattern="^${GJS_TICKET_PREFIX}-[0-9]+"
    if [[ "$branch" =~ $pattern ]]; then
      local jira_prefix="${MATCH}"
      local msg_pattern="^${GJS_TICKET_PREFIX}-[0-9]+:"
      if [[ ! "$message" =~ $msg_pattern ]]; then
        message="$jira_prefix: $message"
        echo "📝 Auto-prefixed commit message: \"$message\""
      fi
    fi
  fi

  echo "🧩 Staging all changes..."
  git add .

  echo "💬 Committing with message: \"$message\" (no-verify)"
  if git commit -m "$message" --no-verify; then
    echo "✅ Commit successful."
  else
    echo "ℹ️  Nothing to commit, checking if there are commits to push..."
    if ! git log origin/"$branch".."$branch" --oneline | grep -q .; then
      echo "❌ No commits to push and nothing to commit."
      return 1
    fi
  fi

  echo "🚀 Pushing branch '$branch' to origin..."
  git push -u origin "$branch"
}
alias gf='gcfast' # gcfast [message] | Alias for gcfast

gcommit() { # gcommit [message] | Commit all with hooks and auto-prefix, then push
  if [[ -z "$1" ]]; then
    echo "Usage: gcommit \"commit message\""
    return 1
  fi

  local message="$*"
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)

  if [[ -n "$GJS_TICKET_PREFIX" ]]; then
    local pattern="^${GJS_TICKET_PREFIX}-[0-9]+"
    if [[ "$branch" =~ $pattern ]]; then
      local jira_prefix="${MATCH}"
      local msg_pattern="^${GJS_TICKET_PREFIX}-[0-9]+:"
      if [[ ! "$message" =~ $msg_pattern ]]; then
        message="$jira_prefix: $message"
        echo "📝 Auto-prefixed commit message: \"$message\""
      fi
    fi
  fi

  echo "🧩 Staging all changes..."
  git add .

  echo "💬 Committing with message: \"$message\""
  if git commit -m "$message"; then
    echo "✅ Commit successful."
  else
    echo "ℹ️  Nothing to commit, checking if there are commits to push..."
    if ! git log origin/"$branch".."$branch" --oneline | grep -q .; then
      echo "❌ No commits to push and nothing to commit."
      return 1
    fi
  fi

  echo "🚀 Pushing branch '$branch' to origin..."
  git push -u origin "$branch"
}
alias gc='gcommit' # gcommit [message] | Alias for gcommit

gstart() { # gstart [branch|ticket-number] | Create or switch to branch (Jira-aware)
  local branch_input="$1"

  if [[ -z "$branch_input" ]]; then
    echo "Usage: gstart <branch-name|ticket-number>"
    echo "  branch-name:    Full branch name or existing branch"
    if [[ -n "$GJS_TICKET_PREFIX" ]]; then
      echo "  ticket-number:  Numeric ID to auto-create ${GJS_TICKET_PREFIX}-#####-title branch"
    fi
    return 1
  fi

  local branch
  
  if _gjs_is_ticket_number "$branch_input"; then
    echo "📋 Fetching Jira story title for ${GJS_TICKET_PREFIX}-$branch_input..."
    local story_title
    if ! story_title=$(_gjs_get_jira_story_title "$branch_input"); then
      echo "❌ Failed to get story title. Using simple branch name."
      branch="${GJS_TICKET_PREFIX}-$branch_input"
    else
      echo "📝 Story title: $story_title"
      
      if [[ -n "$GJS_BRANCH_WEBHOOK_URL" ]]; then
        echo "📡 Getting branch suffix from webhook..."
        local webhook_response
        webhook_response=$(curl -s -X POST \
          -H "Content-Type: application/json" \
          -d "{\"storyTitle\": \"$story_title\"}" \
          "$GJS_BRANCH_WEBHOOK_URL")
        
        if [[ $? -eq 0 ]]; then
          local branch_name=$(echo "$webhook_response" | jq -r '.branchName // ""')
          
          if [[ -n "$branch_name" ]]; then
            branch="${GJS_TICKET_PREFIX}-$branch_input-$branch_name"
            echo "✅ Webhook provided branch suffix: $branch_name"
          else
            echo "⚠️  Webhook failed, using sanitized Jira title"
            local sanitized_title
            sanitized_title=$(_gjs_sanitize_branch_name "$story_title")
            branch="${GJS_TICKET_PREFIX}-$branch_input-$sanitized_title"
          fi
        else
          echo "❌ Failed to call webhook, using sanitized Jira title"
          local sanitized_title
          sanitized_title=$(_gjs_sanitize_branch_name "$story_title")
          branch="${GJS_TICKET_PREFIX}-$branch_input-$sanitized_title"
        fi
      else
        local sanitized_title
        sanitized_title=$(_gjs_sanitize_branch_name "$story_title")
        branch="${GJS_TICKET_PREFIX}-$branch_input-$sanitized_title"
      fi
      
      echo "🌿 Created branch name: $branch"
    fi
  else
    if ! branch=$(_gjs_resolve_branch_input "$branch_input" "any"); then
      return 1
    fi
  fi

  if _gjs_branch_exists_local "$branch"; then
    git checkout "$branch" || return 1
  elif _gjs_branch_exists_remote "$branch"; then
    echo "📡 Branch not found locally, checking out from origin..."
    git checkout -t "origin/$branch" || return 1
  else
    git checkout -b "$branch" || return 1
  fi
}
alias gt='gstart' # gstart [branch] | Alias for gstart
alias gcreate='gstart' # gstart [branch] | Alias for gstart

gmerge() { # gmerge [*branch] | Merge branch into current branch if no conflicts
  local branch_input="$1"
  local current_branch=$(git rev-parse --abbrev-ref HEAD)
  local branch

  if [[ -z "$branch_input" ]]; then
    local -a branches=()
    while IFS= read -r b; do
      branches+=("$b")
    done < <(_gjs_get_recent_branches)

    if [[ ${#branches[@]} -eq 0 ]]; then
      echo "No recent branches found."
      return 1
    fi

    echo "Merge into $current_branch from (↑/↓ select, Enter confirm, q cancel):"
    local picked
    if ! picked=$(_gjs_interactive_menu "${branches[@]}"); then
      echo "Cancelled."
      return 1
    fi
    branch_input="$picked"
  fi

  if ! branch=$(_gjs_resolve_branch_input "$branch_input" "any"); then
    return 1
  fi
  
  echo "🔍 Checking for potential conflicts with $branch..."
  if [ -n "$(git status --porcelain)" ]; then
    echo "❌ Current branch has uncommitted changes. Commit or stash changes first."
    return 1
  fi
  
  echo "🔄 Switching to $branch to pull latest changes..."
  if _gjs_branch_exists_local "$branch"; then
    if ! git checkout "$branch"; then
      echo "❌ Failed to switch to $branch"
      return 1
    fi
  else
    if _gjs_branch_exists_remote "$branch"; then
      echo "📡 Branch not found locally, checking out from origin..."
      if ! git fetch origin "$branch"; then
        echo "❌ Failed to fetch $branch from origin"
        return 1
      fi
      if ! git checkout -t "origin/$branch"; then
        echo "❌ Failed to checkout $branch from origin"
        return 1
      fi
    else
      echo "❌ Branch '$branch' not found locally or on origin."
      return 1
    fi
  fi
  
  echo "⬇️  Pulling latest changes for $branch..."
  if ! git pull; then
    echo "❌ Failed to pull changes for $branch"
    git checkout "$current_branch"
    return 1
  fi
  
  echo "🔄 Switching back to $current_branch..."
  if ! git checkout "$current_branch"; then
    echo "❌ Failed to switch back to $current_branch"
    return 1
  fi
  
  if git merge-tree $(git merge-base HEAD "$branch") HEAD "$branch" 2>/dev/null | grep -q "<<<<<<<"; then
    echo "❌ Merge would create conflicts. Aborting merge."
    return 1
  fi
  
  echo "✅ No conflicts detected. Merging $branch into $current_branch..."
  git merge "$branch" --no-edit
}
alias gm='gmerge' # gmerge [*branch] | Alias for gmerge

gpush() { # gpush [*branch] | Push branch and create upstream tracking
  local current_branch=$(git rev-parse --abbrev-ref HEAD)
  local branch_input="$1"
  local branch

  if [ -z "$branch_input" ]; then
    branch=$current_branch
  else
    if ! branch=$(_gjs_resolve_branch_input "$branch_input" "local"); then
      return 1
    fi
  fi
  
  echo "🚀 Pushing branch '$branch' to origin with upstream tracking..."
  git push -u origin "$branch"
}
alias gpu='gpush' # gpush [*branch] | Alias for gpush

gdelete() { # gdelete [*branch] | Delete feature branch if clean and pushed
  local current_branch=$(git rev-parse --abbrev-ref HEAD)
  local branch_input="$1"
  local branch

  if [[ -z "$branch_input" ]]; then
    local -a branches=()
    while IFS= read -r b; do
      branches+=("$b")
    done < <(_gjs_get_recent_branches)

    if [[ ${#branches[@]} -eq 0 ]]; then
      echo "No recent branches found."
      return 1
    fi

    echo "Delete branch (↑/↓ select, Enter confirm, q cancel):"
    local picked
    if ! picked=$(_gjs_interactive_menu "${branches[@]}"); then
      echo "Cancelled."
      return 1
    fi
    branch_input="$picked"
  fi

  if ! branch=$(_gjs_resolve_branch_input "$branch_input" "local"); then
    return 1
  fi
  
  if [ "$branch" = "master" ] || [ "$branch" = "develop" ]; then
    echo "❌ Cannot delete master or develop branches."
    return 1
  fi
  
  echo "🔍 Checking if branch '$branch' is safe to delete..."
  
  if [ "$branch" = "$current_branch" ] && [ -n "$(git status --porcelain)" ]; then
    echo "❌ Branch has uncommitted changes. Commit or stash changes first."
    return 1
  fi
  
  if ! git show-ref --verify --quiet refs/heads/"$branch"; then
    echo "❌ Branch '$branch' does not exist locally."
    return 1
  fi
  
  if git log origin/"$branch".."$branch" --oneline 2>/dev/null | grep -q .; then
    echo "❌ Branch has unpushed commits. Push changes first."
    return 1
  fi
  
  if ! git ls-remote --quiet origin "$branch" 2>/dev/null; then
    echo "❌ Branch '$branch' does not exist on origin. Push branch first."
    return 1
  fi
  
  echo "✅ Branch is safe to delete."
  
  if [ "$current_branch" != "master" ]; then
    echo "🔄 Switching to master branch..."
    if ! git checkout master; then
      echo "❌ Failed to switch to master branch. Aborting deletion."
      return 1
    fi
  fi
  
  echo "🗑️  Deleting local branch '$branch'..."
  git branch -d "$branch"
}
alias gdel='gdelete' # gdelete [*branch] | Alias for gdelete

testJira() { # testJira | Test Jira API connection
  echo "🧪 Testing Jira API connection..."
  
  if [[ -z "$GJS_JIRA_API_TOKEN" || -z "$GJS_JIRA_DOMAIN" || -z "$GJS_TICKET_PREFIX" ]]; then
    echo "❌ Jira not configured. Run: git-jira-shortcuts init"
    return 1
  fi
  
  echo "📡 Testing API call to $GJS_JIRA_DOMAIN..."
  local response
  response=$(curl -sS \
    -H "Authorization: Basic $GJS_JIRA_API_TOKEN" \
    -H "Accept: application/json" \
    "https://$GJS_JIRA_DOMAIN/rest/api/3/myself" 2>/dev/null)
  
  if [[ $? -ne 0 ]]; then
    echo "❌ Jira API call failed. Token might be expired or malformed."
    echo "   Run: git-jira-shortcuts init"
    return 1
  fi
  
  local display_name
  display_name=$(echo "$response" | jq -r '.displayName // empty')
  
  if [[ -z "$display_name" ]]; then
    echo "❌ Jira API test failed."
    echo "$response"
    return 1
  fi
  
  echo "✅ Jira API is working! Authenticated as: $display_name"
  return 0
}
alias tj='testJira' # testJira | Test Jira API connection
