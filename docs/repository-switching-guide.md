# Repository Runner Switching Guide

This guide explains how to switch your GitHub Actions runner from one repository to another using the repository switching functionality.

## Overview

The repository switching feature allows you to cleanly move your AWS EC2-based GitHub Actions runner from one repository to another without manual reconfiguration. This is useful when:

- Moving between different projects
- Switching from a test repository to production
- Reorganizing your repository structure
- Sharing a runner between different repositories over time

## Prerequisites

Before switching repositories, ensure you have:

- **Admin permissions** on both the current and new repositories
- **GitHub PAT** with `repo` scope that works with both repositories
- **AWS credentials** configured for managing the EC2 instance
- **Runner currently configured** and working with the source repository

## Quick Start

### 1. Basic Repository Switch

Switch from one repository to another under the same GitHub account:

```bash
# Set environment variables
export CURRENT_GITHUB_USERNAME="myusername"
export CURRENT_GITHUB_REPOSITORY="old-project"
export NEW_GITHUB_USERNAME="myusername"
export NEW_GITHUB_REPOSITORY="new-project"
export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"

# Perform the switch
./scripts/switch-repository-runner.sh
```

### 2. Switch to Different User's Repository

Switch to a repository owned by a different user (requires access):

```bash
# Set environment variables
export CURRENT_GITHUB_USERNAME="myusername"
export CURRENT_GITHUB_REPOSITORY="my-project"
export NEW_GITHUB_USERNAME="otheruser"
export NEW_GITHUB_REPOSITORY="their-project"
export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"

# Perform the switch
./scripts/switch-repository-runner.sh
```

## Step-by-Step Process

### Step 1: Validate Configuration

Before making any changes, validate that the switch is possible:

```bash
# Check if both repositories are accessible and switching is possible
./scripts/switch-repository-runner.sh --validate-only
```

Expected output:
```
=== Repository Runner Switching v1.0.0 ===

[INFO] Validating prerequisites for repository switching...
[SUCCESS] Prerequisites validation passed
[INFO] Validating current and new repository configurations...
=== Validating Current Repository ===
[INFO] Repository: myusername/old-project
[SUCCESS] All repository configuration validations passed
=== Validating New Repository ===
[INFO] Repository: myusername/new-project
[SUCCESS] All repository configuration validations passed
[SUCCESS] Both repositories validated successfully
[SUCCESS] No conflicts detected
[SUCCESS] All validations passed. Ready for repository switching.
```

### Step 2: Check Current Status

Review the current runner configuration:

```bash
# Show current runner status and configuration
./scripts/switch-repository-runner.sh --status
```

This will show:
- Current local runner configuration
- Runners registered in the current repository
- Runners registered in the new repository (if any)

### Step 3: Preview Changes (Optional)

See what the switching process would do without making changes:

```bash
# Dry run to preview the switching process
./scripts/switch-repository-runner.sh --dry-run
```

### Step 4: Perform the Switch

Execute the actual repository switch:

```bash
# Perform the repository switch
./scripts/switch-repository-runner.sh
```

The switching process will:

1. **Validate prerequisites** - Check environment variables and tool availability
2. **Validate repositories** - Ensure both repositories are accessible with proper permissions
3. **Check for conflicts** - Identify potential issues before starting
4. **Unregister from current repository** - Clean removal from the old repository
5. **Register with new repository** - Configure runner for the new repository
6. **Restart runner service** - Ensure the runner is active and ready

### Step 5: Verify the Switch

After switching, verify the runner is working correctly:

```bash
# Check the new status
./scripts/switch-repository-runner.sh --status

# Or check in GitHub UI
# Go to New Repository → Settings → Actions → Runners
# Verify your runner appears and shows "Idle" status
```

## Advanced Usage

### Force Switching

If validation warnings appear but you want to proceed anyway:

```bash
# Force switch despite validation warnings
./scripts/switch-repository-runner.sh --force
```

Use this carefully, as it bypasses safety checks.

### Custom Runner Configuration

You can customize the runner configuration during switching:

```bash
# Set custom runner name and labels
export RUNNER_NAME="my-custom-runner"
export RUNNER_LABELS="custom-runner,ubuntu-22.04,aws"

# Perform switch with custom configuration
./scripts/switch-repository-runner.sh
```

### Batch Repository Switching

For switching between multiple repositories programmatically:

```bash
#!/bin/bash
# switch-between-repos.sh

REPOSITORIES=("repo1" "repo2" "repo3")
CURRENT_REPO="repo1"

for NEW_REPO in "${REPOSITORIES[@]}"; do
    if [ "$NEW_REPO" != "$CURRENT_REPO" ]; then
        echo "Switching from $CURRENT_REPO to $NEW_REPO"
        
        export CURRENT_GITHUB_USERNAME="myusername"
        export CURRENT_GITHUB_REPOSITORY="$CURRENT_REPO"
        export NEW_GITHUB_USERNAME="myusername"
        export NEW_GITHUB_REPOSITORY="$NEW_REPO"
        
        if ./scripts/switch-repository-runner.sh; then
            echo "Successfully switched to $NEW_REPO"
            CURRENT_REPO="$NEW_REPO"
            
            # Wait for runner to be ready
            sleep 30
        else
            echo "Failed to switch to $NEW_REPO"
            break
        fi
    fi
done
```

## Troubleshooting

### Common Issues

#### "Missing required environment variables"

Ensure all required variables are set:

```bash
# Check current environment variables
echo "Current: $CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY"
echo "New: $NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY"
echo "PAT: ${GH_PAT:0:10}..." # Show first 10 characters only
```

#### "Repository validation failed"

Check repository access and permissions:

```bash
# Test repository access
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY" | \
  jq '{name: .name, private: .private, permissions: .permissions}'
```

#### "Runner already exists in new repository"

Remove the existing runner first:

```bash
# Get existing runner ID
EXISTING_RUNNER_ID=$(curl -s -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY/actions/runners" | \
  jq -r ".runners[] | select(.name==\"$RUNNER_NAME\") | .id")

# Remove existing runner
if [ "$EXISTING_RUNNER_ID" != "null" ]; then
  curl -X DELETE -H "Authorization: token $GH_PAT" \
    "https://api.github.com/repos/$NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY/actions/runners/$EXISTING_RUNNER_ID"
fi
```

#### "Runner service failed to start"

Check the runner service status on EC2:

```bash
# SSH to instance and check service
ssh ubuntu@$INSTANCE_IP << 'EOF'
cd ~/actions-runner
sudo ./svc.sh status
sudo journalctl -u actions.runner.* -n 20
EOF
```

### Recovery Procedures

If switching fails partway through, you can recover:

#### Manual Cleanup

```bash
# SSH to EC2 instance
ssh ubuntu@$INSTANCE_IP

# Navigate to runner directory
cd ~/actions-runner

# Stop and clean up service
sudo ./svc.sh stop || true
sudo ./svc.sh uninstall || true

# Remove configuration
sudo -u ubuntu ./config.sh remove --token dummy_token || true

# Clean configuration files
rm -f .runner .credentials .credentials_rsaparams || true

# Exit SSH
exit

# Now reconfigure for the desired repository
export GITHUB_USERNAME="$NEW_GITHUB_USERNAME"
export GITHUB_REPOSITORY="$NEW_GITHUB_REPOSITORY"
./scripts/repo-runner-setup.sh
```

#### Rollback to Previous Repository

```bash
# Switch back to the original repository
export CURRENT_GITHUB_USERNAME="$NEW_GITHUB_USERNAME"
export CURRENT_GITHUB_REPOSITORY="$NEW_GITHUB_REPOSITORY"
export NEW_GITHUB_USERNAME="$ORIGINAL_USERNAME"
export NEW_GITHUB_REPOSITORY="$ORIGINAL_REPOSITORY"

./scripts/switch-repository-runner.sh
```

## Best Practices

### 1. Always Validate First

```bash
# Always run validation before switching
./scripts/switch-repository-runner.sh --validate-only
```

### 2. Check for Running Jobs

Ensure no jobs are currently running before switching:

```bash
# Check for active workflow runs
curl -H "Authorization: token $GH_PAT" \
  "https://api.github.com/repos/$CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY/actions/runs?status=in_progress" | \
  jq '.total_count'
```

### 3. Document Repository Changes

Keep track of repository switches for audit purposes:

```bash
# Log repository switches
echo "$(date): Switched runner from $CURRENT_GITHUB_USERNAME/$CURRENT_GITHUB_REPOSITORY to $NEW_GITHUB_USERNAME/$NEW_GITHUB_REPOSITORY" >> ~/runner-switches.log
```

### 4. Test After Switching

Always test the runner after switching:

```bash
# Create a simple test workflow in the new repository
cat > .github/workflows/test-runner.yml << 'EOF'
name: Test Runner
on:
  workflow_dispatch:

jobs:
  test:
    runs-on: [self-hosted, gha_aws_runner]
    steps:
      - name: Test runner
        run: |
          echo "Runner is working!"
          echo "Repository: ${{ github.repository }}"
          echo "Runner name: $(hostname)"
          uname -a
EOF
```

### 5. Monitor Resource Usage

Keep an eye on resource usage when switching frequently:

```bash
# Check EC2 instance costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Security Considerations

### PAT Security

- Use a PAT with minimal required scopes (`repo` only)
- Rotate PATs regularly (recommended: every 90 days)
- Store PATs securely and never commit them to repositories

### Repository Access

- Only switch to repositories you have legitimate access to
- Verify repository ownership before switching
- Be cautious when switching to repositories owned by others

### Audit Trail

- Keep logs of repository switches
- Monitor runner usage across repositories
- Review access patterns regularly

## Integration with CI/CD

### Workflow Integration

You can integrate repository switching into your CI/CD workflows:

```yaml
name: Switch Runner Repository
on:
  workflow_dispatch:
    inputs:
      target_repository:
        description: 'Target repository (username/repo)'
        required: true
        type: string

jobs:
  switch-runner:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}
      
      - name: Switch repository
        env:
          CURRENT_GITHUB_USERNAME: ${{ github.repository_owner }}
          CURRENT_GITHUB_REPOSITORY: ${{ github.event.repository.name }}
          NEW_GITHUB_USERNAME: ${{ split(github.event.inputs.target_repository, '/')[0] }}
          NEW_GITHUB_REPOSITORY: ${{ split(github.event.inputs.target_repository, '/')[1] }}
          GH_PAT: ${{ secrets.GH_PAT }}
        run: |
          ./scripts/switch-repository-runner.sh
```

### Automated Switching

For automated switching based on schedules or events:

```bash
#!/bin/bash
# automated-switch.sh

# Switch to development repository during work hours
HOUR=$(date +%H)
DAY=$(date +%u)  # 1=Monday, 7=Sunday

if [ "$DAY" -le 5 ] && [ "$HOUR" -ge 9 ] && [ "$HOUR" -le 17 ]; then
    # Work hours: use development repository
    TARGET_REPO="dev-project"
else
    # Off hours: use production repository for maintenance
    TARGET_REPO="prod-project"
fi

export CURRENT_GITHUB_USERNAME="myusername"
export CURRENT_GITHUB_REPOSITORY="current-repo"
export NEW_GITHUB_USERNAME="myusername"
export NEW_GITHUB_REPOSITORY="$TARGET_REPO"

./scripts/switch-repository-runner.sh
```

## Conclusion

The repository switching functionality provides a clean and automated way to move your GitHub Actions runner between repositories. By following this guide and best practices, you can efficiently manage your runner resources across multiple projects while maintaining security and reliability.

For additional help, refer to:
- [Repository Troubleshooting Guide](repository-troubleshooting-guide.md)
- [Repository Validation Guide](repository-validation-guide.md)
- [GitHub Actions Runner Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)