# Repository Runner Migration Guide

This document explains the changes made to support repository-level GitHub Actions runners while maintaining backward compatibility.

## Changes Made

### 1. New Files Created

- **`terraform.tfvars.example`** - Comprehensive example configuration with repository-specific guidance
- **`README.md`** - Complete setup and usage guide for repository runners
- **`REPOSITORY_MIGRATION.md`** - This migration guide

### 2. Updated Comments and Documentation

All Terraform files have been updated with repository-specific comments:

- **`main.tf`** - Added repository runner context and feature overview
- **`variables.tf`** - Added section headers and repository-specific descriptions
- **`outputs.tf`** - Updated descriptions to reference repository secrets usage
- **`ec2.tf`** - Updated comments and tags to reflect repository usage
- **`security.tf`** - Added detailed security context for repository runners
- **`vpc.tf`** - Updated resource naming and descriptions
- **`locals.tf`** - Updated tags and comments for repository context
- **`user_data.sh`** - Added repository runner setup notes and verification
- **`versions.tf`** - Added backward compatibility notes
- **`terraform.tfvars`** - Added header explaining repository usage

### 3. Backward Compatibility

**✅ Infrastructure Unchanged:**
- All AWS resources remain identical
- Same resource names and configurations
- Same networking and security setup
- Same tool versions and installations

**✅ Migration Path:**
- Existing infrastructure can be updated in-place
- Only runner registration process changes
- GitHub workflows need updates (not Terraform)
- No resource recreation required

## Key Differences from Organization Setup

| Aspect | Organization Runner | Repository Runner |
|--------|-------------------|------------------|
| **GitHub API** | `/orgs/{org}/actions/runners` | `/repos/{owner}/{repo}/actions/runners` |
| **PAT Scope** | `repo` + `admin:org` | `repo` only |
| **Permissions** | Organization admin | Repository admin |
| **Registration** | Organization-wide | Repository-specific |
| **Infrastructure** | ✅ Same | ✅ Same |

## Migration Steps

1. **Update GitHub PAT scope** from `admin:org` to `repo` only
2. **Update repository secrets** with new variable names
3. **Update GitHub Actions workflows** to use repository endpoints
4. **Re-register runner** with repository-specific configuration
5. **Test workflows** to ensure functionality

## Validation Checklist

- [ ] terraform.tfvars.example created with repository guidance
- [ ] All .tf files updated with repository-specific comments
- [ ] Resource tags updated to reflect repository usage
- [ ] Documentation explains repository vs organization differences
- [ ] Backward compatibility maintained for existing infrastructure
- [ ] Migration path documented for existing users

## Files Modified

```
terraform/
├── main.tf ✅ Updated comments
├── variables.tf ✅ Added section headers and repository context
├── locals.tf ✅ Updated tags and comments
├── vpc.tf ✅ Updated resource naming
├── security.tf ✅ Added security context
├── ec2.tf ✅ Updated comments and tags
├── outputs.tf ✅ Updated descriptions
├── user_data.sh ✅ Added repository setup notes
├── versions.tf ✅ Added compatibility notes
├── terraform.tfvars ✅ Added header
├── terraform.tfvars.example ✅ NEW - Comprehensive example
├── README.md ✅ NEW - Setup guide
└── REPOSITORY_MIGRATION.md ✅ NEW - This file
```

All changes maintain full backward compatibility while providing clear guidance for repository-level usage.