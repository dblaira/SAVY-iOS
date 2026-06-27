#!/usr/bin/env bash
# Weekday suite status — for Cursor Automation or manual runs.
# Checks savy-gateway health + open PRs on the four iOS suite repos.
set -u

GATEWAY_HEALTH_URL="${GATEWAY_HEALTH_URL:-https://savy-gateway.vercel.app/api/v1/health}"
REPOS=(
  "dblaira/SAVY-iOS"
  "dblaira/Re_Call"
  "dblaira/Understood"
  "dblaira/Boring_News"
)

failures=0

section() {
  printf '\n== %s ==\n' "$1"
}

pass() {
  printf 'OK: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1"
  failures=$((failures + 1))
}

section "Gateway"
health="$(curl -fsS "$GATEWAY_HEALTH_URL" 2>/dev/null)" || {
  fail "Could not reach $GATEWAY_HEALTH_URL"
  health=""
}

if [ -n "$health" ]; then
  ok="$(printf '%s' "$health" | sed -n 's/.*"ok"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p' | tr -d ' ')"
  phase="$(printf '%s' "$health" | sed -n 's/.*"phase"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  if [ "$ok" = "true" ]; then
    pass "savy-gateway phase=$phase"
  else
    fail "savy-gateway not ok: $health"
  fi
  printf '%s\n' "$health"
fi

section "Open PRs"
if ! command -v gh >/dev/null 2>&1; then
  fail "gh not installed"
else
  for repo in "${REPOS[@]}"; do
    count="$(gh pr list --repo "$repo" --state open --json number --jq 'length' 2>/dev/null || echo err)"
    if [ "$count" = "err" ]; then
      fail "$repo — could not list PRs"
    elif [ "$count" = "0" ]; then
      pass "$repo — no open PRs"
    else
      printf 'OPEN: %s — %s PR(s)\n' "$repo" "$count"
      gh pr list --repo "$repo" --state open --limit 5 \
        --json number,title,url \
        --jq '.[] | "  #\(.number) \(.title) \(.url)"' 2>/dev/null || true
    fi
  done
fi

section "Summary"
if [ "$failures" -eq 0 ]; then
  pass "Suite weekday status clean"
  exit 0
fi

fail "$failures check(s) need attention"
exit 1
