# Governance Copilot Chat Participant

VS Code extension that registers a `@governance` chat participant in GitHub Copilot Chat, providing conversational access to the governance engine.

## Quick Start

```bash
cd governance/copilot-participant
npm install
npm run build
```

Press **F5** in VS Code to launch a development host with the extension loaded.

## Commands

| Command      | Description                      | Example                                                                 |
| ------------ | -------------------------------- | ----------------------------------------------------------------------- |
| `/create`    | Create a new governed repository | `@governance /create azure-ai-landing-zone my-repo team-slug "Project"` |
| `/assess`    | Assess compliance                | `@governance /assess cloud-native-app my-org/my-repo`                   |
| `/remediate` | Fix governance gaps              | `@governance /remediate data-platform my-org/my-repo safe`              |
| `/profiles`  | List governance profiles         | `@governance /profiles`                                                 |
| `/report`    | Generate compliance report       | `@governance /report azure-ai-landing-zone my-org/my-repo`              |
| `/azure`     | Azure OIDC/RBAC/KV setup         | `@governance /azure azure-ai-landing-zone my-org/my-repo <sub-id>`      |

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│  VS Code Copilot Chat                                   │
│                                                         │
│  User: @governance /assess cloud-native-app org/repo    │
│                                                         │
│  ┌───────────────────────────────┐                      │
│  │ Chat Participant Extension    │                      │
│  │  → Parses command + args      │                      │
│  │  → Calls engine scripts       │                      │
│  │  → Formats response stream    │                      │
│  └───────────────┬───────────────┘                      │
│                  │                                       │
│                  ▼                                       │
│  ┌───────────────────────────────┐                      │
│  │ governance/engine/*.sh        │                      │
│  │  assess-repo.sh               │                      │
│  │  create-repo.sh               │                      │
│  │  remediate-repo.sh            │                      │
│  └───────────────────────────────┘                      │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- VS Code 1.93+ with GitHub Copilot Chat
- `gh` CLI (authenticated)
- `yq` and `jq` installed
- `GH_TOKEN` environment variable (for governance operations)

## Development

```bash
# Watch mode (recompile on changes)
npm run watch

# Package as VSIX
npm run package
```

## Difference from MCP Server

| Feature   | Chat Participant              | MCP Server                        |
| --------- | ----------------------------- | --------------------------------- |
| Interface | `@governance` in Copilot Chat | Any MCP-compatible AI agent       |
| Protocol  | VS Code Extension API         | Model Context Protocol (stdio)    |
| Setup     | Install extension             | Configure in `.vscode/mcp.json`   |
| Best for  | Interactive VS Code users     | Automation, multi-agent workflows |

Both delegate to the same underlying engine scripts — choose based on your workflow.

## Related

- [MCP Server](../mcp-server/) — For agent-to-agent and automation use cases
- [Engine Scripts](../engine/) — Direct CLI usage
- [Governance README](../README.md) — Full governance engine documentation
