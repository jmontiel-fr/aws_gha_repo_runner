# Troubleshooting Resources Summary

This document provides a quick reference to all available troubleshooting resources for the repository-level GitHub Actions runner setup.

## 📚 Documentation Files

### Core Troubleshooting Guides
- **[Repository Troubleshooting Guide](repository-troubleshooting-guide.md)** - Comprehensive troubleshooting for repository-level issues
- **[Repository Migration Guide](repository-migration-guide.md)** - Step-by-step migration from organization to repository setup
- **[Repository Switching Guide](repository-switching-guide.md)** - How to switch runner between different repositories
- **[Repository Validation Guide](repository-validation-guide.md)** - Validation procedures and best practices

### Setup and Configuration Guides
- **[GitHub Runner Installation Guide](github-runner-setup.md)** - Complete setup instructions for repository-level runners
- **[Example Workflows Guide](example-workflows-guide.md)** - Working workflow examples and templates

### Testing and Validation
- **[Cross-Repository Testing](cross-repository-testing.md)** - Testing across multiple repositories
- **[Repository Runner Troubleshooting](repository-runner-troubleshooting.md)** - Specific runner troubleshooting procedures

## 🛠️ Scripts and Tools

### Repository Management Scripts
| Script | Purpose | Usage |
|--------|---------|-------|
| `create-repository-runner.sh` | Provision dedicated EC2 instance | `./scripts/create-repository-runner.sh --username johndoe --repository my-app --key-pair my-key` |
| `configure-repository-runner.sh` | Configure runner on instance | `./scripts/configure-repository-runner.sh --username johndoe --repository my-app --instance-id i-xxx --pat ghp_xxx` |
| `destroy-repository-runner.sh` | Clean up repository resources | `./scripts/destroy-repository-runner.sh --username johndoe --repository my-app` |

### Validation and Testing Scripts
| Script | Purpose | Usage |
|--------|---------|-------|
| `validate-repository-configuration.sh` | Comprehensive validation | `./scripts/validate-repository-configuration.sh` |
| `health-check-runner.sh` | Monitor runner health | `./scripts/health-check-runner.sh` |
| `run-comprehensive-tests.sh` | Run all tests | `./scripts/run-comprehensive-tests.sh` |
| `test-repository-setup.sh` | Test setup process | `./scripts/test-repository-setup.sh` |
| `test-workflow-integration.sh` | Test workflow integration | `./scripts/test-workflow-integration.sh` |

### Legacy and Utility Scripts
| Script | Purpose | Usage |
|--------|---------|-------|
| `repo-runner-setup.sh` | Legacy repository setup | `./scripts/repo-runner-setup.sh` |
| `switch-repository-runner.sh` | Switch between repositories | `./scripts/switch-repository-runner.sh` |
| `repo-validation-functions.sh` | Validation function library | `source scripts/repo-validation-functions.sh` |

## 🚨 Quick Troubleshooting Checklist

### Before You Start
Run the comprehensive validation script:
```bash
export GITHUB_USERNAME="your-username"
export GITHUB_REPOSITORY="your-repository"
export GH_PAT="your-github-pat"
./scripts/validate-repository-configuration.sh
```

### Common Issues Quick Reference

#### 1. Runner Registration Fails
```bash
# Check GitHub PAT permissions
curl -H "Authorization: token $GH_PAT" https://api.github.com/user

# Validate repository access
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY"

# Test registration token generation
curl -X POST -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners/registration-token"
```

#### 2. Instance Won't Start
```bash
# Check instance status
aws ec2 describe-instances --instance-ids $INSTANCE_ID

# Check AWS credentials
aws sts get-caller-identity

# Validate instance exists
./scripts/health-check-runner.sh
```

#### 3. SSH Connection Issues
```bash
# Test SSH connectivity
nc -z -w5 $INSTANCE_IP 22

# Check security groups
aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID

# Update IP if changed
curl ifconfig.me
```

#### 4. Runner Appears Offline
```bash
# Check runner service on instance
ssh ubuntu@$INSTANCE_IP 'sudo systemctl status actions.runner.*'

# Check runner logs
ssh ubuntu@$INSTANCE_IP 'sudo journalctl -u actions.runner.* -f'

# Restart runner service
ssh ubuntu@$INSTANCE_IP 'cd ~/actions-runner && sudo ./svc.sh restart'
```

#### 5. Workflow Fails with "No runners available"
```yaml
# Verify correct workflow syntax
jobs:
  my-job:
    runs-on: [self-hosted, gha_aws_runner]  # Correct format
```

```bash
# Check runner labels
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners" | \
  jq '.runners[] | {name: .name, labels: [.labels[].name]}'
```

## 🔧 Diagnostic Commands

### Repository Health Check
```bash
# Quick health check
./scripts/health-check-runner.sh

# Comprehensive validation
./scripts/validate-repository-configuration.sh

# Test all components
./scripts/run-comprehensive-tests.sh
```

### GitHub API Diagnostics
```bash
# Test authentication
curl -H "Authorization: token $GH_PAT" https://api.github.com/user

# Check repository access
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY"

# List repository runners
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/runners"

# Check Actions permissions
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$GITHUB_USERNAME/$GITHUB_REPOSITORY/actions/permissions"
```

### AWS Infrastructure Diagnostics
```bash
# Check instance status
aws ec2 describe-instances --instance-ids $INSTANCE_ID

# Check security groups
aws ec2 describe-security-groups --group-ids $SECURITY_GROUP_ID

# Test AWS permissions
aws ec2 describe-instances --max-items 1

# Check service quotas
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A
```

### Instance Diagnostics
```bash
# SSH to instance
ssh ubuntu@$INSTANCE_IP

# Check system resources
free -h && df -h && top -bn1 | head -10

# Check runner status
cd ~/actions-runner && sudo ./svc.sh status

# Check runner logs
sudo journalctl -u actions.runner.* --no-pager -n 50

# Check network connectivity
curl -I https://api.github.com
```

## 📞 Getting Help

### Self-Service Resources
1. **Run Diagnostics**: Start with `./scripts/validate-repository-configuration.sh`
2. **Check Documentation**: Review the specific troubleshooting guide for your issue
3. **Test Components**: Use individual test scripts to isolate problems
4. **Review Logs**: Check both GitHub Actions logs and EC2 instance logs

### Documentation Hierarchy
1. **Quick Issues**: Use this summary for common problems
2. **Detailed Issues**: Refer to [Repository Troubleshooting Guide](repository-troubleshooting-guide.md)
3. **Setup Issues**: Check [GitHub Runner Installation Guide](github-runner-setup.md)
4. **Migration Issues**: See [Repository Migration Guide](repository-migration-guide.md)

### Script-Based Diagnostics
```bash
# Run comprehensive diagnostics
./scripts/run-comprehensive-tests.sh

# Health check with detailed output
./scripts/health-check-runner.sh --verbose

# Validate specific configuration
./scripts/validate-repository-configuration.sh --detailed
```

## 🔄 Recovery Procedures

### Complete Runner Reset
```bash
# 1. Unregister runner
./scripts/destroy-repository-runner.sh --username $USERNAME --repository $REPO --no-instance-cleanup

# 2. Clean instance configuration
ssh ubuntu@$INSTANCE_IP 'cd ~/actions-runner && sudo ./svc.sh stop && sudo ./svc.sh uninstall'

# 3. Reconfigure runner
./scripts/configure-repository-runner.sh --username $USERNAME --repository $REPO --instance-id $INSTANCE_ID --pat $GH_PAT
```

### Instance Recreation
```bash
# 1. Destroy existing instance
./scripts/destroy-repository-runner.sh --username $USERNAME --repository $REPO --force

# 2. Create new instance
./scripts/create-repository-runner.sh --username $USERNAME --repository $REPO --key-pair $KEY_PAIR

# 3. Configure new runner
./scripts/configure-repository-runner.sh --username $USERNAME --repository $REPO --instance-id $NEW_INSTANCE_ID --pat $GH_PAT
```

### Repository Migration
```bash
# Use the switching script for clean migration
export CURRENT_GITHUB_USERNAME="old-user"
export CURRENT_GITHUB_REPOSITORY="old-repo"
export NEW_GITHUB_USERNAME="new-user"
export NEW_GITHUB_REPOSITORY="new-repo"
export GH_PAT="your-pat"

./scripts/switch-repository-runner.sh
```

This summary provides quick access to all troubleshooting resources and common solutions for repository-level GitHub Actions runner issues.