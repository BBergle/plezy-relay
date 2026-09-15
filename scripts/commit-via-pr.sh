#!/usr/bin/env bash
# Land an automated change on the default branch through a pull request.
#
# main is protected by a ruleset that requires one, and GitHub Actions cannot be
# named as a bypass actor on a user-owned repo, so the bot takes the same route
# a human does: branch, open a PR, merge it.
#
# Usage: commit-via-pr.sh <branch> <commit message> <file>...
set -euo pipefail

branch="${1:?branch name required}"; shift
message="${1:?commit message required}"; shift
(($# > 0)) || { echo "::error::no files given"; exit 1; }

# Not `git diff`: a heartbeat file is untracked on its first run and a plain
# diff would report the tree as clean.
if [[ -z "$(git status --porcelain -- "$@")" ]]; then
  echo "nothing to commit"; exit 0
fi

git config user.name  'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git switch -c "$branch"
git add -- "$@"
git commit -m "$message"
# --force: a re-run for the same release reuses the branch name.
git push --force -u origin "$branch"

url=$(gh pr list --head "$branch" --state open --json url --jq '.[0].url // empty')
if [[ -z "$url" ]]; then
  url=$(gh pr create --base "${BASE_BRANCH:-main}" --head "$branch" \
    --title "$message" \
    --body 'Opened by the release automation, which cannot push to main directly.')
fi
echo "pull request: ${url}"

# GitHub computes mergeability asynchronously, so a merge attempted immediately
# after opening the PR can 405. Retry briefly rather than failing the run.
for attempt in 1 2 3 4 5 6; do
  if gh pr merge "$url" --squash --delete-branch; then
    echo "merged ${url}"
    exit 0
  fi
  echo "not mergeable yet (attempt ${attempt}); retrying"
  sleep 10
done
echo "::error::could not merge ${url}"
exit 1
