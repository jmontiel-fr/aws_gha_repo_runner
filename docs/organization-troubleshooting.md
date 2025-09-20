# Repository-Level Runner Troubleshooting Guide

This guide provides comprehensive troubleshooting information for repository-level GitHub Actions runner issues, including common problems, diagnostic procedures, and solutions.

## Quick Diagnostic Checklist

Before diving into detailed troubleshooting, run through this quick checklist:

- [ ] GitHub PAT has `repo` scope
- [ ] User has repository admin permissions
- [ ] Runner appears in repository settings (Settings → Actions → Runners)
- [ ] EC2 instance is running and accessible
- [ ] Security groups allow GitHub IP ranges
- [ ] Runner service is active on EC2 instance
- [ ] Repository allows self-hosted runners

## Common Issues and Solutions

### 1. Runner Registration Issues

#### Issue: "Failed to generate registration token"

**Symptoms:**
```
❌ Failed to generate registration token (HTTP 403)
❌ This indicates insufficient permissions
```

**Causes:**
- GitHub PAT lacks `repo` scope
- User doesn't have repository admin permissions
- Repository has restricted runner permissions

**Solutions:**

1. **Verify PAT Scopes:**
```bash
# Check current PAT permissions
curl -H "Authorization: token $GH_PAT" https://api.github.com/user | jq '.permissions'

# Test organization access
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION"
```

2. **Update PAT Scopes:**
   - Go to GitHub Settings → Developer settings → Personal access tokens
   - Edit your token and ensure `repo` scope is selected
   - Regenerate token if necessary

3. **Verify Repository Permissions:**
```bash
# Check your repository permissions
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/collaborators/$USERNAME/permission"
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

#### Issue: "Organization not found or insufficient permissions"

**Symptoms:**
```
❌ Organization not found or insufficient permissions (HTTP 404)
```

**Causes:**
- Incorrect organization name
- Organization is private and user lacks access
- PAT doesn't have organization access

**Solutions:**

1. **Verify Organization Name:**
```bash
# List organizations you have access to
curl -H "Authorization: token $GH_PAT" https://api.github.com/user/orgs
```

2. **Check Organization Visibility:**
   - Ensure organization exists and is accessible
   - Verify you're a member of the organization
   - Check organization privacy settings

#### Issue: "Runner name already exists"

**Symptoms:**
```
❌ Runner name 'gha_aws_runner' already exists
```

**Causes:**
- Previous runner registration wasn't properly cleaned up
- Another instance is using the same runner name
- Ephemeral configuration not working properly

**Solutions:**

1. **List Existing Runners:**
```bash
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners" | \
  jq '.runners[] | {id: .id, name: .name, status: .status}'
```

2. **Remove Existing Runner:**
```bash
# Get runner ID
RUNNER_ID=$(curl -s -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners" | \
  jq -r ".runners[] | select(.name==\"gha_aws_runner\") | .id")

# Remove runner
curl -X DELETE -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/$RUNNER_ID"
```

3. **Use Unique Runner Name:**
```bash
export RUNNER_NAME="gha_aws_runner_$(date +%s)"
```

### 2. Runner Connectivity Issues

#### Issue: "Runner appears offline"

**Symptoms:**
- Runner shows "Offline" status in organization settings
- Jobs timeout waiting for runner
- Runner service appears to be running

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
# View runner logs
sudo journalctl -u actions.runner.* -f

# Check runner directory logs
tail -f ~/actions-runner/_diag/Runner_*.log
```

3. **Test Network Connectivity:**
```bash
# Test GitHub connectivity
curl -I https://github.com
curl -I https://api.github.com

# Test DNS resolution
nslookup github.com
nslookup api.github.com
```

**Solutions:**

1. **Restart Runner Service:**
```bash
cd ~/actions-runner
sudo ./svc.sh stop
sudo ./svc.sh start
```

2. **Check Security Group Rules:**
```bash
# Verify HTTPS outbound access
aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID
```

3. **Verify GitHub IP Ranges:**
```bash
# Get current GitHub IP ranges
curl https://api.github.com/meta | jq '.actions'

# Update security group if needed
```

#### Issue: "Jobs fail with 'No runners available'"

**Symptoms:**
- Workflows fail immediately with runner availability error
- Runner appears online in organization settings
- Other repositories can use the runner

**Causes:**
- Repository doesn't have access to organization runners
- Workflow uses incorrect runner labels
- Repository Actions are disabled

**Solutions:**

1. **Verify Repository Actions Settings:**
   - Go to Repository Settings → Actions → General
   - Ensure Actions are enabled
   - Check runner permissions

2. **Check Workflow Labels:**
```yaml
# Correct label usage
runs-on: [self-hosted, gha_aws_runner]

# Common mistakes
runs-on: gha_aws_runner  # Missing array format
runs-on: [self-hosted, wrong-label]  # Incorrect label
```

3. **Test Runner Access:**
```bash
# List organization runners
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners"

# Check repository Actions permissions
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_ORGANIZATION/$REPO_NAME/actions/permissions"
```

### 3. Cross-Repository Issues

#### Issue: "Runner contamination between repositories"

**Symptoms:**
- Files from previous jobs visible in new jobs
- Environment variables persisting between repositories
- Unexpected tool configurations

**Causes:**
- Ephemeral configuration not working
- Improper cleanup between jobs
- Shared file system contamination

**Diagnostic Steps:**

1. **Check Ephemeral Configuration:**
```bash
# Verify runner configuration
cd ~/actions-runner
cat .runner | jq '.ephemeral'
```

2. **Monitor Job Isolation:**
```bash
# Create test script to check isolation
cat > test-isolation.sh << 'EOF'
#!/bin/bash
echo "=== Job Isolation Test ==="
echo "Repository: $GITHUB_REPOSITORY"
echo "Run ID: $GITHUB_RUN_ID"
echo "Working Directory: $(pwd)"
echo "Home Directory: $HOME"
echo "Temp Files:"
ls -la /tmp/ | grep -E "(runner|github|actions)" || echo "No temp files found"
echo "Environment Variables:"
env | grep -E "(GITHUB|RUNNER)" | head -10
EOF
```

**Solutions:**

1. **Reconfigure Runner as Ephemeral:**
```bash
cd ~/actions-runner

# Remove current configuration
sudo ./svc.sh stop
sudo ./svc.sh uninstall

# Get new registration token
REGISTRATION_TOKEN=$(curl -s -X POST \
  -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/registration-token" | \
  jq -r '.token')

# Reconfigure with ephemeral flag
sudo -u ubuntu ./config.sh \
  --url "https://github.com/$GITHUB_ORGANIZATION" \
  --token "$REGISTRATION_TOKEN" \
  --name "gha_aws_runner" \
  --labels "gha_aws_runner" \
  --ephemeral \
  --unattended \
  --replace

# Reinstall service
sudo ./svc.sh install ubuntu
sudo ./svc.sh start
```

2. **Implement Manual Cleanup:**
```yaml
# Add cleanup step to workflows
- name: Cleanup workspace
  if: always()
  run: |
    # Clean temporary files
    rm -rf /tmp/github-* /tmp/runner-* || true
    
    # Clean workspace
    cd ${{ github.workspace }}
    git clean -ffdx || true
    
    # Reset environment
    unset $(env | grep -E "^(CUSTOM|APP)_" | cut -d= -f1) || true
```

#### Issue: "Performance degradation with multiple repositories"

**Symptoms:**
- Slower job execution times
- Increased queue times
- Resource exhaustion errors

**Diagnostic Steps:**

1. **Monitor System Resources:**
```bash
# Check CPU and memory usage
top -bn1 | head -20

# Check disk usage
df -h

# Check running processes
ps aux | grep -E "(runner|github|actions)"
```

2. **Analyze Job Patterns:**
```bash
# Get recent workflow runs
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runs?per_page=50" | \
  jq '.workflow_runs[] | {repo: .repository.name, status: .status, created: .created_at, updated: .updated_at}'
```

**Solutions:**

1. **Optimize Instance Size:**
```hcl
# In terraform.tfvars
instance_type = "t3.small"  # Upgrade from t3.micro
```

2. **Implement Job Limits:**
```yaml
# Add timeout and resource limits
jobs:
  build:
    runs-on: [self-hosted, gha_aws_runner]
    timeout-minutes: 30  # Prevent runaway jobs
    steps:
      - name: Resource check
        run: |
          # Check available resources before starting
          free -h
          df -h
```

3. **Scale Runner Infrastructure:**
   - Deploy multiple runner instances
   - Use different runner labels for different workloads
   - Implement load balancing strategies

### 4. AWS Infrastructure Issues

#### Issue: "EC2 instance fails to start"

**Symptoms:**
- AWS CLI commands timeout
- Instance stuck in "pending" state
- SSH connection failures

**Diagnostic Steps:**

1. **Check Instance Status:**
```bash
aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID
```

2. **Check Instance Logs:**
```bash
aws ec2 get-console-output --instance-id $EC2_INSTANCE_ID
```

3. **Verify Security Groups:**
```bash
aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID
```

**Solutions:**

1. **Check AWS Service Health:**
   - Visit AWS Service Health Dashboard
   - Verify region availability
   - Check for service disruptions

2. **Verify IAM Permissions:**
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

3. **Check Instance Limits:**
```bash
# Check EC2 limits
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A  # Running On-Demand instances
```

#### Issue: "Security group blocks GitHub access"

**Symptoms:**
- Runner can't connect to GitHub
- Registration fails with network errors
- Jobs fail with connectivity issues

**Diagnostic Steps:**

1. **Test GitHub Connectivity:**
```bash
# From EC2 instance
curl -v https://github.com
curl -v https://api.github.com
```

2. **Check Security Group Rules:**
```bash
aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID | \
  jq '.SecurityGroups[0].IpPermissionsEgress'
```

**Solutions:**

1. **Update Security Group Rules:**
```bash
# Allow HTTPS outbound to GitHub IP ranges
GITHUB_IPS=$(curl -s https://api.github.com/meta | jq -r '.actions[]')

for ip in $GITHUB_IPS; do
  aws ec2 authorize-security-group-egress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 443 \
    --cidr $ip
done
```

2. **Use Terraform to Manage Rules:**
```hcl
# In security.tf
data "http" "github_meta" {
  url = "https://api.github.com/meta"
}

locals {
  github_actions_ips = jsondecode(data.http.github_meta.body).actions
}

resource "aws_security_group_rule" "github_actions_egress" {
  count             = length(local.github_actions_ips)
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [local.github_actions_ips[count.index]]
  security_group_id = aws_security_group.runner.id
}
```

### 5. GitHub Organization Settings Issues

#### Issue: "Organization doesn't allow self-hosted runners"

**Symptoms:**
- Runner registration succeeds but jobs fail
- Organization settings show restrictions
- API calls return permission errors

**Solutions:**

1. **Check Organization Settings:**
   - Go to Organization Settings → Actions → General
   - Under "Runners", ensure "Allow organization runners" is enabled
   - Check runner group permissions

2. **Verify Runner Groups:**
   - Go to Organization Settings → Actions → Runner groups
   - Ensure appropriate repositories have access
   - Check runner group policies

3. **Update Organization Policies:**
```bash
# Check current organization Actions permissions
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/permissions"

# Update if necessary (requires admin permissions)
curl -X PUT -H "Authorization: token $GH_PAT" \
  -H "Content-Type: application/json" \
  -d '{"enabled_repositories": "all", "allowed_actions": "all"}' \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/permissions"
```

## Diagnostic Scripts

### 1. Comprehensive Health Check Script

```bash
#!/bin/bash
# File: scripts/health-check.sh

set -e

GITHUB_ORGANIZATION="${GITHUB_ORGANIZATION:-}"
GH_PAT="${GH_PAT:-}"
EC2_INSTANCE_ID="${EC2_INSTANCE_ID:-}"

echo "=== Organization Runner Health Check ==="
echo "Organization: $GITHUB_ORGANIZATION"
echo "Instance ID: $EC2_INSTANCE_ID"
echo "Timestamp: $(date -u)"
echo ""

# Check 1: Prerequisites
echo "=== 1. Prerequisites Check ==="
command -v curl >/dev/null && echo "✓ curl installed" || echo "✗ curl missing"
command -v jq >/dev/null && echo "✓ jq installed" || echo "✗ jq missing"
command -v aws >/dev/null && echo "✓ aws cli installed" || echo "✗ aws cli missing"

[ -n "$GITHUB_ORGANIZATION" ] && echo "✓ GITHUB_ORGANIZATION set" || echo "✗ GITHUB_ORGANIZATION missing"
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

# Check 3: Organization Access
echo ""
echo "=== 3. Organization Access ==="
ORG_RESPONSE=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION")
ORG_HTTP_CODE="${ORG_RESPONSE: -3}"

if [ "$ORG_HTTP_CODE" = "200" ]; then
    echo "✓ Organization access working"
else
    echo "✗ Organization access failed (HTTP $ORG_HTTP_CODE)"
fi

# Check 4: Runner Registration Token
echo ""
echo "=== 4. Runner Registration Token ==="
TOKEN_RESPONSE=$(curl -s -w "%{http_code}" -X POST \
  -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners/registration-token")
TOKEN_HTTP_CODE="${TOKEN_RESPONSE: -3}"

if [ "$TOKEN_HTTP_CODE" = "201" ]; then
    echo "✓ Registration token generation working"
else
    echo "✗ Registration token generation failed (HTTP $TOKEN_HTTP_CODE)"
fi

# Check 5: EC2 Instance Status
echo ""
echo "=== 5. EC2 Instance Status ==="
if INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null); then
    echo "✓ EC2 instance state: $INSTANCE_STATE"
    
    if [ "$INSTANCE_STATE" = "running" ]; then
        PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
          --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
        echo "✓ Public IP: $PUBLIC_IP"
    fi
else
    echo "✗ Failed to get EC2 instance status"
fi

# Check 6: Organization Runners
echo ""
echo "=== 6. Organization Runners ==="
RUNNERS_RESPONSE=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners")
RUNNERS_HTTP_CODE="${RUNNERS_RESPONSE: -3}"

if [ "$RUNNERS_HTTP_CODE" = "200" ]; then
    RUNNERS_BODY="${RUNNERS_RESPONSE%???}"
    RUNNER_COUNT=$(echo "$RUNNERS_BODY" | jq '.total_count')
    echo "✓ Organization runners API working ($RUNNER_COUNT runners)"
    
    if [ "$RUNNER_COUNT" -gt 0 ]; then
        echo "Runners:"
        echo "$RUNNERS_BODY" | jq -r '.runners[] | "  - \(.name) (\(.status))"'
    fi
else
    echo "✗ Organization runners API failed (HTTP $RUNNERS_HTTP_CODE)"
fi

echo ""
echo "=== Health Check Complete ==="
```

### 2. Runner Connectivity Test Script

```bash
#!/bin/bash
# File: scripts/test-connectivity.sh

EC2_INSTANCE_IP="${1:-}"

if [ -z "$EC2_INSTANCE_IP" ]; then
    echo "Usage: $0 <EC2_INSTANCE_IP>"
    exit 1
fi

echo "=== Runner Connectivity Test ==="
echo "Instance IP: $EC2_INSTANCE_IP"
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

# Test 3: Remote Connectivity (via SSH)
echo ""
echo "=== 3. Remote Connectivity (via SSH) ==="
if command -v ssh >/dev/null && [ -f ~/.ssh/id_rsa ]; then
    echo "Testing connectivity from EC2 instance..."
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@"$EC2_INSTANCE_IP" '
        echo "Connected to $(hostname)"
        echo "Testing GitHub connectivity from instance:"
        curl -I https://github.com >/dev/null 2>&1 && echo "✓ GitHub.com accessible from instance" || echo "✗ GitHub.com not accessible from instance"
        curl -I https://api.github.com >/dev/null 2>&1 && echo "✓ GitHub API accessible from instance" || echo "✗ GitHub API not accessible from instance"
        
        echo "Testing DNS resolution:"
        nslookup github.com >/dev/null 2>&1 && echo "✓ DNS resolution working" || echo "✗ DNS resolution failed"
        
        echo "Checking runner service:"
        if [ -d ~/actions-runner ]; then
            cd ~/actions-runner
            sudo ./svc.sh status | grep -q "active (running)" && echo "✓ Runner service active" || echo "✗ Runner service not active"
        else
            echo "✗ Runner not installed"
        fi
    ' 2>/dev/null || echo "✗ SSH connection failed"
else
    echo "⚠ SSH key not found or SSH not available - skipping remote tests"
fi

echo ""
echo "=== Connectivity Test Complete ==="
```

## Prevention and Monitoring

### 1. Proactive Monitoring

Set up monitoring to catch issues early:

```bash
#!/bin/bash
# File: scripts/monitor-runner.sh

# Run this script periodically (e.g., via cron) to monitor runner health

GITHUB_ORGANIZATION="${GITHUB_ORGANIZATION:-}"
GH_PAT="${GH_PAT:-}"
ALERT_EMAIL="${ALERT_EMAIL:-admin@example.com}"

check_runner_health() {
    local response
    response=$(curl -s -w "%{http_code}" -H "Authorization: token $GH_PAT" \
      "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners")
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" != "200" ]; then
        echo "ALERT: Runner API access failed (HTTP $http_code)"
        return 1
    fi
    
    local online_runners
    online_runners=$(echo "$body" | jq '[.runners[] | select(.status == "online")] | length')
    
    if [ "$online_runners" -eq 0 ]; then
        echo "ALERT: No online runners found"
        return 1
    fi
    
    echo "OK: $online_runners runner(s) online"
    return 0
}

# Run health check and alert if needed
if ! check_runner_health; then
    # Send alert (implement your preferred alerting method)
    echo "Runner health check failed at $(date)" | mail -s "Runner Alert" "$ALERT_EMAIL"
fi
```

### 2. Automated Recovery

Implement automated recovery procedures:

```bash
#!/bin/bash
# File: scripts/auto-recovery.sh

# Automated recovery script for common runner issues

recover_runner() {
    echo "=== Automated Runner Recovery ==="
    
    # Step 1: Check if instance is running
    local instance_state
    instance_state=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].State.Name' --output text)
    
    if [ "$instance_state" != "running" ]; then
        echo "Starting EC2 instance..."
        aws ec2 start-instances --instance-ids "$EC2_INSTANCE_ID"
        aws ec2 wait instance-running --instance-ids "$EC2_INSTANCE_ID"
    fi
    
    # Step 2: Get instance IP
    local public_ip
    public_ip=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    
    # Step 3: Restart runner service
    echo "Restarting runner service..."
    ssh -o ConnectTimeout=30 ubuntu@"$public_ip" '
        cd ~/actions-runner
        sudo ./svc.sh stop
        sleep 5
        sudo ./svc.sh start
    '
    
    # Step 4: Verify recovery
    sleep 30
    if check_runner_health; then
        echo "✓ Recovery successful"
        return 0
    else
        echo "✗ Recovery failed"
        return 1
    fi
}

# Run recovery if health check fails
if ! check_runner_health; then
    recover_runner
fi
```

## Getting Help

### 1. GitHub Support Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Self-hosted Runners Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
- [GitHub Community Forum](https://github.community/)
- [GitHub Support](https://support.github.com/)

### 2. AWS Support Resources

- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [AWS Support Center](https://console.aws.amazon.com/support/)
- [AWS Community Forums](https://forums.aws.amazon.com/)

### 3. Collecting Diagnostic Information

When seeking help, collect this information:

```bash
#!/bin/bash
# File: scripts/collect-diagnostics.sh

echo "=== Diagnostic Information Collection ==="
echo "Timestamp: $(date -u)"
echo ""

echo "=== Environment ==="
echo "OS: $(uname -a)"
echo "GitHub Organization: $GITHUB_ORGANIZATION"
echo "EC2 Instance ID: $EC2_INSTANCE_ID"
echo ""

echo "=== GitHub API Test ==="
curl -s -H "Authorization: token $GH_PAT" https://api.github.com/user | jq '.login'
echo ""

echo "=== Organization Runners ==="
curl -s -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners" | \
  jq '.runners[] | {name: .name, status: .status, busy: .busy}'
echo ""

echo "=== EC2 Instance Status ==="
aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" | \
  jq '.Reservations[0].Instances[0] | {state: .State.Name, ip: .PublicIpAddress}'
echo ""

echo "=== Recent Workflow Runs ==="
curl -s -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runs?per_page=5" | \
  jq '.workflow_runs[] | {repo: .repository.name, status: .status, conclusion: .conclusion}'
```

This troubleshooting guide should help you diagnose and resolve most common issues with organization-level GitHub Actions runners. Remember to always check the basics first (permissions, connectivity, configuration) before diving into complex debugging procedures.