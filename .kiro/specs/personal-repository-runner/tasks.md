# Implementation Plan

- [x] 1. Update documentation to reflect repository-level configuration





  - Replace organization-specific references with repository-specific ones
  - Update README.md with repository-level setup instructions
  - Update GitHub PAT scope requirements from admin:org to repo only
  - _Requirements: 5.1, 5.2, 5.3_

- [x] 2. Create repository-level runner setup script




  - Create scripts/repo-runner-setup.sh based on existing org-runner-setup.sh
  - Replace organization API endpoints with repository API endpoints
  - Update environment variable validation for GITHUB_USERNAME and GITHUB_REPOSITORY
  - Remove admin:org scope validation and add repository admin validation
  - _Requirements: 1.1, 1.2, 2.1, 2.3, 3.1, 3.2_

- [x] 3. Update GitHub Actions workflows for repository-level usage





  - Create .github/workflows/runner-demo.yml with repository-specific configuration
  - Create .github/workflows/configure-runner.yml for manual runner management
  - Update workflow to use github.repository instead of organization variables
  - Implement repository-level runner registration and unregistration
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 8.1, 8.2_

- [x] 4. Modify existing scripts to support repository-level operations





  - Update any existing workflow scripts to use repository API endpoints
  - Replace organization-level secret references with repository-level ones
  - Update runner URL format from organization to repository format
  - _Requirements: 1.1, 1.3, 7.4_
-

- [x] 5. Create repository configuration validation functions



  - Implement repository existence validation
  - Add repository access permission validation
  - Create GitHub PAT scope validation for repo-only access
  - Add repository admin permission verification
  - _Requirements: 2.2, 2.4, 3.2, 3.3, 3.5_





- [x] 6. Create Terraform module for repository-specific EC2 provisioning
  - Create terraform/modules/repository-runner module for dedicated EC2 instances
  - Implement parametrized naming convention: runner-{username}-{repository}
  - Add instance tagging for repository identification and cost tracking
  - Create user-data script for automated runner installation
  - Add outputs for instance ID and IP address
  - _Requirements: 8.1, 8.2, 8.3_

- [x] 7. Create EC2 instance provisioning and management scripts
  - Create scripts/create-repository-runner.sh for automated instance creation
  - Create scripts/configure-repository-runner.sh for runner setup on instance
  - Create scripts/destroy-repository-runner.sh for cleanup and cost optimization
  - Implement instance lifecycle management with proper error handling
  - _Requirements: 8.1, 8.4, 8.5_

- [ ] 8. Update Terraform configuration comments and examples
  - Update terraform.tfvars.example with repository-specific variable names
  - Update comments in Terraform files to reflect repository usage
  - Ensure backward compatibility with existing infrastructure
  - _Requirements: 7.1, 7.2_

- [x] 7. Create migration guide and troubleshooting documentation




  - Write migration steps from organization to repository setup
  - Create troubleshooting guide for repository-specific issues
  - Document common error scenarios and solutions
  - Add repository permission validation steps



  - _Requirements: 5.4, 5.5, 7.3, 7.5_

- [ ] 9. Update example workflows and test scenarios
  - Update workflows to include EC2 provisioning and instance management
  - Create working example workflows that demonstrate repository runner usage
  - Add test scenarios for different repository types (public/private)
  - Implement workflow examples that work with current repository automatically
  - Add debugging and validation steps to example workflows
  - _Requirements: 9.1, 9.3, 9.4, 9.5_

- [ ] 10. Implement repository runner instance management functionality
  - Create script to provision dedicated EC2 instance for repository
  - Add functionality to configure runner on provisioned instance
  - Implement cleanup and destruction of repository-specific instances
  - Add validation to prevent conflicts and ensure proper resource management
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 8.1, 8.4_

- [x] 11. Create comprehensive testing and validation scripts
  - Write test script to validate repository-level setup
  - Create integration tests for workflow functionality
  - Add validation for all repository configuration requirements
  - Implement health check script for repository runner status
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_