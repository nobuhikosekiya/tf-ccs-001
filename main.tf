terraform {
  required_providers {
    ec = {
      source  = "elastic/ec"
      version = ">= 0.5.0"
    }
  }
}

provider "ec" {
  apikey = var.elastic_api_key
}

# Variables
variable "elastic_api_key" {
  description = "API key for Elastic Cloud"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Region for the deployments"
  type        = string
  default     = "us-east-1"
}

variable "elasticsearch_version" {
  description = "Elasticsearch version"
  type        = string
  default     = "8.17.4"
}

variable "ccs_user_password" {
  description = "Password for the cross cluster search user"
  type        = string
  default     = "StrongPassword123!"
  sensitive   = true
}

variable "ccs_user_name" {
  description = "User name for the cross cluster search user"
  type        = string
  default     = "ccs_user"
}

# Local deployment
resource "ec_deployment" "local_deployment" {
  name = "local-deployment"
  region = var.region
  version = var.elasticsearch_version
  deployment_template_id = "aws-storage-optimized"

  elasticsearch = {
    hot = {
      size          = "1g"
      zone_count    = 1
      autoscaling = {}
    }
    # Define a remote cluster connection from local to remote
    remote_cluster = [{
      deployment_id = ec_deployment.remote_deployment.id
      alias         = "remote-cluster"
      ref_id        = "main-elasticsearch"  # This is the default ref_id for the main Elasticsearch resource
    }]
  }

  kibana = {
    size = "1g"
    zone_count = 1
  }

  # This deployment depends on the remote deployment being created first
  depends_on = [
    ec_deployment.remote_deployment
  ]
}

# Remote deployment
resource "ec_deployment" "remote_deployment" {
  name = "remote-deployment"
  region = var.region
  version = var.elasticsearch_version
  deployment_template_id = "aws-storage-optimized"

  elasticsearch = {
    hot = {
      size          = "1g"
      zone_count    = 1
      autoscaling = {}
    }
  }

  kibana = {
    size = "1g"
    zone_count = 1
  }
}

# Output deployment IDs and endpoints
output "local_deployment_id" {
  value = ec_deployment.local_deployment.id
}

output "local_elasticsearch_endpoint" {
  value = ec_deployment.local_deployment.elasticsearch.https_endpoint
}

output "local_elasticsearch_password" {
  value = ec_deployment.local_deployment.elasticsearch_password
  sensitive = true
}

output "remote_deployment_id" {
  value = ec_deployment.remote_deployment.id
}

output "remote_elasticsearch_endpoint" {
  value = ec_deployment.remote_deployment.elasticsearch.https_endpoint
}

output "remote_elasticsearch_password" {
  value = ec_deployment.remote_deployment.elasticsearch_password
  sensitive = true
}

# CCS user credentials output
output "ccs_user_username" {
  value = var.ccs_user_name
  description = "Username for the cross cluster search user"
}

output "ccs_user_password" {
  value = var.ccs_user_password
  description = "Password for the cross cluster search user"
  sensitive = true
}

# Null resource for setting up CCS configuration using local-exec provisioner
resource "null_resource" "setup_cross_cluster_search" {
  depends_on = [
    ec_deployment.local_deployment,
    ec_deployment.remote_deployment
  ]

  # Provisioner to set up remote cluster connection from local to remote
  provisioner "local-exec" {
    command = <<-EOT
      # Create indexA in local deployment with mapping
      curl -X PUT "${ec_deployment.remote_deployment.elasticsearch.https_endpoint}/index_a" \
        -u "elastic:${ec_deployment.remote_deployment.elasticsearch_password}" \
        -H "Content-Type: application/json" \
        -d '{
          "settings": {
            "number_of_shards": 1,
            "number_of_replicas": 1
          },
          "mappings": {
            "properties": {
              "id": { "type": "keyword" },
              "name": { "type": "text" },
              "description": { "type": "text" },
              "tags": { "type": "keyword" },
              "created_at": { "type": "date" }
            }
          }
        }' >> provision.log

      # Create indexB in local deployment with mapping
      curl -X PUT "${ec_deployment.remote_deployment.elasticsearch.https_endpoint}/index_b" \
        -u "elastic:${ec_deployment.remote_deployment.elasticsearch_password}" \
        -H "Content-Type: application/json" \
        -d '{
          "settings": {
            "number_of_shards": 1,
            "number_of_replicas": 1
          },
          "mappings": {
            "properties": {
              "id": { "type": "keyword" },
              "title": { "type": "text" },
              "content": { "type": "text" },
              "category": { "type": "keyword" },
              "published": { "type": "boolean" },
              "updated_at": { "type": "date" }
            }
          }
        }' >> provision.log
      
      # Add sample documents to indexA
      curl -X POST "${ec_deployment.remote_deployment.elasticsearch.https_endpoint}/index_a/_bulk" \
        -u "elastic:${ec_deployment.remote_deployment.elasticsearch_password}" \
        -H "Content-Type: application/x-ndjson" \
        --data-binary '
{"index":{"_id":"1"}}
{"id":"A001","name":"Product Alpha","description":"This is our flagship product with advanced features","tags":["premium","featured"],"created_at":"2025-01-15T08:30:00Z"}
{"index":{"_id":"2"}}
{"id":"A002","name":"Product Beta","description":"Great value product for everyday use","tags":["standard","popular"],"created_at":"2025-02-20T10:15:00Z"}
{"index":{"_id":"3"}}
{"id":"A003","name":"Product Gamma","description":"Entry-level product with essential features","tags":["basic","affordable"],"created_at":"2025-03-05T14:45:00Z"}
{"index":{"_id":"4"}}
{"id":"A004","name":"Product Delta","description":"Special edition with unique customizations","tags":["limited","exclusive"],"created_at":"2025-04-10T09:00:00Z"}
{"index":{"_id":"5"}}
{"id":"A005","name":"Product Epsilon","description":"Professional grade for enterprise users","tags":["enterprise","powerful"],"created_at":"2025-04-25T16:30:00Z"}
' >> provision.log
      
      # Add sample documents to indexB
      curl -X POST "${ec_deployment.remote_deployment.elasticsearch.https_endpoint}/index_b/_bulk" \
        -u "elastic:${ec_deployment.remote_deployment.elasticsearch_password}" \
        -H "Content-Type: application/x-ndjson" \
        --data-binary '
{"index":{"_id":"1"}}
{"id":"B001","title":"Confidential Report: Q1 2025","content":"Financial analysis and forecasting for the first quarter","category":"finance","published":false,"updated_at":"2025-01-30T11:00:00Z"}
{"index":{"_id":"2"}}
{"id":"B002","title":"Customer Satisfaction Survey Results","content":"Analysis of customer feedback from global markets","category":"marketing","published":true,"updated_at":"2025-02-15T13:20:00Z"}
{"index":{"_id":"3"}}
{"id":"B003","title":"Internal Security Protocol","content":"Updated security guidelines for all employees","category":"security","published":true,"updated_at":"2025-03-10T09:45:00Z"}
{"index":{"_id":"4"}}
{"id":"B004","title":"New Product Roadmap","content":"Strategic planning for upcoming product launches","category":"product","published":false,"updated_at":"2025-03-25T15:10:00Z"}
{"index":{"_id":"5"}}
{"id":"B005","title":"HR Policy Updates","content":"Revised workplace policies and benefits information","category":"hr","published":true,"updated_at":"2025-04-05T10:30:00Z"}
' >> provision.log

      # Create a dataview for all remote indices
      curl -X PUT "${ec_deployment.local_deployment.elasticsearch.https_endpoint}/_data_view/remote_all_indices" \
        -u "elastic:${ec_deployment.local_deployment.elasticsearch_password}" \
        -H "Content-Type: application/json" \
        -d '{
          "title": "remote-cluster:*",
          "name": "All Remote Indices",
          "timeFieldName": "created_at"
        }' >> provision.log

      # Set up local role for kibana access and cross-cluster search
      curl -X PUT "${ec_deployment.local_deployment.elasticsearch.https_endpoint}/_security/role/kibana-ccs-user" \
        -u "elastic:${ec_deployment.local_deployment.elasticsearch_password}" \
        -H "Content-Type: application/json" \
        -d '{
          "cluster": [
            "monitor"
          ],
          "indices": [
            {
              "names": ["remote-cluster:*"],
              "privileges": ["read", "view_index_metadata"]
            }
          ],
          "applications": [
            {
              "application": "kibana-.kibana",
              "privileges": ["read", "space_read"],
              "resources": ["*"]
            }
          ]
        }' >> provision.log

      # Set up remote role for cross-cluster search
      curl -X PUT "${ec_deployment.remote_deployment.elasticsearch.https_endpoint}/_security/role/remote-search-a" \
        -u "elastic:${ec_deployment.remote_deployment.elasticsearch_password}" \
        -H "Content-Type: application/json" \
        -d '{
          "indices": [
            {
              "names": ["index_a"],
              "privileges": ["read", "read_cross_cluster"]
            }
          ]
        }' >> provision.log

      # Set up local role for cross-cluster search
      curl -X PUT "${ec_deployment.local_deployment.elasticsearch.https_endpoint}/_security/role/remote-search-a" \
        -u "elastic:${ec_deployment.local_deployment.elasticsearch_password}" \
        -H "Content-Type: application/json" \
        -d '{}' >> provision.log

      # Create a user with the CCS role
      curl -X PUT "${ec_deployment.local_deployment.elasticsearch.https_endpoint}/_security/user/${var.ccs_user_name}" \
        -u "elastic:${ec_deployment.local_deployment.elasticsearch_password}" \
        -H "Content-Type: application/json" \
        -d '{
          "password": "${var.ccs_user_password}",
          "roles": ["remote-search-a, kibana-ccs-user"],
          "full_name": "Cross Cluster Search User",
          "email": "ccs@example.com"
        }' >> provision.log
    EOT
  }
}