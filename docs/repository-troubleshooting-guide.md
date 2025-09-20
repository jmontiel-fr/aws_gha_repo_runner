# Repository-Level Runner Troubleshooting Guide

This guide provides comprehensive troubleshooting information for repository-level GitHub Actions runner issues, including common problems, diagnostic procedures, and solutions specific to personal GitHub account repositories.

## Quick Diagnostic Checklist

Before diving into detailed troubleshooting, run through this quick checklist:

- [ ] GitHub PAT has `repo` scope only (not `admin:org`)
- [ ] User has repository admin permissions
- [ ] Runner appears in repository settings (Settings → Actions → Runners)
- [ ] EC2 instance is running and accessible
- [ ] Security groups allow GitHub IP ranges
- [ ] Runner service is active on EC2 instance
- [ ] Repository allows self-hosted runners
- [ ] Repository Actions are enabled

## Common Issues and Solutions

### 1. Repository Runner Registration Issues

#### Issue: "Failed to generate registration token (HTTP 403)"

**Symptoms:**
```
❌ Failed to generate registration token (HTTP 403)
❌ This indicates insufficient permissions for repository access
```

**Causes:**
- GitHub PAT lacks `repo` scope
- User doesn't have repository admin permissions
- Repository has restricted runner permissions
- PAT has expired or been revoked

**Solutions:**

1. **Verify PAT Scopes:**
```bash
# Check current PAT permissions
curl -H "Authorization: token $GH_PAT" https://api.github.com/user | jq '.login'

# Test repository access specifically
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY" | \
  jq '{name: .name, private: .private, permissions: .permissions}'
```

2. **Update PAT Scopes:**
   - Go to GitHub Settings → Developer settings → Personal access tokens
   - Edit your token and ensure `repo` scope is selected (full control of private repositories)
   - **Remove** `admin:org` scope if present (not needed for repository-level)
   - Regenerate token if necessary

3. **Verify Repository Admin Permissions:**
```bash
# Check your repository permissions
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/collaborators/$GITHUB_USERNAME/permission"
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

4. **Check Repository Actions Settings:**
   - Go to Repository Settings → Actions → General
   - Ensure "Allow all actions and reusable workflows" is enabled
   - Verify "Allow {username} actions and reusable workflows" includes your repository

#### Issue: "Repository not found (HTTP 404)"

**Symptoms:**
```
❌ Repository not found or insufficient permissions (HTTP 404)
```

**Causes:**
- Incorrect repository name or username
- Repository is private and PAT lacks access
- Repository doesn't exist
- Typo in repository URL format

**Solutions:**

1. **Verify Repository Details:**
```bash
# List repositories you have access to
curl -H "Authorization: token $GH_PAT" https://api.github.com/user/repos | \
  jq '.[] | {name: .name, full_name: .full_name, private: .private}'

# Check specific repository
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY"
```

2. **Verify Environment Variables:**
```bash
echo "Username: $GITHUB_USERNAME"
echo "Repository: $GITHUB_REPOSITORY"
echo "Full name: $GITHUB_USERNAME/$GITHUB_REPOSITORY"

# Ensure no extra spaces or special characters
export GITHUB_USERNAME=$(echo "$GITHUB_USERNAME" | tr -d '[:space:]')
export GITHUB_REPOSITORY=$(echo "$GITHUB_REPOSITORY" | tr -d '[:space:]')
```

3. **Check Repository URL Format:**
```bash
# Correct format for repository API
REPO_URL="https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY"
echo "Testing URL: $REPO_URL"

# Test the URL
curl -I -H "Authorization: token $GH_PAT" "$REPO_URL"
```

#### Issue: "Runner name already exists in repository"

**Symptoms:**
```
❌ Runner name 'gha_aws_runner' already exists in repository
```

**Causes:**
- Previous runner registration wasn't properly cleaned up
- Another instance is using the same runner name
- Runner configuration conflicts

**Solutions:**

1. **List Existing Repository Runners:**
```bash
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners" | \
  jq '.runners[] | {id: .id, name: .name, status: .status}'
```

2. **Remove Existing Runner:**
```bash
# Get runner ID
RUNNER_ID=$(curl -s -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners" | \
  jq -r ".runners[] | select(.name==\"$RUNNER_NAME\") | .id")

# Remove runner if found
if [ "$RUNNER_ID" != "null" ] && [ -n "$RUNNER_ID" ]; then
  echo "Removing existing runner ID: $RUNNER_ID"
  curl -X DELETE -H "Authorization: token $GH_PAT" \
    "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/$RUNNER_ID"
  echo "Runner removed successfully"
else
  echo "Runner not found in API"
fi
```

3. **Use Unique Runner Name:**
```bash
export RUNNER_NAME="gha_aws_runner_$(date +%s)"
echo "Using unique runner name: $RUNNER_NAME"
```

4. **Clean Runner Configuration on EC2:**
```bash
# SSH to instance and clean configuration
ssh ubuntu@$INSTANCE_IP << 'EOF'
cd ~/actions-runner

# Stop service if running
sudo ./svc.sh stop || true
sudo ./svc.sh uninstall || true

# Remove configuration files
sudo -u ubuntu ./config.sh remove --token dummy_token || true

# Clean any leftover files
rm -f .runner .credentials .credentials_rsaparams || true

echo "Runner configuration cleaned"
EOF
```

### 2. Repository Runner Connectivity Issues

#### Issue: "Runner appears offline in repository settings"

**Symptoms:**
- Runner shows "Offline" status in repository settings
- Jobs timeout waiting for runner
- Runner service appears to be running on EC2

**Diagnostic Steps:**

1. **Check Runner Service Status:**
```bash
# SSH to EC2 instance
ssh -i ~/.ssh/key.pem ubuntu@$INSTANCE_IP

# Check service status
cd ~/actions-runner
sudo ./svc.sh status
```

2. **Check Runner Logs:**
```bash
# View runner service logs
sudo journalctl -u actions.runner.* -f

# Check runner directory logs
tail -f ~/actions-runner/_diag/Runner_*.log

# Check for specific errors
grep -i error ~/actions-runner/_diag/Runner_*.log | tail -10
```

3. **Test Network Connectivity:**
```bash
# Test GitHub connectivity from EC2 instance
curl -I https://github.com
curl -I https://api.github.com

# Test DNS resolution
nslookup github.com
nslookup api.github.com

# Test specific repository API endpoint
curl -I "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY"
```

**Solutions:**

1. **Restart Runner Service:**
```bash
cd ~/actions-runner
sudo ./svc.sh stop
sleep 5
sudo ./svc.sh start

# Check status after restart
sudo ./svc.sh status
```

2. **Reconfigure Runner:**
```bash
# Generate new registration token
REGISTRATION_TOKEN=$(curl -s -X POST \
  -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token" | \
  jq -r '.token')

# Reconfigure runner
cd ~/actions-runner
sudo ./svc.sh stop
sudo ./svc.sh uninstall

sudo -u ubuntu ./config.sh \
  --url "https://github.com/$GITHUB_USERNAME/$GITHUB_REPOSITORY" \
  --token "$REGISTRATION_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "gha_aws_runner" \
  --work "_work" \
  --unattended \
  --replace

sudo ./svc.sh install ubuntu
sudo ./svc.sh start
```

3. **Check Security Group Rules:**
```bash
# Verify HTTPS outbound access to GitHub
aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID | \
  jq '.SecurityGroups[0].IpPermissionsEgress[] | select(.IpProtocol == "tcp" and .FromPort == 443)'

# Get current GitHub IP ranges
curl https://api.github.com/meta | jq '.actions'
```

#### Issue: "Jobs fail with 'No runners available'"

**Symptoms:**
- Workflows fail immediately with runner availability error
- Runner appears online in repository settings
- Error message: "No runners available"

**Causes:**
- Workflow uses incorrect runner labels
- Repository Actions are disabled
- Runner is busy with another job
- Workflow targeting wrong runner

**Solutions:**

1. **Verify Workflow Labels:**
```yaml
# Correct label usage for repository runner
jobs:
  my-job:
    runs-on: [self-hosted, gha_aws_runner]

# Common mistakes to avoid:
# runs-on: gha_aws_runner              # Missing array format
# runs-on: [self-hosted, wrong-label]  # Incorrect label
# runs-on: ubuntu-latest               # Using GitHub-hosted instead
```

2. **Check Repository Actions Settings:**
   - Go to Repository Settings → Actions → General
   - Ensure "Allow all actions and reusable workflows" is selected
   - Verify Actions are enabled for the repository

3. **Verify Runner Labels:**
```bash
# Check current runner labels
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners" | \
  jq '.runners[] | {name: .name, labels: [.labels[].name]}'
```

4. **Test Runner Availability:**
```bash
# Check if runner is busy
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners" | \
  jq '.runners[] | {name: .name, status: .status, busy: .busy}'
```

### 3. Repository-Specific Permission Issues

#### Issue: "Actions are disabled for this repository"

**Symptoms:**
- Workflows don't trigger
- Actions tab shows "Actions are disabled"
- Runner registration succeeds but workflows fail

**Solutions:**

1. **Enable Actions for Repository:**
   - Go to Repository Settings → Actions → General
   - Under "Actions permissions", select "Allow all actions and reusable workflows"
   - Click "Save"

2. **Check Organization-Level Restrictions (if applicable):**
   - If repository is in an organization, check organization Actions settings
   - Go to Organization Settings → Actions → General
   - Ensure repository is allowed to use Actions

3. **Verify Repository Visibility:**
```bash
# Check if repository allows Actions
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/permissions"
```

#### Issue: "Self-hosted runners not allowed"

**Symptoms:**
- Repository runner registration succeeds
- Workflows fail with "Self-hosted runners are not allowed"
- Runner appears in settings but can't be used

**Solutions:**

1. **Enable Self-Hosted Runners:**
   - Go to Repository Settings → Actions → General
   - Under "Runners", ensure self-hosted runners are allowed
   - If in organization, check organization runner policies

2. **Check Runner Group Permissions (Organization repositories):**
   - Go to Organization Settings → Actions → Runner groups
   - Ensure repository has access to appropriate runner group
   - Verify runner group allows self-hosted runners

### 4. Repository Workflow Issues

#### Issue: "Workflow secrets not found"

**Symptoms:**
- Workflows fail with "Secret not found" errors
- AWS credentials or GitHub PAT not accessible
- Environment variables are empty

**Solutions:**

1. **Verify Repository Secrets:**
   - Go to Repository Settings → Secrets and variables → Actions
   - Ensure all required secrets are configured:
     - `AWS_ACCESS_KEY_ID`
     - `AWS_SECRET_ACCESS_KEY`
     - `AWS_REGION`
     - `GH_PAT`
     - `EC2_INSTANCE_ID`
     - `RUNNER_NAME`

2. **Test Secret Access:**
```yaml
# Add debug step to workflow
- name: Debug secrets
  run: |
    echo "AWS Region: ${{ secrets.AWS_REGION }}"
    echo "Instance ID: ${{ secrets.EC2_INSTANCE_ID }}"
    echo "Runner Name: ${{ secrets.RUNNER_NAME }}"
    # Don't echo sensitive secrets like PAT or AWS keys
```

3. **Check Secret Names:**
```bash
# List repository secrets (names only)
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/secrets" | \
  jq '.secrets[] | .name'
```

#### Issue: "Repository context not available"

**Symptoms:**
- `${{ github.repository }}` returns unexpected value
- Workflow can't access repository information
- Context variables are empty

**Solutions:**

1. **Verify Repository Context:**
```yaml
# Add debug step to check context
- name: Debug repository context
  run: |
    echo "Repository: ${{ github.repository }}"
    echo "Repository owner: ${{ github.repository_owner }}"
    echo "Repository name: ${{ github.event.repository.name }}"
    echo "Ref: ${{ github.ref }}"
    echo "SHA: ${{ github.sha }}"
```

2. **Use Correct Context Variables:**
```yaml
# Correct usage for repository-level operations
- name: Generate registration token
  run: |
    TOKEN=$(curl -s -X POST \
      -H "Authorization: token ${{ secrets.GH_PAT }}" \
      "https://api.github.com/repos/${{ github.repository }}/actions/runners/registration-token" | \
      jq -r '.token')
```

### 5. AWS Infrastructure Issues for Repository Runners

#### Issue: "EC2 instance fails to start for repository workflows"

**Symptoms:**
- AWS CLI commands timeout in workflows
- Instance stuck in "pending" state
- SSH connection failures from workflows

**Diagnostic Steps:**

1. **Check Instance Status:**
```bash
aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID | \
  jq '.Reservations[0].Instances[0] | {state: .State.Name, reason: .StateReason.Message}'
```

2. **Check AWS Credentials in Workflow:**
```yaml
- name: Test AWS credentials
  run: |
    aws sts get-caller-identity
    aws ec2 describe-instances --instance-ids ${{ secrets.EC2_INSTANCE_ID }} --query 'Reservations[0].Instances[0].State.Name'
```

3. **Verify IAM Permissions:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus"
      ],
      "Resource": "*"
    }
  ]
}
```

**Solutions:**

1. **Update AWS Credentials:**
   - Verify AWS credentials in repository secrets
   - Test credentials with AWS CLI locally
   - Ensure IAM user has required permissions

2. **Check Instance Limits:**
```bash
# Check EC2 service quotas
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A  # Running On-Demand instances
```

3. **Verify Security Groups:**
```bash
# Check security group rules for SSH access
aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID | \
  jq '.SecurityGroups[0].IpPermissions[] | select(.FromPort == 22)'
```

### 6. Repository Runner Switching Issues

#### Issue: "Need to switch runner to different repository"

**Symptoms:**
- Want to use the same EC2 runner with a different repository
- Need to move runner from one project to another
- Current repository no longer needs the runner

**Solutions:**

Use the repository switching script to cleanly move the runner:

1. **Basic Repository Switch:**
```bash
# Set environment variables for current and new repositories
export CURRENT_GITHUB_USERNAME="myusername"
export CURRENT_GITHUB_REPOSITORY="old-repo"
export NEW_GITHUB_USERNAME="myusername"
export NEW_GITHUB_REPOSITORY="new-repo"
export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"

# Run the switching script
./scripts/switch-repository-runner.sh
```

2. **Validate Before Switching:**
```bash
# Check if switching is possible
./scripts/switch-repository-runner.sh --validate-only

# Show current runner status
./scripts/switch-repository-runner.sh --status
```

3. **Dry Run to Preview Changes:**
```bash
# See what would happen without making changes
./scripts/switch-repository-runner.sh --dry-run
```

4. **Force Switch Despite Warnings:**
```bash
# Force switch even if validation warnings exist
./scripts/switch-repository-runner.sh --force
```

#### Issue: "Runner switching fails with permission errors"

**Symptoms:**
```
❌ Failed to unregister from current repository
❌ New repository validation failed
❌ Insufficient permissions for repository switching
```

**Causes:**
- PAT lacks admin permissions on one or both repositories
- Repository doesn't exist or is inaccessible
- Runner is currently busy with a job

**Solutions:**

1. **Verify Permissions on Both Repositories:**
```bash
# Check current repository permissions
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY" | \
  jq '.permissions'

# Check new repository permissions
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY" | \
  jq '.permissions'
```

2. **Wait for Running Jobs to Complete:**
```bash
# Check if runner is busy
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY/actions/runners" | \
  jq '.runners[] | select(.name=="'$RUNNER_NAME'") | {name: .name, status: .status, busy: .busy}'
```

3. **Manual Cleanup if Switching Fails:**
```bash
# If switching fails partway through, clean up manually
ssh ubuntu@$INSTANCE_IP << 'EOF'
cd ~/actions-runner

# Stop service
sudo ./svc.sh stop || true
sudo ./svc.sh uninstall || true

# Remove configuration
sudo -u ubuntu ./config.sh remove --token dummy_token || true

# Clean configuration files
rm -f .runner .credentials .credentials_rsaparams || true

echo "Runner cleaned up - ready for reconfiguration"
EOF

# Then run the setup script for the new repository
export GITHUB_USERNAME="$NEW_GITHUB_USERNAME"
export GITHUB_REPOSITORY="$NEW_GITHUB_REPOSITORY"
./scripts/repo-runner-setup.sh
```

#### Issue: "Runner appears in both repositories after switching"

**Symptoms:**
- Runner shows up in both old and new repository settings
- Workflows from both repositories try to use the runner
- Conflicting job assignments

**Causes:**
- Switching process didn't complete properly
- Network issues during unregistration
- API delays in updating runner status

**Solutions:**

1. **Manual Cleanup of Old Repository:**
```bash
# Get runner ID from old repository
OLD_RUNNER_ID=$(curl -s -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY/actions/runners" | \
  jq -r ".runners[] | select(.name==\"$RUNNER_NAME\") | .id")

# Remove runner from old repository
if [ "$OLD_RUNNER_ID" != "null" ] && [ -n "$OLD_RUNNER_ID" ]; then
  curl -X DELETE -H "Authorization: token $GH_PAT" \
    "https://api.github.com/repos/$CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY/actions/runners/$OLD_RUNNER_ID"
  echo "Removed runner from old repository"
fi
```

2. **Verify Runner Configuration:**
```bash
# SSH to instance and check configuration
ssh ubuntu@$INSTANCE_IP << 'EOF'
cd ~/actions-runner

# Check current configuration
if [ -f .runner ]; then
  cat .runner | jq '{serverUrl: .serverUrl, agentName: .agentName}'
else
  echo "No runner configuration found"
fi
EOF
```

3. **Re-run Switching Process:**
```bash
# If runner is in inconsistent state, re-run the switch
./scripts/switch-repository-runner.sh --force
```

### 7. Repository Runner Performance Issues

#### Issue: "Slow job execution on repository runner"

**Symptoms:**
- Jobs take longer than expected
- Resource exhaustion errors
- Timeouts during job execution

**Diagnostic Steps:**

1. **Monitor System Resources:**
```bash
# SSH to EC2 instance and check resources
ssh ubuntu@$INSTANCE_IP << 'EOF'
echo "=== System Resources ==="
free -h
df -h
top -bn1 | head -20

echo "=== Running Processes ==="
ps aux | grep -E "(runner|github|actions)" | head -10

echo "=== Disk Usage ==="
du -sh ~/actions-runner/_work/* 2>/dev/null || echo "No work directories"
EOF
```

2. **Check Job History:**
```bash
# Get recent workflow runs for repository
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runs?per_page=10" | \
  jq '.workflow_runs[] | {id: .id, status: .status, conclusion: .conclusion, created_at: .created_at, updated_at: .updated_at}'
```

**Solutions:**

1. **Optimize Instance Size:**
```hcl
# In terraform.tfvars - upgrade instance type
instance_type = "t3.small"  # Upgrade from t3.micro
# or
instance_type = "t3.medium" # For more demanding workloads
```

2. **Add Resource Monitoring to Workflows:**
```yaml
- name: Check resources before job
  run: |
    echo "=== Available Resources ==="
    free -h
    df -h
    echo "=== CPU Info ==="
    nproc
    cat /proc/loadavg
```

3. **Implement Job Timeouts:**
```yaml
jobs:
  build:
    runs-on: [self-hosted, gha_aws_runner]
    timeout-minutes: 30  # Prevent runaway jobs
    steps:
      - name: Your build step
        timeout-minutes: 20  # Step-level timeout
        run: |
          # Your build commands
```

4. **Clean Up Work Directory:**
```yaml
- name: Clean workspace
  if: always()
  run: |
    # Clean temporary files
    rm -rf /tmp/github-* /tmp/runner-* || true
    
    # Clean workspace
    cd ${{ github.workspace }}
    git clean -ffdx || true
```

## Diagnostic Scripts

### 1. Repository Runner Health Check Script

```bash
#!/bin/bash
# File: scripts/repo-runner-health-check.sh

set -e

GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GH_PAT="${GH_PAT:-}"
EC2_INSTANCE_ID="${EC2_INSTANCE_ID:-}"

echo "=== Repository Runner Health Check ==="
echo "Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
echo "Instance ID: $EC2_INSTANCE_ID"
echo "Timestamp: $(date -u)"
echo ""

# Check 1: Prerequisites
echo "=== 1. Prerequisites Check ==="
command -v curl >/dev/null && echo "✓ curl installed" || echo "✗ curl missing"
command -v jq >/dev/null && echo "✓ jq installed" || echo "✗ jq missing"
command -v aws >/dev/null && echo "✓ aws cli installed" || echo "✗ aws cli missing"

[ -n "$GITHUB_USERNAME" ] && echo "✓ GITHUB_USERNAME set" || echo "✗ GITHUB_USERNAME missing"
[ -n "$GITHUB_REPOSITORY" ] && echo "✓ GITHUB_REPOSITORY set" || echo "✗ GITHUB_REPOSITORY missing"
[ -n "$GH_PAT" ] && echo "✓ GH_PAT set" || echo "✗ GH_PAT missing"
[ -n "$EC2_INSTANCE_ID" ] && echo "✓ EC2_INSTANCE_ID set" || echo "✗ EC2_INSTANCE_ID missing"

# Check 2: GitHub API Access
echo ""
echo "=== 2. GitHub API Access ==="
if curl -s -H "Authorization: token $GH_PAT" https://api.github.com/user >/dev/null; then
    USERNAME=$(curl -s -H "Authorization: token $GH_PAT" https://api.github.com/user | jq -r '.login')
    echo "✓ GitHub API access working (user: $USERNAME)"
else
    echo "✗ GitHub API access failed"
fi

# Check 3: Repository Access
echo ""
echo "=== 3. Repository Access ==="
REPO_RESPONSE=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY")
REPO_HTTP_CODE="${REPO_RESPONSE: -3}"

if [ "$REPO_HTTP_CODE" = "200" ]; then
    echo "✓ Repository access working"
    REPO_BODY="${REPO_RESPONSE%???}"
    REPO_PRIVATE=$(echo "$REPO_BODY" | jq -r '.private')
    echo "  Repository is private: $REPO_PRIVATE"
else
    echo "✗ Repository access failed (HTTP $REPO_HTTP_CODE)"
fi

# Check 4: Repository Permissions
echo ""
echo "=== 4. Repository Permissions ==="
PERM_RESPONSE=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/collaborators/$USERNAME/permission")
PERM_HTTP_CODE="${PERM_RESPONSE: -3}"

if [ "$PERM_HTTP_CODE" = "200" ]; then
    PERM_BODY="${PERM_RESPONSE%???}"
    PERMISSION=$(echo "$PERM_BODY" | jq -r '.permission')
    if [ "$PERMISSION" = "admin" ]; then
        echo "✓ Repository admin permissions confirmed"
    else
        echo "⚠ Repository permission level: $PERMISSION (admin required for runners)"
    fi
else
    echo "✗ Repository permission check failed (HTTP $PERM_HTTP_CODE)"
fi

# Check 5: Runner Registration Token
echo ""
echo "=== 5. Runner Registration Token ==="
TOKEN_RESPONSE=$(curl -s -w "%{http_code}" -X POST \
  -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token")
TOKEN_HTTP_CODE="${TOKEN_RESPONSE: -3}"

if [ "$TOKEN_HTTP_CODE" = "201" ]; then
    echo "✓ Registration token generation working"
else
    echo "✗ Registration token generation failed (HTTP $TOKEN_HTTP_CODE)"
    TOKEN_BODY="${TOKEN_RESPONSE%???}"
    echo "  Response: $TOKEN_BODY"
fi

# Check 6: EC2 Instance Status
echo ""
echo "=== 6. EC2 Instance Status ==="
if INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null); then
    echo "✓ EC2 instance state: $INSTANCE_STATE"
    
    if [ "$INSTANCE_STATE" = "running" ]; then
        PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
          --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
        echo "✓ Public IP: $PUBLIC_IP"
        
        # Test SSH connectivity
        if nc -z -w5 "$PUBLIC_IP" 22 2>/dev/null; then
            echo "✓ SSH port accessible"
        else
            echo "⚠ SSH port not accessible"
        fi
    fi
else
    echo "✗ Failed to get EC2 instance status"
fi

# Check 7: Repository Runners
echo ""
echo "=== 7. Repository Runners ==="
RUNNERS_RESPONSE=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners")
RUNNERS_HTTP_CODE="${RUNNERS_RESPONSE: -3}"

if [ "$RUNNERS_HTTP_CODE" = "200" ]; then
    RUNNERS_BODY="${RUNNERS_RESPONSE%???}"
    RUNNER_COUNT=$(echo "$RUNNERS_BODY" | jq '.total_count')
    echo "✓ Repository runners API working ($RUNNER_COUNT runners)"
    
    if [ "$RUNNER_COUNT" -gt 0 ]; then
        echo "Runners:"
        echo "$RUNNERS_BODY" | jq -r '.runners[] | "  - \(.name) (\(.status)) - Labels: \([.labels[].name] | join(","))"'
    fi
else
    echo "✗ Repository runners API failed (HTTP $RUNNERS_HTTP_CODE)"
fi

# Check 8: Repository Actions Settings
echo ""
echo "=== 8. Repository Actions Settings ==="
ACTIONS_RESPONSE=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/permissions")
ACTIONS_HTTP_CODE="${ACTIONS_RESPONSE: -3}"

if [ "$ACTIONS_HTTP_CODE" = "200" ]; then
    ACTIONS_BODY="${ACTIONS_RESPONSE%???}"
    ACTIONS_ENABLED=$(echo "$ACTIONS_BODY" | jq -r '.enabled')
    ALLOWED_ACTIONS=$(echo "$ACTIONS_BODY" | jq -r '.allowed_actions')
    echo "✓ Actions enabled: $ACTIONS_ENABLED"
    echo "✓ Allowed actions: $ALLOWED_ACTIONS"
else
    echo "⚠ Could not check Actions permissions (HTTP $ACTIONS_HTTP_CODE)"
fi

echo ""
echo "=== Health Check Complete ==="
```

### 2. Repository Runner Connectivity Test Script

```bash
#!/bin/bash
# File: scripts/test-repo-connectivity.sh

EC2_INSTANCE_IP="${1:-}"
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"

if [ -z "$EC2_INSTANCE_IP" ]; then
    echo "Usage: $0 <EC2_INSTANCE_IP>"
    echo "Environment variables needed: GITHUB_USERNAME, GITHUB_REPOSITORY"
    exit 1
fi

echo "=== Repository Runner Connectivity Test ==="
echo "Instance IP: $EC2_INSTANCE_IP"
echo "Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
echo "Timestamp: $(date -u)"
echo ""

# Test 1: SSH Connectivity
echo "=== 1. SSH Connectivity ==="
if nc -z -w5 "$EC2_INSTANCE_IP" 22; then
    echo "✓ SSH port (22) is accessible"
else
    echo "✗ SSH port (22) is not accessible"
fi

# Test 2: GitHub Connectivity (from local)
echo ""
echo "=== 2. GitHub Connectivity (Local) ==="
curl -I https://github.com >/dev/null 2>&1 && echo "✓ GitHub.com accessible" || echo "✗ GitHub.com not accessible"
curl -I https://api.github.com >/dev/null 2>&1 && echo "✓ GitHub API accessible" || echo "✗ GitHub API not accessible"

# Test repository-specific endpoint
REPO_URL="https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY"
curl -I "$REPO_URL" >/dev/null 2>&1 && echo "✓ Repository API accessible" || echo "✗ Repository API not accessible"

# Test 3: Remote Connectivity (via SSH)
echo ""
echo "=== 3. Remote Connectivity (via SSH) ==="
if command -v ssh >/dev/null && [ -f ~/.ssh/id_rsa ]; then
    echo "Testing connectivity from EC2 instance..."
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$EC2_INSTANCE_IP" << EOF
        echo "Connected to \$(hostname)"
        echo "Testing GitHub connectivity from instance:"
        curl -I https://github.com >/dev/null 2>&1 && echo "✓ GitHub.com accessible from instance" || echo "✗ GitHub.com not accessible from instance"
        curl -I https://api.github.com >/dev/null 2>&1 && echo "✓ GitHub API accessible from instance" || echo "✗ GitHub API not accessible from instance"
        
        # Test repository-specific endpoint
        curl -I "$REPO_URL" >/dev/null 2>&1 && echo "✓ Repository API accessible from instance" || echo "✗ Repository API not accessible from instance"
        
        echo "Testing DNS resolution:"
        nslookup github.com >/dev/null 2>&1 && echo "✓ DNS resolution working" || echo "✗ DNS resolution failed"
        
        echo "Checking runner service:"
        if [ -d ~/actions-runner ]; then
            cd ~/actions-runner
            if sudo ./svc.sh status | grep -q "active (running)"; then
                echo "✓ Runner service active"
                
                # Check runner configuration
                if [ -f .runner ]; then
                    RUNNER_URL=\$(cat .runner | jq -r '.serverUrl // empty')
                    echo "✓ Runner configured for: \$RUNNER_URL"
                    
                    # Verify it's configured for the correct repository
                    if echo "\$RUNNER_URL" | grep -q "$GITHUB_USERNAME/$GITHUB_REPOSITORY"; then
                        echo "✓ Runner configured for correct repository"
                    else
                        echo "⚠ Runner configured for different repository: \$RUNNER_URL"
                    fi
                else
                    echo "⚠ Runner configuration file not found"
                fi
            else
                echo "✗ Runner service not active"
                sudo ./svc.sh status
            fi
        else
            echo "✗ Runner not installed"
        fi
EOF
else
    echo "⚠ SSH key not found or SSH not available - skipping remote tests"
fi

echo ""
echo "=== Connectivity Test Complete ==="
```

### 3. Repository Runner Recovery Script

```bash
#!/bin/bash
# File: scripts/recover-repo-runner.sh

set -e

GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GH_PAT="${GH_PAT:-}"
EC2_INSTANCE_ID="${EC2_INSTANCE_ID:-}"
RUNNER_NAME="${RUNNER_NAME:-gha_aws_runner}"

echo "=== Repository Runner Recovery ==="
echo "Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
echo "Runner Name: $RUNNER_NAME"
echo "Instance ID: $EC2_INSTANCE_ID"
echo ""

# Function to check runner health
check_runner_health() {
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

# Recovery function
recover_runner() {
    echo "=== Starting Automated Recovery ==="
    
    # Step 1: Check if instance is running
    local instance_state
    instance_state=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].State.Name' --output text)
    
    echo "Current instance state: $instance_state"
    
    if [ "$instance_state" != "running" ]; then
        echo "Starting EC2 instance..."
        aws ec2 start-instances --instance-ids "$EC2_INSTANCE_ID"
        aws ec2 wait instance-running --instance-ids "$EC2_INSTANCE_ID"
        echo "Instance started successfully"
    fi
    
    # Step 2: Get instance IP
    local public_ip
    public_ip=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    
    echo "Instance IP: $public_ip"
    
    # Step 3: Generate new registration token
    echo "Generating new registration token..."
    local registration_token
    registration_token=$(curl -s -X POST \
      -H "Authorization: token $GH_PAT" \
      "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token" | \
      jq -r '.token')
    
    if [ "$registration_token" = "null" ] || [ -z "$registration_token" ]; then
        echo "Failed to generate registration token"
        return 1
    fi
    
    echo "Registration token generated successfully"
    
    # Step 4: Reconfigure runner
    echo "Reconfiguring runner..."
    ssh -o ConnectTimeout=30 -o StrictHostKeyChecking=no ubuntu@"$public_ip" << EOF
        cd ~/actions-runner
        
        # Stop existing service
        sudo ./svc.sh stop || true
        sudo ./svc.sh uninstall || true
        
        # Remove existing configuration
        sudo -u ubuntu ./config.sh remove --token dummy_token || true
        
        # Configure new runner
        sudo -u ubuntu ./config.sh \
          --url "https://github.com/$GITHUB_USERNAME/$GITHUB_REPOSITORY" \
          --token "$registration_token" \
          --name "$RUNNER_NAME" \
          --labels "gha_aws_runner" \
          --work "_work" \
          --unattended \
          --replace
        
        # Install and start service
        sudo ./svc.sh install ubuntu
        sudo ./svc.sh start
        
        echo "Runner reconfigured successfully"
EOF
    
    # Step 5: Verify recovery
    echo "Waiting for runner to come online..."
    sleep 30
    
    if check_runner_health; then
        echo "✓ Recovery successful"
        return 0
    else
        echo "✗ Recovery failed"
        return 1
    fi
}

# Main execution
echo "Checking current runner health..."
if ! check_runner_health; then
    echo "Runner health check failed, starting recovery..."
    if recover_runner; then
        echo "Recovery completed successfully"
    else
        echo "Recovery failed - manual intervention required"
        exit 1
    fi
else
    echo "Runner is healthy - no recovery needed"
fi
```

## Prevention and Monitoring

### 1. Proactive Monitoring for Repository Runners

Set up monitoring to catch issues early:

```bash
#!/bin/bash
# File: scripts/monitor-repo-runner.sh

# Run this script periodically (e.g., via cron) to monitor repository runner health

GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GH_PAT="${GH_PAT:-}"
ALERT_EMAIL="${ALERT_EMAIL:-admin@example.com}"

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
        echo "ALERT: No online runners found in repository $GITHUB_USERNAME/$GITHUB_REPOSITORY"
        return 1
    fi
    
    echo "OK: $online_runners repository runner(s) online"
    return 0
}

# Run health check and alert if needed
if ! check_repo_runner_health; then
    # Send alert (implement your preferred alerting method)
    echo "Repository runner health check failed at $(date)" | \
      mail -s "Repository Runner Alert - $GITHUB_USERNAME/$GITHUB_REPOSITORY" "$ALERT_EMAIL"
fi
```

### 2. Repository Runner Maintenance

Regular maintenance tasks for repository runners:

```bash
#!/bin/bash
# File: scripts/maintain-repo-runner.sh

# Regular maintenance script for repository runners

GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
EC2_INSTANCE_ID="${EC2_INSTANCE_ID:-}"

echo "=== Repository Runner Maintenance ==="
echo "Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
echo "Date: $(date)"
echo ""

# Get instance IP
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

if [ "$PUBLIC_IP" = "null" ] || [ -z "$PUBLIC_IP" ]; then
    echo "Could not get instance IP - instance may be stopped"
    exit 1
fi

echo "Connecting to instance: $PUBLIC_IP"

# Perform maintenance tasks
ssh ubuntu@"$PUBLIC_IP" << 'EOF'
echo "=== Maintenance Tasks ==="

# Update system packages
echo "1. Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Clean up temporary files
echo "2. Cleaning temporary files..."
sudo rm -rf /tmp/github-* /tmp/runner-* || true
sudo find /tmp -name "*actions*" -type f -mtime +7 -delete || true

# Clean up runner work directory
echo "3. Cleaning runner work directory..."
cd ~/actions-runner
sudo rm -rf _work/* || true

# Check disk usage
echo "4. Checking disk usage..."
df -h

# Check runner service status
echo "5. Checking runner service..."
sudo ./svc.sh status

# Update runner if needed (check for new versions)
echo "6. Checking for runner updates..."
CURRENT_VERSION=$(./config.sh --version 2>/dev/null | head -1 || echo "Unknown")
echo "Current runner version: $CURRENT_VERSION"

echo "=== Maintenance Complete ==="
EOF

echo "Maintenance completed for repository runner"
```

## Getting Help

### 1. GitHub Support Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Self-hosted Runners Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
- [GitHub Community Forum](https://github.community/)
- [GitHub Support](https://support.github.com/)

### 2. Repository-Specific Support

When seeking help for repository-level runner issues, provide:

1. **Repository Information**:
   - Repository URL
   - Repository visibility (public/private)
   - Your permission level

2. **Runner Configuration**:
   - Runner name and labels
   - Registration method used
   - Current runner status

3. **Error Details**:
   - Specific error messages
   - Workflow run URLs
   - Runner logs if accessible

### 3. Collecting Diagnostic Information

```bash
#!/bin/bash
# File: scripts/collect-repo-diagnostics.sh

echo "=== Repository Runner Diagnostic Information ==="
echo "Timestamp: $(date -u)"
echo "Repository: $GITHUB_USERNAME/$GITHUB_REPOSITORY"
echo ""

echo "=== Environment ==="
echo "OS: $(uname -a)"
echo "GitHub Username: $GITHUB_USERNAME"
echo "GitHub Repository: $GITHUB_REPOSITORY"
echo "EC2 Instance ID: $EC2_INSTANCE_ID"
echo ""

echo "=== GitHub API Test ==="
curl -s -H "Authorization: token $GH_PAT" https://api.github.com/user | jq '.login'
echo ""

echo "=== Repository Access ==="
curl -s -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY" | \
  jq '{name: .name, private: .private, permissions: .permissions}'
echo ""

echo "=== Repository Runners ==="
curl -s -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners" | \
  jq '.runners[] | {name: .name, status: .status, busy: .busy, labels: [.labels[].name]}'
echo ""

echo "=== EC2 Instance Status ==="
aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" | \
  jq '.Reservations[0].Instances[0] | {state: .State.Name, ip: .PublicIpAddress, type: .InstanceType}'
echo ""

echo "=== Recent Workflow Runs ==="
curl -s -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runs?per_page=5" | \
  jq '.workflow_runs[] | {id: .id, name: .name, status: .status, conclusion: .conclusion, created_at: .created_at}'
```

This troubleshooting guide provides comprehensive solutions for repository-level GitHub Actions runner issues. The repository-level approach offers simplified permissions and dedicated resources, but requires proper configuration and monitoring to ensure reliable operation.