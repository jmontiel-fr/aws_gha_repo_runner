# Example Workflows Guide

This guide explains all the example workflows provided for testing and demonstrating repository-level GitHub Actions runners.

## Overview

The repository includes several example workflows that demonstrate different aspects of repository-level runner functionality:

1. **Simple Runner Test** - Basic functionality test that works with any repository
2. **Test Repository Runner** - Comprehensive testing with multiple scenarios
3. **Repository Type Tests** - Tests for different repository types (public/private)
4. **Feature Demonstration** - Complete feature showcase with debugging
5. **Runner Demo** - Interactive demo with job type selection
6. **Configure Runner** - Manual runner management workflow

## Workflow Details

### 1. Simple Runner Test (`simple-runner-test.yml`)

**Purpose:** Basic test that automatically works with any repository, regardless of configuration.

**Features:**
- ✅ Automatic configuration detection
- ✅ Works with both GitHub-hosted and self-hosted runners
- ✅ Graceful fallback to GitHub-hosted if self-hosted not available
- ✅ Basic environment and tool testing
- ✅ Repository content validation

**When to use:**
- First-time setup validation
- Quick health checks
- Continuous integration testing
- Demonstrating basic functionality

**Triggers:**
- Manual dispatch (`workflow_dispatch`)
- Push to main/master branch (when workflow file changes)
- Pull requests to main/master branch

**Example usage:**
```yaml
# Automatically triggered on push/PR
# Or run manually from Actions tab
```

### 2. Test Repository Runner (`test-repository-runner.yml`)

**Purpose:** Comprehensive testing workflow with multiple test scenarios and extensive debugging.

**Features:**
- ✅ Pre-flight validation of all requirements
- ✅ Multiple test scenarios (basic, build-test, docker-build, aws-integration, full-validation)
- ✅ Detailed error reporting and debugging
- ✅ Resource monitoring and performance testing
- ✅ Automatic cleanup with optional skip for debugging

**Test Scenarios:**
- **Basic:** Environment validation and basic commands
- **Build-test:** Development tools and build processes
- **Docker-build:** Docker functionality and container operations
- **AWS-integration:** AWS CLI and service integration
- **Full-validation:** Complete system validation

**When to use:**
- Comprehensive system testing
- Troubleshooting runner issues
- Performance validation
- Before production deployment

**Example usage:**
```bash
# Run from Actions tab with parameters:
# - test_scenario: "full-validation"
# - debug_mode: true
# - skip_cleanup: false
```

### 3. Repository Type Tests (`repository-type-tests.yml`)

**Purpose:** Test runner behavior across different repository types and configurations.

**Features:**
- ✅ Automatic repository type detection (public/private)
- ✅ Permission validation and security checks
- ✅ Cross-repository scenario testing
- ✅ Security recommendations based on repository type
- ✅ Comprehensive configuration analysis

**Test Types:**
- **Current:** Test current repository configuration
- **Public-simulation:** Simulate public repository behavior and security implications
- **Private-simulation:** Test private repository features and security
- **Cross-repository:** Test repository switching scenarios

**When to use:**
- Security validation
- Repository migration testing
- Understanding repository-specific behavior
- Compliance checking

**Example usage:**
```bash
# Test current repository
test_type: "current"
validate_permissions: true

# Simulate public repository security
test_type: "public-simulation"
```

### 4. Feature Demonstration (`feature-demonstration.yml`)

**Purpose:** Complete showcase of all repository runner features with detailed explanations.

**Features:**
- ✅ Auto repository detection and configuration
- ✅ Intelligent runner lifecycle management
- ✅ Advanced debugging and diagnostics
- ✅ Performance monitoring and optimization
- ✅ Security and compliance features
- ✅ Failure scenario testing

**Demonstration Levels:**
- **Basic:** Core functionality only
- **Intermediate:** Additional debugging features
- **Advanced:** Performance monitoring included
- **Complete:** All features including security analysis

**When to use:**
- Learning about runner capabilities
- Demonstrating features to stakeholders
- Comprehensive system analysis
- Training and documentation

**Example usage:**
```bash
# Complete feature demonstration
demo_level: "complete"
enable_debugging: true
test_failure_scenarios: true
```

### 5. Runner Demo (`runner-demo.yml`)

**Purpose:** Interactive demonstration workflow with selectable job types.

**Features:**
- ✅ Multiple job type demonstrations (build, test, deploy, validation)
- ✅ Enhanced debugging output
- ✅ Resource usage monitoring
- ✅ Tool availability testing
- ✅ Optional cleanup skip for debugging

**Job Types:**
- **Build:** Simulated build process with artifact creation
- **Test:** Unit test execution with results reporting
- **Deploy:** Deployment simulation with manifest creation
- **Validation:** Comprehensive environment validation

**When to use:**
- Interactive demonstrations
- Testing specific job types
- Debugging runner environment
- Training purposes

**Example usage:**
```bash
# Test build functionality
job_type: "build"
enable_debugging: false
skip_cleanup: false

# Debug validation with cleanup skip
job_type: "validation"
enable_debugging: true
skip_cleanup: true
```

### 6. Configure Runner (`configure-runner.yml`)

**Purpose:** Manual runner management and configuration workflow.

**Features:**
- ✅ Manual runner registration/removal
- ✅ Runner status checking
- ✅ EC2 instance management
- ✅ Configuration validation
- ✅ Detailed logging and error reporting

**Actions:**
- **Configure:** Register runner with repository
- **Remove:** Unregister runner from repository
- **Status:** Check current runner status

**When to use:**
- Initial runner setup
- Runner maintenance
- Troubleshooting registration issues
- Manual runner management

**Example usage:**
```bash
# Configure new runner
action: "configure"

# Check runner status
action: "status"

# Remove runner
action: "remove"
```

## Usage Patterns

### Getting Started

1. **First-time setup:**
   ```bash
   # 1. Run Simple Runner Test to validate basic setup
   # 2. If self-hosted runner not available, configure secrets
   # 3. Run Configure Runner workflow to register runner
   # 4. Run Test Repository Runner for comprehensive validation
   ```

2. **Regular testing:**
   ```bash
   # Use Simple Runner Test for quick health checks
   # Use specific job types in Runner Demo for targeted testing
   ```

3. **Troubleshooting:**
   ```bash
   # 1. Run Test Repository Runner with debug mode enabled
   # 2. Use Repository Type Tests to check configuration
   # 3. Run Feature Demonstration for comprehensive analysis
   ```

### Debugging Workflows

All workflows include debugging capabilities:

**Enable debugging:**
```yaml
inputs:
  enable_debugging: true
  debug_mode: true
```

**Debug output includes:**
- Environment variables
- System information
- Process lists
- Network connections
- System logs
- Resource usage

**Skip cleanup for debugging:**
```yaml
inputs:
  skip_cleanup: true
```

This keeps the runner registered for manual inspection.

## Workflow Dependencies

### Required Secrets

All workflows require these repository secrets:

```bash
# AWS Configuration
AWS_ACCESS_KEY_ID      # AWS access key for EC2 management
AWS_SECRET_ACCESS_KEY  # AWS secret access key
AWS_REGION            # AWS region (e.g., eu-west-1)

# GitHub Configuration
GH_PAT                # GitHub PAT with 'repo' scope

# EC2 Configuration
EC2_INSTANCE_ID       # EC2 instance ID from Terraform output

# Optional
RUNNER_NAME           # GitHub runner name (defaults to gha_aws_runner)
```

### Infrastructure Requirements

- AWS EC2 instance deployed via Terraform
- Security groups configured for SSH access
- GitHub Actions enabled in repository
- Repository admin permissions

## Error Handling

### Common Issues and Solutions

1. **Missing secrets:**
   ```bash
   Error: Required secrets not configured
   Solution: Configure secrets in repository settings
   ```

2. **Runner not found:**
   ```bash
   Error: No runner available with labels [self-hosted, gha_aws_runner]
   Solution: Run Configure Runner workflow or check runner status
   ```

3. **EC2 instance issues:**
   ```bash
   Error: Instance not found or not running
   Solution: Check EC2_INSTANCE_ID and instance state
   ```

4. **Permission errors:**
   ```bash
   Error: HTTP 403 Forbidden
   Solution: Check GitHub PAT permissions and repository access
   ```

### Debugging Steps

1. **Check workflow logs** for specific error messages
2. **Run validation workflows** to identify configuration issues
3. **Enable debug mode** for detailed output
4. **Check repository settings** for secrets and permissions
5. **Verify AWS resources** are properly configured
6. **Review troubleshooting guide** for specific solutions

## Best Practices

### Workflow Selection

- **Development:** Use Simple Runner Test for quick validation
- **Testing:** Use Test Repository Runner for comprehensive testing
- **Production:** Use specific job types in Runner Demo
- **Troubleshooting:** Use Feature Demonstration with debugging enabled

### Security Considerations

- **Public repositories:** Review security warnings in Repository Type Tests
- **Private repositories:** Use all features safely
- **Secrets management:** Rotate GitHub PAT regularly
- **Access control:** Ensure minimal required permissions

### Performance Optimization

- **Resource monitoring:** Use performance features in workflows
- **Cost optimization:** Stop instances when not needed
- **Batch operations:** Combine multiple tests in single workflow run
- **Caching:** Use workflow artifacts for repeated operations

## Customization

### Adding Custom Tests

Extend existing workflows by adding custom steps:

```yaml
- name: Custom test
  run: |
    echo "Running custom validation..."
    # Add your custom test logic here
```

### Creating New Workflows

Use existing workflows as templates:

1. Copy an existing workflow file
2. Modify job names and descriptions
3. Add custom test logic
4. Update documentation

### Environment-specific Configuration

Customize workflows for different environments:

```yaml
env:
  ENVIRONMENT: ${{ github.ref == 'refs/heads/main' && 'production' || 'development' }}
```

## Monitoring and Maintenance

### Regular Health Checks

- Run Simple Runner Test weekly
- Monitor workflow execution times
- Check resource usage patterns
- Review error logs regularly

### Maintenance Tasks

- Update runner software monthly
- Rotate credentials quarterly
- Review and update security configurations
- Monitor AWS costs and usage

### Alerting

Set up notifications for:
- Workflow failures
- Runner registration issues
- Resource threshold breaches
- Security events

## Support and Troubleshooting

For additional help:

1. **Check the troubleshooting guide:** `docs/repository-runner-troubleshooting.md`
2. **Review workflow logs** for specific error messages
3. **Run diagnostic workflows** with debug mode enabled
4. **Check GitHub and AWS status pages** for service issues
5. **Consult documentation** for GitHub Actions and AWS EC2

Remember to always test changes in a non-production environment first!