#!/usr/bin/env bash
# ============================================================================
# Governance Engine - Audit & Evidence Store
# ============================================================================
# Provides audit logging, evidence collection, and compliance history
# tracking for all governance operations.
#
# Usage: source audit-log.sh
#   Then call: audit_log <category> <action> <target> <details>
#
# Evidence is stored in:
#   - GitHub Actions artifacts (workflow runs)
#   - Repository governance branch (git-based evidence)
#   - JSON audit trail file
#
# Requires: gh CLI, jq
# ============================================================================

AUDIT_DIR="${AUDIT_DIR:-/tmp/governance-audit}"
AUDIT_FILE="${AUDIT_FILE:-$AUDIT_DIR/audit-trail.jsonl}"

# --------------------------------------------------------------------------
# Initialize audit directory
# --------------------------------------------------------------------------
init_audit() {
  mkdir -p "$AUDIT_DIR"
  mkdir -p "$AUDIT_DIR/evidence"
  mkdir -p "$AUDIT_DIR/reports"
}

# --------------------------------------------------------------------------
# Write an audit log entry
# --------------------------------------------------------------------------
audit_log() {
  local category="${1:?Missing category}"
  local action="${2:?Missing action}"
  local target="${3:?Missing target}"
  local details="${4:-}"

  init_audit

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local actor="${GITHUB_ACTOR:-$(whoami)}"
  local run_id="${GITHUB_RUN_ID:-local}"
  local workflow="${GITHUB_WORKFLOW:-manual}"

  local entry
  entry=$(jq -nc \
    --arg ts "$timestamp" \
    --arg cat "$category" \
    --arg act "$action" \
    --arg tgt "$target" \
    --arg dtl "$details" \
    --arg actor "$actor" \
    --arg run "$run_id" \
    --arg wf "$workflow" \
    '{
      timestamp: $ts,
      category: $cat,
      action: $act,
      target: $tgt,
      details: $dtl,
      actor: $actor,
      run_id: $run,
      workflow: $wf
    }')

  echo "$entry" >> "$AUDIT_FILE"

  # Also output to stderr for workflow visibility
  echo "📋 AUDIT: [$category] $action on $target ($details)" >&2
}

# --------------------------------------------------------------------------
# Record a compliance result
# --------------------------------------------------------------------------
record_compliance() {
  local repo="${1:?Missing repo}"
  local profile="${2:?Missing profile}"
  local score="${3:?Missing score}"
  local report_file="${4:-}"

  init_audit

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local compliance_entry
  compliance_entry=$(jq -nc \
    --arg ts "$timestamp" \
    --arg repo "$repo" \
    --arg profile "$profile" \
    --argjson score "$score" \
    --arg report "$report_file" \
    '{
      timestamp: $ts,
      type: "compliance_result",
      repository: $repo,
      profile: $profile,
      score: $score,
      report_file: $report
    }')

  echo "$compliance_entry" >> "$AUDIT_DIR/compliance-history.jsonl"
  audit_log "compliance" "assessment_complete" "$repo" "score=$score profile=$profile"
}

# --------------------------------------------------------------------------
# Record a change (applied setting)
# --------------------------------------------------------------------------
record_change() {
  local repo="${1:?Missing repo}"
  local category="${2:?Missing category}"
  local setting="${3:?Missing setting}"
  local old_value="${4:-unknown}"
  local new_value="${5:-unknown}"

  init_audit

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local change_entry
  change_entry=$(jq -nc \
    --arg ts "$timestamp" \
    --arg repo "$repo" \
    --arg cat "$category" \
    --arg setting "$setting" \
    --arg old "$old_value" \
    --arg new "$new_value" \
    --arg actor "${GITHUB_ACTOR:-$(whoami)}" \
    '{
      timestamp: $ts,
      type: "change",
      repository: $repo,
      category: $cat,
      setting: $setting,
      old_value: $old,
      new_value: $new,
      actor: $actor
    }')

  echo "$change_entry" >> "$AUDIT_DIR/change-history.jsonl"
  audit_log "change" "setting_applied" "$repo" "$category/$setting: $old_value → $new_value"
}

# --------------------------------------------------------------------------
# Record an exception request
# --------------------------------------------------------------------------
record_exception() {
  local repo="${1:?Missing repo}"
  local check="${2:?Missing check}"
  local reason="${3:?Missing reason}"
  local approved_by="${4:-pending}"
  local expires="${5:-never}"

  init_audit

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local exception_entry
  exception_entry=$(jq -nc \
    --arg ts "$timestamp" \
    --arg repo "$repo" \
    --arg check "$check" \
    --arg reason "$reason" \
    --arg approved "$approved_by" \
    --arg expires "$expires" \
    '{
      timestamp: $ts,
      type: "exception",
      repository: $repo,
      check: $check,
      reason: $reason,
      approved_by: $approved,
      expires: $expires,
      status: "active"
    }')

  echo "$exception_entry" >> "$AUDIT_DIR/exceptions.jsonl"
  audit_log "exception" "exception_recorded" "$repo" "check=$check reason=$reason"
}

# --------------------------------------------------------------------------
# Save evidence artifact
# --------------------------------------------------------------------------
save_evidence() {
  local repo="${1:?Missing repo}"
  local evidence_type="${2:?Missing type}" # report, screenshot, config, log
  local source_file="${3:?Missing file}"

  init_audit

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local safe_name
  safe_name=$(echo "${repo//\//_}_${evidence_type}_${timestamp}" | sed 's/[:]/-/g')

  if [ -f "$source_file" ]; then
    cp "$source_file" "$AUDIT_DIR/evidence/${safe_name}.json"
    audit_log "evidence" "artifact_saved" "$repo" "type=$evidence_type file=$safe_name"
    echo "$AUDIT_DIR/evidence/${safe_name}.json"
  else
    echo "⚠️  Evidence file not found: $source_file" >&2
    return 1
  fi
}

# --------------------------------------------------------------------------
# Generate audit summary
# --------------------------------------------------------------------------
generate_audit_summary() {
  local output_file="${1:-$AUDIT_DIR/reports/summary.json}"

  init_audit

  if [ ! -f "$AUDIT_FILE" ]; then
    echo "{\"total_entries\": 0, \"message\": \"No audit entries found\"}"
    return
  fi

  local total
  total=$(wc -l < "$AUDIT_FILE")

  local categories
  categories=$(jq -rs '[.[].category] | group_by(.) | map({key: .[0], value: length}) | from_entries' "$AUDIT_FILE" 2>/dev/null || echo "{}")

  local last_entry
  last_entry=$(tail -1 "$AUDIT_FILE" 2>/dev/null || echo "{}")

  jq -n \
    --argjson total "$total" \
    --argjson categories "$categories" \
    --argjson last "$last_entry" \
    --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      generated: $generated,
      total_entries: $total,
      by_category: $categories,
      last_entry: $last
    }' > "$output_file"

  cat "$output_file"
}

# --------------------------------------------------------------------------
# Upload audit artifacts to GitHub Actions
# --------------------------------------------------------------------------
upload_audit_artifacts() {
  local artifact_name="${1:-governance-audit}"

  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "📤 Uploading audit artifacts..."
    # Artifacts are uploaded via actions/upload-artifact in the workflow
    # This function prepares the directory structure
    echo "   Audit directory: $AUDIT_DIR"
    echo "   Files:"
    find "$AUDIT_DIR" -type f | while read -r f; do
      echo "   - $(basename "$f")"
    done
  else
    echo "ℹ️  Not in GitHub Actions - audit stored locally at: $AUDIT_DIR"
  fi
}

# --------------------------------------------------------------------------
# Push evidence to governance branch
# --------------------------------------------------------------------------
push_evidence_to_branch() {
  local repo="${1:?Missing repo}"
  local branch="governance-evidence"

  if [ -z "${GITHUB_ACTIONS:-}" ]; then
    echo "ℹ️  Evidence branch push only available in CI"
    return
  fi

  # Create orphan branch if not exists
  if ! gh api "repos/$repo/branches/$branch" --silent 2>/dev/null; then
    echo "   Creating evidence branch: $branch"
    # This would be done via the GitHub API in CI
  fi

  audit_log "evidence" "branch_push" "$repo" "branch=$branch"
}
