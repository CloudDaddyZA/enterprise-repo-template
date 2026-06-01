#!/usr/bin/env bash
# ============================================================================
# Governance Engine - Repository Creator
# ============================================================================
# Creates a new repository from the golden template and applies all governance
# settings defined in the selected profile.
#
# Usage: ./create-repo.sh <profile> <org> <repo-name> <team-slug> <project-name>
#
# Requires: gh CLI authenticated, yq installed
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/../profiles"

# --------------------------------------------------------------------------
# Arguments
# --------------------------------------------------------------------------
PROFILE_NAME="${1:?Usage: create-repo.sh <profile> <org> <repo-name> <team-slug> <project-name>}"
ORG="${2:?Missing: organization name}"
REPO_NAME="${3:?Missing: repository name}"
TEAM_SLUG="${4:?Missing: team slug}"
PROJECT_NAME="${5:?Missing: project name}"

PROFILE_FILE="$PROFILE_DIR/${PROFILE_NAME}.yml"
REPO="$ORG/$REPO_NAME"

# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------
if [ ! -f "$PROFILE_FILE" ]; then
  echo "❌ Profile not found: $PROFILE_FILE"
  echo "Available profiles:"
  ls "$PROFILE_DIR"/*.yml 2>/dev/null | xargs -I{} basename {} .yml
  exit 1
fi

command -v gh >/dev/null 2>&1 || { echo "❌ gh CLI not found"; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "❌ yq not found"; exit 1; }

echo "============================================"
echo "🏗️  Governance Engine - Create Repository"
echo "============================================"
echo "Profile:      $PROFILE_NAME"
echo "Organization: $ORG"
echo "Repository:   $REPO_NAME"
echo "Team:         $TEAM_SLUG"
echo "Project:      $PROJECT_NAME"
echo "============================================"
echo ""

# --------------------------------------------------------------------------
# Step 1: Create Repository from Template
# --------------------------------------------------------------------------
echo "📦 Step 1/9: Creating repository from template..."

VISIBILITY=$(yq '.repository.visibility' "$PROFILE_FILE")
TEMPLATE_REPO="${TEMPLATE_REPO:-$ORG/enterprise-repo-template}"

gh repo create "$REPO" \
  --template "$TEMPLATE_REPO" \
  "--${VISIBILITY}" \
  --clone=false

# Wait for repo to be ready
sleep 5

echo "✅ Repository created: $REPO"

# --------------------------------------------------------------------------
# Step 2: Apply Repository Settings
# --------------------------------------------------------------------------
echo "⚙️  Step 2/9: Applying repository settings..."

HAS_WIKI=$(yq '.repository.has_wiki' "$PROFILE_FILE")
HAS_ISSUES=$(yq '.repository.has_issues' "$PROFILE_FILE")
HAS_PROJECTS=$(yq '.repository.has_projects' "$PROFILE_FILE")
DELETE_BRANCH=$(yq '.repository.delete_branch_on_merge' "$PROFILE_FILE")
ALLOW_SQUASH=$(yq '.repository.allow_squash_merge' "$PROFILE_FILE")
ALLOW_MERGE=$(yq '.repository.allow_merge_commit' "$PROFILE_FILE")
ALLOW_REBASE=$(yq '.repository.allow_rebase_merge' "$PROFILE_FILE")
ALLOW_AUTO=$(yq '.repository.allow_auto_merge' "$PROFILE_FILE")

gh api "repos/$REPO" --method PATCH \
  -f has_wiki="$HAS_WIKI" \
  -f has_issues="$HAS_ISSUES" \
  -f has_projects="$HAS_PROJECTS" \
  -f delete_branch_on_merge="$DELETE_BRANCH" \
  -f allow_squash_merge="$ALLOW_SQUASH" \
  -f allow_merge_commit="$ALLOW_MERGE" \
  -f allow_rebase_merge="$ALLOW_REBASE" \
  -f allow_auto_merge="$ALLOW_AUTO" \
  --silent

# Set topics
TOPICS=$(yq -o=json '.repository.topics' "$PROFILE_FILE")
gh api "repos/$REPO/topics" --method PUT \
  --input <(echo "{\"names\": $TOPICS}") \
  --silent

echo "✅ Repository settings applied"

# --------------------------------------------------------------------------
# Step 3: Apply Rulesets
# --------------------------------------------------------------------------
echo "🛡️  Step 3/9: Applying branch rulesets..."

RULESET_COUNT=$(yq '.rulesets | length' "$PROFILE_FILE")
for i in $(seq 0 $((RULESET_COUNT - 1))); do
  RULESET_NAME=$(yq ".rulesets[$i].name" "$PROFILE_FILE")
  echo "   Creating ruleset: $RULESET_NAME"

  APPROVALS=$(yq ".rulesets[$i].rules.pull_request.required_approving_review_count" "$PROFILE_FILE")
  DISMISS_STALE=$(yq ".rulesets[$i].rules.pull_request.dismiss_stale_reviews" "$PROFILE_FILE")
  REQUIRE_CODEOWNER=$(yq ".rulesets[$i].rules.pull_request.require_code_owner_review" "$PROFILE_FILE")
  LINEAR_HISTORY=$(yq ".rulesets[$i].rules.required_linear_history // false" "$PROFILE_FILE")

  # Build status checks array
  STATUS_CHECKS=$(yq -o=json ".rulesets[$i].rules.required_status_checks.required_status_checks" "$PROFILE_FILE")

  gh api "repos/$REPO/rulesets" --method POST \
    --input <(cat <<EOF
{
  "name": "$RULESET_NAME",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": $APPROVALS,
        "dismiss_stale_reviews_on_push": $DISMISS_STALE,
        "require_code_owner_review": $REQUIRE_CODEOWNER,
        "require_last_push_approval": false
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": $STATUS_CHECKS
      }
    },
    { "type": "deletion" },
    { "type": "non_fast_forward" }
  ],
  "bypass_actors": []
}
EOF
  ) --silent

done
echo "✅ Rulesets applied"

# --------------------------------------------------------------------------
# Step 4: Configure Team Permissions
# --------------------------------------------------------------------------
echo "👥 Step 4/9: Configuring team permissions..."

TEAM_COUNT=$(yq '.teams | length' "$PROFILE_FILE")
for i in $(seq 0 $((TEAM_COUNT - 1))); do
  SLUG=$(yq ".teams[$i].slug" "$PROFILE_FILE" | sed "s/\${TEAM_SLUG}/$TEAM_SLUG/g")
  PERMISSION=$(yq ".teams[$i].permission" "$PROFILE_FILE")

  # Try to add team; skip if team doesn't exist
  if gh api "orgs/$ORG/teams/$SLUG" --silent 2>/dev/null; then
    gh api "orgs/$ORG/teams/$SLUG/repos/$REPO" --method PUT \
      -f permission="$PERMISSION" --silent 2>/dev/null || true
    echo "   ✅ $SLUG → $PERMISSION"
  else
    echo "   ⚠️  Team not found: $SLUG (skipping)"
  fi
done
echo "✅ Team permissions configured"

# --------------------------------------------------------------------------
# Step 5: Create Environments
# --------------------------------------------------------------------------
echo "🌍 Step 5/9: Creating environments..."

ENV_COUNT=$(yq '.environments | length' "$PROFILE_FILE")
for i in $(seq 0 $((ENV_COUNT - 1))); do
  ENV_NAME=$(yq ".environments[$i].name" "$PROFILE_FILE")
  WAIT_TIMER=$(yq ".environments[$i].protection_rules.wait_timer // 0" "$PROFILE_FILE")

  gh api "repos/$REPO/environments/$ENV_NAME" --method PUT \
    --input <(echo "{\"wait_timer\": $WAIT_TIMER}") \
    --silent

  echo "   ✅ $ENV_NAME (wait: ${WAIT_TIMER}m)"
done
echo "✅ Environments created"

# --------------------------------------------------------------------------
# Step 6: Bootstrap Secrets & Variables
# --------------------------------------------------------------------------
echo "🔐 Step 6/9: Setting up repository variables..."

# Set standard variables
gh api "repos/$REPO/actions/variables" --method POST \
  -f name="PROJECT_NAME" -f value="$PROJECT_NAME" --silent 2>/dev/null || true
gh api "repos/$REPO/actions/variables" --method POST \
  -f name="TEAM_SLUG" -f value="$TEAM_SLUG" --silent 2>/dev/null || true
gh api "repos/$REPO/actions/variables" --method POST \
  -f name="GOVERNANCE_PROFILE" -f value="$PROFILE_NAME" --silent 2>/dev/null || true

echo "✅ Repository variables set"

# --------------------------------------------------------------------------
# Step 7: Create Labels
# --------------------------------------------------------------------------
echo "🏷️  Step 7/9: Creating labels..."

LABEL_COUNT=$(yq '.labels | length' "$PROFILE_FILE")
for i in $(seq 0 $((LABEL_COUNT - 1))); do
  LABEL_NAME=$(yq ".labels[$i].name" "$PROFILE_FILE")
  LABEL_COLOR=$(yq ".labels[$i].color" "$PROFILE_FILE")
  LABEL_DESC=$(yq ".labels[$i].description" "$PROFILE_FILE")

  gh api "repos/$REPO/labels" --method POST \
    -f name="$LABEL_NAME" \
    -f color="$LABEL_COLOR" \
    -f description="$LABEL_DESC" \
    --silent 2>/dev/null || \
  gh api "repos/$REPO/labels/$LABEL_NAME" --method PATCH \
    -f color="$LABEL_COLOR" \
    -f description="$LABEL_DESC" \
    --silent 2>/dev/null || true
done
echo "✅ Labels configured ($LABEL_COUNT labels)"

# --------------------------------------------------------------------------
# Step 8: Create Project Board (if enabled)
# --------------------------------------------------------------------------
echo "📋 Step 8/9: Setting up project board..."

PROJECT_ENABLED=$(yq '.project.enabled' "$PROFILE_FILE")
if [ "$PROJECT_ENABLED" = "true" ]; then
  BOARD_NAME=$(yq '.project.name' "$PROFILE_FILE" | sed "s/\${PROJECT_NAME}/$PROJECT_NAME/g")

  # Create project (V2)
  PROJECT_ID=$(gh api graphql -f query='
    mutation($org: String!, $title: String!) {
      createProjectV2(input: {ownerId: $org, title: $title}) {
        projectV2 { id }
      }
    }' -f org="$ORG" -f title="$BOARD_NAME" --jq '.data.createProjectV2.projectV2.id' 2>/dev/null || echo "")

  if [ -n "$PROJECT_ID" ]; then
    echo "   ✅ Project created: $BOARD_NAME"
  else
    echo "   ⚠️  Could not create project (may need org-level permissions)"
  fi
else
  echo "   ⏭️  Project board disabled in profile"
fi

# --------------------------------------------------------------------------
# Step 9: Enable Security Features
# --------------------------------------------------------------------------
echo "🔒 Step 9/9: Enabling security features..."

# Enable secret scanning
SECRET_SCANNING=$(yq '.security.secret_scanning.enabled' "$PROFILE_FILE")
PUSH_PROTECTION=$(yq '.security.secret_scanning.push_protection' "$PROFILE_FILE")

if [ "$SECRET_SCANNING" = "true" ]; then
  gh api "repos/$REPO" --method PATCH \
    --input <(echo '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}') \
    --silent 2>/dev/null || true
  echo "   ✅ Secret scanning + push protection enabled"
fi

# Enable Dependabot
DEPENDABOT_ALERTS=$(yq '.security.dependabot.alerts' "$PROFILE_FILE")
if [ "$DEPENDABOT_ALERTS" = "true" ]; then
  gh api "repos/$REPO/vulnerability-alerts" --method PUT --silent 2>/dev/null || true
  echo "   ✅ Dependabot alerts enabled"
fi

echo "✅ Security features configured"

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "============================================"
echo "✅ Repository Governance Complete!"
echo "============================================"
echo ""
echo "Repository: https://github.com/$REPO"
echo "Profile:    $PROFILE_NAME"
echo ""
echo "Next steps:"
echo "  1. Run Azure OIDC setup workflow (if Azure integration enabled)"
echo "  2. Update CODEOWNERS with actual team members"
echo "  3. Configure environment secrets for deployments"
echo "  4. Run the CI pipeline to validate the setup"
echo "============================================"
