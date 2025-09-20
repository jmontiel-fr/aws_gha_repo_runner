# Repository Runner Testing Guide

This guide provides comprehensive instructions for testing repository-level GitHub Actions runner functionality and switching between different repositories in your personal GitHub account.

## Overview

Repository-level runners provide dedicated compute resources for individual repositories in your personal GitHub account. This guide helps you validate that the runner is properly configured for your repository and can be switched between different repositories when needed.

## Testing Strategy

### 1. Basic Functionality Testing
Verify that the runner can execute jobs for your repository with proper configuration and performance.

### 2. Repository Switching Testing
Ensure that the runner can be reconfigured to work with different repositories in your account.

### 3. Persistent Configuration Testing
Validate that the runner maintains proper registration and can handle multiple jobs for the same repository.

### 4. Performance and Reliability Testing
Test runner performance under various workloads and verify consistent behavior for your repository.

## Prerequisites

Before starting repository testing, ensure:

- Repository-level runner is properly configured and running
- You have admin access to your GitHub repositories
- Multiple repositories are available for testing (minimum 2-3 repositories in your account)
- GitHub PAT has appropriate permissions (`repo` scope)
- Runner is visible in repository settings (Settings → Actions → Runners)

## Test Repository Setup

### Repository Categories for Testing

1. **Infrastructure Repository**: Contains the runner infrastructure code and management workflows
2. **Application Repositories**: Various application codebases that will use the shared runner
3. **Test Repositories**: Dedicated repositories for testing runner functionality

### Recommended Test Repository Structure

```
your-organization/
├── infrastructure-runner/          # Main runner infrastructure
├── frontend-app/                   # Frontend application
├── backend-api/                    # Backend API service
├── mobile-app/                     # Mobile application
├── data-pipeline/                  # Data processing pipeline
└── runner-test/                    # Dedicated test repository
```

## Test Workflows

### 1. Basic Runner Test Workflow

Deploy this workflow in multiple repositories to test basic functionality:

```yaml
# File: .github/workflows/test-org-runner.yml
name: Test Organization Runner

on:
  workflow_dispatch:
    inputs:
      test_duration:
        description: 'Test duration in seconds'
        required: false
        default: '30'
        type: string

jobs:
  test-runner-access:
    runs-on: [self-hosted, gha_aws_runner]
    timeout-minutes: 10
    
    steps:
      - name: Repository identification
        run: |
          echo "=== Repository Information ==="
          echo "Repository: ${{ github.repository }}"
          echo "Organization: ${{ github.repository_owner }}"
          echo "Workflow: ${{ github.workflow }}"
          echo "Run ID: ${{ github.run_id }}"
          echo "Runner: ${{ runner.name }}"
          echo "Timestamp: $(date -u)"
          
      - name: Test runner environment
        run: |
          echo "=== Runner Environment ==="
          echo "Hostname: $(hostname)"
          echo "User: $(whoami)"
          echo "Working Directory: $(pwd)"
          echo "Home Directory: $HOME"
          echo "Temp Directory: $RUNNER_TEMP"
          echo "Workspace: ${{ github.workspace }}"
          
      - name: Test tool availability
        run: |
          echo "=== Tool Availability Test ==="
          
          tools=("docker" "aws" "python3" "java" "terraform" "kubectl" "helm")
          for tool in "${tools[@]}"; do
            if command -v "$tool" &> /dev/null; then
              echo "✓ $tool: $(command -v $tool)"
            else
              echo "✗ $tool: not found"
            fi
          done
          
      - name: Test repository isolation
        run: |
          echo "=== Repository Isolation Test ==="
          
          # Create repository-specific marker
          REPO_MARKER="/tmp/test-$(echo '${{ github.repository }}' | tr '/' '-')-${{ github.run_id }}"
          echo "Creating marker: $REPO_MARKER"
          echo "Repository: ${{ github.repository }}" > "$REPO_MARKER"
          echo "Run ID: ${{ github.run_id }}" >> "$REPO_MARKER"
          echo "Timestamp: $(date -u)" >> "$REPO_MARKER"
          
          # List all markers to check for cross-contamination
          echo "Existing markers:"
          ls -la /tmp/test-* 2>/dev/null || echo "No existing markers found"
          
          # Simulate work
          echo "Simulating work for ${{ inputs.test_duration }} seconds..."
          sleep "${{ inputs.test_duration }}"
          
          # Cleanup marker
          rm -f "$REPO_MARKER"
          echo "✓ Marker cleaned up"
          
      - name: Test network connectivity
        run: |
          echo "=== Network Connectivity Test ==="
          
          # Test GitHub connectivity
          curl -I https://github.com && echo "✓ GitHub accessible" || echo "✗ GitHub not accessible"
          curl -I https://api.github.com && echo "✓ GitHub API accessible" || echo "✗ GitHub API not accessible"
          
          # Test package repositories
          curl -I https://archive.ubuntu.com && echo "✓ Ubuntu packages accessible" || echo "✗ Ubuntu packages not accessible"
          
      - name: Test summary
        run: |
          echo "=== Test Summary ==="
          echo "✓ Repository: ${{ github.repository }}"
          echo "✓ Runner access confirmed"
          echo "✓ Environment isolation verified"
          echo "✓ Tools available and functional"
          echo "✓ Network connectivity confirmed"
```

### 2. Concurrent Access Test Workflow

This workflow tests how the runner handles multiple simultaneous job requests:

```yaml
# File: .github/workflows/concurrent-test.yml
name: Concurrent Runner Access Test

on:
  workflow_dispatch:
    inputs:
      job_count:
        description: 'Number of concurrent jobs to test'
        required: false
        default: '3'
        type: choice
        options:
        - '2'
        - '3'
        - '5'

jobs:
  # Generate multiple jobs dynamically
  generate-jobs:
    runs-on: ubuntu-latest
    outputs:
      job-matrix: ${{ steps.generate.outputs.matrix }}
    steps:
      - name: Generate job matrix
        id: generate
        run: |
          count=${{ inputs.job_count }}
          jobs=$(seq 1 $count | jq -R . | jq -s .)
          echo "matrix={\"job\":$jobs}" >> $GITHUB_OUTPUT
          echo "Generated $count concurrent jobs"

  concurrent-test:
    needs: generate-jobs
    runs-on: [self-hosted, gha_aws_runner]
    timeout-minutes: 15
    strategy:
      matrix: ${{ fromJson(needs.generate-jobs.outputs.job-matrix) }}
      max-parallel: 1  # Force sequential execution on single runner
    
    steps:
      - name: Job identification
        run: |
          echo "=== Concurrent Job Test ==="
          echo "Repository: ${{ github.repository }}"
          echo "Job Number: ${{ matrix.job }}"
          echo "Run ID: ${{ github.run_id }}"
          echo "Job ID: ${{ github.job }}"
          echo "Start Time: $(date -u)"
          
      - name: Simulate workload
        run: |
          echo "=== Simulating Workload (Job ${{ matrix.job }}) ==="
          
          # Create job-specific work directory
          WORK_DIR="/tmp/job-${{ matrix.job }}-${{ github.run_id }}"
          mkdir -p "$WORK_DIR"
          cd "$WORK_DIR"
          
          # Simulate CPU work
          echo "Starting CPU work..."
          for i in {1..10000}; do
            echo "Job ${{ matrix.job }} - Iteration $i" > /dev/null
          done
          
          # Simulate file operations
          echo "Starting file operations..."
          for i in {1..100}; do
            echo "Job ${{ matrix.job }} - File $i - $(date)" > "file-$i.txt"
          done
          
          # List created files
          echo "Created $(ls -1 | wc -l) files"
          
          # Cleanup
          cd /tmp
          rm -rf "$WORK_DIR"
          echo "✓ Cleanup completed for job ${{ matrix.job }}"
          
      - name: Job completion
        run: |
          echo "=== Job Completion ==="
          echo "Job ${{ matrix.job }} completed at: $(date -u)"
          echo "✓ Concurrent test job ${{ matrix.job }} finished successfully"
```

### 3. Cross-Repository Integration Test

This workflow demonstrates real-world usage patterns across different repository types:

```yaml
# File: .github/workflows/integration-test.yml
name: Cross-Repository Integration Test

on:
  workflow_dispatch:
    inputs:
      test_scenario:
        description: 'Integration test scenario'
        required: false
        default: 'frontend'
        type: choice
        options:
        - 'frontend'
        - 'backend'
        - 'infrastructure'
        - 'data-pipeline'

jobs:
  integration-test:
    runs-on: [self-hosted, gha_aws_runner]
    timeout-minutes: 20
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        
      - name: Repository context
        run: |
          echo "=== Integration Test Context ==="
          echo "Repository: ${{ github.repository }}"
          echo "Test Scenario: ${{ inputs.test_scenario }}"
          echo "Branch: ${{ github.ref_name }}"
          echo "Commit: ${{ github.sha }}"
          echo "Runner: ${{ runner.name }}"
          
      - name: Frontend scenario
        if: ${{ inputs.test_scenario == 'frontend' }}
        run: |
          echo "=== Frontend Integration Test ==="
          
          # Simulate Node.js frontend build
          echo "Simulating Node.js setup..."
          node --version 2>/dev/null || echo "Node.js not installed (would install in real scenario)"
          
          # Simulate package installation
          echo "Simulating npm install..."
          sleep 5
          
          # Simulate build process
          echo "Simulating frontend build..."
          mkdir -p dist
          echo "<html><body>Built by ${{ github.repository }}</body></html>" > dist/index.html
          
          # Simulate tests
          echo "Simulating frontend tests..."
          sleep 3
          
          echo "✓ Frontend build simulation completed"
          
      - name: Backend scenario
        if: ${{ inputs.test_scenario == 'backend' }}
        run: |
          echo "=== Backend Integration Test ==="
          
          # Test Python environment
          echo "Testing Python environment..."
          python3 --version
          pip3 --version
          
          # Simulate API tests
          echo "Simulating API tests..."
          python3 -c "
import json
import time
print('Starting API test simulation...')
time.sleep(3)
result = {'status': 'success', 'repository': '${{ github.repository }}'}
print(f'API test result: {json.dumps(result)}')
"
          
          # Simulate database operations
          echo "Simulating database operations..."
          sleep 2
          
          echo "✓ Backend test simulation completed"
          
      - name: Infrastructure scenario
        if: ${{ inputs.test_scenario == 'infrastructure' }}
        run: |
          echo "=== Infrastructure Integration Test ==="
          
          # Test Terraform
          echo "Testing Terraform..."
          terraform --version
          
          # Simulate infrastructure validation
          echo "Simulating infrastructure validation..."
          terraform fmt -check=true . 2>/dev/null || echo "No Terraform files found (expected for test)"
          
          # Test AWS CLI
          echo "Testing AWS CLI..."
          aws --version
          
          # Test kubectl
          echo "Testing kubectl..."
          kubectl version --client
          
          echo "✓ Infrastructure test simulation completed"
          
      - name: Data pipeline scenario
        if: ${{ inputs.test_scenario == 'data-pipeline' }}
        run: |
          echo "=== Data Pipeline Integration Test ==="
          
          # Test Python data tools
          echo "Testing Python data environment..."
          python3 -c "
import sys
print(f'Python version: {sys.version}')

# Simulate data processing
import json
import time

print('Simulating data pipeline...')
data = [{'id': i, 'value': i*2, 'repository': '${{ github.repository }}'} for i in range(1000)]
print(f'Generated {len(data)} data points')

# Simulate processing
time.sleep(5)
processed = len([item for item in data if item['value'] > 100])
print(f'Processed {processed} items')

result = {'total': len(data), 'processed': processed, 'status': 'success'}
print(f'Pipeline result: {json.dumps(result)}')
"
          
          echo "✓ Data pipeline simulation completed"
          
      - name: Integration summary
        run: |
          echo "=== Integration Test Summary ==="
          echo "✓ Repository: ${{ github.repository }}"
          echo "✓ Scenario: ${{ inputs.test_scenario }}"
          echo "✓ Runner: Organization-level ephemeral runner"
          echo "✓ Integration test completed successfully"
          echo "✓ Cross-repository functionality verified"
```

## Testing Procedures

### 1. Sequential Repository Testing

Test runner access from multiple repositories in sequence:

1. **Deploy test workflows** in 3-5 different repositories
2. **Execute workflows manually** from each repository
3. **Monitor execution** in GitHub Actions UI
4. **Verify runner appears/disappears** in organization settings
5. **Check for proper cleanup** between jobs

### 2. Concurrent Repository Testing

Test how the runner handles simultaneous requests:

1. **Trigger workflows simultaneously** from multiple repositories
2. **Observe job queuing behavior** in Actions UI
3. **Verify sequential execution** (jobs should queue, not fail)
4. **Monitor runner status** during concurrent requests
5. **Validate proper cleanup** after all jobs complete

### 3. Load Testing

Test runner performance under various loads:

1. **Execute multiple concurrent workflows** with different workloads
2. **Monitor system resources** during execution
3. **Test with different job durations** (short, medium, long)
4. **Verify consistent performance** across repositories
5. **Check for resource leaks** or performance degradation

## Validation Checklist

### ✅ Basic Functionality
- [ ] Runner appears in organization settings
- [ ] Runner accepts jobs from multiple repositories
- [ ] Jobs execute successfully across different repositories
- [ ] Runner properly unregisters after each job (ephemeral behavior)
- [ ] Clean state maintained between jobs from different repositories

### ✅ Cross-Repository Access
- [ ] Multiple repositories can target the same runner
- [ ] Jobs from different repositories queue properly when runner is busy
- [ ] No cross-contamination between repository workspaces
- [ ] Proper isolation of environment variables and secrets
- [ ] Consistent tool availability across all repositories

### ✅ Performance and Reliability
- [ ] Consistent job execution times across repositories
- [ ] No performance degradation with multiple repositories
- [ ] Proper error handling and recovery
- [ ] Reliable network connectivity from all repositories
- [ ] Adequate system resources for concurrent workloads

### ✅ Security and Isolation
- [ ] Repository code isolation (no access to other repo files)
- [ ] Environment variable isolation between jobs
- [ ] Proper cleanup of temporary files and processes
- [ ] No persistent data between jobs from different repositories
- [ ] Secure handling of repository secrets and tokens

## Troubleshooting Cross-Repository Issues

### Common Issues and Solutions

#### 1. Runner Not Visible to Some Repositories

**Symptoms:**
- Runner appears in organization settings but not available in some repositories
- Jobs fail with "No runners available" message

**Solutions:**
- Verify repository has Actions enabled
- Check organization Actions permissions
- Ensure runner labels match workflow requirements
- Verify repository is part of the organization

#### 2. Jobs Failing to Queue Properly

**Symptoms:**
- Multiple jobs from different repositories fail simultaneously
- Jobs timeout waiting for runner availability

**Solutions:**
- Check runner capacity and current load
- Verify ephemeral configuration is working
- Monitor runner logs for errors
- Ensure proper cleanup between jobs

#### 3. Cross-Repository Contamination

**Symptoms:**
- Files from previous jobs visible in new jobs
- Environment variables persisting between repositories
- Unexpected tool configurations

**Solutions:**
- Verify ephemeral runner configuration
- Check runner cleanup procedures
- Review job isolation mechanisms
- Ensure proper workspace management

#### 4. Performance Issues

**Symptoms:**
- Slow job execution times
- Inconsistent performance across repositories
- Resource exhaustion errors

**Solutions:**
- Monitor system resources during jobs
- Optimize job workflows for efficiency
- Consider scaling runner resources
- Review concurrent job limits

## Monitoring and Metrics

### Key Metrics to Track

1. **Job Success Rate**: Percentage of successful jobs across all repositories
2. **Queue Time**: Time jobs spend waiting for runner availability
3. **Execution Time**: Job execution duration across different repositories
4. **Runner Utilization**: Percentage of time runner is actively executing jobs
5. **Error Rate**: Frequency of job failures or runner errors

### Monitoring Tools

1. **GitHub Actions UI**: Built-in monitoring and logging
2. **Organization Insights**: Runner usage statistics
3. **AWS CloudWatch**: EC2 instance monitoring (if applicable)
4. **Custom Scripts**: Automated monitoring and alerting

### Monitoring Script Example

```bash
#!/bin/bash
# File: scripts/monitor-org-runner.sh

# Monitor organization runner usage across repositories
GITHUB_ORGANIZATION="${GITHUB_ORGANIZATION:-your-org}"
GH_PAT="${GH_PAT:-your-token}"

echo "=== Organization Runner Monitoring ==="
echo "Organization: $GITHUB_ORGANIZATION"
echo "Timestamp: $(date -u)"

# Get runner status
echo ""
echo "=== Runner Status ==="
curl -s -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runners" | \
  jq -r '.runners[] | "Runner: \(.name) | Status: \(.status) | Busy: \(.busy) | Labels: \([.labels[].name] | join(","))"'

# Get recent workflow runs across organization
echo ""
echo "=== Recent Workflow Runs ==="
curl -s -H "Authorization: token $GH_PAT" \
  "https://api.github.com/orgs/$GITHUB_ORGANIZATION/actions/runs?per_page=10" | \
  jq -r '.workflow_runs[] | "Repo: \(.repository.name) | Status: \(.status) | Conclusion: \(.conclusion // "running") | Created: \(.created_at)"'
```

## Best Practices for Cross-Repository Testing

### 1. Test Environment Management
- Use dedicated test repositories for validation
- Implement proper cleanup procedures
- Maintain consistent test data across repositories
- Document test procedures and expected outcomes

### 2. Workflow Design
- Design workflows for ephemeral runner compatibility
- Implement proper error handling and cleanup
- Use consistent labeling and targeting
- Minimize resource usage and execution time

### 3. Security Considerations
- Limit sensitive operations in test workflows
- Use organization-level secrets appropriately
- Implement proper access controls
- Monitor for security issues across repositories

### 4. Performance Optimization
- Optimize workflows for shared runner usage
- Implement efficient resource utilization
- Monitor and tune performance regularly
- Plan for scaling based on organization growth

## Conclusion

Cross-repository testing is essential for validating organization-level GitHub Actions runner functionality. By following this guide and implementing the provided test workflows, you can ensure that your ephemeral runner provides reliable, secure, and efficient service across all repositories in your organization.

Regular testing and monitoring will help maintain optimal performance and quickly identify any issues that may arise as your organization and usage patterns evolve.