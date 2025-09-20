# Repository Runner Troubleshooting Guide

This guide provides comprehensive troubleshooting steps for repository-level GitHub Actions runners, including common issues, debugging techniques, and solutions.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Common Issues](#common-issues)
- [Debugging Workflows](#debugging-workflows)
- [Error Messages and Solutions](#error-messages-and-solutions)
- [Performance Issues](#performance-issues)
- [Security Troubleshooting](#security-troubleshooting)
- [Advanced Diagnostics](#advanced-diagnostics)

## Quick Diagnostics

### Pre-flight Checklist

Before troubleshooting, verify these basic requirements:

```bash
# 1. Check repository secrets
# Go to: Repository Settings → Secrets and variables → Actions
# Required secrets:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY
# - AWS_REGION
# - GH_PAT
# - EC2_INSTANCE_ID
# - RUNNER_NAME (optional)

# 2. Verify GitHub PAT permissions
curl -H "Authorization: token $GH_PAT" https://api.github.com/user

# 3. Test AWS credentials
aws sts get-caller-identity

# 4. Check EC2 instance exists
aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID
```

### Quick Status Check

Run this workflow to get a comprehensive status overview:

1. Go to **Actions** tab in your repository
2. Run **"Test Repository Runner"** workflow
3. Select **"basic"** test scenario
4. Review the validation results

## Common Issues

### 1. Runner Not Appearing in Repository

**Symptoms:**
- Workflow shows runner registration success
- Runner doesn't appear in Settings → Actions → Runners
- Jobs remain queued indefinitely

**Diagnosis:**
```bash
# Check if runner is registered via API
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$OWNER/$REPO/actions/runners"

# Check EC2 instance status
aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].State.Name'

# SSH to instance and check runner service
ssh ubuntu@$INSTANCE_IP
cd ~/actions-runner
sudo ./svc.sh status
```

**Solutions:**
1. **Service not running:**
   ```bash
   sudo ./svc.sh start
   ```

2. **Configuration issues:**
   ```bash
   # Remove and reconfigure
   sudo ./svc.sh stop
   sudo ./svc.sh uninstall
   sudo -u ubuntu ./config.sh remove --token $TOKEN
   # Then reconfigure with new token
   ```

3. **Network connectivity:**
   - Check security groups allow outbound HTTPS (443)
   - Verify instance has internet access
   - Check DNS resolution

### 2. Authentication Failures

**Symptoms:**
- HTTP 401 or 403 errors in workflow logs
- "Bad credentials" messages
- Token generation failures

**Diagnosis:**
```bash
# Test GitHub PAT
curl -I -H "Authorization: token $GH_PAT" https://api.github.com/user

# Check PAT scopes
curl -I -H "Authorization: token $GH_PAT" https://api.github.com/user | grep x-oauth-scopes

# Test repository access
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$OWNER/$REPO"
```

**Solutions:**
1. **Invalid PAT:**
   - Generate new GitHub PAT with `repo` scope
   - Update `GH_PAT` secret in repository

2. **Insufficient permissions:**
   - Ensure you have admin access to the repository
   - For organization repositories, check organization policies

3. **Expired token:**
   - GitHub PATs expire based on organization settings
   - Generate new token and update secret

### 3. EC2 Instance Issues

**Symptoms:**
- Instance fails to start
- SSH connection timeouts
- Instance not found errors

**Diagnosis:**
```bash
# Check instance status
aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID

# Check instance logs
aws logs get-log-events --log-group-name /aws/ec2/instances \
  --log-stream-name $EC2_INSTANCE_ID

# Test SSH connectivity
nc -zv $INSTANCE_IP 22
```

**Solutions:**
1. **Instance stopped:**
   ```bash
   aws ec2 start-instances --instance-ids $EC2_INSTANCE_ID
   aws ec2 wait instance-running --instance-ids $EC2_INSTANCE_ID
   ```

2. **SSH access issues:**
   - Check security group allows SSH (port 22) from GitHub Actions IPs
   - Verify SSH key configuration
   - Check instance user data script execution

3. **Instance terminated:**
   - Redeploy using Terraform
   - Check AWS account limits and billing

### 4. Workflow Execution Failures

**Symptoms:**
- Jobs fail to start on self-hosted runner
- "No runner available" messages
- Jobs stuck in queued state

**Diagnosis:**
```bash
# Check runner labels
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$OWNER/$REPO/actions/runners" | \
  jq '.runners[] | {name: .name, status: .status, labels: [.labels[].name]}'

# Check workflow file syntax
# Ensure runs-on matches runner labels: [self-hosted, gha_aws_runner]
```

**Solutions:**
1. **Label mismatch:**
   ```yaml
   # Correct workflow syntax
   jobs:
     my-job:
       runs-on: [self-hosted, gha_aws_runner]
   ```

2. **Runner offline:**
   - Check runner service status on EC2 instance
   - Restart runner service if needed
   - Re-register runner if configuration is corrupted

3. **Resource constraints:**
   - Check EC2 instance has sufficient resources
   - Monitor disk space and memory usage
   - Consider upgrading instance type

## Debugging Workflows

### Enable Debug Logging

Add these environment variables to your workflow:

```yaml
env:
  ACTIONS_STEP_DEBUG: true
  ACTIONS_RUNNER_DEBUG: true
```

### Debug Workflow Template

Use this workflow for comprehensive debugging:

```yaml
name: Debug Repository Runner
on:
  workflow_dispatch:
    inputs:
      debug_level:
        description: 'Debug level'
        required: true
        default: 'basic'
        type: choice
        options:
        - basic
        - detailed
        - comprehensive

jobs:
  debug-runner:
    runs-on: ubuntu-latest
    steps:
      - name: Debug GitHub context
        run: |
          echo "Repository: ${{ github.repository }}"
          echo "Actor: ${{ github.actor }}"
          echo "Event: ${{ github.event_name }}"
          echo "Ref: ${{ github.ref }}"
          
      - name: Test GitHub API access
        run: |
          curl -H "Authorization: token ${{ secrets.GH_PAT }}" \
            "https://api.github.com/repos/${{ github.repository }}"
            
      - name: Test AWS access
        run: |
          aws sts get-caller-identity
          aws ec2 describe-instances --instance-ids ${{ secrets.EC2_INSTANCE_ID }}
          
      - name: Test runner registration
        run: |
          curl -X POST \
            -H "Authorization: token ${{ secrets.GH_PAT }}" \
            "https://api.github.com/repos/${{ github.repository }}/actions/runners/registration-token"
```

### SSH Debugging

If you need to debug the EC2 instance directly:

```bash
# Get instance IP
INSTANCE_IP=$(aws ec2 describe-instances \
  --instance-ids $EC2_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

# SSH to instance (requires SSH key access)
ssh -i ~/.ssh/your-key.pem ubuntu@$INSTANCE_IP

# Check runner status
cd ~/actions-runner
sudo ./svc.sh status

# Check runner logs
sudo journalctl -u actions.runner.* -f

# Check system logs
sudo tail -f /var/log/syslog
```

## Error Messages and Solutions

### "Bad credentials" (HTTP 401)

**Cause:** Invalid or expired GitHub PAT

**Solution:**
1. Generate new GitHub PAT with `repo` scope
2. Update `GH_PAT` secret in repository settings
3. Ensure PAT hasn't expired

### "Not Found" (HTTP 404)

**Cause:** Repository doesn't exist or no access

**Solution:**
1. Verify repository name is correct
2. Check GitHub PAT has access to repository
3. Ensure repository isn't private without proper access

### "Forbidden" (HTTP 403)

**Cause:** Insufficient permissions

**Solution:**
1. Ensure you have admin permissions on repository
2. Check organization policies don't block self-hosted runners
3. Verify GitHub PAT has required scopes

### "InvalidInstanceID.NotFound"

**Cause:** EC2 instance doesn't exist

**Solution:**
1. Verify `EC2_INSTANCE_ID` secret is correct
2. Check instance wasn't terminated
3. Ensure you're using correct AWS region

### "UnauthorizedOperation"

**Cause:** AWS credentials lack required permissions

**Solution:**
1. Verify AWS credentials are correct
2. Ensure IAM user/role has EC2 permissions
3. Check AWS region matches instance location

### "Connection timeout"

**Cause:** Network connectivity issues

**Solution:**
1. Check security groups allow required traffic
2. Verify instance has public IP
3. Check VPC routing and internet gateway

## Performance Issues

### Slow Job Execution

**Diagnosis:**
```bash
# Check instance type and resources
aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].{Type:InstanceType,State:State.Name}'

# Monitor resource usage on instance
ssh ubuntu@$INSTANCE_IP
htop
df -h
free -h
```

**Solutions:**
1. **Upgrade instance type:**
   - Modify Terraform configuration
   - Use larger instance for resource-intensive jobs

2. **Optimize workflows:**
   - Cache dependencies
   - Parallelize jobs
   - Use local Docker registry

3. **Storage optimization:**
   - Clean up old Docker images
   - Use EBS-optimized instances
   - Monitor disk usage

### High Costs

**Diagnosis:**
```bash
# Check instance running time
aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].LaunchTime'

# Monitor usage patterns in AWS Cost Explorer
```

**Solutions:**
1. **Implement auto-stop:**
   - Stop instance after job completion
   - Use scheduled workflows for regular tasks

2. **Right-size instance:**
   - Use t3.micro for light workloads
   - Consider spot instances for non-critical jobs

3. **Optimize usage:**
   - Batch multiple jobs
   - Use workflow_dispatch for manual testing
   - Monitor and analyze usage patterns

## Security Troubleshooting

### Runner Security Issues

**Check security configuration:**
```bash
# Verify security groups
aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID

# Check instance metadata access
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/

# Verify runner isolation
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$OWNER/$REPO/actions/runners"
```

**Security best practices:**
1. **Minimal PAT scopes:** Use only `repo` scope
2. **Private repositories:** Don't use self-hosted runners with public repos
3. **Network security:** Restrict security group rules
4. **Regular updates:** Keep runner software updated
5. **Monitoring:** Enable CloudTrail and CloudWatch logging

### Access Control Issues

**Symptoms:**
- Unauthorized access to runner
- Cross-repository access
- Privilege escalation

**Solutions:**
1. **Repository isolation:**
   - Verify runner is registered to correct repository only
   - Check no organization-level registration

2. **Network isolation:**
   - Use dedicated VPC for runners
   - Implement network ACLs
   - Monitor network traffic

3. **Credential management:**
   - Rotate GitHub PAT regularly
   - Use IAM roles instead of access keys when possible
   - Monitor credential usage

## Advanced Diagnostics

### Comprehensive Health Check

Run this script for complete system diagnosis:

```bash
#!/bin/bash
# comprehensive-health-check.sh

echo "=== Repository Runner Health Check ==="
echo "Timestamp: $(date)"
echo ""

# 1. GitHub API connectivity
echo "1. GitHub API Connectivity"
if curl -s -H "Authorization: token $GH_PAT" https://api.github.com/user > /dev/null; then
    echo "✅ GitHub API: Connected"
else
    echo "❌ GitHub API: Failed"
fi

# 2. AWS API connectivity
echo "2. AWS API Connectivity"
if aws sts get-caller-identity > /dev/null 2>&1; then
    echo "✅ AWS API: Connected"
else
    echo "❌ AWS API: Failed"
fi

# 3. EC2 instance status
echo "3. EC2 Instance Status"
INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
    --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null)
echo "Instance state: $INSTANCE_STATE"

# 4. Runner registration status
echo "4. Runner Registration Status"
RUNNERS=$(curl -s -H "Authorization: token $GH_PAT" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runners")
RUNNER_COUNT=$(echo "$RUNNERS" | jq -r '.total_count // 0')
echo "Registered runners: $RUNNER_COUNT"

# 5. Network connectivity
echo "5. Network Connectivity"
if [ "$INSTANCE_STATE" = "running" ]; then
    INSTANCE_IP=$(aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    if nc -zv $INSTANCE_IP 22 2>/dev/null; then
        echo "✅ SSH connectivity: OK"
    else
        echo "❌ SSH connectivity: Failed"
    fi
fi

echo ""
echo "Health check completed"
```

### Log Analysis

**GitHub Actions logs:**
- Check workflow run logs in Actions tab
- Look for specific error messages and HTTP status codes
- Review job execution times and resource usage

**AWS CloudWatch logs:**
- EC2 instance logs: `/aws/ec2/instances`
- VPC Flow Logs: Network traffic analysis
- CloudTrail: API call auditing

**Runner logs on EC2:**
```bash
# Runner service logs
sudo journalctl -u actions.runner.* --since "1 hour ago"

# System logs
sudo tail -100 /var/log/syslog

# Docker logs (if using Docker)
sudo docker logs $(sudo docker ps -q)
```

### Performance Profiling

**Monitor resource usage:**
```bash
# CPU and memory usage
top -b -n 1

# Disk I/O
iostat -x 1 5

# Network usage
iftop -t -s 10

# Process monitoring
ps aux --sort=-%cpu | head -20
```

**Workflow performance analysis:**
```yaml
# Add timing to workflow steps
- name: Performance monitoring
  run: |
    echo "Job start time: $(date)"
    time your-command-here
    echo "Job end time: $(date)"
```

## Getting Help

If you're still experiencing issues after following this guide:

1. **Check GitHub Status:** https://www.githubstatus.com/
2. **Check AWS Status:** https://status.aws.amazon.com/
3. **Review Documentation:** 
   - [GitHub Actions Documentation](https://docs.github.com/en/actions)
   - [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
4. **Community Support:**
   - GitHub Community Forum
   - Stack Overflow (tags: github-actions, aws-ec2)
5. **Professional Support:**
   - GitHub Support (for GitHub-related issues)
   - AWS Support (for AWS-related issues)

## Preventive Measures

To avoid common issues:

1. **Regular maintenance:**
   - Update runner software monthly
   - Rotate credentials quarterly
   - Review and update security groups

2. **Monitoring:**
   - Set up CloudWatch alarms for instance health
   - Monitor workflow execution times
   - Track costs and usage patterns

3. **Documentation:**
   - Keep configuration documentation updated
   - Document any custom modifications
   - Maintain troubleshooting runbooks

4. **Testing:**
   - Run health checks regularly
   - Test disaster recovery procedures
   - Validate security configurations

Remember: Always test changes in a non-production environment first!