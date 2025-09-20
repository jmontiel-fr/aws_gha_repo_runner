# Repository-Level Runner Migration Guide

This guide provides step-by-step instructions for migrating from organization-level GitHub Actions runners to repository-level runners for personal GitHub accounts. The migration simplifies permissions, reduces administrative overhead, and provides dedicated runner access for individual repositories.

## Migration Overview

### What Changes in Repository-Level Setup

| Aspect | Organization-Level | Repository-Level |
|--------|-------------------|------------------|
| **Scope** | All repositories in organization | Single repository only |
| **GitHub PAT** | `repo` + `admin:org` scopes | `repo` scope only |
| **Permissions** | Organization admin required | Repository admin required |
| **API Endpoints** | `/orgs/{org}/actions/runners/*` | `/repos/{owner}/{repo}/actions/runners/*` |
| **Runner URL** | `https://github.com/{org}` | `https://github.com/{owner}/{repo}` |
| **Access Control** | Organization-wide | Repository-specific |
| **Management** | Centralized organization control | Individual repository control |

### Benefits of Repository-Level Migration

- **Simplified Permissions**: No organization admin permissions required
- **Reduced Scope**: GitHub PAT only needs `repo` scope
- **Personal Control**: Full control over runner without organization dependencies
- **Dedicated Resources**: Runner exclusively available to your repository
- **Easy Setup**: Simpler configuration and management process
- **Repository Isolation**: Complete isolation from other repositories

## Pre-Migration Checklist

Before starting the migration, ensure you have:

- [ ] **Repository Admin Access**: Admin permissions on the target repository
- [ ] **GitHub PAT**: Personal Access Token with `repo` scope
- [ ] **AWS Access**: Existing EC2 instance and AWS credentials
- [ ] **Backup**: Current runner configuration documented
- [ ] **Downtime Window**: Planned maintenance window for migration
- [ ] **Testing Repository**: Test repository for validation (optional but recommended)

### Verify Current Setup

Document your current organization-level configuration:

```bash
# Document current organization setup
echo "=== Current Organization Setup ==="
echo "Organization: $GITHUB_ORGANIZATION"
echo "Runner Name: $RUNNER_NAME"
echo "EC2 Instance: $EC2_INSTANCE_ID"

# List current organization runners
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners" | \
  jq '.runners[] | {name: .name, status: .status, labels: [.labels[].name]}'

# Check current runner configuration on EC2
ssh ubuntu@$INSTANCE_IP 'cd ~/actions-runner && cat .runner | jq .'
```

## Migration Process

### Phase 1: Preparation

#### Step 1: Create Repository-Specific GitHub PAT

1. **Generate New PAT** (recommended for clean separation):
   - Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Click "Generate new token (classic)"
   - Set expiration and note: "Repository Runner - [REPO_NAME]"
   - Select scopes: **Only `repo` (Full control of private repositories)**
   - Click "Generate token" and save securely

2. **Verify PAT Permissions**:
```bash
# Test new PAT with repository access
export GH_PAT_REPO="your_new_repository_pat"
export GITHUB_USERNAME="your-username"
export GITHUB_REPOSITORY="your-repository"

# Verify repository access
curl -H "Authorization: token $GH_PAT_REPO" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY" | \
  jq '{name: .name, private: .private, permissions: .permissions}'

# Verify admin permissions
curl -H "Authorization: token $GH_PAT_REPO" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/collaborators/$GITHUB_USERNAME/permission" | \
  jq '.permission'
```

Expected response: `"admin"`

#### Step 2: Update Repository Secrets

Configure repository-specific secrets in your target repository:

1. **Navigate to Repository Settings**:
   - Go to `https://github.com/{username}/{repository}/settings`
   - Click "Secrets and variables" → "Actions"

2. **Add Required Secrets**:
```yaml
# Repository Secrets (Settings → Secrets and variables → Actions)
AWS_ACCESS_KEY_ID: "AKIA..."           # Same as organization setup
AWS_SECRET_ACCESS_KEY: "wJal..."       # Same as organization setup  
AWS_REGION: "eu-west-1"                # Same as organization setup
GH_PAT: "ghp_..."                      # NEW: Repository-scoped PAT
EC2_INSTANCE_ID: "i-1234567890abcdef0" # Same as organization setup
RUNNER_NAME: "gha_aws_runner"          # Can be same or different
GITHUB_USERNAME: "your-username"       # NEW: Your GitHub username
GITHUB_REPOSITORY: "your-repository"   # NEW: Repository name
```

3. **Verify Secret Configuration**:
   - Ensure all secrets are properly set
   - Test access by running a simple workflow (optional)

#### Step 3: Backup Current Configuration

Create a backup of your current setup:

```bash
# Create backup directory
mkdir -p ~/runner-migration-backup/$(date +%Y%m%d)
cd ~/runner-migration-backup/$(date +%Y%m%d)

# Backup current runner configuration
ssh ubuntu@$INSTANCE_IP 'cd ~/actions-runner && tar czf - .runner .credentials .credentials_rsaparams' > runner-config-backup.tar.gz

# Backup current environment variables
cat > current-config.env << EOF
GITHUB_ORGANIZATION=$GITHUB_ORGANIZATION
GH_PAT=$GH_PAT
RUNNER_NAME=$RUNNER_NAME
EC2_INSTANCE_ID=$EC2_INSTANCE_ID
AWS_REGION=$AWS_REGION
EOF

# Document current organization runners
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners" > org-runners-backup.json

echo "Backup created in $(pwd)"
```

### Phase 2: Migration Execution

#### Step 1: Stop Organization Runner

```bash
# Set organization environment variables
export GITHUB_ORGANIZATION="your-organization"
export GH_PAT="your_org_pat"
export EC2_INSTANCE_ID="i-1234567890abcdef0"

# Get instance IP
INSTANCE_IP=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo "Stopping organization runner on $INSTANCE_IP"

# SSH to instance and stop runner service
ssh ubuntu@$INSTANCE_IP << 'EOF'
cd ~/actions-runner

# Stop the runner service
sudo ./svc.sh stop
echo "Runner service stopped"

# Uninstall the service
sudo ./svc.sh uninstall
echo "Runner service uninstalled"
EOF
```

#### Step 2: Unregister from Organization

```bash
# Get current runner ID
RUNNER_ID=$(curl -s -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners" | \
  jq -r ".runners[] | select(.name==\"$RUNNER_NAME\") | .id")

if [ "$RUNNER_ID" != "null" ] && [ -n "$RUNNER_ID" ]; then
    echo "Unregistering runner ID $RUNNER_ID from organization"
    
    # Remove runner from organization
    curl -X DELETE \
      -H "Authorization: token $GH_PAT" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/$RUNNER_ID"
    
    echo "Runner unregistered from organization"
else
    echo "Runner not found in organization or already unregistered"
fi

# Remove runner configuration on instance
ssh ubuntu@$INSTANCE_IP << 'EOF'
cd ~/actions-runner

# Remove existing configuration
sudo -u ubuntu ./config.sh remove --token dummy_token || true
echo "Runner configuration removed"
EOF
```

#### Step 3: Configure Repository Runner

```bash
# Set repository environment variables
export GITHUB_USERNAME="your-username"
export GITHUB_REPOSITORY="your-repository"
export GH_PAT_REPO="your_repository_pat"
export RUNNER_NAME="gha_aws_runner"

echo "Configuring repository runner for $GITHUB_USERNAME/$GITHUB_REPOSITORY"

# Generate repository registration token
REGISTRATION_TOKEN=$(curl -s -X POST \
  -H "Authorization: token $GH_PAT_REPO" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token" | \
  jq -r '.token')

if [ "$REGISTRATION_TOKEN" = "null" ] || [ -z "$REGISTRATION_TOKEN" ]; then
    echo "Failed to generate registration token. Check PAT permissions."
    exit 1
fi

echo "Registration token generated successfully"

# Configure runner for repository
ssh ubuntu@$INSTANCE_IP << EOF
cd ~/actions-runner

echo "Configuring runner for repository access..."

# Configure the runner
sudo -u ubuntu ./config.sh \
  --url https://github.com/$GITHUB_USERNAME/$GITHUB_REPOSITORY \
  --token $REGISTRATION_TOKEN \
  --name $RUNNER_NAME \
  --labels gha_aws_runner \
  --work _work \
  --unattended \
  --replace

echo "Runner configured for repository"

# Install and start service
sudo ./svc.sh install ubuntu
sudo ./svc.sh start

echo "Runner service installed and started"
EOF
```

#### Step 4: Verify Repository Registration

```bash
# Wait for runner to register
echo "Waiting for runner registration..."
sleep 30

# Check repository runners
echo "Checking repository runners..."
curl -s -H "Authorization: token $GH_PAT_REPO" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners" | \
  jq '.runners[] | {name: .name, status: .status, labels: [.labels[].name]}'

# Verify runner appears in repository settings
echo ""
echo "✓ Migration complete! Verify runner appears in:"
echo "  https://github.com/$GITHUB_USERNAME/$GITHUB_REPOSITORY/settings/actions/runners"
```

### Phase 3: Update Workflows

#### Step 1: Create Repository Workflow Files

Create the repository-level workflow files in your repository:

```bash
# Create workflows directory
mkdir -p .github/workflows

# Create repository runner demo workflow
cat > .github/workflows/runner-demo.yml << 'EOF'
name: Repository Self-Hosted Runner Demo
on: 
  workflow_dispatch:
    inputs:
      job_type:
        description: 'Type of job to run'
        required: true
        default: 'build'
        type: choice
        options:
        - build
        - test
        - deploy

jobs:
  start-runner:
    name: Start self-hosted EC2 runner
    runs-on: ubuntu-latest
    outputs:
      runner-name: ${{ steps.start.outputs.runner-name }}
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Start EC2 instance
        id: start-ec2
        run: |
          aws ec2 start-instances --instance-ids ${{ secrets.EC2_INSTANCE_ID }}
          aws ec2 wait instance-running --instance-ids ${{ secrets.EC2_INSTANCE_ID }}
          
          # Get instance IP
          INSTANCE_IP=$(aws ec2 describe-instances \
            --instance-ids ${{ secrets.EC2_INSTANCE_ID }} \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text)
          echo "instance-ip=$INSTANCE_IP" >> $GITHUB_OUTPUT

      - name: Generate registration token
        id: token
        run: |
          TOKEN=$(curl -s -X POST \
            -H "Authorization: token ${{ secrets.GH_PAT }}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners/registration-token" | \
            jq -r '.token')
          echo "registration-token=$TOKEN" >> $GITHUB_OUTPUT

      - name: Register runner with repository
        run: |
          # Wait for instance to be ready
          sleep 30
          
          # SSH and configure runner (implement based on your SSH setup)
          echo "Runner registration would happen here"
          echo "Use your SSH key and method to connect to instance"

      - name: Set runner name output
        id: start
        run: echo "runner-name=${{ secrets.RUNNER_NAME }}" >> $GITHUB_OUTPUT

  your-job:
    name: Run job on self-hosted runner
    needs: start-runner
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Show runner environment
        run: |
          echo "=== Runner Environment ==="
          echo "Runner name: ${{ needs.start-runner.outputs.runner-name }}"
          echo "Repository: ${{ github.repository }}"
          echo "Workflow: ${{ github.workflow }}"
          echo "Job type: ${{ github.event.inputs.job_type }}"
          echo ""
          echo "=== System Information ==="
          uname -a
          echo ""
          echo "=== Available Tools ==="
          docker --version || echo "Docker not available"
          aws --version || echo "AWS CLI not available"
          python3 --version || echo "Python3 not available"

      - name: Run job based on input
        run: |
          case "${{ github.event.inputs.job_type }}" in
            "build")
              echo "Running build job..."
              # Add your build commands here
              ;;
            "test")
              echo "Running test job..."
              # Add your test commands here
              ;;
            "deploy")
              echo "Running deploy job..."
              # Add your deploy commands here
              ;;
          esac

  stop-runner:
    name: Stop self-hosted EC2 runner
    needs: [start-runner, your-job]
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Unregister runner from repository
        run: |
          # Get runner ID
          RUNNER_ID=$(curl -s \
            -H "Authorization: token ${{ secrets.GH_PAT }}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners" | \
            jq -r ".runners[] | select(.name==\"${{ secrets.RUNNER_NAME }}\") | .id")
          
          if [ "$RUNNER_ID" != "null" ] && [ -n "$RUNNER_ID" ]; then
            echo "Unregistering runner ID: $RUNNER_ID"
            curl -X DELETE \
              -H "Authorization: token ${{ secrets.GH_PAT }}" \
              -H "Accept: application/vnd.github.v3+json" \
              "https://api.github.com/repos/${{ github.repository }}/actions/runners/$RUNNER_ID"
          else
            echo "Runner not found or already unregistered"
          fi

      - name: Stop EC2 instance
        run: |
          aws ec2 stop-instances --instance-ids ${{ secrets.EC2_INSTANCE_ID }}
          echo "EC2 instance stopped: ${{ secrets.EC2_INSTANCE_ID }}"
EOF

# Create manual runner configuration workflow
cat > .github/workflows/configure-runner.yml << 'EOF'
name: Configure Repository Runner
on:
  workflow_dispatch:
    inputs:
      action:
        description: 'Runner action'
        required: true
        default: 'configure'
        type: choice
        options:
        - configure
        - remove
        - status

jobs:
  manage-runner:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Get EC2 instance status
        id: ec2-status
        run: |
          STATUS=$(aws ec2 describe-instances \
            --instance-ids ${{ secrets.EC2_INSTANCE_ID }} \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text)
          echo "status=$STATUS" >> $GITHUB_OUTPUT
          echo "EC2 instance status: $STATUS"

      - name: Start EC2 if needed
        if: steps.ec2-status.outputs.status != 'running'
        run: |
          echo "Starting EC2 instance..."
          aws ec2 start-instances --instance-ids ${{ secrets.EC2_INSTANCE_ID }}
          aws ec2 wait instance-running --instance-ids ${{ secrets.EC2_INSTANCE_ID }}

      - name: Configure runner
        if: github.event.inputs.action == 'configure'
        run: |
          # Generate registration token
          TOKEN=$(curl -s -X POST \
            -H "Authorization: token ${{ secrets.GH_PAT }}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners/registration-token" | \
            jq -r '.token')
          
          echo "Registration token generated for repository ${{ github.repository }}"
          echo "Configure runner manually using SSH with this token"

      - name: Remove runner
        if: github.event.inputs.action == 'remove'
        run: |
          # Get runner ID and remove
          RUNNER_ID=$(curl -s \
            -H "Authorization: token ${{ secrets.GH_PAT }}" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners" | \
            jq -r ".runners[] | select(.name==\"${{ secrets.RUNNER_NAME }}\") | .id")
          
          if [ "$RUNNER_ID" != "null" ] && [ -n "$RUNNER_ID" ]; then
            curl -X DELETE \
              -H "Authorization: token ${{ secrets.GH_PAT }}" \
              "https://api.github.com/repos/${{ github.repository }}/actions/runners/$RUNNER_ID"
            echo "Runner removed from repository"
          fi

      - name: Show runner status
        if: github.event.inputs.action == 'status'
        run: |
          echo "=== Repository Runners ==="
          curl -s \
            -H "Authorization: token ${{ secrets.GH_PAT }}" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners" | \
            jq -r '.runners[] | "Name: \(.name), Status: \(.status), Labels: \([.labels[].name] | join(","))"'
EOF

echo "Workflow files created in .github/workflows/"
```

#### Step 2: Commit and Test Workflows

```bash
# Add and commit workflow files
git add .github/workflows/
git commit -m "Add repository-level runner workflows"
git push origin main

echo ""
echo "✓ Workflows committed. Test by:"
echo "  1. Go to Actions tab in your repository"
echo "  2. Run 'Configure Repository Runner' workflow"
echo "  3. Run 'Repository Self-Hosted Runner Demo' workflow"
```

### Phase 4: Validation and Testing

#### Step 1: Validate Runner Registration

```bash
# Comprehensive validation script
cat > validate-migration.sh << 'EOF'
#!/bin/bash

set -e

echo "=== Repository Runner Migration Validation ==="
echo "Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
echo "Timestamp: $(date -u)"
echo ""

# Test 1: Repository API Access
echo "=== 1. Repository API Access ==="
REPO_RESPONSE=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT_REPO" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY")
REPO_HTTP_CODE="${REPO_RESPONSE: -3}"

if [ "$REPO_HTTP_CODE" = "200" ]; then
    echo "✓ Repository API access working"
else
    echo "✗ Repository API access failed (HTTP $REPO_HTTP_CODE)"
    exit 1
fi

# Test 2: Repository Runners
echo ""
echo "=== 2. Repository Runners ==="
RUNNERS_RESPONSE=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT_REPO" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners")
RUNNERS_HTTP_CODE="${RUNNERS_RESPONSE: -3}"

if [ "$RUNNERS_HTTP_CODE" = "200" ]; then
    RUNNERS_BODY="${RUNNERS_RESPONSE%???}"
    RUNNER_COUNT=$(echo "$RUNNERS_BODY" | jq '.total_count')
    echo "✓ Repository runners API working ($RUNNER_COUNT runners)"
    
    if [ "$RUNNER_COUNT" -gt 0 ]; then
        echo "Runners:"
        echo "$RUNNERS_BODY" | jq -r '.runners[] | "  - \(.name) (\(.status))"'
    else
        echo "⚠ No runners found - check runner configuration"
    fi
else
    echo "✗ Repository runners API failed (HTTP $RUNNERS_HTTP_CODE)"
    exit 1
fi

# Test 3: EC2 Instance Status
echo ""
echo "=== 3. EC2 Instance Status ==="
INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].State.Name' --output text)
echo "✓ EC2 instance state: $INSTANCE_STATE"

if [ "$INSTANCE_STATE" = "running" ]; then
    PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
      --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    echo "✓ Public IP: $PUBLIC_IP"
fi

# Test 4: Runner Service Status (if instance is running)
if [ "$INSTANCE_STATE" = "running" ]; then
    echo ""
    echo "=== 4. Runner Service Status ==="
    
    # Test SSH connectivity first
    if nc -z -w5 "$PUBLIC_IP" 22; then
        echo "✓ SSH connectivity working"
        
        # Check runner service status
        ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$PUBLIC_IP" '
            cd ~/actions-runner
            if sudo ./svc.sh status | grep -q "active (running)"; then
                echo "✓ Runner service is active"
            else
                echo "✗ Runner service is not active"
                sudo ./svc.sh status
            fi
        ' 2>/dev/null || echo "⚠ Could not check runner service status via SSH"
    else
        echo "⚠ SSH connectivity not available - cannot check runner service"
    fi
fi

echo ""
echo "=== Migration Validation Complete ==="
echo ""
echo "Next steps:"
echo "1. Test workflows in GitHub Actions tab"
echo "2. Verify runner appears in repository settings"
echo "3. Run a test job to confirm functionality"
EOF

chmod +x validate-migration.sh

# Run validation
export GH_PAT_REPO="your_repository_pat"
./validate-migration.sh
```

#### Step 2: Test Repository Workflows

1. **Navigate to Actions Tab**:
   - Go to `https://github.com/{username}/{repository}/actions`

2. **Test Configuration Workflow**:
   - Click "Configure Repository Runner"
   - Click "Run workflow"
   - Select "status" action
   - Click "Run workflow"
   - Verify runner appears in output

3. **Test Demo Workflow**:
   - Click "Repository Self-Hosted Runner Demo"
   - Click "Run workflow"
   - Select job type (e.g., "build")
   - Click "Run workflow"
   - Monitor execution and verify success

#### Step 3: Verify Repository Settings

1. **Check Runner in Settings**:
   - Go to `https://github.com/{username}/{repository}/settings/actions/runners`
   - Verify `gha_aws_runner` appears with "Idle" status
   - Note: Runner should only be visible in this specific repository

2. **Verify Actions Settings**:
   - Go to `https://github.com/{username}/{repository}/settings/actions/general`
   - Ensure "Allow all actions and reusable workflows" is selected
   - Verify "Allow {username} actions and reusable workflows" includes your repository

## Post-Migration Tasks

### 1. Clean Up Organization Resources

After successful migration and validation:

```bash
# Remove organization-specific secrets (if no longer needed)
echo "Clean up organization-level secrets and configurations"

# Update documentation
echo "Update any documentation referencing organization setup"

# Notify team members (if applicable)
echo "Notify team about migration to repository-level runner"
```

### 2. Update Documentation

Update any project documentation to reflect repository-level setup:

```bash
# Update README.md
cat >> README.md << 'EOF'

## GitHub Actions Runner

This repository uses a self-hosted GitHub Actions runner configured at the repository level.

### Runner Configuration
- **Scope**: Repository-specific access only
- **Labels**: `gha_aws_runner`
- **Management**: Repository Settings → Actions → Runners

### Usage in Workflows
```yaml
jobs:
  my-job:
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - name: Run on repository runner
        run: echo "Running on dedicated repository runner"
```

### Manual Runner Management
Use the "Configure Repository Runner" workflow in the Actions tab to:
- Configure runner for this repository
- Remove runner registration
- Check runner status
EOF
```

### 3. Monitor and Maintain

Set up monitoring for the repository-level runner:

```bash
# Create monitoring script for repository runner
cat > scripts/monitor-repo-runner.sh << 'EOF'
#!/bin/bash

# Repository runner monitoring script
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GH_PAT="${GH_PAT:-}"

check_repo_runner_health() {
    local response
    response=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
      "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "200" ]; then
        echo "ALERT: Repository runner API access failed (HTTP $http_code)"
        return 1
    fi
    
    local online_runners
    online_runners=$(echo "$body" | jq '[.runners[] | select(.status == "online")] | length')
    
    if [ "$online_runners" -eq 0 ]; then
        echo "ALERT: No online runners found in repository"
        return 1
    fi
    
    echo "OK: $online_runners repository runner(s) online"
    return 0
}

# Run health check
check_repo_runner_health
EOF

chmod +x scripts/monitor-repo-runner.sh
```

## Rollback Procedure

If you need to rollback to organization-level setup:

### 1. Stop Repository Runner

```bash
# Stop repository runner
ssh ubuntu@$INSTANCE_IP << 'EOF'
cd ~/actions-runner
sudo ./svc.sh stop
sudo ./svc.sh uninstall
sudo -u ubuntu ./config.sh remove --token dummy_token || true
EOF
```

### 2. Restore Organization Configuration

```bash
# Restore from backup
cd ~/runner-migration-backup/$(date +%Y%m%d)
source current-config.env

# Generate organization registration token
REGISTRATION_TOKEN=$(curl -s -X POST \
  -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/registration-token" | \
  jq -r '.token')

# Reconfigure for organization
ssh ubuntu@$INSTANCE_IP << EOF
cd ~/actions-runner

sudo -u ubuntu ./config.sh \
  --url https://github.com/$GITHUB_ORGANIZATION \
  --token $REGISTRATION_TOKEN \
  --name $RUNNER_NAME \
  --labels gha_aws_runner \
  --ephemeral \
  --unattended

sudo ./svc.sh install ubuntu
sudo ./svc.sh start
EOF
```

## Troubleshooting Migration Issues

### Common Migration Problems

1. **PAT Permission Issues**:
   - Ensure new PAT has `repo` scope
   - Verify repository admin permissions
   - Test PAT with API calls before migration

2. **Runner Registration Failures**:
   - Check registration token expiration (1 hour limit)
   - Verify repository URL format
   - Ensure runner name is unique in repository

3. **SSH Connectivity Issues**:
   - Verify security group allows SSH access
   - Check SSH key permissions and location
   - Test SSH connectivity before migration

4. **Workflow Failures**:
   - Update workflow files to use repository secrets
   - Verify all required secrets are configured
   - Test workflows with simple jobs first

### Getting Help

If you encounter issues during migration:

1. **Check Migration Logs**: Review all command outputs and error messages
2. **Validate Prerequisites**: Ensure all requirements are met
3. **Test Components**: Test each component (PAT, SSH, AWS) individually
4. **Use Rollback**: Use rollback procedure if needed
5. **Seek Support**: Contact support with specific error messages and logs

## Migration Checklist

Use this checklist to track migration progress:

- [ ] **Pre-Migration**
  - [ ] Repository admin access verified
  - [ ] New GitHub PAT created with `repo` scope
  - [ ] Repository secrets configured
  - [ ] Current configuration backed up
  - [ ] Downtime window planned

- [ ] **Migration Execution**
  - [ ] Organization runner stopped
  - [ ] Runner unregistered from organization
  - [ ] Repository runner configured
  - [ ] Runner registered with repository
  - [ ] Workflow files created and committed

- [ ] **Validation**
  - [ ] Repository API access working
  - [ ] Runner appears in repository settings
  - [ ] Test workflows executed successfully
  - [ ] Runner service status verified

- [ ] **Post-Migration**
  - [ ] Organization resources cleaned up
  - [ ] Documentation updated
  - [ ] Monitoring configured
  - [ ] Team notified (if applicable)

## Summary

This migration guide provides a comprehensive process for converting from organization-level to repository-level GitHub Actions runners. The repository-level approach offers simplified permissions, dedicated resources, and easier management for personal GitHub accounts.

Key benefits after migration:
- **Simplified Setup**: Only `repo` scope PAT required
- **Personal Control**: Full control without organization dependencies
- **Dedicated Access**: Runner exclusively for your repository
- **Easy Management**: Direct repository-level control and monitoring

The migration process is designed to be safe and reversible, with comprehensive validation and rollback procedures to ensure a smooth transition.