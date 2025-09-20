# Requirements Document

## Introduction

This feature converts the existing organization-level GitHub Actions runner infrastructure to work with personal GitHub account repositories. The system will create dedicated AWS EC2 instances for each repository runner, with parametrized naming and automated provisioning. Each repository will have its own isolated EC2 instance to ensure complete separation and security, while maintaining cost-optimized runner capabilities.

## Requirements

### Requirement 1

**User Story:** As a developer with a personal GitHub account, I want to create dedicated AWS runners for each of my repositories, so that I can run CI/CD workflows with complete isolation and without needing organization admin permissions.

#### Acceptance Criteria

1. WHEN a user configures a runner THEN the system SHALL create a dedicated EC2 instance for that specific repository
2. WHEN a user provides repository details THEN the system SHALL provision an EC2 instance with a parametrized name based on the repository
3. WHEN the runner is configured THEN it SHALL be available only to the specified repository with complete isolation
4. WHEN a user creates multiple repository runners THEN each SHALL have its own dedicated EC2 instance
5. IF the user lacks repository admin permissions THEN the system SHALL provide clear error messages with remediation steps

### Requirement 2

**User Story:** As a developer, I want simplified GitHub PAT requirements, so that I don't need organization admin permissions to use the runner.

#### Acceptance Criteria

1. WHEN configuring the runner THEN the system SHALL require only `repo` scope for the GitHub PAT
2. WHEN validating permissions THEN the system SHALL NOT require `admin:org` scope
3. WHEN checking repository access THEN the system SHALL verify the user has admin permissions on the target repository
4. WHEN generating registration tokens THEN the system SHALL use repository-level API endpoints
5. IF the PAT lacks required scopes THEN the system SHALL provide specific guidance on required permissions

### Requirement 3

**User Story:** As a developer, I want to easily specify which repository to use with the runner, so that I can quickly switch between different projects.

#### Acceptance Criteria

1. WHEN configuring the runner THEN the system SHALL accept GitHub username and repository name as parameters
2. WHEN validating repository details THEN the system SHALL verify the repository exists and is accessible
3. WHEN the repository is private THEN the system SHALL ensure the PAT has appropriate access
4. WHEN switching repositories THEN the system SHALL cleanly unregister from the previous repository
5. IF the repository doesn't exist THEN the system SHALL provide clear error messages

### Requirement 4

**User Story:** As a developer, I want the same workflow automation capabilities, so that I can start/stop the runner automatically from GitHub Actions.

#### Acceptance Criteria

1. WHEN using GitHub Actions workflows THEN the system SHALL provide repository-level runner management
2. WHEN starting the runner THEN the workflow SHALL register it with the current repository automatically
3. WHEN stopping the runner THEN the workflow SHALL unregister it from the current repository
4. WHEN workflows run THEN they SHALL use the same runner labels and configuration
5. IF workflow secrets are missing THEN the system SHALL provide clear documentation on required secrets

### Requirement 5

**User Story:** As a developer, I want updated documentation and examples, so that I can easily understand how to use the repository-level runner.

#### Acceptance Criteria

1. WHEN reading documentation THEN it SHALL clearly explain repository-level configuration and usage
2. WHEN following setup instructions THEN they SHALL be specific to personal GitHub accounts
3. WHEN viewing examples THEN they SHALL show repository-level configuration and usage
4. WHEN troubleshooting THEN the guide SHALL address repository-specific issues
5. IF configuration fails THEN error messages SHALL reference updated documentation

### Requirement 6

**User Story:** As a developer, I want to maintain the same security and cost optimization features, so that the runner remains secure and cost-effective.

#### Acceptance Criteria

1. WHEN the runner operates THEN it SHALL maintain persistent registration with the target repository
2. WHEN jobs complete THEN the runner SHALL remain available for subsequent jobs
3. WHEN using AWS resources THEN the system SHALL maintain the same cost optimization features
4. WHEN accessing the runner THEN it SHALL maintain the same security group restrictions
5. IF security issues arise THEN the system SHALL provide the same isolation guarantees

### Requirement 7

**User Story:** As a developer, I want backward compatibility with existing infrastructure, so that I can reuse my existing AWS setup without major changes.

#### Acceptance Criteria

1. WHEN using existing Terraform configuration THEN it SHALL work without major modifications
2. WHEN using the same EC2 instance THEN it SHALL support repository-level configurations
3. WHEN migrating from organization setup THEN the system SHALL cleanly transition without data loss
4. WHEN using existing scripts THEN they SHALL be adaptable to repository-level usage
5. IF conflicts arise THEN the system SHALL provide migration guidance

### Requirement 8

**User Story:** As a developer, I want automated EC2 instance provisioning for each repository runner, so that I can easily create isolated infrastructure without manual AWS configuration.

#### Acceptance Criteria

1. WHEN creating a repository runner THEN the system SHALL automatically provision a dedicated EC2 instance
2. WHEN provisioning an instance THEN the system SHALL use a parametrized naming convention based on repository details
3. WHEN the instance is created THEN it SHALL be tagged with repository information for identification and cost tracking
4. WHEN multiple repositories need runners THEN each SHALL get its own dedicated EC2 instance
5. IF instance provisioning fails THEN the system SHALL provide clear error messages and rollback procedures

### Requirement 9

**User Story:** As a developer, I want example workflows that work with my repository, so that I can quickly test and validate the runner setup.

#### Acceptance Criteria

1. WHEN using example workflows THEN they SHALL work with the current repository automatically
2. WHEN workflows reference secrets THEN they SHALL use repository-level secret names
3. WHEN testing the runner THEN example workflows SHALL demonstrate all key features
4. WHEN workflows fail THEN they SHALL provide clear error messages for debugging
5. IF examples don't work THEN documentation SHALL provide troubleshooting steps