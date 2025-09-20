# Repository Runner Testing and Validation Scripts

This directory contains comprehensive testing and validation scripts for the repository-level GitHub Actions runner setup. These scripts ensure that all components work correctly and meet the security and optimization requirements.

## Overview

The testing suite consists of four main categories of tests:

1. **Repository Configuration Validation** - Validates all configuration requirements
2. **Repository Setup Testing** - Tests the complete setup process
3. **Workflow Integration Testing** - Tests GitHub Actions workflow functionality
4. **Runner Health Monitoring** - Monitors runner status and health

## Test Scripts

### Core Test Scripts

| Script | Purpose | Requirements Tested |
|--------|---------|-------------------|
| `validate-repository-configuration.sh` | Validates all repository configuration requirements | 6.1-6.5 |
| `test-repository-setup.sh` | Comprehensive setup validation | All requirements |
| `test-workflow-integration.sh` | GitHub Actions workflow testing | 4.1-4.4, 8.1-8.5 |
| `health-check-runner.sh` | Runner health monitoring | 6.1-6.5 |

### Orchestration Script

| Script | Purpose |
|--------|---------|
| `run-comprehensive-tests.sh` | Runs all test suites and generates reports |

### Supporting Scripts

| Script | Purpose |
|--------|---------|
| `repo-validation-functions.sh` | Validation function library |
| `test-repo-validation.sh` | Unit tests for validation functions |
| `test-repository-switching.sh` | Tests repository switching functionality |

## Quick Start

### Prerequisites

1. **Required Tools**: `curl`, `jq`, `aws` (optional), `ssh` (optional)
2. **Environment Variables**:
   ```bash
   export GITHUB_USERNAME="your-username"
   export GITHUB_REPOSITORY="your-repo"
   export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
   ```
3. **Optional AWS Variables** (for full testing):
   ```bash
   export AWS_ACCESS_KEY_ID="AKIA..."
   export AWS_SECRET_ACCESS_KEY="..."
   export AWS_REGION="us-east-1"
   export EC2_INSTANCE_ID="i-1234567890abcdef0"
   ```

### Run All Tests

```bash
# Run comprehensive test suite
./scripts/run-comprehensive-tests.sh

# Run with HTML report generation
./scripts/run-comprehensive-tests.sh --html
```

### Run Individual Test Suites

```bash
# Repository configuration validation
./scripts/run-comprehensive-tests.sh validation

# Setup testing
./scripts/run-comprehensive-tests.sh setup

# Workflow integration testing
./scripts/run-comprehensive-tests.sh integration

# Health check
./scripts/run-comprehensive-tests.sh health
```

### Run Individual Scripts

```bash
# Repository configuration validation
./scripts/validate-repository-configuration.sh

# Comprehensive setup test
./scripts/test-repository-setup.sh

# Workflow integration test
./scripts/test-workflow-integration.sh

# Runner health check
./scripts/health-check-runner.sh
```

## Test Categories

### 1. Repository Configuration Validation

**Script**: `validate-repository-configuration.sh`

Validates all repository configuration requirements against Requirement 6 acceptance criteria:

- **6.1 Persistent Registration**: Tests runner registration capability
- **6.2 Runner Availability**: Validates runner availability for jobs
- **6.3 Cost Optimization**: Checks AWS cost optimization features
- **6.4 Security Restrictions**: Validates security group and PAT restrictions
- **6.5 Isolation Guarantees**: Tests repository isolation

```bash
./scripts/validate-repository-configuration.sh
```

### 2. Repository Setup Testing

**Script**: `test-repository-setup.sh`

Comprehensive testing of the repository-level setup process:

- Prerequisites and dependencies
- Configuration validation
- Permission and access tests
- Integration and workflow tests
- Security and best practices
- Performance and optimization

```bash
./scripts/test-repository-setup.sh
```

### 3. Workflow Integration Testing

**Script**: `test-workflow-integration.sh`

Tests GitHub Actions workflow integration and functionality:

- Workflow file validation
- GitHub API integration
- AWS integration
- End-to-end workflow testing

```bash
./scripts/test-workflow-integration.sh
```

### 4. Runner Health Monitoring

**Script**: `health-check-runner.sh`

Comprehensive health monitoring for the runner system:

- GitHub connectivity and repository access
- Runner registration status
- Local runner installation and service
- AWS infrastructure status
- Workflow health

```bash
./scripts/health-check-runner.sh
```

## Test Results and Reports

### Output Files

All test scripts generate detailed JSON reports:

- `/tmp/repository-configuration-validation.json` - Configuration validation results
- `/tmp/repository-setup-test-results.json` - Setup test results
- `/tmp/workflow-integration-test-results.json` - Integration test results
- `/tmp/runner-health-report.json` - Health check results
- `/tmp/comprehensive-test-results/` - Comprehensive test suite results

### Comprehensive Test Report

The orchestration script generates:

- **JSON Report**: `comprehensive-test-report.json`
- **HTML Report**: `comprehensive-test-report.html` (with `--html` flag)
- **Individual Logs**: `*-output.log` files for each suite

### Exit Codes

| Exit Code | Meaning |
|-----------|---------|
| 0 | All tests passed |
| 1 | Some tests failed or warnings present |
| 2 | Critical failures or unhealthy status |

## Environment Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `GITHUB_USERNAME` | GitHub username | `myusername` |
| `GITHUB_REPOSITORY` | Repository name | `my-repo` |
| `GH_PAT` | GitHub Personal Access Token (repo scope) | `ghp_xxxxxxxxxxxxxxxxxxxx` |

### Optional Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS access key | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret access key | `wJal...` |
| `AWS_REGION` | AWS region | `us-east-1` |
| `EC2_INSTANCE_ID` | EC2 instance ID | `i-1234567890abcdef0` |
| `RUNNER_NAME` | Runner name | `gha_aws_runner` |

## Test Scenarios

### Basic Configuration Test

Tests minimal configuration without AWS:

```bash
export GITHUB_USERNAME="myusername"
export GITHUB_REPOSITORY="my-repo"
export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
./scripts/run-comprehensive-tests.sh
```

### Full Integration Test

Tests complete setup with AWS integration:

```bash
export GITHUB_USERNAME="myusername"
export GITHUB_REPOSITORY="my-repo"
export GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_REGION="us-east-1"
export EC2_INSTANCE_ID="i-1234567890abcdef0"
./scripts/run-comprehensive-tests.sh --html
```

### Health Monitoring

Regular health checks for operational monitoring:

```bash
# Quick health check
./scripts/health-check-runner.sh

# JSON-only output for monitoring systems
./scripts/health-check-runner.sh --json-only
```

## Troubleshooting

### Common Issues

1. **Missing Tools**
   ```bash
   # Install required tools
   # Ubuntu/Debian
   sudo apt-get install curl jq
   
   # macOS
   brew install curl jq
   ```

2. **Permission Errors**
   ```bash
   # Make scripts executable
   chmod +x scripts/*.sh
   ```

3. **AWS Credentials**
   ```bash
   # Configure AWS credentials
   aws configure
   # or
   export AWS_ACCESS_KEY_ID="..."
   export AWS_SECRET_ACCESS_KEY="..."
   ```

4. **GitHub PAT Scope**
   - Ensure PAT has `repo` scope
   - Verify repository admin permissions
   - Check PAT expiration

### Test Failures

1. **Configuration Validation Failures**
   - Check environment variables
   - Verify GitHub repository access
   - Confirm AWS credentials (if using)

2. **Setup Test Failures**
   - Ensure all prerequisites are met
   - Check network connectivity
   - Verify file permissions

3. **Integration Test Failures**
   - Check workflow files exist
   - Verify GitHub Actions is enabled
   - Confirm repository secrets are set

4. **Health Check Failures**
   - Check runner installation
   - Verify service status
   - Check AWS instance status

### Getting Help

1. **Verbose Output**: Most scripts provide detailed output explaining failures
2. **Log Files**: Check individual log files in results directory
3. **JSON Reports**: Review detailed JSON reports for programmatic analysis
4. **Exit Codes**: Use exit codes to determine failure types

## Integration with CI/CD

### GitHub Actions Integration

Add to your workflow:

```yaml
- name: Run Repository Tests
  run: |
    export GITHUB_USERNAME="${{ github.repository_owner }}"
    export GITHUB_REPOSITORY="${{ github.event.repository.name }}"
    export GH_PAT="${{ secrets.GH_PAT }}"
    ./scripts/run-comprehensive-tests.sh
```

### Monitoring Integration

Use health check for monitoring:

```bash
# Cron job for regular health checks
0 */6 * * * /path/to/scripts/health-check-runner.sh --json-only > /var/log/runner-health.json
```

## Development and Customization

### Adding New Tests

1. Create test function in appropriate script
2. Add to test execution flow
3. Update JSON report structure
4. Add documentation

### Modifying Validation Criteria

1. Update validation functions in `repo-validation-functions.sh`
2. Modify test scripts to use new criteria
3. Update requirement mappings
4. Test thoroughly

### Custom Reporting

1. Modify JSON report structure
2. Add custom report generators
3. Integrate with monitoring systems
4. Update documentation

## Security Considerations

### Sensitive Information

- Scripts handle GitHub PATs and AWS credentials securely
- No sensitive information is logged in plain text
- Temporary files are created in `/tmp` with appropriate permissions

### Network Security

- Scripts only connect to required endpoints (GitHub API, AWS API)
- No unnecessary network connections
- Validates SSL/TLS connections

### File Permissions

- Scripts check and set appropriate file permissions
- Sensitive files are protected from unauthorized access
- Temporary files are cleaned up appropriately

## Performance Considerations

### Test Execution Time

- Individual scripts: 30 seconds - 5 minutes
- Comprehensive suite: 5-15 minutes
- Network-dependent tests may take longer

### Resource Usage

- Minimal CPU and memory usage
- Network bandwidth for API calls
- Temporary disk space for reports

### Optimization

- Tests run in parallel where possible
- Caching of API responses where appropriate
- Efficient error handling to fail fast

## Maintenance

### Regular Updates

1. Update scripts when requirements change
2. Add new tests for new features
3. Update documentation
4. Test with new GitHub/AWS API versions

### Version Management

- Scripts include version information
- Backward compatibility considerations
- Migration guides for breaking changes

### Monitoring

- Regular execution of test suites
- Monitoring of test success rates
- Alerting on test failures