# Installation Troubleshooting Guide

This guide provides comprehensive troubleshooting information for the enhanced GitHub Actions runner installation process, covering common issues, error codes, and resolution steps.

## Table of Contents

- [Overview](#overview)
- [Error Codes Reference](#error-codes-reference)
- [Common Installation Issues](#common-installation-issues)
- [System State Issues](#system-state-issues)
- [Package Management Issues](#package-management-issues)
- [Network Connectivity Issues](#network-connectivity-issues)
- [GitHub Authentication Issues](#github-authentication-issues)
- [Resource Constraint Issues](#resource-constraint-issues)
- [Advanced Troubleshooting](#advanced-troubleshooting)
- [Diagnostic Tools](#diagnostic-tools)
- [Prevention Best Practices](#prevention-best-practices)

## Overview

The enhanced installation process includes robust error handling, automatic retry mechanisms, and comprehensive diagnostic information collection. When issues occur, the system provides detailed error messages, troubleshooting steps, and diagnostic data to help resolve problems quickly.

### Enhanced Installation Features

- **System Readiness Validation**: Waits for cloud-init and validates system resources
- **Package Manager Monitoring**: Detects and handles package lock conflicts
- **Retry Mechanisms**: Exponential backoff for transient failures
- **Comprehensive Logging**: Detailed logs and metrics collection
- **Error Recovery**: Automatic recovery from common issues

## Error Codes Reference

The installation system uses structured error codes to categorize different types of failures:

| Error Code | Category | Description |
|------------|----------|-------------|
| **100** | SYSTEM_NOT_READY | System is not ready for installation |
| **101** | CLOUD_INIT_TIMEOUT | Cloud-init failed to complete within timeout |
| **102** | INSUFFICIENT_RESOURCES | System lacks required resources (disk/memory) |
| **103** | NETWORK_CONNECTIVITY | Network connectivity issues |
| **200** | PACKAGE_MANAGER_BUSY | Package managers are busy or locked |
| **201** | PACKAGE_INSTALL_FAILED | Package installation failed after retries |
| **202** | DEPENDENCY_MISSING | Required dependencies are missing |
| **203** | DPKG_LOCK_TIMEOUT | dpkg locks could not be acquired |
| **300** | RUNNER_DOWNLOAD_FAILED | Failed to download GitHub Actions runner |
| **301** | RUNNER_CONFIG_FAILED | Runner configuration failed |
| **302** | RUNNER_SERVICE_FAILED | Runner service failed to start |
| **303** | GITHUB_AUTH_FAILED | GitHub authentication failed |
| **304** | GITHUB_REGISTRATION_FAILED | Runner registration with GitHub failed |
| **999** | UNKNOWN_ERROR | Unclassified error |

## Common Installation Issues

### Issue: Installation Hangs During System Readiness Check

**Symptoms:**
- Script appears to hang with "Waiting for cloud-init to complete..."
- No progress for several minutes

**Causes:**
- Cloud-init is taking longer than expected
- System updates are running in background
- Network connectivity issues

**Resolution:**
1. **Check cloud-init status:**
   ```bash
   ssh -i ~/.ssh/your-key.pem ubuntu@your-instance-ip
   cloud-init status --long
   ```

2. **Monitor cloud-init logs:**
   ```bash
   tail -f /var/log/cloud-init-output.log
   ```

3. **If cloud-init is stuck, clean and reboot:**
   ```bash
   sudo cloud-init clean --reboot
   ```

4. **Skip cloud-init waiting (not recommended):**
   ```bash
   # Add --force flag to skip cloud-init waiting
   ./scripts/configure-repository-runner.sh --force [other options]
   ```

### Issue: Package Installation Fails Repeatedly

**Symptoms:**
- Multiple retry attempts for package installation
- Error messages about dpkg locks or apt conflicts

**Causes:**
- Automatic updates running in background
- Previous installation was interrupted
- Package database corruption

**Resolution:**
1. **Check running package processes:**
   ```bash
   ps aux | grep -E '(apt|dpkg|unattended-upgrade)'
   ```

2. **Wait for automatic updates:**
   ```bash
   sudo systemctl status unattended-upgrades
   ```

3. **Manual cleanup if processes are stuck:**
   ```bash
   sudo killall apt apt-get dpkg
   sudo dpkg --configure -a
   sudo apt-get update
   ```

4. **Fix broken packages:**
   ```bash
   sudo apt-get install -f
   sudo apt-get autoremove
   sudo apt-get autoclean
   ```

### Issue: Runner Service Fails to Start

**Symptoms:**
- Installation completes but runner service is not active
- Runner doesn't appear in GitHub repository settings

**Causes:**
- Service installation failed
- Configuration file corruption
- Permission issues

**Resolution:**
1. **Check service status:**
   ```bash
   cd ~/actions-runner
   sudo ./svc.sh status
   ```

2. **Check service logs:**
   ```bash
   sudo journalctl -u actions.runner.* -f
   ```

3. **Reinstall service:**
   ```bash
   cd ~/actions-runner
   sudo ./svc.sh uninstall
   sudo ./svc.sh install ubuntu
   sudo ./svc.sh start
   ```

4. **Verify configuration:**
   ```bash
   cat ~/actions-runner/.runner
   cat ~/actions-runner/.credentials
   ```

## System State Issues

### Cloud-init Timeout (Error Code: 101)

**Description:** Cloud-init process is taking longer than the 10-minute timeout.

**Troubleshooting Steps:**

1. **Check cloud-init status:**
   ```bash
   cloud-init status
   cloud-init status --long
   ```

2. **Monitor cloud-init progress:**
   ```bash
   tail -f /var/log/cloud-init-output.log
   ```

3. **Check for errors:**
   ```bash
   grep -i error /var/log/cloud-init.log
   ```

4. **Common solutions:**
   - Wait longer for slow network connections
   - Check security group allows outbound traffic
   - Verify instance has internet connectivity

### Insufficient Resources (Error Code: 102)

**Description:** System lacks required disk space or memory.

**Troubleshooting Steps:**

1. **Check disk space:**
   ```bash
   df -h
   ```

2. **Free up space:**
   ```bash
   sudo apt-get clean
   sudo apt-get autoremove
   sudo journalctl --vacuum-time=7d
   ```

3. **Check memory:**
   ```bash
   free -h
   ```

4. **Consider instance upgrade:**
   - Use larger instance type (t3.small instead of t3.micro)
   - Add swap space as temporary solution

## Package Management Issues

### Package Manager Busy (Error Code: 200)

**Description:** Package managers (apt, dpkg) are currently busy or locked.

**Troubleshooting Steps:**

1. **Identify lock holders:**
   ```bash
   sudo lsof /var/lib/dpkg/lock*
   ```

2. **Check running processes:**
   ```bash
   ps aux | grep -E '(apt|dpkg|unattended-upgrade)'
   ```

3. **Wait for completion:**
   ```bash
   # The script automatically waits, but you can monitor manually
   sudo systemctl status unattended-upgrades
   ```

4. **Force unlock (use with caution):**
   ```bash
   sudo rm /var/lib/dpkg/lock*
   sudo dpkg --configure -a
   ```

### DPKG Lock Timeout (Error Code: 203)

**Description:** Could not acquire dpkg locks within the timeout period.

**Troubleshooting Steps:**

1. **Check lock files:**
   ```bash
   ls -la /var/lib/dpkg/lock*
   ```

2. **Identify processes holding locks:**
   ```bash
   sudo fuser /var/lib/dpkg/lock*
   ```

3. **Kill stuck processes (if safe):**
   ```bash
   sudo pkill -f apt
   sudo pkill -f dpkg
   ```

4. **Clean up and retry:**
   ```bash
   sudo dpkg --configure -a
   sudo apt-get update
   ```

## Network Connectivity Issues

### Network Connectivity (Error Code: 103)

**Description:** Cannot connect to required services (GitHub, package repositories).

**Troubleshooting Steps:**

1. **Test basic connectivity:**
   ```bash
   ping -c 3 8.8.8.8
   ping -c 3 github.com
   ```

2. **Test DNS resolution:**
   ```bash
   nslookup github.com
   nslookup api.github.com
   ```

3. **Test HTTPS connectivity:**
   ```bash
   curl -I https://api.github.com
   curl -I https://github.com
   ```

4. **Check security group rules:**
   - Ensure outbound HTTPS (443) is allowed
   - Ensure outbound HTTP (80) is allowed
   - Check NACLs if using custom VPC

5. **Check GitHub status:**
   - Visit: https://www.githubstatus.com/

## GitHub Authentication Issues

### GitHub Auth Failed (Error Code: 303)

**Description:** GitHub authentication failed during runner registration.

**Troubleshooting Steps:**

1. **Verify PAT validity:**
   ```bash
   curl -H "Authorization: token YOUR_PAT" https://api.github.com/user
   ```

2. **Check PAT permissions:**
   - Ensure 'repo' scope is enabled
   - For organization repos, ensure appropriate org permissions

3. **Verify repository access:**
   ```bash
   curl -H "Authorization: token YOUR_PAT" \
     "https://api.github.com/repos/USERNAME/REPOSITORY"
   ```

4. **Check repository settings:**
   - Ensure Actions are enabled
   - Verify you have admin permissions
   - Check if repository is archived or disabled

5. **Generate new PAT if needed:**
   - Visit: https://github.com/settings/tokens
   - Create new token with 'repo' scope

### GitHub Registration Failed (Error Code: 304)

**Description:** Runner registration with GitHub repository failed.

**Troubleshooting Steps:**

1. **Check repository Actions settings:**
   - Go to Repository → Settings → Actions → General
   - Ensure Actions are enabled
   - Check runner permissions

2. **Verify registration token:**
   ```bash
   # Test token generation
   curl -X POST -H "Authorization: token YOUR_PAT" \
     "https://api.github.com/repos/USERNAME/REPOSITORY/actions/runners/registration-token"
   ```

3. **Check existing runners:**
   ```bash
   curl -H "Authorization: token YOUR_PAT" \
     "https://api.github.com/repos/USERNAME/REPOSITORY/actions/runners"
   ```

4. **Remove conflicting runners:**
   - Go to Repository → Settings → Actions → Runners
   - Remove any existing runners with the same name

## Resource Constraint Issues

### Low Disk Space

**Symptoms:**
- Installation fails with disk space errors
- Package installation fails

**Resolution:**
1. **Check available space:**
   ```bash
   df -h /
   df -h /tmp
   ```

2. **Clean system:**
   ```bash
   sudo apt-get clean
   sudo apt-get autoremove
   sudo journalctl --vacuum-time=7d
   rm -rf /tmp/*
   ```

3. **Resize instance storage:**
   - Stop instance
   - Modify EBS volume size
   - Restart and extend filesystem

### Low Memory

**Symptoms:**
- Installation is very slow
- Processes are killed by OOM killer

**Resolution:**
1. **Check memory usage:**
   ```bash
   free -h
   top
   ```

2. **Add swap space:**
   ```bash
   sudo fallocate -l 1G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

3. **Upgrade instance type:**
   - Use t3.small or larger for better performance

## Advanced Troubleshooting

### Collecting Diagnostic Information

The enhanced installation process automatically collects diagnostic information when errors occur. You can also collect this manually:

```bash
# Run diagnostic collection
./scripts/installation-error-handler.sh --collect-diagnostics

# Or collect specific diagnostics
source scripts/installation-error-handler.sh
collect_system_diagnostics
collect_package_diagnostics
collect_network_diagnostics
collect_github_diagnostics USERNAME REPOSITORY PAT
```

### Manual Installation Steps

If the automated installation fails, you can perform manual installation:

1. **Download runner manually:**
   ```bash
   mkdir -p ~/actions-runner && cd ~/actions-runner
   RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
   curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
     "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
   tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
   ```

2. **Install dependencies manually:**
   ```bash
   sudo ./bin/installdependencies.sh
   ```

3. **Configure runner manually:**
   ```bash
   ./config.sh --url https://github.com/USERNAME/REPOSITORY \
     --token YOUR_REGISTRATION_TOKEN \
     --name runner-USERNAME-REPOSITORY \
     --labels self-hosted,gha_aws_runner \
     --unattended
   ```

4. **Install service manually:**
   ```bash
   sudo ./svc.sh install ubuntu
   sudo ./svc.sh start
   ```

### Debug Mode

Enable debug mode for verbose logging:

```bash
DEBUG=true ./scripts/configure-repository-runner.sh [options]
```

This provides detailed information about each step of the installation process.

## Diagnostic Tools

### Built-in Diagnostic Commands

The installation system includes several diagnostic tools:

```bash
# Test system readiness
source scripts/system-readiness-functions.sh
validate_system_readiness

# Test package managers
source scripts/package-manager-functions.sh
check_package_managers
wait_for_package_managers 60

# Collect comprehensive diagnostics
./scripts/installation-error-handler.sh --collect-diagnostics
```

### Log Analysis

Installation logs are stored in `/var/log/github-runner/` (or `~/.github-runner-logs/` if system directory is not accessible):

```bash
# View installation log
tail -f /var/log/github-runner/runner-installation.log

# Search for errors
grep -i error /var/log/github-runner/runner-installation.log

# View metrics (requires jq)
cat /var/log/github-runner/installation-metrics.json | jq '.'
```

### System Health Checks

Use the existing health check script for comprehensive system validation:

```bash
./scripts/health-check-runner.sh
```

## Prevention Best Practices

### Instance Preparation

1. **Use appropriate instance size:**
   - Minimum: t3.micro (1 vCPU, 1GB RAM)
   - Recommended: t3.small (2 vCPU, 2GB RAM)

2. **Ensure adequate storage:**
   - Minimum: 8GB root volume
   - Recommended: 20GB for multiple repositories

3. **Configure security groups properly:**
   - Allow outbound HTTPS (443)
   - Allow outbound HTTP (80)
   - Allow SSH (22) from your IP

### GitHub Configuration

1. **Use appropriate PAT scopes:**
   - Required: `repo` scope
   - Avoid: `admin:org` scope (security risk)

2. **Verify repository settings:**
   - Enable Actions in repository settings
   - Ensure you have admin permissions
   - Check organization policies if applicable

### Network Configuration

1. **Ensure internet connectivity:**
   - Use public subnets or NAT gateway
   - Configure route tables properly
   - Test connectivity before installation

2. **DNS configuration:**
   - Use reliable DNS servers (8.8.8.8, 1.1.1.1)
   - Ensure DNS resolution works

### Monitoring and Maintenance

1. **Monitor installation logs:**
   - Set up log aggregation if managing multiple runners
   - Monitor for recurring issues

2. **Regular health checks:**
   - Run health check script periodically
   - Monitor runner status in GitHub

3. **Keep system updated:**
   - Allow automatic security updates
   - Monitor for runner version updates

## Getting Help

If you continue to experience issues after following this guide:

1. **Check the logs:**
   - Installation logs: `/var/log/github-runner/runner-installation.log`
   - System logs: `sudo journalctl -xe`
   - Runner logs: `sudo journalctl -u actions.runner.*`

2. **Run diagnostic collection:**
   ```bash
   ./scripts/installation-error-handler.sh --collect-diagnostics > diagnostics.txt
   ```

3. **Test individual components:**
   ```bash
   # Test system readiness
   ./scripts/test-system-readiness.sh
   
   # Test installation robustness
   ./scripts/test-installation-robustness.sh
   ```

4. **Consult additional resources:**
   - [GitHub Actions Documentation](https://docs.github.com/en/actions)
   - [GitHub Actions Runner Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
   - [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)

Remember to include diagnostic information and specific error messages when seeking help to ensure faster resolution of issues.