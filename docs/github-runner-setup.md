# GitHub Runner Installation Guide

This guide provides step-by-step instructions for setting up the GitHub Actions runner on your EC2 instance to work with the repository-level runner infrastructure. The runner is configured at the repository level for your personal GitHub account, providing dedicated runner access with simplified permission requirements.

## Configuration Overview

### Repository-Level Runner (Default Configuration)
- **Scope**: Dedicated to a specific repository in your personal GitHub account
- **Management**: Per-repository configuration and control
- **Simplified Permissions**: Requires only `repo` scope GitHub PAT
- **Easy Switching**: Can be reconfigured for different repositories as needed
- **API Requirements**: GitHub PAT with `repo` scope only

## Prerequisites

- EC2 instance deployed using the Terraform configuration in this repository
- GitHub repository where you want to register the runner
- GitHub Personal Access Token (PAT) with `repo` scope
- Admin permissions on the target repository

### Repository-Level Prerequisites

For repository-level runner setup, you must have:

1. **Repository Admin Access**: You must have admin permissions on the target repository
2. **Repository Settings Access**: Ability to manage Actions settings at the repository level
3. **Runner Management Permissions**: Access to create, configure, and manage self-hosted runners for the repository
4. **API Access**: GitHub PAT with `repo` scope for repository-level API operations

### Verifying Repository Permissions

Check your repository permissions:

```bash
# Verify repository access and permissions
curl -H "Authorization: token $GH_PAT" \
  https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY

# Check repository permissions
curl -H "Authorization: token $GH_PAT" \
  https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/collaborators/$YOUR_USERNAME/permission
```

Expected response for admin access:
```json
{
  "permission": "admin",
  "user": {
    "login": "your-username"
  }
}
```

## Repository-Level Runner Configuration

### Repository-Level Runner Benefits
- **Dedicated Access**: Runner exclusively available to your specific repository
- **Simplified Permissions**: No organization admin permissions required
- **Easy Management**: Direct control over runner configuration and usage
- **Personal Control**: Full control over runner lifecycle and settings
- **Repository Isolation**: Complete isolation and security for your repository

## Required GitHub PAT Permissions

### For Repository-Level Runners
Your GitHub Personal Access Token must have the following scopes:
- `repo` (Full control of private repositories)

**Requirements for Repository-Level Setup:**
- The `repo` scope is **sufficient** for repository-level runner registration, token generation, and management operations
- You must have **admin permissions** on the target repository to register runners
- The PAT must be created by a user with repository admin access
- Repository-level runners use API access to `/repos/{owner}/{repo}/actions/runners/*` endpoints

## Manual Runner Installation

### Step 1: Connect to Your EC2 Instance

```bash
# Replace with your instance's public IP and key pair
ssh -i ~/.ssh/your-key-pair.pem ubuntu@<INSTANCE_PUBLIC_IP>
```

### Step 2: Create Runner Directory

```bash
# Create a directory for the GitHub runner
mkdir -p ~/actions-runner
cd ~/actions-runner
```

### Step 3: Download GitHub Actions Runner

```bash
# Download the latest runner package for Linux x64
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz

# Validate the hash (optional but recommended)
echo "29fc8cf2dab4c195bb147384e7e2c94cfd4d4022c793b346a6175435265aa278  actions-runner-linux-x64-2.311.0.tar.gz" | shasum -a 256 -c

# Extract the installer
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz
```

### Step 4: Get Registration Token

You need to obtain a registration token from GitHub before configuring the runner. Choose the appropriate method based on your runner configuration:

#### For Repository-Level Runners (Default Configuration)

**Repository-Level API Endpoint:**
```
POST https://api.github.com/repos/{owner}/{repo}/actions/runners/registration-token
```

**Using GitHub CLI (if installed):**
```bash
# Set repository details
export GITHUB_USERNAME="your-username"
export GITHUB_REPOSITORY="your-repository"

# Generate repository-level registration token
gh api -X POST /repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token
```

**Using curl with PAT (requires repo scope only):**
```bash
# Set your repository details and PAT
export GITHUB_USERNAME="your-username"
export GITHUB_REPOSITORY="your-repository"
export GH_PAT="ghp_your_personal_access_token"

# Generate repository-level registration token
curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_PAT" \
  https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token
```

**Example Response:**
```json
{
  "token": "AABF3JGZDX3P5PMEXLND6VK9DS2JSPBDNG",
  "expires_at": "2024-01-20T22:47:24Z"
}
```

**Important Notes:**
- Registration tokens expire after 1 hour
- The PAT requires only `repo` scope for repository-level token generation
- Repository admin permissions are required to generate registration tokens

### Step 5: Configure the Runner

#### For Repository-Level Runner (Default Configuration):

```bash
# Set your repository details and registration token
export GITHUB_USERNAME="your-username"
export GITHUB_REPOSITORY="your-repository"
export REGISTRATION_TOKEN="your-registration-token-from-api"

# Configure the runner for repository-specific access
./config.sh \
  --url https://github.com/$GITHUB_USERNAME/$GITHUB_REPOSITORY \
  --token $REGISTRATION_TOKEN \
  --name gha_aws_runner \
  --labels gha_aws_runner \
  --work _work \
  --unattended
```

**Repository-Level Configuration Parameters:**
- `--url`: Repository URL format: `https://github.com/{owner}/{repo}`
- `--token`: Registration token obtained from repository API (`/repos/{owner}/{repo}/actions/runners/registration-token`)
- `--name`: Unique runner name within the repository
- `--labels`: Custom labels for targeting this runner in repository workflows
- `--work`: Work directory for job execution
- `--unattended`: Non-interactive configuration mode

**Repository-Level Configuration Benefits:**
- **Dedicated Access**: Runner exclusively available to your repository
- **Persistent Registration**: Runner stays registered for multiple jobs
- **Simplified Management**: Direct control over runner lifecycle
- **Easy Switching**: Can be reconfigured for different repositories when needed

## Ephemeral Runner Configuration

The runner is configured with the `--ephemeral` flag, which provides several benefits for organization-level deployment:

- **Single-Use**: The runner will automatically unregister itself after completing one job
- **No Persistence**: No job history or artifacts are retained on the runner
- **Security**: Each job runs on a "clean" runner instance
- **Cost Optimization**: Reduces the need for manual cleanup
- **Organization Access**: When configured at organization level, the ephemeral runner can serve any repository within the organization

### Organization-Level Ephemeral Benefits

For organization-level runners, the ephemeral configuration provides:

1. **Cross-Repository Access**: Any repository in the organization can use the runner
2. **Job Queuing**: Multiple repositories can queue jobs; they execute sequentially
3. **Automatic Cleanup**: Runner unregisters after each job, ensuring clean state
4. **Centralized Management**: Organization admins can monitor all runner activity
5. **Resource Sharing**: Efficient utilization of compute resources across the organization

## Runner Labels and Targeting

The runner is configured with the label `gha_aws_runner`. Use this label in your workflow files to target the ephemeral runner:

### Organization-Level Usage
Any repository within the organization can use the runner:

```yaml
# In any repository within the organization
jobs:
  my-job:
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - name: Run on organization ephemeral runner
        run: echo "Running on AWS ephemeral runner from any repo"
```

### Repository-Level Usage
Only the specific repository can use the runner:

```yaml
# Only in the repository where runner is registered
jobs:
  my-job:
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - name: Run on repository ephemeral runner
        run: echo "Running on AWS ephemeral runner"
```

## Starting the Runner

### Manual Start (for testing):
```bash
# Start the runner interactively
./run.sh
```

### Service Installation (for persistent operation):
```bash
# Install as a service (run as root)
sudo ./svc.sh install

# Start the service
sudo ./svc.sh start

# Check service status
sudo ./svc.sh status
```

## Automated Runner Management

For production use, the GitHub Actions workflows in this repository handle runner lifecycle automatically. The workflows support both organization-level and repository-level runner management.

### Organization-Level Workflow Management

The automated workflows use organization-level API endpoints and can be triggered from any repository within the organization:

1. **start-runner job**: 
   - Starts EC2 instance using AWS CLI
   - Generates organization-level registration token
   - Registers runner at organization level using GitHub API
   - Makes runner available to all repositories in the organization

2. **your-job**: 
   - Runs on the ephemeral runner with label `gha_aws_runner`
   - Can be executed from any repository within the organization
   - Jobs are queued if multiple repositories trigger simultaneously

3. **stop-runner job**: 
   - Unregisters runner using organization-level GitHub API
   - Stops EC2 instance using AWS CLI
   - Cleans up runner registration from organization

### Required GitHub Secrets for Organization-Level Automation

The automated workflows require these secrets to be configured in the repository that manages the runner infrastructure:

```yaml
# AWS Configuration
AWS_ACCESS_KEY_ID: "AKIA..."
AWS_SECRET_ACCESS_KEY: "..."
AWS_REGION: "eu-west-1"
EC2_INSTANCE_ID: "i-1234567890abcdef0"

# GitHub Organization Configuration  
GH_PAT: "ghp_..."  # Must have 'repo' and 'admin:org' scopes
GITHUB_ORGANIZATION: "your-organization-name"
RUNNER_NAME: "gha_aws_runner"
```

### Cross-Repository Usage

Once the organization-level runner is active, any repository in the organization can use it:

```yaml
# In any repository within the organization
name: Use Organization Runner
on: [push]
jobs:
  build:
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - uses: actions/checkout@v4
      - name: Build on organization runner
        run: |
          echo "Building on shared organization runner"
          # Your build steps here
```

## Verification

### Check Runner Registration:

#### For Repository-Level Runners:
1. Go to your GitHub repository Settings (https://github.com/YOUR_USERNAME/YOUR_REPOSITORY/settings)
2. Navigate to Actions → Runners
3. Verify `gha_aws_runner` appears in the repository runners list with "Idle" status
4. Note: Repository runners are only visible and accessible to the specific repository

### Test Runner Functionality:
```bash
# On the EC2 instance, verify tools are available
docker --version
aws --version
python3 --version
java -version
terraform --version
kubectl version --client
helm version
```

## Troubleshooting

### Runner Registration Issues:

#### Organization-Level Registration:
- Verify your PAT has `admin:org` scope for organization-level operations
- Ensure you have organization admin permissions
- Check that the registration token hasn't expired (tokens expire after 1 hour)
- Verify the runner name `gha_aws_runner` is unique within the organization
- Confirm the organization URL format: `https://github.com/YOUR_ORGANIZATION`

#### Repository-Level Registration:
- Verify your PAT has `repo` scope for repository access
- Check that the registration token hasn't expired (tokens expire after 1 hour)
- Ensure the runner name `gha_aws_runner` is unique within the repository
- Confirm the repository URL format: `https://github.com/YOUR_USERNAME/YOUR_REPOSITORY`

#### Common Registration Errors:
```bash
# Error: HTTP 403 Forbidden
# Solution: Check PAT permissions and organization admin access

# Error: HTTP 404 Not Found  
# Solution: Verify organization/repository name and URL format

# Error: Runner name already exists
# Solution: Use a unique runner name or remove existing runner first
```

### Connection Issues:
- Verify security group allows HTTPS (443) outbound to GitHub IP ranges
- Check that the instance has internet connectivity
- Ensure GitHub.com and api.github.com are accessible from the instance

### Service Issues:
```bash
# Check runner service logs
sudo journalctl -u actions.runner.* -f

# Restart runner service
sudo ./svc.sh stop
sudo ./svc.sh start
```

### Network Connectivity Test:
```bash
# Test GitHub connectivity
curl -I https://github.com
curl -I https://api.github.com

# Test DNS resolution
nslookup github.com
nslookup api.github.com
```

## Organization-Level API Endpoints and Management

### Complete API Reference for Organization Runners

GitHub provides comprehensive API endpoints for managing organization-level runners. All endpoints require a PAT with `admin:org` scope.

#### Registration Token Generation:
```bash
POST /orgs/{org}/actions/runners/registration-token
```

#### List Organization Runners:
```bash
GET /orgs/{org}/actions/runners
```

#### Get Specific Organization Runner:
```bash
GET /orgs/{org}/actions/runners/{runner_id}
```

#### Remove Organization Runner:
```bash
DELETE /orgs/{org}/actions/runners/{runner_id}
```

#### List Organization Runner Applications:
```bash
GET /orgs/{org}/actions/runners/downloads
```

### API Authentication Requirements

All organization-level API calls require:
- **GitHub PAT**: Personal Access Token with `admin:org` scope
- **Organization Permissions**: User must have organization admin/owner role
- **API Headers**: 
  - `Accept: application/vnd.github.v3+json`
  - `Authorization: token {your_pat}`

### Organization Runner Management Examples

#### Generate Registration Token:
```bash
# Basic token generation
curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_PAT" \
  https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/registration-token

# With error handling and token extraction
RESPONSE=$(curl -s -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_PAT" \
  https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/registration-token)

REGISTRATION_TOKEN=$(echo $RESPONSE | jq -r '.token')
EXPIRES_AT=$(echo $RESPONSE | jq -r '.expires_at')

echo "Registration token: $REGISTRATION_TOKEN"
echo "Expires at: $EXPIRES_AT"
```

#### List All Organization Runners:
```bash
# List all runners with details
curl -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_PAT" \
  https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners

# List runners and extract specific information
curl -s -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_PAT" \
  https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners | \
  jq '.runners[] | {id: .id, name: .name, status: .status, labels: [.labels[].name]}'
```

#### Get Specific Runner Details:
```bash
# Get runner by ID
curl -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_PAT" \
  https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/$RUNNER_ID

# Find runner by name and get details
RUNNER_ID=$(curl -s -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_PAT" \
  https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners | \
  jq -r ".runners[] | select(.name==\"gha_aws_runner\") | .id")

echo "Runner ID for gha_aws_runner: $RUNNER_ID"
```

#### Remove a Specific Runner:
```bash
# Remove runner by ID
curl -X DELETE \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_PAT" \
  https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/$RUNNER_ID

# Remove runner by name (find ID first)
RUNNER_ID=$(curl -s -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_PAT" \
  https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners | \
  jq -r ".runners[] | select(.name==\"gha_aws_runner\") | .id")

if [ "$RUNNER_ID" != "null" ] && [ -n "$RUNNER_ID" ]; then
  curl -X DELETE \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: token $GH_PAT" \
    https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/$RUNNER_ID
  echo "Runner gha_aws_runner (ID: $RUNNER_ID) removed successfully"
else
  echo "Runner gha_aws_runner not found"
fi
```

#### List Available Runner Applications:
```bash
# Get download URLs for runner applications
curl -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_PAT" \
  https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/downloads
```

## Ephemeral Runner Configuration for Organization Access

### Understanding Ephemeral Runners in Organizations

Ephemeral runners are particularly powerful when configured at the organization level because they provide:

1. **Cross-Repository Availability**: Any repository in the organization can trigger jobs on the runner
2. **Automatic Cleanup**: Runner unregisters after each job, ensuring clean state for the next repository
3. **Security Isolation**: No persistent data between jobs from different repositories
4. **Cost Optimization**: Single runner instance can serve multiple repositories efficiently
5. **Queue Management**: Jobs from multiple repositories are queued and executed sequentially

### Ephemeral Configuration Requirements

For organization-level ephemeral runners, ensure:

- **Registration URL**: Must use organization URL format (`https://github.com/{org}`)
- **API Endpoints**: Use organization-level API endpoints for token generation and management
- **PAT Permissions**: GitHub PAT must have `admin:org` scope
- **Runner Labels**: Use consistent labels across the organization for workflow targeting
- **Ephemeral Flag**: Always include `--ephemeral` flag in runner configuration

### Organization Ephemeral Runner Workflow

1. **Job Trigger**: Any repository in the organization triggers a workflow that requires the runner
2. **Runner Activation**: If runner is idle, it picks up the job immediately
3. **Job Execution**: Runner executes the job with access to the triggering repository's code
4. **Automatic Cleanup**: Runner unregisters itself after job completion
5. **Next Job Ready**: Runner is ready for the next job from any repository in the organization

### Cross-Repository Usage Examples

#### Repository A Workflow:
```yaml
# In repository: org/frontend-app
name: Frontend Build
on: [push]
jobs:
  build:
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - uses: actions/checkout@v4
      - name: Build frontend
        run: npm run build
```

#### Repository B Workflow:
```yaml
# In repository: org/backend-api  
name: Backend Tests
on: [push]
jobs:
  test:
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: python -m pytest
```

Both workflows can use the same organization-level ephemeral runner, with jobs queued if triggered simultaneously.

### Organization Runner Configuration Script

Here's a complete script for organization-level ephemeral runner setup:

```bash
#!/bin/bash
set -e

# Organization-level ephemeral runner configuration script
# Requires: GitHub PAT with admin:org scope, organization admin permissions

# Configuration variables
GITHUB_ORGANIZATION="${GITHUB_ORGANIZATION:-your-organization}"
GH_PAT="${GH_PAT:-your-personal-access-token}"
RUNNER_NAME="${RUNNER_NAME:-gha_aws_runner}"

echo "=== Organization-Level Ephemeral Runner Setup ==="
echo "Organization: $GITHUB_ORGANIZATION"
echo "Runner Name: $RUNNER_NAME"

# Validate prerequisites
if [ -z "$GITHUB_ORGANIZATION" ] || [ "$GITHUB_ORGANIZATION" = "your-organization" ]; then
  echo "Error: Please set GITHUB_ORGANIZATION environment variable"
  exit 1
fi

if [ -z "$GH_PAT" ] || [ "$GH_PAT" = "your-personal-access-token" ]; then
  echo "Error: Please set GH_PAT environment variable with admin:org scope"
  exit 1
fi

# Verify organization access
echo "Verifying organization access..."
ORG_CHECK=$(curl -s -H "Authorization: token $GH_PAT" \
  https://api.github.com/orgs/$GITHUB_ORGANIZATION)

if echo "$ORG_CHECK" | grep -q "Not Found"; then
  echo "Error: Organization not found or insufficient permissions"
  echo "Ensure your PAT has admin:org scope and you have organization admin access"
  exit 1
fi

echo "Organization access verified."

# Generate registration token
echo "Generating organization-level registration token..."
RESPONSE=$(curl -s -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GH_PAT" \
  https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/registration-token)

REGISTRATION_TOKEN=$(echo $RESPONSE | jq -r '.token')
EXPIRES_AT=$(echo $RESPONSE | jq -r '.expires_at')

if [ "$REGISTRATION_TOKEN" = "null" ]; then
  echo "Failed to generate registration token."
  echo "Response: $RESPONSE"
  echo "Check your PAT permissions (requires admin:org scope)"
  exit 1
fi

echo "Registration token generated successfully."
echo "Token expires at: $EXPIRES_AT"

# Check if runner already exists
echo "Checking for existing runner..."
EXISTING_RUNNER=$(curl -s -H "Authorization: token $GH_PAT" \
  https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners | \
  jq -r ".runners[] | select(.name==\"$RUNNER_NAME\") | .id")

if [ -n "$EXISTING_RUNNER" ] && [ "$EXISTING_RUNNER" != "null" ]; then
  echo "Warning: Runner '$RUNNER_NAME' already exists (ID: $EXISTING_RUNNER)"
  echo "Removing existing runner..."
  curl -s -X DELETE \
    -H "Authorization: token $GH_PAT" \
    https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/$EXISTING_RUNNER
  echo "Existing runner removed."
fi

# Configure the ephemeral runner for organization access
echo "Configuring ephemeral runner for organization access..."
./config.sh \
  --url https://github.com/$GITHUB_ORGANIZATION \
  --token $REGISTRATION_TOKEN \
  --name $RUNNER_NAME \
  --labels gha_aws_runner \
  --ephemeral \
  --unattended

echo "=== Runner Configuration Complete ==="
echo "Organization: $GITHUB_ORGANIZATION"
echo "Runner Name: $RUNNER_NAME"
echo "Configuration: Ephemeral (single-use)"
echo "Access: All repositories in organization"
echo "Labels: gha_aws_runner"
echo ""
echo "The runner is now configured and ready to accept jobs from any repository"
echo "in the '$GITHUB_ORGANIZATION' organization."
echo ""
echo "To start the runner:"
echo "  ./run.sh"
echo ""
echo "To install as a service:"
echo "  sudo ./svc.sh install"
echo "  sudo ./svc.sh start"
```

## Security Considerations

### Organization-Level Security:
- Organization runners have access to all repositories within the organization
- Use ephemeral runners to minimize security exposure across repositories
- Implement organization-level security policies and runner access controls
- Monitor runner activity across all organization repositories
- Consider repository-specific runners for highly sensitive operations

### General Security:
- The runner has access to repository code during job execution
- Regularly rotate your GitHub PAT
- Monitor runner activity in GitHub Actions logs
- Use secrets management for sensitive data
- Implement proper network security groups and access controls

## Next Steps

### For Organization-Level Deployment (Recommended)

After setting up the organization-level runner, you can:

1. **Use Automated Workflows**: Leverage the GitHub Actions workflows in this repository for automated runner lifecycle management
2. **Cross-Repository Access**: Configure workflows in any repository within your organization to use the shared runner
3. **Centralized Management**: Monitor and manage all runner activity from the organization settings
4. **Cost Optimization**: Benefit from shared resource utilization across multiple repositories
5. **Scaling**: Add additional runners or modify instance types based on organization-wide usage patterns

### For Repository-Level Deployment

After setting up the repository-level runner:

1. **Dedicated Resources**: Use the runner exclusively for the specific repository
2. **Isolated Environment**: Maintain complete isolation from other repositories
3. **Custom Configuration**: Tailor the runner configuration to repository-specific requirements

### Integration with CI/CD Pipelines

Both deployment types support:
- Automated runner lifecycle management
- Cost-optimized start/stop operations  
- Integration with existing CI/CD workflows
- Custom tool installations and configurations

### Documentation References

- **Main README.md**: Complete usage instructions and workflow examples
- **Terraform Configuration**: Infrastructure setup and customization options
- **GitHub Actions Workflows**: Example implementations for both organization and repository levels

### Monitoring and Maintenance

- **Organization Level**: Monitor runner usage across all repositories in organization settings
- **Repository Level**: Monitor runner activity in individual repository settings
- **AWS Costs**: Track EC2 instance usage and optimize based on actual workflow patterns
- **Security**: Regularly review runner access logs and rotate GitHub PATs