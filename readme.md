# Elasticsearch Cross Cluster Search (CCS) with Terraform

This project automates the deployment and configuration of Elasticsearch Cross Cluster Search (CCS) using Terraform with the Elastic Cloud provider. It creates a complete setup with two Elastic deployments, index creation, data loading, and security configuration with field and document level security.

## Architecture Overview

```
+-------------------------+             +-------------------------+
|                         |             |                         |
|   LOCAL DEPLOYMENT      |             |   REMOTE DEPLOYMENT     |
|   ---------------       |             |   ----------------      |
|                         |             |                         |
|   +---------------+     |             |   +---------------+     |
|   |               |     |             |   |               |     |
|   | Elasticsearch |     |             |   | Elasticsearch |     |
|   |               |     |             |   |               |     |
|   +-------+-------+     |             |   +-------+-------+     |
|           |             |             |           |             |
|           | Remote      |             |           |             |
|           | Connection  +-------------+           |             |
|           |             |             |           |             |
|   +-------+-------+     |             |   +-------+-------+     |
|   |               |     |             |   |               |     |
|   |    Kibana     |     |             |   |    Kibana     |     |
|   |               |     |             |   |               |     |
|   +---------------+     |             |   +---------------+     |
|                         |             |                         |
+-------------------------+             +-------------------------+
    ^                                       ^
    |                                       |
    |                                       |
    |    +--------------------------+       |
    |    |                          |       |
    +----+    CCS User              +-------+
         |    - Kibana Access       |
         |    - Cross Cluster Role  |
         |    - Data View           |
         |    - Field/Doc Security  |
         +--------------------------+
```

## Components

### Infrastructure

1. **Local Deployment**
   - Elasticsearch cluster (1g size, 1 zone)
   - Kibana instance (1g size, 1 zone)
   - Remote Cluster connection to Remote Deployment

2. **Remote Deployment**
   - Elasticsearch cluster (1g size, 1 zone)
   - Kibana instance (1g size, 1 zone)
   - Contains source data in indices

### Data

1. **Index A (`index_a`)**
   - Contains product data with fields:
     - `id` (keyword)
     - `name` (text)
     - `description` (text)
     - `tags` (keyword)
     - `created_at` (date)
   - Populated with 5 sample product records

2. **Index B (`index_b`)**
   - Contains document data with fields:
     - `id` (keyword)
     - `title` (text)
     - `content` (text)
     - `category` (keyword)
     - `published` (boolean)
     - `updated_at` (date)
   - Populated with 5 sample document records

### Security

1. **Roles**
   - `remote-search-a`: Access to index_a only with field and document level security
     - **Field Level Security**: Grants access to `["description", "created_at", "tags", "name", "id"]` but excludes `["id", "created_at"]`
     - **Document Level Security**: Only returns documents where `tags` field matches "enterprise"
   - `remote-search-all`: Access to all indices on remote cluster
   - `kibana-ccs-user`: Role for Kibana access and using CCS

2. **User**
   - `ccs_user`: User with credentials defined in Terraform
   - Assigned roles: `remote-search-a` and `kibana-ccs-user`
   - Access to Kibana and ability to perform cross-cluster search
   - **Limited Access**: Due to field and document level security, this user will only see:
     - Documents in index_a that have the tag "enterprise"
     - Only the fields: `description`, `tags`, and `name` (excluding `id` and `created_at`)

### Security Features

This implementation demonstrates advanced Elasticsearch security features:

1. **Field Level Security (FLS)**
   - Controls which fields users can access within documents
   - Configured to grant access to specific fields while explicitly denying others
   - Example: User can see `description` and `tags` but not `id` or `created_at`

2. **Document Level Security (DLS)**
   - Controls which documents users can access based on query criteria
   - Configured with a query that only returns documents with `"tags": "enterprise"`
   - Acts as a filter applied to all search requests

3. **Cross-Cluster Security**
   - Security settings are enforced across cluster boundaries
   - Remote cluster respects the security configuration of the querying user
   - Provides secure data access across distributed Elasticsearch deployments

### Data Views

1. **Remote All Indices**
   - Name: "All Remote Indices"
   - Pattern: `remote-cluster:*`
   - Access to all indices in the remote cluster (subject to security restrictions)
   - Time field: `created_at`

## Getting Started

### Prerequisites

- Terraform installed (version 1.0.0+)
- Elastic Cloud API key

### Setup

1. Clone this repository
2. Create `terraform.tfvars` file (use `terraform.tfvars.example` as a template)
3. Add your Elastic Cloud API key to the `terraform.tfvars` file

### Deployment

```bash
# Initialize Terraform with required providers
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### Implementation Approach

This project uses two Terraform providers:

1. **ec** provider (Elastic Cloud provider)
   - Manages the cloud infrastructure and deployments
   - Creates and configures the Elasticsearch and Kibana instances
   - Sets up cross-cluster search connections

2. **elasticstack** provider (Elastic Stack provider) 
   - Manages configuration within the Elastic Stack
   - Creates indices, data views, users, and security roles
   - Configures cross-cluster search permissions
   - Implements field and document level security

Most operations are handled through native Terraform resources, with only bulk document indexing done via a local-exec provisioner since there's no specific Terraform resource for bulk operations yet.

### Testing

Run the included test script to verify the setup:

```bash
bash test-ccs-script.sh
```

The script will test:
- Index existence and content
- Cross-cluster search capabilities
- Access to all indices via wildcard patterns
- Data view configuration
- Kibana access for the CCS user
- **Security restrictions**: Field and document level security enforcement

### Expected Test Results

When the test script runs correctly, you should see output similar to the following:

```
====================================================
              TEST SUMMARY
====================================================
Results from test execution:
✅ PASS: Index A exists in remote deployment
✅ PASS: Index B exists in remote deployment
✅ PASS: Cross Cluster Search works for Index A
✅ EXPECTED FAILURE: Cross Cluster Search works for Index B (status: 403) - This is correct, as access to Index B should be restricted
✅ PASS: Wildcard search across all remote indices
✅ PASS: List all data views
✅ PASS: Access data view by ID
✅ PASS: Data View for remote indices exists
✅ PASS: CCS User has Kibana access
✅ PASS: Remote cluster connection is established

====================================================
              OVERALL RESULT
====================================================
✅ ALL TESTS PASSED: Elasticsearch Cross Cluster Search is working correctly!
   Note: 1 test(s) were expected to fail and did fail as intended.
====================================================
```

### Security Testing Notes

- The test for "Cross Cluster Search works for Index B" is expected to fail with a 403 status code, as we're intentionally restricting access to Index B through our security configuration.
- When testing Index A access, you'll only see documents that have the tag "enterprise" due to document level security.
- The returned documents will only show fields: `description`, `tags`, and `name` due to field level security (excluding `id` and `created_at`).

## Configuration Files

- `main.tf`: Main Terraform configuration
  - Cloud deployments using the `ec` provider
  - Elasticsearch/Kibana configuration using the `elasticstack` provider
  - Index creation, data views, and security roles with field and document level security
- `terraform.tfvars.example`: Example variables file
- `test-ccs-script.sh`: Testing script
- `.gitignore`: Git ignore file for Terraform

## Security Configuration Details

The `remote_search_a` role implements both field and document level security:

```hcl
resource "elasticstack_elasticsearch_security_role" "remote_search_a" {
  provider = elasticstack.remote
  name     = "remote-search-a"
  
  indices {
    names      = ["index_a"]
    privileges = ["read", "read_cross_cluster"]
    field_security {
      grant = ["description", "created_at", "tags", "name", "id"]
      except = ["id", "created_at"]
    }
    query = <<-EOT
    {
      "match": {
          "tags": "enterprise"
      }
    }
    EOT
  }
}
```

This configuration:
- Grants access to specific fields but excludes sensitive ones
- Filters documents to only show those with "enterprise" tags
- Applies these restrictions across cross-cluster search operations

## Outputs

The following outputs are provided after deployment:

- `local_deployment_id`: ID of the local deployment
- `local_elasticsearch_endpoint`: HTTPS endpoint for local Elasticsearch
- `local_elasticsearch_password`: Password for local Elasticsearch
- `remote_deployment_id`: ID of the remote deployment
- `remote_elasticsearch_endpoint`: HTTPS endpoint for remote Elasticsearch
- `remote_elasticsearch_password`: Password for remote Elasticsearch
- `ccs_user_username`: Username for the cross-cluster search user
- `ccs_user_password`: Password for the cross-cluster search user

## Accessing Kibana

To access Kibana with the CCS user:

1. Get the Kibana URL from the Elastic Cloud console or using:
   ```bash
   terraform output -raw local_deployment_id
   ```

2. Use the CCS user credentials:
   ```bash
   terraform output -raw ccs_user_username
   terraform output -raw ccs_user_password
   ```

3. Navigate to the "Discover" tab in Kibana
4. Select the "All Remote Indices" data view to explore data from the remote cluster
5. **Note**: Due to security restrictions, you'll only see:
   - Documents from index_a that have the "enterprise" tag
   - Limited fields: `description`, `tags`, and `name`

## Security Best Practices Demonstrated

This project showcases several Elasticsearch security best practices:

1. **Principle of Least Privilege**: Users only have access to data they need
2. **Field Level Security**: Sensitive fields are hidden from users
3. **Document Level Security**: Only relevant documents are accessible
4. **Role-Based Access Control**: Different roles for different access levels
5. **Cross-Cluster Security**: Security policies enforced across deployments
6. **API Key Management**: Secure authentication using API keys