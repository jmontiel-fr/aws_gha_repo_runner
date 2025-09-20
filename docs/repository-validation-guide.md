# Repository Configuration Validation Guide

This guide explains how to use the repository configuration validation functions for the personal repository runner setup.

## Overview

The validation functions library (`scripts/repo-validation-functions.sh`) provides comprehensive validation for repository-level GitHub Actions runner configuration. It validates:

- Repository existence and accessibility
- GitHub PAT scope and permissions
- Repository admin permissions
- GitHub Actions availability
- Runner registration capabilities

## Quick Start

### Basic Usage

```bash
# Source the validation library
source scripts/repo-validation-functions.sh

# Run comprehensive validation
validate_repository_configuration "username" "repository" "pat_token"
```

### Environment Variables

Set these environment variables for easier testing:

```bash
export GITHUB_USERNAME="your-github-username"
export GITHUB_REPOSITORY="your-repository-name"
export GH_PAT="ghp_your_personal_access_token"
```

### Test the Validation Functions

```bash
# Run the test suite
./scripts/test-repo-validation.sh

# Test with live credentials (optional)
export GITHUB_USERNAME="your-username"
export GITHUB_REPOSITORY="your-repo"
export GH_PAT="your-token"
./scripts/test-repo-validation.sh
```

## Available Validation Functions

### Repository Existence Validation

#### `validate_repository_exists <username> <repository> <pat>`
Validates that a repository exists and is accessible.

**Returns:** 0 on success, 1 on failure

**Example:**
```bash
if validate_repository_exists "myuser" "myrepo" "$GH_PAT"; then
    echo "Repository exists and is accessible"
fi
```

#### `validate_actions_enabled <username> <repository> <pat>`
Checks if GitHub Actions is enabled for the repository.

**Returns:** 0 if enabled, 1 if disabled or error

### Repository Access Validation

#### `validate_repository_access <username> <repository> <pat>`
Validates repository access permissions for the authenticated user.

**Returns:** 0 on success, 1 on failure

**Checks:**
- Repository exists
- User has pull access
- User has push access (warning if missing)

### PAT Scope Validation

#### `validate_pat_repo_scope <pat>`
Validates GitHub PAT has required repo scope.

**Returns:** 0 if valid, 1 if invalid

**Checks:**
- PAT authentication works
- PAT has repo scope access
- PAT can access user repositories

#### `validate_pat_no_admin_org <pat>`
Security check to verify PAT doesn't have excessive admin:org permissions.

**Returns:** 0 (always succeeds, provides warnings only)

### Admin Permission Validation

#### `validate_repository_admin_permissions <username> <repository> <pat>`
Verifies user has admin permissions on the repository.

**Returns:** 0 if admin, 1 if not admin or error

#### `validate_runner_registration_access <username> <repository> <pat>`
Tests runner registration token generation (ultimate admin permission test).

**Returns:** 0 if can generate token, 1 if cannot

### Comprehensive Validation

#### `validate_repository_configuration <username> <repository> <pat>`
Runs all repository configuration validations in sequence.

**Returns:** 0 if all validations pass, 1 if any fail

**Validation Steps:**
1. PAT Scope Validation
2. Repository Existence Validation
3. Repository Access Validation
4. Admin Permission Validation
5. GitHub Actions Validation
6. Runner Registration Test
7. Security Validation

### Utility Functions

#### `validate_user_authentication <pat>`
Validates user authentication and returns username.

#### `validate_username_format <username>`
Validates GitHub username format.

#### `validate_repository_format <repository>`
Validates GitHub repository name format.

#### `validate_required_tools`
Checks if required tools (curl, jq) are available.

## Integration with Runner Setup Script

The `repo-runner-setup.sh` script automatically uses the validation library:

```bash
# Validate configuration only (no runner setup)
./scripts/repo-runner-setup.sh --validate-only

# Full setup with validation
export GITHUB_USERNAME="your-username"
export GITHUB_REPOSITORY="your-repo"
export GH_PAT="your-token"
./scripts/repo-runner-setup.sh
```

## Error Handling

The validation functions provide detailed error messages for common issues:

### Authentication Errors
- **401 Unauthorized:** PAT is invalid or expired
- **403 Forbidden:** PAT lacks required permissions

### Repository Errors
- **404 Not Found:** Repository doesn't exist or no access
- **Repository archived:** Actions may be limited
- **Repository disabled:** Cannot use Actions

### Permission Errors
- **No admin access:** Cannot manage runners
- **Actions disabled:** Enable in repository settings
- **Invalid PAT scope:** Ensure 'repo' scope is included

## Security Best Practices

1. **Use minimal PAT scope:** Only 'repo' scope is required
2. **Avoid admin:org scope:** Not needed for repository-level runners
3. **Rotate PATs regularly:** Recommended every 90 days
4. **Validate permissions:** Always run validation before setup

## Troubleshooting

### Common Issues

#### "Missing required tools: jq"
Install jq JSON processor:
```bash
# On Ubuntu/Debian
sudo apt-get install jq

# On macOS
brew install jq

# On Windows (Git Bash)
curl -L -o jq.exe https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-win64.exe
```

#### "Repository not found or insufficient permissions"
1. Verify repository name is correct
2. Ensure repository exists
3. Check PAT has 'repo' scope
4. Verify you have access to the repository

#### "Insufficient repository permissions"
1. Ensure you have admin permissions on the repository
2. Contact repository owner to grant admin access
3. Verify PAT scope includes repository administration

#### "GitHub Actions is not enabled"
1. Go to repository Settings → Actions → General
2. Enable Actions for the repository
3. Configure Actions permissions as needed

### Debug Mode

For detailed debugging, you can examine individual validation steps:

```bash
# Source the library
source scripts/repo-validation-functions.sh

# Run individual validations
validate_pat_repo_scope "$GH_PAT"
validate_repository_exists "$GITHUB_USERNAME" "$GITHUB_REPOSITORY" "$GH_PAT"
validate_repository_admin_permissions "$GITHUB_USERNAME" "$GITHUB_REPOSITORY" "$GH_PAT"
```

## Requirements Mapping

This validation library addresses the following requirements from the specification:

- **Requirement 2.2:** PAT scope validation for repo-only access
- **Requirement 2.4:** Repository admin permission verification  
- **Requirement 3.2:** Repository existence and access validation
- **Requirement 3.3:** Repository accessibility verification
- **Requirement 3.5:** Clear error messages for configuration issues

## Examples

### Basic Validation
```bash
#!/bin/bash
source scripts/repo-validation-functions.sh

USERNAME="myuser"
REPOSITORY="myrepo"
PAT="ghp_xxxxxxxxxxxxxxxxxxxx"

if validate_repository_configuration "$USERNAME" "$REPOSITORY" "$PAT"; then
    echo "✅ Configuration is valid - ready for runner setup"
else
    echo "❌ Configuration validation failed"
    exit 1
fi
```

### Custom Validation Workflow
```bash
#!/bin/bash
source scripts/repo-validation-functions.sh

# Step 1: Validate tools
if ! validate_required_tools; then
    echo "Please install required tools"
    exit 1
fi

# Step 2: Validate formats
if ! validate_username_format "$USERNAME"; then
    exit 1
fi

if ! validate_repository_format "$REPOSITORY"; then
    exit 1
fi

# Step 3: Validate GitHub access
if ! validate_pat_repo_scope "$PAT"; then
    exit 1
fi

# Step 4: Validate repository
if ! validate_repository_exists "$USERNAME" "$REPOSITORY" "$PAT"; then
    exit 1
fi

# Step 5: Validate permissions
if ! validate_repository_admin_permissions "$USERNAME" "$REPOSITORY" "$PAT"; then
    exit 1
fi

echo "All validations passed!"
```

## Library Information

To see available functions and usage information:

```bash
# Show library info
./scripts/repo-validation-functions.sh

# Or source and call directly
source scripts/repo-validation-functions.sh
show_validation_library_info
```