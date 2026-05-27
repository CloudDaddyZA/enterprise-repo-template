# Source Code

This directory contains the application source code.

## Structure

Organize your source code based on your project's needs:

### Monorepo Layout

```
src/
├── services/
│   ├── api/           # Backend API service
│   ├── web/           # Frontend web application
│   └── worker/        # Background worker service
├── packages/
│   ├── shared/        # Shared libraries
│   └── config/        # Shared configuration
└── README.md
```

### Single Service Layout

```
src/
├── controllers/       # Request handlers
├── services/          # Business logic
├── models/            # Data models
├── middleware/        # HTTP middleware
├── utils/             # Utility functions
└── config/            # Application configuration
```

## Guidelines

- Follow the project's coding standards (see CONTRIBUTING.md)
- Keep modules focused and loosely coupled
- Use dependency injection where appropriate
- Document public APIs
- No secrets or credentials in source code
