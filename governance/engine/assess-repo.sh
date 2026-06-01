#!/usr/bin/env bash
# ============================================================================
# Governance Engine - Repository Assessor
# ============================================================================
# Assesses an existing repository against a governance profile and produces
# a compliance report with a score and remediation recommendations.
#
# Usage: ./assess-repo.sh <profile> <org/repo>
#
# Output: JSON compliance report to stdout (or file if REPORT_FILE is set)
# Requires: gh CLI authenticated, yq installed
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/../profiles"

# --------------------------------------------------------------------------
# Arguments
# --------------------------------------------------------------------------
PROFILE_NAME="${1:?Usage: assess-repo.sh <profile> <org/repo>}"
REPO="${2:?Missing: org/repo}"
REPORT_FILE="${REPORT_FILE:-}"

PROFILE_FILE="$PROFILE_DIR/${PROFILE_NAME}.yml"

# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------
if [ ! -f "$PROFILE_FILE" ]; then
  echo "❌ Profile not found: $PROFILE_FILE" >&2
  exit 1
fi

command -v gh >/dev/null 2>&1 || { echo "❌ gh CLI not found" >&2; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "❌ yq not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ jq not found" >&2; exit 1; }

echo "============================================" >&2
echo "🔍 Governance Engine - Assess Repository" >&2
echo "============================================" >&2
echo "Profile: $PROFILE_NAME" >&2
echo "Repo:    $REPO" >&2
echo "============================================" >&2
echo "" >&2

# --------------------------------------------------------------------------
# Initialize Report
# --------------------------------------------------------------------------
TOTAL_CHECKS=0
PASSED_CHECKS=0
FINDINGS="[]"

add_finding() {
  local category="$1"
  local check="$2"
  local status="$3"  # pass, fail, warn
  local message="$4"
  local remediation="${5:-}"

  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  if [ "$status" = "pass" ]; then
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
  fi

  FINDINGS=$(echo "$FINDINGS" | jq \
    --arg cat "$category" \
    --arg chk "$check" \
    --arg sts "$status" \
    --arg msg "$message" \
    --arg rem "$remediation" \
    '. += [{"category": $cat, "check": $chk, "status": $sts, "message": $msg, "remediation": $rem}]')
}

# --------------------------------------------------------------------------
# Check 1: Repository Settings
# --------------------------------------------------------------------------
echo "📋 Checking repository settings..." >&2

REPO_DATA=$(gh api "repos/$REPO" 2>/dev/null)

# Visibility
EXPECTED_VIS=$(yq '.repository.visibility' "$PROFILE_FILE")
ACTUAL_VIS=$(echo "$REPO_DATA" | jq -r '.visibility // "unknown"')
if [ "$ACTUAL_VIS" = "$EXPECTED_VIS" ]; then
  add_finding "repository" "visibility" "pass" "Visibility is $ACTUAL_VIS"
else
  add_finding "repository" "visibility" "fail" "Expected $EXPECTED_VIS, got $ACTUAL_VIS" "Change visibility to $EXPECTED_VIS"
fi

# Delete branch on merge
EXPECTED_DEL=$(yq '.repository.delete_branch_on_merge' "$PROFILE_FILE")
ACTUAL_DEL=$(echo "$REPO_DATA" | jq -r '.delete_branch_on_merge // false')
if [ "$ACTUAL_DEL" = "$EXPECTED_DEL" ]; then
  add_finding "repository" "delete_branch_on_merge" "pass" "Delete branch on merge: $ACTUAL_DEL"
else
  add_finding "repository" "delete_branch_on_merge" "fail" "Expected $EXPECTED_DEL, got $ACTUAL_DEL" "Enable delete branch on merge"
fi

# Squash merge
EXPECTED_SQUASH=$(yq '.repository.allow_squash_merge' "$PROFILE_FILE")
ACTUAL_SQUASH=$(echo "$REPO_DATA" | jq -r '.allow_squash_merge // false')
if [ "$ACTUAL_SQUASH" = "$EXPECTED_SQUASH" ]; then
  add_finding "repository" "allow_squash_merge" "pass" "Squash merge: $ACTUAL_SQUASH"
else
  add_finding "repository" "allow_squash_merge" "fail" "Expected $EXPECTED_SQUASH, got $ACTUAL_SQUASH" "Set allow_squash_merge to $EXPECTED_SQUASH"
fi

# Merge commit
EXPECTED_MERGE=$(yq '.repository.allow_merge_commit' "$PROFILE_FILE")
ACTUAL_MERGE=$(echo "$REPO_DATA" | jq -r '.allow_merge_commit // true')
if [ "$ACTUAL_MERGE" = "$EXPECTED_MERGE" ]; then
  add_finding "repository" "allow_merge_commit" "pass" "Merge commit: $ACTUAL_MERGE"
else
  add_finding "repository" "allow_merge_commit" "fail" "Expected $EXPECTED_MERGE, got $ACTUAL_MERGE" "Set allow_merge_commit to $EXPECTED_MERGE"
fi

echo "   ✅ Repository settings checked" >&2

# --------------------------------------------------------------------------
# Check 2: Branch Protection / Rulesets
# --------------------------------------------------------------------------
echo "🛡️  Checking rulesets..." >&2

RULESETS=$(gh api "repos/$REPO/rulesets" 2>/dev/null || echo "[]")
RULESET_COUNT=$(echo "$RULESETS" | jq 'length')

EXPECTED_RULESETS=$(yq '.rulesets | length' "$PROFILE_FILE")
if [ "$RULESET_COUNT" -ge "$EXPECTED_RULESETS" ]; then
  add_finding "rulesets" "count" "pass" "$RULESET_COUNT ruleset(s) found (expected $EXPECTED_RULESETS)"
else
  add_finding "rulesets" "count" "fail" "Found $RULESET_COUNT ruleset(s), expected $EXPECTED_RULESETS" "Create missing rulesets"
fi

# Check if main branch has active ruleset
MAIN_RULESET=$(echo "$RULESETS" | jq '[.[] | select(.enforcement == "active")] | length')
if [ "$MAIN_RULESET" -gt 0 ]; then
  add_finding "rulesets" "active_enforcement" "pass" "Active ruleset found for main branch"
else
  add_finding "rulesets" "active_enforcement" "fail" "No active ruleset found" "Create an active ruleset for main branch"
fi

echo "   ✅ Rulesets checked" >&2

# --------------------------------------------------------------------------
# Check 3: Required Files
# --------------------------------------------------------------------------
echo "📄 Checking required files..." >&2

FILE_COUNT=$(yq '.required_files | length' "$PROFILE_FILE")
for i in $(seq 0 $((FILE_COUNT - 1))); do
  FILE_PATH=$(yq ".required_files[$i].path" "$PROFILE_FILE")

  # Check if file exists in repo
  if gh api "repos/$REPO/contents/$FILE_PATH" --silent 2>/dev/null; then
    add_finding "required_files" "$FILE_PATH" "pass" "File exists: $FILE_PATH"
  else
    add_finding "required_files" "$FILE_PATH" "fail" "Missing required file: $FILE_PATH" "Create $FILE_PATH from template"
  fi
done

echo "   ✅ Required files checked" >&2

# --------------------------------------------------------------------------
# Check 4: Workflows
# --------------------------------------------------------------------------
echo "⚡ Checking workflows..." >&2

WORKFLOW_COUNT=$(yq '.workflows | length' "$PROFILE_FILE")
for i in $(seq 0 $((WORKFLOW_COUNT - 1))); do
  WF_NAME=$(yq ".workflows[$i].name" "$PROFILE_FILE")
  WF_REQUIRED=$(yq ".workflows[$i].required" "$PROFILE_FILE")

  if gh api "repos/$REPO/contents/.github/workflows/$WF_NAME" --silent 2>/dev/null; then
    add_finding "workflows" "$WF_NAME" "pass" "Workflow exists: $WF_NAME"
  elif [ "$WF_REQUIRED" = "true" ]; then
    add_finding "workflows" "$WF_NAME" "fail" "Missing required workflow: $WF_NAME" "Add $WF_NAME from template"
  else
    add_finding "workflows" "$WF_NAME" "warn" "Optional workflow missing: $WF_NAME"
  fi
done

echo "   ✅ Workflows checked" >&2

# --------------------------------------------------------------------------
# Check 5: Environments
# --------------------------------------------------------------------------
echo "🌍 Checking environments..." >&2

ENVIRONMENTS=$(gh api "repos/$REPO/environments" 2>/dev/null | jq '.environments // []')
EXISTING_ENVS=$(echo "$ENVIRONMENTS" | jq -r '.[].name' 2>/dev/null || echo "")

ENV_COUNT=$(yq '.environments | length' "$PROFILE_FILE")
for i in $(seq 0 $((ENV_COUNT - 1))); do
  ENV_NAME=$(yq ".environments[$i].name" "$PROFILE_FILE")

  if echo "$EXISTING_ENVS" | grep -q "^${ENV_NAME}$"; then
    add_finding "environments" "$ENV_NAME" "pass" "Environment exists: $ENV_NAME"
  else
    add_finding "environments" "$ENV_NAME" "fail" "Missing environment: $ENV_NAME" "Create environment: $ENV_NAME"
  fi
done

echo "   ✅ Environments checked" >&2

# --------------------------------------------------------------------------
# Check 6: Security Features
# --------------------------------------------------------------------------
echo "🔒 Checking security features..." >&2

# Secret scanning
EXPECTED_SECRET=$(yq '.security.secret_scanning.enabled' "$PROFILE_FILE")
if [ "$EXPECTED_SECRET" = "true" ]; then
  SECRET_STATUS=$(echo "$REPO_DATA" | jq -r '.security_and_analysis.secret_scanning.status // "disabled"')
  if [ "$SECRET_STATUS" = "enabled" ]; then
    add_finding "security" "secret_scanning" "pass" "Secret scanning enabled"
  else
    add_finding "security" "secret_scanning" "fail" "Secret scanning not enabled" "Enable secret scanning"
  fi
fi

# Push protection
EXPECTED_PUSH=$(yq '.security.secret_scanning.push_protection' "$PROFILE_FILE")
if [ "$EXPECTED_PUSH" = "true" ]; then
  PUSH_STATUS=$(echo "$REPO_DATA" | jq -r '.security_and_analysis.secret_scanning_push_protection.status // "disabled"')
  if [ "$PUSH_STATUS" = "enabled" ]; then
    add_finding "security" "push_protection" "pass" "Push protection enabled"
  else
    add_finding "security" "push_protection" "fail" "Push protection not enabled" "Enable push protection"
  fi
fi

# Dependabot
EXPECTED_DEPENDABOT=$(yq '.security.dependabot.alerts' "$PROFILE_FILE")
if [ "$EXPECTED_DEPENDABOT" = "true" ]; then
  DEPENDABOT_STATUS=$(gh api "repos/$REPO/vulnerability-alerts" 2>/dev/null && echo "enabled" || echo "disabled")
  if [ "$DEPENDABOT_STATUS" = "enabled" ]; then
    add_finding "security" "dependabot_alerts" "pass" "Dependabot alerts enabled"
  else
    add_finding "security" "dependabot_alerts" "fail" "Dependabot alerts not enabled" "Enable Dependabot alerts"
  fi
fi

echo "   ✅ Security features checked" >&2

# --------------------------------------------------------------------------
# Check 7: Labels
# --------------------------------------------------------------------------
echo "🏷️  Checking labels..." >&2

REPO_LABELS=$(gh api "repos/$REPO/labels" --paginate 2>/dev/null | jq -r '.[].name' || echo "")
LABEL_COUNT=$(yq '.labels | length' "$PROFILE_FILE")
MISSING_LABELS=0

for i in $(seq 0 $((LABEL_COUNT - 1))); do
  LABEL_NAME=$(yq ".labels[$i].name" "$PROFILE_FILE")
  if echo "$REPO_LABELS" | grep -q "^${LABEL_NAME}$"; then
    : # pass silently
  else
    MISSING_LABELS=$((MISSING_LABELS + 1))
  fi
done

if [ "$MISSING_LABELS" -eq 0 ]; then
  add_finding "labels" "completeness" "pass" "All $LABEL_COUNT required labels present"
else
  add_finding "labels" "completeness" "warn" "$MISSING_LABELS of $LABEL_COUNT labels missing" "Sync labels from profile"
fi

echo "   ✅ Labels checked" >&2

# --------------------------------------------------------------------------
# Generate Report
# --------------------------------------------------------------------------
echo "" >&2
echo "📊 Generating compliance report..." >&2

if [ "$TOTAL_CHECKS" -gt 0 ]; then
  SCORE=$(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))
else
  SCORE=0
fi

FAILED_CHECKS=$((TOTAL_CHECKS - PASSED_CHECKS))
FAIL_COUNT=$(echo "$FINDINGS" | jq '[.[] | select(.status == "fail")] | length')
WARN_COUNT=$(echo "$FINDINGS" | jq '[.[] | select(.status == "warn")] | length')

REPORT=$(jq -n \
  --arg repo "$REPO" \
  --arg profile "$PROFILE_NAME" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson score "$SCORE" \
  --argjson total "$TOTAL_CHECKS" \
  --argjson passed "$PASSED_CHECKS" \
  --argjson failed "$FAIL_COUNT" \
  --argjson warnings "$WARN_COUNT" \
  --argjson findings "$FINDINGS" \
  '{
    "report": {
      "repository": $repo,
      "profile": $profile,
      "timestamp": $timestamp,
      "score": $score,
      "summary": {
        "total_checks": $total,
        "passed": $passed,
        "failed": $failed,
        "warnings": $warnings
      },
      "findings": $findings
    }
  }')

# Output report
if [ -n "$REPORT_FILE" ]; then
  echo "$REPORT" > "$REPORT_FILE"
  echo "📄 Report saved to: $REPORT_FILE" >&2
else
  echo "$REPORT"
fi

# Print summary to stderr
echo "" >&2
echo "============================================" >&2
echo "📊 Compliance Score: ${SCORE}%" >&2
echo "============================================" >&2
echo "Total checks: $TOTAL_CHECKS" >&2
echo "  ✅ Passed:   $PASSED_CHECKS" >&2
echo "  ❌ Failed:   $FAIL_COUNT" >&2
echo "  ⚠️  Warnings: $WARN_COUNT" >&2
echo "============================================" >&2

# Exit with non-zero if score below threshold
THRESHOLD="${COMPLIANCE_THRESHOLD:-80}"
if [ "$SCORE" -lt "$THRESHOLD" ]; then
  echo "⚠️  Score below threshold ($THRESHOLD%). Remediation recommended." >&2
  exit 1
fi
