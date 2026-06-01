import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { execSync } from "child_process";
import { readFileSync, readdirSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const GOVERNANCE_ROOT = join(__dirname, "../..");
const ENGINE_DIR = join(GOVERNANCE_ROOT, "engine");
const PROFILES_DIR = join(GOVERNANCE_ROOT, "profiles");

// ============================================================================
// MCP Server: Golden Repository Governance Engine
// ============================================================================
const server = new Server(
  {
    name: "governance-engine",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
      resources: {},
    },
  }
);

// ============================================================================
// Resources: Expose governance profiles and documentation
// ============================================================================
server.setRequestHandler(ListResourcesRequestSchema, async () => {
  const profiles = readdirSync(PROFILES_DIR)
    .filter((f) => f.endsWith(".yml"))
    .map((f) => ({
      uri: `governance://profiles/${f.replace(".yml", "")}`,
      name: f.replace(".yml", ""),
      description: `Governance profile: ${f.replace(".yml", "")}`,
      mimeType: "text/yaml",
    }));

  return {
    resources: [
      ...profiles,
      {
        uri: "governance://capability-matrix",
        name: "capability-matrix",
        description: "Who configures what - org vs repo vs automation",
        mimeType: "text/markdown",
      },
    ],
  };
});

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;

  if (uri.startsWith("governance://profiles/")) {
    const profileName = uri.replace("governance://profiles/", "");
    const filePath = join(PROFILES_DIR, `${profileName}.yml`);
    if (existsSync(filePath)) {
      return {
        contents: [
          {
            uri,
            mimeType: "text/yaml",
            text: readFileSync(filePath, "utf-8"),
          },
        ],
      };
    }
  }

  if (uri === "governance://capability-matrix") {
    return {
      contents: [
        {
          uri,
          mimeType: "text/markdown",
          text: getCapabilityMatrix(),
        },
      ],
    };
  }

  throw new Error(`Resource not found: ${uri}`);
});

// ============================================================================
// Tools: Governance operations
// ============================================================================
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "list_profiles",
      description:
        "List all available governance profiles with their descriptions",
      inputSchema: { type: "object", properties: {} },
    },
    {
      name: "get_profile",
      description: "Get the full YAML content of a governance profile",
      inputSchema: {
        type: "object",
        properties: {
          profile: {
            type: "string",
            description:
              "Profile name (e.g., azure-ai-landing-zone, cloud-native-app, aks-platform, fabric-project, data-platform)",
          },
        },
        required: ["profile"],
      },
    },
    {
      name: "create_repository",
      description:
        "Create a new governed repository from a profile. Provisions the repo with all governance settings.",
      inputSchema: {
        type: "object",
        properties: {
          profile: {
            type: "string",
            description: "Governance profile to apply",
          },
          org: { type: "string", description: "GitHub organization" },
          repo_name: { type: "string", description: "New repository name" },
          team_slug: { type: "string", description: "Team slug for permissions" },
          project_name: {
            type: "string",
            description: "Project board name",
          },
        },
        required: ["profile", "org", "repo_name", "team_slug", "project_name"],
      },
    },
    {
      name: "assess_repository",
      description:
        "Assess an existing repository against a governance profile. Returns compliance score and findings.",
      inputSchema: {
        type: "object",
        properties: {
          profile: {
            type: "string",
            description: "Governance profile to assess against",
          },
          repo: {
            type: "string",
            description: "Repository in org/repo format",
          },
        },
        required: ["profile", "repo"],
      },
    },
    {
      name: "remediate_repository",
      description:
        "Remediate governance gaps in an existing repository. Supports safe (preview), semi-auto, and auto modes.",
      inputSchema: {
        type: "object",
        properties: {
          profile: {
            type: "string",
            description: "Governance profile to enforce",
          },
          repo: {
            type: "string",
            description: "Repository in org/repo format",
          },
          mode: {
            type: "string",
            enum: ["safe", "semi-auto", "auto"],
            description:
              "safe=preview only, semi-auto=apply API+PR for files, auto=apply all",
          },
        },
        required: ["profile", "repo", "mode"],
      },
    },
    {
      name: "azure_integrate",
      description:
        "Set up Azure OIDC, RBAC, Key Vault, and federated credentials for a repository",
      inputSchema: {
        type: "object",
        properties: {
          profile: {
            type: "string",
            description: "Governance profile with Azure settings",
          },
          repo: {
            type: "string",
            description: "Repository in org/repo format",
          },
          subscription_id: {
            type: "string",
            description: "Azure subscription ID (optional, uses current)",
          },
          resource_group: {
            type: "string",
            description: "Azure resource group (optional, auto-creates)",
          },
        },
        required: ["profile", "repo"],
      },
    },
    {
      name: "generate_report",
      description:
        "Generate a formatted compliance report (markdown, JSON, or badge)",
      inputSchema: {
        type: "object",
        properties: {
          repo: {
            type: "string",
            description: "Repository in org/repo format",
          },
          format: {
            type: "string",
            enum: ["markdown", "json", "badge"],
            description: "Report output format",
          },
          report_data: {
            type: "string",
            description: "JSON compliance report data from assess_repository",
          },
        },
        required: ["repo", "format"],
      },
    },
    {
      name: "compare_profiles",
      description:
        "Compare two governance profiles to see differences in requirements",
      inputSchema: {
        type: "object",
        properties: {
          profile_a: { type: "string", description: "First profile name" },
          profile_b: { type: "string", description: "Second profile name" },
        },
        required: ["profile_a", "profile_b"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  switch (name) {
    case "list_profiles":
      return handleListProfiles();
    case "get_profile":
      return handleGetProfile(args.profile);
    case "create_repository":
      return handleCreateRepository(args);
    case "assess_repository":
      return handleAssessRepository(args);
    case "remediate_repository":
      return handleRemediateRepository(args);
    case "azure_integrate":
      return handleAzureIntegrate(args);
    case "generate_report":
      return handleGenerateReport(args);
    case "compare_profiles":
      return handleCompareProfiles(args);
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
});

// ============================================================================
// Tool Handlers
// ============================================================================

function handleListProfiles() {
  const profiles = readdirSync(PROFILES_DIR)
    .filter((f) => f.endsWith(".yml"))
    .map((f) => {
      const content = readFileSync(join(PROFILES_DIR, f), "utf-8");
      const nameMatch = content.match(/^name:\s*(.+)$/m);
      const descMatch = content.match(/^description:\s*(.+)$/m);
      return {
        id: f.replace(".yml", ""),
        name: nameMatch ? nameMatch[1] : f,
        description: descMatch ? descMatch[1] : "",
      };
    });

  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(profiles, null, 2),
      },
    ],
  };
}

function handleGetProfile(profileName) {
  const filePath = join(PROFILES_DIR, `${profileName}.yml`);
  if (!existsSync(filePath)) {
    return {
      content: [{ type: "text", text: `Profile not found: ${profileName}` }],
      isError: true,
    };
  }
  return {
    content: [{ type: "text", text: readFileSync(filePath, "utf-8") }],
  };
}

function handleCreateRepository(args) {
  const { profile, org, repo_name, team_slug, project_name } = args;
  const script = join(ENGINE_DIR, "create-repo.sh");

  try {
    const output = execSync(
      `bash "${script}" "${profile}" "${org}" "${repo_name}" "${team_slug}" "${project_name}"`,
      { encoding: "utf-8", timeout: 120000 }
    );
    return { content: [{ type: "text", text: output }] };
  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${error.message}\n${error.stderr || ""}` }],
      isError: true,
    };
  }
}

function handleAssessRepository(args) {
  const { profile, repo } = args;
  const script = join(ENGINE_DIR, "assess-repo.sh");

  try {
    const output = execSync(`bash "${script}" "${profile}" "${repo}"`, {
      encoding: "utf-8",
      timeout: 60000,
    });
    return { content: [{ type: "text", text: output }] };
  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${error.message}\n${error.stderr || ""}` }],
      isError: true,
    };
  }
}

function handleRemediateRepository(args) {
  const { profile, repo, mode } = args;
  const script = join(ENGINE_DIR, "remediate-repo.sh");

  try {
    const output = execSync(
      `bash "${script}" "${profile}" "${repo}" "${mode}"`,
      { encoding: "utf-8", timeout: 120000 }
    );
    return { content: [{ type: "text", text: output }] };
  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${error.message}\n${error.stderr || ""}` }],
      isError: true,
    };
  }
}

function handleAzureIntegrate(args) {
  const { profile, repo, subscription_id, resource_group } = args;
  const script = join(ENGINE_DIR, "azure-integrate.sh");

  const subArg = subscription_id ? ` "${subscription_id}"` : "";
  const rgArg = resource_group ? ` "${resource_group}"` : "";

  try {
    const output = execSync(
      `bash "${script}" "${profile}" "${repo}"${subArg}${rgArg}`,
      { encoding: "utf-8", timeout: 180000 }
    );
    return { content: [{ type: "text", text: output }] };
  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${error.message}\n${error.stderr || ""}` }],
      isError: true,
    };
  }
}

function handleGenerateReport(args) {
  const { repo, format, report_data } = args;
  const script = join(ENGINE_DIR, "format-report.sh");

  try {
    const input = report_data || "{}";
    const output = execSync(
      `echo '${input.replace(/'/g, "\\'")}' | bash "${script}" "${format}" "${repo}"`,
      { encoding: "utf-8", timeout: 30000 }
    );
    return { content: [{ type: "text", text: output }] };
  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${error.message}\n${error.stderr || ""}` }],
      isError: true,
    };
  }
}

function handleCompareProfiles(args) {
  const { profile_a, profile_b } = args;
  const fileA = join(PROFILES_DIR, `${profile_a}.yml`);
  const fileB = join(PROFILES_DIR, `${profile_b}.yml`);

  if (!existsSync(fileA))
    return { content: [{ type: "text", text: `Profile not found: ${profile_a}` }], isError: true };
  if (!existsSync(fileB))
    return { content: [{ type: "text", text: `Profile not found: ${profile_b}` }], isError: true };

  const contentA = readFileSync(fileA, "utf-8");
  const contentB = readFileSync(fileB, "utf-8");

  // Simple comparison - extract key settings
  const comparison = `# Profile Comparison: ${profile_a} vs ${profile_b}\n\n` +
    `## ${profile_a}\n\`\`\`yaml\n${contentA.slice(0, 2000)}\n\`\`\`\n\n` +
    `## ${profile_b}\n\`\`\`yaml\n${contentB.slice(0, 2000)}\n\`\`\``;

  return { content: [{ type: "text", text: comparison }] };
}

// ============================================================================
// Helpers
// ============================================================================

function getCapabilityMatrix() {
  return `# Capability Matrix

| Capability | Org Level (Admin) | Repo Level (Admin) | Automation (Agent) | Notes |
|---|---|---|---|---|
| Org Rulesets | ✅ | ❌ | ⚠️ (if allowed) | Requires org admin |
| Repo Rulesets / Branch Protection | ❌ | ✅ | ✅ | Can be automated via API / CLI |
| Environments | ❌ | ✅ | ✅ | Approvals per env |
| Secrets / Variables | ❌ | ✅ | ✅ | Repo or Org level |
| Teams & Permissions | ✅ | ❌ | ✅ | Depends on rights |
| Workflows / Files | ❌ | ✅ | ✅ | Via PR or direct |
| Security Scanning | ✅ | ✅ | ✅ | If enabled by org |
| Projects / Labels / Milestones | ❌ | ✅ | ✅ | Repo level |
| Azure OIDC / App Reg | ❌ | ❌ | ✅ | Requires Azure access |
`;
}

// ============================================================================
// Start Server
// ============================================================================
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Governance MCP Server running on stdio");
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
