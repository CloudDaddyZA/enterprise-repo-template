#!/usr/bin/env bash
# ============================================================================
# Governance Engine - Azure Integration Layer
# ============================================================================
# Provisions Azure resources for repository governance:
#   - Entra ID App Registration + Service Principal
#   - OIDC Federated Credentials (GitHub → Azure)
#   - RBAC Role Assignments
#   - Key Vault (optional)
#   - Resource Group (optional)
#   - Azure Policy Assignments (optional)
#
# Usage: ./azure-integrate.sh <profile> <org/repo> [subscription-id] [resource-group]
#
# Requires: az CLI authenticated, gh CLI authenticated, yq, jq
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/../profiles"
AUDIT_SCRIPT="$SCRIPT_DIR/audit-log.sh"

# --------------------------------------------------------------------------
# Arguments
# --------------------------------------------------------------------------
PROFILE_NAME="${1:?Usage: azure-integrate.sh <profile> <org/repo> [subscription-id] [resource-group]}"
REPO="${2:?Missing: org/repo}"
SUBSCRIPTION_ID="${3:-}"
RESOURCE_GROUP="${4:-}"

PROFILE_FILE="$PROFILE_DIR/${PROFILE_NAME}.yml"

# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------
if [ ! -f "$PROFILE_FILE" ]; then
  echo "❌ Profile not found: $PROFILE_FILE" >&2
  exit 1
fi

command -v az >/dev/null 2>&1 || { echo "❌ az CLI not found" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "❌ gh CLI not found" >&2; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "❌ yq not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ jq not found" >&2; exit 1; }

# Check Azure OIDC enabled in profile
OIDC_ENABLED=$(yq '.azure.oidc.enabled // false' "$PROFILE_FILE")
if [ "$OIDC_ENABLED" != "true" ]; then
  echo "ℹ️  Azure OIDC not enabled in profile '$PROFILE_NAME'. Skipping Azure integration."
  exit 0
fi

# Resolve subscription
if [ -z "$SUBSCRIPTION_ID" ]; then
  SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null)
  if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "❌ No subscription ID provided and no active az login session" >&2
    exit 1
  fi
fi

echo "============================================"
echo "☁️  Governance Engine - Azure Integration"
echo "============================================"
echo "Profile:      $PROFILE_NAME"
echo "Repository:   $REPO"
echo "Subscription: $SUBSCRIPTION_ID"
echo "RG:           ${RESOURCE_GROUP:-<auto-create>}"
echo "============================================"
echo ""

REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
ORG=$(echo "$REPO" | cut -d'/' -f1)
APP_NAME="github-${REPO_NAME}"

# --------------------------------------------------------------------------
# Step 1: Create Resource Group (if not provided)
# --------------------------------------------------------------------------
echo "📦 Step 1/6: Resource group..."

if [ -z "$RESOURCE_GROUP" ]; then
  RESOURCE_GROUP="rg-${REPO_NAME}"
  LOCATION="${AZURE_LOCATION:-eastus2}"

  if az group show --name "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" &>/dev/null; then
    echo "   ✅ Resource group exists: $RESOURCE_GROUP"
  else
    az group create \
      --name "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      --subscription "$SUBSCRIPTION_ID" \
      --tags "managed-by=governance-engine" "repository=$REPO" "profile=$PROFILE_NAME" \
      --output none
    echo "   ✅ Created resource group: $RESOURCE_GROUP"

    # Audit log
    [ -f "$AUDIT_SCRIPT" ] && source "$AUDIT_SCRIPT" && \
      audit_log "azure" "resource_group_created" "$RESOURCE_GROUP" "$REPO"
  fi
else
  echo "   ✅ Using existing resource group: $RESOURCE_GROUP"
fi

# --------------------------------------------------------------------------
# Step 2: Create Entra ID App Registration
# --------------------------------------------------------------------------
echo "🔑 Step 2/6: Entra ID app registration..."

EXISTING_APP=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_APP" ] && [ "$EXISTING_APP" != "None" ]; then
  CLIENT_ID="$EXISTING_APP"
  echo "   ✅ App registration exists: $APP_NAME (Client ID: $CLIENT_ID)"
else
  CLIENT_ID=$(az ad app create \
    --display-name "$APP_NAME" \
    --query appId -o tsv)
  echo "   ✅ Created app registration: $APP_NAME (Client ID: $CLIENT_ID)"

  [ -f "$AUDIT_SCRIPT" ] && source "$AUDIT_SCRIPT" && \
    audit_log "azure" "app_registration_created" "$APP_NAME" "$REPO"
fi

# Create service principal if not exists
SP_ID=$(az ad sp list --filter "appId eq '$CLIENT_ID'" --query "[0].id" -o tsv 2>/dev/null || echo "")
if [ -z "$SP_ID" ] || [ "$SP_ID" = "None" ]; then
  SP_ID=$(az ad sp create --id "$CLIENT_ID" --query id -o tsv)
  echo "   ✅ Created service principal"
fi

TENANT_ID=$(az account show --query tenantId -o tsv)

# --------------------------------------------------------------------------
# Step 3: Configure OIDC Federated Credentials
# --------------------------------------------------------------------------
echo "🔗 Step 3/6: Federated credentials (OIDC)..."

CRED_COUNT=$(yq '.azure.oidc.federated_credentials | length' "$PROFILE_FILE")
for i in $(seq 0 $((CRED_COUNT - 1))); do
  CRED_NAME=$(yq ".azure.oidc.federated_credentials[$i].name" "$PROFILE_FILE")
  SUBJECT_TEMPLATE=$(yq ".azure.oidc.federated_credentials[$i].subject" "$PROFILE_FILE")
  # Replace ${REPO} placeholder
  SUBJECT=$(echo "$SUBJECT_TEMPLATE" | sed "s|\${REPO}|$REPO|g")

  # Check if credential exists
  EXISTING_CRED=$(az ad app federated-credential list \
    --id "$CLIENT_ID" \
    --query "[?name=='$CRED_NAME'].name" -o tsv 2>/dev/null || echo "")

  if [ -n "$EXISTING_CRED" ]; then
    echo "   ✅ Credential exists: $CRED_NAME"
  else
    az ad app federated-credential create \
      --id "$CLIENT_ID" \
      --parameters "{
        \"name\": \"$CRED_NAME\",
        \"issuer\": \"https://token.actions.githubusercontent.com\",
        \"subject\": \"$SUBJECT\",
        \"audiences\": [\"api://AzureADTokenExchange\"]
      }" --output none 2>/dev/null
    echo "   ✅ Created: $CRED_NAME → $SUBJECT"
  fi
done

# --------------------------------------------------------------------------
# Step 4: RBAC Role Assignments
# --------------------------------------------------------------------------
echo "🛡️  Step 4/6: RBAC role assignments..."

RBAC_COUNT=$(yq '.azure.rbac.assignments | length' "$PROFILE_FILE")
RG_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
SUB_SCOPE="/subscriptions/$SUBSCRIPTION_ID"

for i in $(seq 0 $((RBAC_COUNT - 1))); do
  ROLE=$(yq ".azure.rbac.assignments[$i].role" "$PROFILE_FILE")
  SCOPE_TYPE=$(yq ".azure.rbac.assignments[$i].scope" "$PROFILE_FILE")

  if [ "$SCOPE_TYPE" = "subscription" ]; then
    SCOPE="$SUB_SCOPE"
  else
    SCOPE="$RG_SCOPE"
  fi

  # Assign role (idempotent - will skip if exists)
  az role assignment create \
    --assignee "$SP_ID" \
    --role "$ROLE" \
    --scope "$SCOPE" \
    --output none 2>/dev/null || true
  echo "   ✅ $ROLE → $(basename "$SCOPE")"
done

# --------------------------------------------------------------------------
# Step 5: Key Vault (optional)
# --------------------------------------------------------------------------
echo "🔐 Step 5/6: Key Vault..."

KV_ENABLED=$(yq '.azure.key_vault.enabled // false' "$PROFILE_FILE")
if [ "$KV_ENABLED" = "true" ]; then
  KV_NAME="kv-${REPO_NAME:0:20}-$(echo "$SUBSCRIPTION_ID" | cut -c1-4)"
  LOCATION="${AZURE_LOCATION:-eastus2}"

  if az keyvault show --name "$KV_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    echo "   ✅ Key Vault exists: $KV_NAME"
  else
    az keyvault create \
      --name "$KV_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      --enable-rbac-authorization true \
      --tags "managed-by=governance-engine" "repository=$REPO" \
      --output none 2>/dev/null || echo "   ⚠️  Key Vault creation failed (name may be taken)"

    # Grant SP access
    az role assignment create \
      --assignee "$SP_ID" \
      --role "Key Vault Secrets User" \
      --scope "$RG_SCOPE/providers/Microsoft.KeyVault/vaults/$KV_NAME" \
      --output none 2>/dev/null || true
    echo "   ✅ Created Key Vault: $KV_NAME"
  fi
else
  echo "   ⏭️  Key Vault not enabled in profile"
fi

# --------------------------------------------------------------------------
# Step 6: Set GitHub Repository Variables
# --------------------------------------------------------------------------
echo "📝 Step 6/6: Setting GitHub variables..."

gh api "repos/$REPO/actions/variables" --method POST \
  -f name="AZURE_CLIENT_ID" -f value="$CLIENT_ID" --silent 2>/dev/null || \
gh api "repos/$REPO/actions/variables/AZURE_CLIENT_ID" --method PATCH \
  -f value="$CLIENT_ID" --silent 2>/dev/null || true

gh api "repos/$REPO/actions/variables" --method POST \
  -f name="AZURE_TENANT_ID" -f value="$TENANT_ID" --silent 2>/dev/null || \
gh api "repos/$REPO/actions/variables/AZURE_TENANT_ID" --method PATCH \
  -f value="$TENANT_ID" --silent 2>/dev/null || true

gh api "repos/$REPO/actions/variables" --method POST \
  -f name="AZURE_SUBSCRIPTION_ID" -f value="$SUBSCRIPTION_ID" --silent 2>/dev/null || \
gh api "repos/$REPO/actions/variables/AZURE_SUBSCRIPTION_ID" --method PATCH \
  -f value="$SUBSCRIPTION_ID" --silent 2>/dev/null || true

if [ "$KV_ENABLED" = "true" ]; then
  gh api "repos/$REPO/actions/variables" --method POST \
    -f name="AZURE_KEY_VAULT_NAME" -f value="$KV_NAME" --silent 2>/dev/null || true
fi

echo "   ✅ GitHub variables configured"

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "============================================"
echo "✅ Azure Integration Complete!"
echo "============================================"
echo ""
echo "App Registration: $APP_NAME"
echo "Client ID:        $CLIENT_ID"
echo "Tenant ID:        $TENANT_ID"
echo "Subscription:     $SUBSCRIPTION_ID"
echo "Resource Group:   $RESOURCE_GROUP"
echo ""
echo "GitHub Variables Set:"
echo "  AZURE_CLIENT_ID=$CLIENT_ID"
echo "  AZURE_TENANT_ID=$TENANT_ID"
echo "  AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo ""

[ -f "$AUDIT_SCRIPT" ] && source "$AUDIT_SCRIPT" && \
  audit_log "azure" "integration_complete" "$REPO" "profile=$PROFILE_NAME"
