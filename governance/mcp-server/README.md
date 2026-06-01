# Governance MCP Server

Model Context Protocol server that enables GitHub Copilot and AI agents to manage repository governance through natural language.

## Setup

```json
// .vscode/mcp.json or VS Code settings
{
  "servers": {
    "governance-engine": {
      "command": "node",
      "args": ["governance/mcp-server/src/index.js"],
      "env": {
        "GH_TOKEN": "${env:GH_TOKEN}"
      }
    }
  }
}
```

## Available Tools

| Tool                   | Description                                      |
| ---------------------- | ------------------------------------------------ |
| `list_profiles`        | List all governance profiles with descriptions   |
| `get_profile`          | Get full YAML content of a specific profile      |
| `create_repository`    | Create a new governed repository from a profile  |
| `assess_repository`    | Assess compliance against a governance profile   |
| `remediate_repository` | Fix governance gaps (safe/semi-auto/auto modes)  |
| `azure_integrate`      | Set up Azure OIDC, RBAC, and Key Vault           |
| `generate_report`      | Generate compliance report (markdown/JSON/badge) |
| `compare_profiles`     | Compare two profiles side-by-side                |

## Example Prompts

```
"Create a new Azure AI Landing Zone repository called contoso-ai for the backend-team"

"Assess the repo contoso-data-platform against the data-platform profile"

"Apply enterprise governance to contoso-data-platform using safe mode"

"Set up Azure OIDC for the contoso-ai repository"

"Compare the azure-ai-landing-zone and cloud-native-app profiles"
```

## Resources

The server exposes governance profiles and the capability matrix as resources that AI agents can read for context.

## Related

- **Chat Participant** — For interactive VS Code Copilot Chat usage, see [`../copilot-participant/`](../copilot-participant/)
- **CLI Scripts** — For direct CLI usage, see [`../engine/`](../engine/)
- **GitHub Actions** — For CI/CD integration, see the `governance-*.yml` workflows
