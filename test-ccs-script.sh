#!/bin/bash
# Scripts to test Elastic Cloud Cross Cluster Search configuration
# Run these after applying the Terraform configuration

# Load variables from Terraform outputs
LOCAL_ENDPOINT=$(terraform output -raw local_elasticsearch_endpoint)
REMOTE_ENDPOINT=$(terraform output -raw remote_elasticsearch_endpoint)

# For sensitive outputs, you need to explicitly output them
# These commands will prompt for confirmation since they expose sensitive values
echo "Running terraform output commands for passwords. You will need to confirm each one:"
LOCAL_PASSWORD=$(terraform output -raw local_elasticsearch_password)
REMOTE_PASSWORD=$(terraform output -raw remote_elasticsearch_password)

# Alternative method if you don't want to use terraform output for passwords:
# Uncomment and set these manually if needed
# LOCAL_PASSWORD="your-local-deployment-password"
# REMOTE_PASSWORD="your-remote-deployment-password"

echo "Local Elasticsearch Endpoint: $LOCAL_ENDPOINT"
echo "Remote Elasticsearch Endpoint: $REMOTE_ENDPOINT"

# 1. Verify indexA in local deployment
echo -e "\n--- Verifying indexA in local deployment ---"
curl -s -X GET "$REMOTE_ENDPOINT/index_a/_search?pretty" \
  -u "elastic:$REMOTE_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "match_all": {}
    },
    "size": 2
  }'

# 2. Verify indexB in local deployment
echo -e "\n--- Verifying indexB in local deployment ---"
curl -s -X GET "$REMOTE_ENDPOINT/index_b/_search?pretty" \
  -u "elastic:$REMOTE_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "match_all": {}
    },
    "size": 2
  }'

# 3. Test Cross Cluster Search for indexA (should succeed)
echo -e "\n--- Testing Cross Cluster Search for indexA (should succeed) ---"
curl -s -X GET "$LOCAL_ENDPOINT/remote-cluster:index_a/_search?pretty" \
  -u "ccs_user:StrongPassword123!" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "match_all": {}
    },
    "size": 2
  }'

# 4. Test Cross Cluster Search for indexB (should fail with permissions error)
echo -e "\n--- Testing Cross Cluster Search for indexB (should fail with permissions error) ---"
curl -s -X GET "$LOCAL_ENDPOINT/remote-cluster:index_b/_search?pretty" \
  -u "ccs_user:StrongPassword123!" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "match_all": {}
    }
  }'

# 6. Check cluster info - verify remote clusters are connected
echo -e "\n--- Verifying remote clusters connection ---"
curl -s -X GET "$LOCAL_ENDPOINT/_remote/info?pretty" \
  -u "elastic:$LOCAL_PASSWORD"