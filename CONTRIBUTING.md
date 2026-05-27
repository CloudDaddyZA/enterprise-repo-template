# Contributing Guide

Thank you for your interest in contributing to this project! This document provides guidelines and information about contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)
- [Code Standards](#code-standards)
- [Testing](#testing)

## Code of Conduct

This project adheres to our Code of Conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the repository maintainers.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Create a feature branch from `main`
4. Set up your development environment (see [Dev Container](#dev-container))
5. Make your changes
6. Submit a pull request

### Dev Container

This repository includes a dev container configuration for consistent development environments:

```bash
# Open in VS Code with Dev Containers extension
code .

# Or use GitHub Codespaces
gh codespace create
```

## Development Workflow

We follow a trunk-based development workflow with the following branch conventions:

| Branch Pattern | Purpose |
|---|---|
| `main` | Production-ready code |
| `release/*` | Release preparation |
| `feature/*` | New features |
| `hotfix/*` | Critical production fixes |

### Creating a Feature Branch

```bash
git checkout main
git pull origin main
git checkout -b feature/your-feature-name
```

## Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages:

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description |
|---|---|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation changes |
| `style` | Code style changes (formatting, semicolons, etc.) |
| `refactor` | Code refactoring (no functional change) |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `build` | Build system or dependency changes |
| `ci` | CI/CD configuration changes |
| `chore` | Other changes (maintenance, tooling) |

### Examples

```
feat(auth): add OAuth2 login support
fix(api): handle null response in user endpoint
docs(readme): update installation instructions
ci(workflows): add CodeQL scanning
```

## Pull Request Process

1. Ensure your branch is up to date with `main`
2. Run all tests locally before submitting
3. Fill out the PR template completely
4. Request review from appropriate code owners
5. Address all review feedback
6. Ensure CI passes before merging

### PR Requirements

- [ ] Passes all CI checks
- [ ] Has at least one approving review from code owners
- [ ] Follows conventional commit format
- [ ] Includes tests for new functionality
- [ ] Documentation updated if needed

## Code Standards

- Follow the language-specific style guide for this project
- Use meaningful variable and function names
- Keep functions small and focused
- Comment complex logic (but prefer self-documenting code)
- No hardcoded secrets or credentials
- Handle errors appropriately

## Testing

- Write unit tests for all new functionality
- Maintain or improve code coverage
- Include integration tests for API changes
- Test edge cases and error scenarios

```bash
# Run tests locally
# (adjust for your language/framework)
npm test
dotnet test
go test ./...
pytest
```

## Questions?

If you have questions about contributing, please open a Discussion in the repository.
