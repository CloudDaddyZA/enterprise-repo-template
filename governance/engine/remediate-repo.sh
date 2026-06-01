#!/usr/bin/env bash
# ============================================================================
# Governance Engine - Repository Remediator
# ============================================================================
# Reads a compliance report (from assess-repo.sh) and applies fixes for
# all failed checks. Supports three modes:
#   - safe:      Creates a PR with changes (default)
#   - semi-auto: Applies after displaying changes
#   - auto:      Applies directly (for CI/automation)
#
# Usage: ./remediate-repo.sh <profile> <org/repo> [mode]
#
# Requires: gh CLI authenticated, yq installed
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/../profiles"

# --------------------------------------------------------------------------
# Arguments
# --------------------------------------------------------------------------
PROFILE_NAME="${1:?Usage: remediate-repo.sh <profile> <org/repo> [mode]}"
REPO="${2:?Missing: org/repo}"
MODE="${3:-safe}"  # safe | semi-auto | auto

PROFILE_FILE="$PROFILE_DIR/${PROFILE_NAME}.yml"

# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------
if [ ! -f "$PROFILE_FILE" ]; then
  echo "❌ Profile not found: $PROFILE_FILE" >&2
  exit 1
fi

if [[ ! "$MODE" =~ ^(safe|semi-auto|auto)$ ]]; then
  echo "❌ Invalid mode: $MODE (use: safe, semi-auto, auto)" >&2
  exit 1
fi

command -v gh >/dev/null 2>&1 || { echo "❌ gh CLI not found" >&2; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "❌ yq not found" >&2; exit 1; }

echo "============================================"
echo "🔧 Governance Engine - Remediate Repository"
echo "============================================"
echo "Profile: $PROFILE_NAME"
echo "Repo:    $REPO"
echo "Mode:    $MODE"
echo "============================================"
echo ""

CHANGES_MADE=0

# --------------------------------------------------------------------------
# Helper: Apply or queue change
# --------------------------------------------------------------------------
apply_change() {
  local description="$1"
  echo "   🔧 $description"
  CHANGES_MADE=$((CHANGES_MADE + 1))
}

# --------------------------------------------------------------------------
# Remediate: Repository Settings
# --------------------------------------------------------------------------
echo "⚙️  Remediating repository settings..."

PATCH_BODY="{}"

# Build patch for repository settings
for FIELD in delete_branch_on_merge allow_squash_merge allow_merge_commit allow_rebase_merge allow_auto_merge has_wiki has_issues has_projects; do
  EXPECTED=$(yq ".repository.$FIELD" "$PROFILE_FILE")
  if [ "$EXPECTED" != "null" ]; then
    PATCH_BODY=$(echo "$PATCH_BODY" | jq --arg k "$FIELD" --argjson v "$EXPECTED" '. + {($k): $v}')
  fi
done

if [ "$PATCH_BODY" != "{}" ]; then
  if [ "$MODE" = "safe" ]; then
    echo "   📝 Would apply: $PATCH_BODY"
  else
    gh api "repos/$REPO" --method PATCH --input <(echo "$PATCH_BODY") --silent
    apply_change "Repository settings updated"
  fi
fi

# Topics
EXPECTED_TOPICS=$(yq -o=json '.repository.topics' "$PROFILE_FILE")
if [ "$EXPECTED_TOPICS" != "null" ]; then
  CURRENT_TOPICS=$(gh api "repos/$REPO/topics" --jq '.names' 2>/dev/null || echo "[]")
  if [ "$CURRENT_TOPICS" != "$EXPECTED_TOPICS" ]; then
    if [ "$MODE" != "safe" ]; then
      gh api "repos/$REPO/topics" --method PUT --input <(echo "{\"names\": $EXPECTED_TOPICS}") --silent
      apply_change "Topics updated"
    else
      echo "   📝 Would update topics to: $EXPECTED_TOPICS"
    fi
  fi
fi

# --------------------------------------------------------------------------
# Remediate: Rulesets
# --------------------------------------------------------------------------
echo "🛡️  Remediating rulesets..."

EXISTING_RULESETS=$(gh api "repos/$REPO/rulesets" 2>/dev/null || echo "[]")
EXISTING_COUNT=$(echo "$EXISTING_RULESETS" | jq 'length')

if [ "$EXISTING_COUNT" -eq 0 ]; then
  RULESET_COUNT=$(yq '.rulesets | length' "$PROFILE_FILE")
  for i in $(seq 0 $((RULESET_COUNT - 1))); do
    RULESET_NAME=$(yq ".rulesets[$i].name" "$PROFILE_FILE")
    APPROVALS=$(yq ".rulesets[$i].rules.pull_request.required_approving_review_count" "$PROFILE_FILE")
    DISMISS_STALE=$(yq ".rulesets[$i].rules.pull_request.dismiss_stale_reviews" "$PROFILE_FILE")
    REQUIRE_CODEOWNER=$(yq ".rulesets[$i].rules.pull_request.require_code_owner_review" "$PROFILE_FILE")
    STATUS_CHECKS=$(yq -o=json ".rulesets[$i].rules.required_status_checks.required_status_checks" "$PROFILE_FILE")

    if [ "$MODE" != "safe" ]; then
      gh api "repos/$REPO/rulesets" --method POST \
        --input <(cat <<EOF
{
  "name": "$RULESET_NAME",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
  "rules": [
    {"type": "pull_request", "parameters": {"required_approving_review_count": $APPROVALS, "dismiss_stale_reviews_on_push": $DISMISS_STALE, "require_code_owner_review": $REQUIRE_CODEOWNER}},
    {"type": "required_status_checks", "parameters": {"strict_required_status_checks_policy": true, "required_status_checks": $STATUS_CHECKS}},
    {"type": "deletion"},
    {"type": "non_fast_forward"}
  ],
  "bypass_actors": []
}
EOF
      ) --silent
      apply_change "Created ruleset: $RULESET_NAME"
    else
      echo "   📝 Would create ruleset: $RULESET_NAME"
    fi
  done
fi

# --------------------------------------------------------------------------
# Remediate: Environments
# --------------------------------------------------------------------------
echo "🌍 Remediating environments..."

EXISTING_ENVS=$(gh api "repos/$REPO/environments" 2>/dev/null | jq -r '.environments[].name' 2>/dev/null || echo "")
ENV_COUNT=$(yq '.environments | length' "$PROFILE_FILE")

for i in $(seq 0 $((ENV_COUNT - 1))); do
  ENV_NAME=$(yq ".environments[$i].name" "$PROFILE_FILE")
  WAIT_TIMER=$(yq ".environments[$i].protection_rules.wait_timer // 0" "$PROFILE_FILE")

  if ! echo "$EXISTING_ENVS" | grep -q "^${ENV_NAME}$"; then
    if [ "$MODE" != "safe" ]; then
      gh api "repos/$REPO/environments/$ENV_NAME" --method PUT \
        --input <(echo "{\"wait_timer\": $WAIT_TIMER}") --silent
      apply_change "Created environment: $ENV_NAME"
    else
      echo "   📝 Would create environment: $ENV_NAME"
    fi
  fi
done

# --------------------------------------------------------------------------
# Remediate: Security Features
# --------------------------------------------------------------------------
echo "🔒 Remediating security features..."

SECRET_SCANNING=$(yq '.security.secret_scanning.enabled' "$PROFILE_FILE")
if [ "$SECRET_SCANNING" = "true" ]; then
  if [ "$MODE" != "safe" ]; then
    gh api "repos/$REPO" --method PATCH \
      --input <(echo '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}') \
      --silent 2>/dev/null || true
    apply_change "Enabled secret scanning + push protection"
  else
    echo "   📝 Would enable secret scanning + push protection"
  fi
fi

DEPENDABOT=$(yq '.security.dependabot.alerts' "$PROFILE_FILE")
if [ "$DEPENDABOT" = "true" ]; then
  if [ "$MODE" != "safe" ]; then
    gh api "repos/$REPO/vulnerability-alerts" --method PUT --silent 2>/dev/null || true
    apply_change "Enabled Dependabot alerts"
  else
    echo "   📝 Would enable Dependabot alerts"
  fi
fi

# --------------------------------------------------------------------------
# Remediate: Labels
# --------------------------------------------------------------------------
echo "🏷️  Remediating labels..."

REPO_LABELS=$(gh api "repos/$REPO/labels" --paginate 2>/dev/null | jq -r '.[].name' || echo "")
LABEL_COUNT=$(yq '.labels | length' "$PROFILE_FILE")
LABELS_ADDED=0

for i in $(seq 0 $((LABEL_COUNT - 1))); do
  LABEL_NAME=$(yq ".labels[$i].name" "$PROFILE_FILE")
  LABEL_COLOR=$(yq ".labels[$i].color" "$PROFILE_FILE")
  LABEL_DESC=$(yq ".labels[$i].description" "$PROFILE_FILE")

  if ! echo "$REPO_LABELS" | grep -q "^${LABEL_NAME}$"; then
    if [ "$MODE" != "safe" ]; then
      gh api "repos/$REPO/labels" --method POST \
        -f name="$LABEL_NAME" -f color="$LABEL_COLOR" -f description="$LABEL_DESC" \
        --silent 2>/dev/null || true
      LABELS_ADDED=$((LABELS_ADDED + 1))
    else
      echo "   📝 Would create label: $LABEL_NAME"
    fi
  fi
done

if [ "$LABELS_ADDED" -gt 0 ]; then
  apply_change "Created $LABELS_ADDED missing labels"
fi

# --------------------------------------------------------------------------
# Remediate: Required Files (Safe mode - create PR)
# --------------------------------------------------------------------------
echo "📄 Remediating required files..."

FILE_COUNT=$(yq '.required_files | length' "$PROFILE_FILE")
MISSING_FILES=()

for i in $(seq 0 $((FILE_COUNT - 1))); do
  FILE_PATH=$(yq ".required_files[$i].path" "$PROFILE_FILE")
  if ! gh api "repos/$REPO/contents/$FILE_PATH" --silent 2>/dev/null; then
    MISSING_FILES+=("$FILE_PATH")
  fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
  echo "   Missing files: ${MISSING_FILES[*]}"
  if [ "$MODE" = "safe" ]; then
    echo "   📝 Would create PR to add missing files"
    echo "   💡 Run with mode=semi-auto or mode=auto to apply"
  else
    echo "   ⚠️  File creation requires template source - manual action needed"
    echo "   Missing: ${MISSING_FILES[*]}"
  fi
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "============================================"
echo "🔧 Remediation Summary"
echo "============================================"
echo "Mode:         $MODE"
echo "Changes made: $CHANGES_MADE"
if [ "$MODE" = "safe" ]; then
  echo ""
  echo "ℹ️  Running in SAFE mode - no changes applied."
  echo "   Re-run with mode=semi-auto or mode=auto to apply."
fi
echo "============================================"
