import * as vscode from "vscode";
import { execSync } from "child_process";
import { readFileSync, readdirSync, existsSync } from "fs";
import { join } from "path";

// ============================================================================
// Governance Engine - Copilot Chat Participant
// ============================================================================

const PARTICIPANT_ID = "governance-engine";

interface GovernanceProfile {
  name: string;
  description: string;
  filePath: string;
}

// ============================================================================
// Extension Activation
// ============================================================================
export function activate(context: vscode.ExtensionContext) {
  const participant = vscode.chat.createChatParticipant(
    PARTICIPANT_ID,
    handler
  );

  participant.iconPath = new vscode.ThemeIcon("shield");

  context.subscriptions.push(participant);
}

export function deactivate() {}

// ============================================================================
// Main Handler
// ============================================================================
const handler: vscode.ChatRequestHandler = async (
  request: vscode.ChatRequest,
  context: vscode.ChatContext,
  stream: vscode.ChatResponseStream,
  token: vscode.CancellationToken
): Promise<vscode.ChatResult> => {
  const command = request.command;

  switch (command) {
    case "create":
      return handleCreate(request, stream, token);
    case "assess":
      return handleAssess(request, stream, token);
    case "remediate":
      return handleRemediate(request, stream, token);
    case "profiles":
      return handleProfiles(request, stream, token);
    case "report":
      return handleReport(request, stream, token);
    case "azure":
      return handleAzure(request, stream, token);
    default:
      return handleGeneral(request, stream, token);
  }
};

// ============================================================================
// Command Handlers
// ============================================================================

async function handleCreate(
  request: vscode.ChatRequest,
  stream: vscode.ChatResponseStream,
  token: vscode.CancellationToken
): Promise<vscode.ChatResult> {
  const prompt = request.prompt.trim();

  if (!prompt) {
    stream.markdown(
      "To create a governed repository, provide the details:\n\n" +
        "```\n" +
        "@governance /create azure-ai-landing-zone my-new-service backend-team \"My New Service\"\n" +
        "```\n\n" +
        "**Parameters:** `<profile> <repo-name> <team-slug> <project-name>`\n\n" +
        "Use `/profiles` to see available governance profiles."
    );
    return { metadata: { command: "create" } };
  }

  const parts = parseArgs(prompt);
  if (parts.length < 4) {
    stream.markdown(
      "⚠️ Missing parameters. Expected:\n\n" +
        "`<profile> <repo-name> <team-slug> <project-name>`"
    );
    return { metadata: { command: "create" } };
  }

  const [profile, repoName, teamSlug, ...projectParts] = parts;
  const projectName = projectParts.join(" ");

  stream.markdown(`## 🏗️ Creating Governed Repository\n\n`);
  stream.markdown(`| Parameter | Value |\n|-----------|-------|\n`);
  stream.markdown(`| Profile | \`${profile}\` |\n`);
  stream.markdown(`| Repository | \`${repoName}\` |\n`);
  stream.markdown(`| Team | \`${teamSlug}\` |\n`);
  stream.markdown(`| Project | ${projectName} |\n\n`);

  stream.progress("Running governance engine...");

  const enginePath = getEnginePath();
  if (!enginePath) {
    stream.markdown(
      "❌ Could not locate the governance engine. Ensure the workspace contains `governance/engine/create-repo.sh`."
    );
    return { metadata: { command: "create" } };
  }

  const org = await getOrg();

  try {
    const result = runEngine(
      enginePath,
      `create-repo.sh`,
      [profile, org, repoName, teamSlug, projectName],
      token
    );
    stream.markdown("### ✅ Repository Created\n\n```\n" + result + "\n```\n");
    stream.markdown(
      `\n🔗 [Open repository](https://github.com/${org}/${repoName})`
    );
  } catch (err: any) {
    stream.markdown(`### ❌ Creation Failed\n\n\`\`\`\n${err.message}\n\`\`\``);
  }

  return { metadata: { command: "create" } };
}

async function handleAssess(
  request: vscode.ChatRequest,
  stream: vscode.ChatResponseStream,
  token: vscode.CancellationToken
): Promise<vscode.ChatResult> {
  const prompt = request.prompt.trim();

  if (!prompt) {
    stream.markdown(
      "To assess a repository, provide:\n\n" +
        "```\n" +
        "@governance /assess azure-ai-landing-zone my-org/my-repo\n" +
        "```\n\n" +
        "**Parameters:** `<profile> <org/repo>`"
    );
    return { metadata: { command: "assess" } };
  }

  const parts = parseArgs(prompt);
  if (parts.length < 2) {
    stream.markdown("⚠️ Missing parameters. Expected: `<profile> <org/repo>`");
    return { metadata: { command: "assess" } };
  }

  const [profile, repo] = parts;

  stream.markdown(`## 🔍 Assessing Repository\n\n`);
  stream.markdown(`| Parameter | Value |\n|-----------|-------|\n`);
  stream.markdown(`| Profile | \`${profile}\` |\n`);
  stream.markdown(`| Repository | \`${repo}\` |\n\n`);

  stream.progress("Running compliance assessment...");

  const enginePath = getEnginePath();
  if (!enginePath) {
    stream.markdown("❌ Could not locate the governance engine.");
    return { metadata: { command: "assess" } };
  }

  try {
    const result = runEngine(
      enginePath,
      `assess-repo.sh`,
      [profile, repo],
      token
    );

    // Try to parse JSON report
    try {
      const report = JSON.parse(result);
      const score = report.report.score;
      const badge =
        score >= 90 ? "🟢" : score >= 70 ? "🟡" : "🔴";

      stream.markdown(`### ${badge} Compliance Score: **${score}%**\n\n`);
      stream.markdown(
        `| Metric | Count |\n|--------|-------|\n` +
          `| Total Checks | ${report.report.summary.total_checks} |\n` +
          `| ✅ Passed | ${report.report.summary.passed} |\n` +
          `| ❌ Failed | ${report.report.summary.failed} |\n` +
          `| ⚠️ Warnings | ${report.report.summary.warnings} |\n\n`
      );

      const failures = report.report.findings.filter(
        (f: any) => f.status === "fail"
      );
      if (failures.length > 0) {
        stream.markdown("### ❌ Failed Checks\n\n");
        stream.markdown(
          "| Category | Check | Remediation |\n|----------|-------|-------------|\n"
        );
        for (const f of failures) {
          stream.markdown(
            `| ${f.category} | ${f.check} | ${f.remediation} |\n`
          );
        }
        stream.markdown(
          "\n💡 Run `@governance /remediate " +
            profile +
            " " +
            repo +
            "` to fix these issues."
        );
      }
    } catch {
      stream.markdown("```\n" + result + "\n```");
    }
  } catch (err: any) {
    stream.markdown(
      `### ❌ Assessment Failed\n\n\`\`\`\n${err.message}\n\`\`\``
    );
  }

  return { metadata: { command: "assess" } };
}

async function handleRemediate(
  request: vscode.ChatRequest,
  stream: vscode.ChatResponseStream,
  token: vscode.CancellationToken
): Promise<vscode.ChatResult> {
  const prompt = request.prompt.trim();

  if (!prompt) {
    stream.markdown(
      "To remediate governance gaps:\n\n" +
        "```\n" +
        "@governance /remediate azure-ai-landing-zone my-org/my-repo safe\n" +
        "```\n\n" +
        "**Parameters:** `<profile> <org/repo> [mode]`\n\n" +
        "| Mode | Behavior |\n|------|----------|\n" +
        "| `safe` | Preview only (default) |\n" +
        "| `semi-auto` | Apply API changes, PR for files |\n" +
        "| `auto` | Apply everything directly |\n"
    );
    return { metadata: { command: "remediate" } };
  }

  const parts = parseArgs(prompt);
  if (parts.length < 2) {
    stream.markdown(
      "⚠️ Missing parameters. Expected: `<profile> <org/repo> [mode]`"
    );
    return { metadata: { command: "remediate" } };
  }

  const [profile, repo, mode = "safe"] = parts;

  stream.markdown(`## 🔧 Remediating Repository\n\n`);
  stream.markdown(`| Parameter | Value |\n|-----------|-------|\n`);
  stream.markdown(`| Profile | \`${profile}\` |\n`);
  stream.markdown(`| Repository | \`${repo}\` |\n`);
  stream.markdown(`| Mode | \`${mode}\` |\n\n`);

  stream.progress("Running remediation engine...");

  const enginePath = getEnginePath();
  if (!enginePath) {
    stream.markdown("❌ Could not locate the governance engine.");
    return { metadata: { command: "remediate" } };
  }

  try {
    const result = runEngine(
      enginePath,
      `remediate-repo.sh`,
      [profile, repo, mode],
      token
    );
    stream.markdown(
      "### ✅ Remediation Complete\n\n```\n" + result + "\n```"
    );
  } catch (err: any) {
    stream.markdown(
      `### ❌ Remediation Failed\n\n\`\`\`\n${err.message}\n\`\`\``
    );
  }

  return { metadata: { command: "remediate" } };
}

async function handleProfiles(
  request: vscode.ChatRequest,
  stream: vscode.ChatResponseStream,
  _token: vscode.CancellationToken
): Promise<vscode.ChatResult> {
  const profiles = getProfiles();

  if (profiles.length === 0) {
    stream.markdown(
      "❌ No governance profiles found. Ensure `governance/profiles/` exists in the workspace."
    );
    return { metadata: { command: "profiles" } };
  }

  stream.markdown("## 📋 Available Governance Profiles\n\n");
  stream.markdown("| Profile | Description |\n|---------|-------------|\n");

  for (const p of profiles) {
    stream.markdown(`| \`${p.name}\` | ${p.description} |\n`);
  }

  stream.markdown(
    "\n\nUse a profile with:\n" +
      "- `@governance /create <profile> ...`\n" +
      "- `@governance /assess <profile> <org/repo>`\n" +
      "- `@governance /remediate <profile> <org/repo> [mode]`"
  );

  return { metadata: { command: "profiles" } };
}

async function handleReport(
  request: vscode.ChatRequest,
  stream: vscode.ChatResponseStream,
  token: vscode.CancellationToken
): Promise<vscode.ChatResult> {
  const prompt = request.prompt.trim();

  if (!prompt) {
    stream.markdown(
      "To generate a compliance report:\n\n" +
        "```\n" +
        "@governance /report azure-ai-landing-zone my-org/my-repo\n" +
        "```\n\n" +
        "**Parameters:** `<profile> <org/repo> [format]`\n\n" +
        "Formats: `markdown` (default), `json-summary`, `badge`"
    );
    return { metadata: { command: "report" } };
  }

  const parts = parseArgs(prompt);
  if (parts.length < 2) {
    stream.markdown(
      "⚠️ Missing parameters. Expected: `<profile> <org/repo> [format]`"
    );
    return { metadata: { command: "report" } };
  }

  const [profile, repo, format = "markdown"] = parts;

  stream.progress("Generating compliance report...");

  const enginePath = getEnginePath();
  if (!enginePath) {
    stream.markdown("❌ Could not locate the governance engine.");
    return { metadata: { command: "report" } };
  }

  try {
    // Assess first, then format
    const assessResult = runEngine(
      enginePath,
      `assess-repo.sh`,
      [profile, repo],
      token
    );

    // Write temp report and format it
    const tmpFile = join(enginePath, "..", ".tmp-report.json");
    require("fs").writeFileSync(tmpFile, assessResult);

    const formatted = runEngine(
      enginePath,
      `format-report.sh`,
      [tmpFile, format],
      token
    );

    require("fs").unlinkSync(tmpFile);

    stream.markdown(formatted);
  } catch (err: any) {
    stream.markdown(
      `### ❌ Report Generation Failed\n\n\`\`\`\n${err.message}\n\`\`\``
    );
  }

  return { metadata: { command: "report" } };
}

async function handleAzure(
  request: vscode.ChatRequest,
  stream: vscode.ChatResponseStream,
  token: vscode.CancellationToken
): Promise<vscode.ChatResult> {
  const prompt = request.prompt.trim();

  if (!prompt) {
    stream.markdown(
      "To set up Azure integration:\n\n" +
        "```\n" +
        "@governance /azure azure-ai-landing-zone my-org/my-repo <subscription-id> [resource-group]\n" +
        "```\n\n" +
        "**This configures:**\n" +
        "- Entra ID App Registration + Service Principal\n" +
        "- OIDC Federated Credentials (GitHub → Azure)\n" +
        "- RBAC Role Assignments\n" +
        "- Key Vault (if enabled in profile)\n" +
        "- Resource Group with governance tags"
    );
    return { metadata: { command: "azure" } };
  }

  const parts = parseArgs(prompt);
  if (parts.length < 3) {
    stream.markdown(
      "⚠️ Missing parameters. Expected: `<profile> <org/repo> <subscription-id> [resource-group]`"
    );
    return { metadata: { command: "azure" } };
  }

  const [profile, repo, subscriptionId, resourceGroup] = parts;

  stream.markdown(`## ☁️ Azure Integration\n\n`);
  stream.markdown(`| Parameter | Value |\n|-----------|-------|\n`);
  stream.markdown(`| Profile | \`${profile}\` |\n`);
  stream.markdown(`| Repository | \`${repo}\` |\n`);
  stream.markdown(`| Subscription | \`${subscriptionId}\` |\n`);
  if (resourceGroup) {
    stream.markdown(`| Resource Group | \`${resourceGroup}\` |\n`);
  }
  stream.markdown("\n");

  stream.progress("Configuring Azure integration...");

  const enginePath = getEnginePath();
  if (!enginePath) {
    stream.markdown("❌ Could not locate the governance engine.");
    return { metadata: { command: "azure" } };
  }

  const args = [profile, repo, subscriptionId];
  if (resourceGroup) args.push(resourceGroup);

  try {
    const result = runEngine(
      enginePath,
      `azure-integrate.sh`,
      args,
      token
    );
    stream.markdown(
      "### ✅ Azure Integration Complete\n\n```\n" + result + "\n```"
    );
  } catch (err: any) {
    stream.markdown(
      `### ❌ Azure Integration Failed\n\n\`\`\`\n${err.message}\n\`\`\``
    );
  }

  return { metadata: { command: "azure" } };
}

async function handleGeneral(
  request: vscode.ChatRequest,
  stream: vscode.ChatResponseStream,
  _token: vscode.CancellationToken
): Promise<vscode.ChatResult> {
  const prompt = request.prompt.trim().toLowerCase();

  // Provide contextual help based on prompt
  if (
    prompt.includes("help") ||
    prompt.includes("what can you do") ||
    !prompt
  ) {
    stream.markdown(
      "## 🛡️ Governance Engine\n\n" +
        "I help manage enterprise repository governance. Here's what I can do:\n\n" +
        "| Command | Description |\n|---------|-------------|\n" +
        "| `/create` | Create a new governed repository from a profile |\n" +
        "| `/assess` | Assess compliance of an existing repository |\n" +
        "| `/remediate` | Fix governance gaps |\n" +
        "| `/profiles` | List available governance profiles |\n" +
        "| `/report` | Generate a compliance report |\n" +
        "| `/azure` | Set up Azure OIDC, RBAC, Key Vault |\n\n" +
        "### Quick Start\n\n" +
        "```\n" +
        "@governance /profiles\n" +
        "@governance /create azure-ai-landing-zone my-service backend-team \"My Service\"\n" +
        "@governance /assess cloud-native-app my-org/existing-repo\n" +
        "```"
    );
  } else {
    // Try to infer intent
    if (prompt.includes("create") || prompt.includes("new repo")) {
      stream.markdown(
        "It looks like you want to create a repository. Use:\n\n" +
          "`@governance /create <profile> <repo-name> <team-slug> <project-name>`"
      );
    } else if (prompt.includes("assess") || prompt.includes("compliance") || prompt.includes("check")) {
      stream.markdown(
        "It looks like you want to assess compliance. Use:\n\n" +
          "`@governance /assess <profile> <org/repo>`"
      );
    } else if (prompt.includes("fix") || prompt.includes("remediate") || prompt.includes("drift")) {
      stream.markdown(
        "It looks like you want to remediate governance gaps. Use:\n\n" +
          "`@governance /remediate <profile> <org/repo> [mode]`"
      );
    } else {
      stream.markdown(
        "I can help with repository governance. Try `@governance /help` to see available commands."
      );
    }
  }

  return { metadata: { command: "general" } };
}

// ============================================================================
// Utilities
// ============================================================================

function getEnginePath(): string | undefined {
  const workspaceFolders = vscode.workspace.workspaceFolders;
  if (!workspaceFolders) return undefined;

  for (const folder of workspaceFolders) {
    const engineDir = join(folder.uri.fsPath, "governance", "engine");
    if (existsSync(engineDir)) {
      return engineDir;
    }
  }
  return undefined;
}

function getProfiles(): GovernanceProfile[] {
  const workspaceFolders = vscode.workspace.workspaceFolders;
  if (!workspaceFolders) return [];

  for (const folder of workspaceFolders) {
    const profilesDir = join(folder.uri.fsPath, "governance", "profiles");
    if (!existsSync(profilesDir)) continue;

    return readdirSync(profilesDir)
      .filter((f) => f.endsWith(".yml"))
      .map((f) => {
        const filePath = join(profilesDir, f);
        const content = readFileSync(filePath, "utf-8");
        const descMatch = content.match(/^#\s*(.+)/m);
        const description =
          descMatch?.[1] || extractYamlDescription(content) || "Governance profile";
        return {
          name: f.replace(".yml", ""),
          description,
          filePath,
        };
      });
  }

  return [];
}

function extractYamlDescription(content: string): string {
  // Try to extract description from profile YAML
  const match = content.match(/description:\s*["']?(.+?)["']?\s*$/m);
  return match?.[1] || "";
}

async function getOrg(): Promise<string> {
  try {
    const result = execSync("gh api user --jq .login", {
      encoding: "utf-8",
      timeout: 10000,
    }).trim();

    // Try to get org from git remote
    const remote = execSync("git remote get-url origin", {
      encoding: "utf-8",
      timeout: 5000,
    }).trim();
    const orgMatch = remote.match(/github\.com[:/]([^/]+)\//);
    if (orgMatch) return orgMatch[1];

    return result;
  } catch {
    return "my-org";
  }
}

function runEngine(
  enginePath: string,
  script: string,
  args: string[],
  token: vscode.CancellationToken
): string {
  if (token.isCancellationRequested) {
    throw new Error("Operation cancelled");
  }

  const scriptPath = join(enginePath, script);
  if (!existsSync(scriptPath)) {
    throw new Error(`Engine script not found: ${script}`);
  }

  const escapedArgs = args.map((a) => `"${a.replace(/"/g, '\\"')}"`).join(" ");
  const cmd = `bash "${scriptPath}" ${escapedArgs}`;

  try {
    return execSync(cmd, {
      encoding: "utf-8",
      timeout: 120000,
      cwd: enginePath,
      env: { ...process.env, GH_TOKEN: process.env.GH_TOKEN || "" },
    }).trim();
  } catch (err: any) {
    const stderr = err.stderr?.toString() || "";
    const stdout = err.stdout?.toString() || "";
    throw new Error(stderr || stdout || err.message);
  }
}

function parseArgs(input: string): string[] {
  const args: string[] = [];
  let current = "";
  let inQuotes = false;
  let quoteChar = "";

  for (const ch of input) {
    if (!inQuotes && (ch === '"' || ch === "'")) {
      inQuotes = true;
      quoteChar = ch;
    } else if (inQuotes && ch === quoteChar) {
      inQuotes = false;
      quoteChar = "";
    } else if (!inQuotes && ch === " ") {
      if (current) {
        args.push(current);
        current = "";
      }
    } else {
      current += ch;
    }
  }
  if (current) args.push(current);

  return args;
}
