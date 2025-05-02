#!/bin/bash
# Scripts to test Elastic Cloud Cross Cluster Search configuration
# Run these after applying the Terraform configuration

# Load variables from Terraform outputs
LOCAL_ENDPOINT=$(terraform output -raw local_elasticsearch_endpoint)
LOCAL_KIBANA_ENDPOINT=$(terraform output -raw local_kibana_endpoint)
REMOTE_ENDPOINT=$(terraform output -raw remote_elasticsearch_endpoint)

# Load credentials from Terraform outputs
echo "Running terraform output commands for passwords. You will need to confirm each one:"
LOCAL_PASSWORD=$(terraform output -raw local_elasticsearch_password)
REMOTE_PASSWORD=$(terraform output -raw remote_elasticsearch_password)
CCS_USER=$(terraform output -raw ccs_user_username)
CCS_PASSWORD=$(terraform output -raw ccs_user_password)

# Alternative method if you don't want to use terraform output for passwords:
# Uncomment and set these manually if needed
# LOCAL_PASSWORD="your-local-deployment-password"
# REMOTE_PASSWORD="your-remote-deployment-password"
# CCS_USER="ccs_user"
# CCS_PASSWORD="StrongPassword123!"

echo "Local Elasticsearch Endpoint: $LOCAL_ENDPOINT"
echo "Remote Elasticsearch Endpoint: $REMOTE_ENDPOINT"
echo "CCS User: $CCS_USER"

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
  -u "$CCS_USER:$CCS_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "match_all": {}
    },
    "size": 2
  }'

# 4. Test Cross Cluster Search for indexB (should now succeed with new role permissions)
echo -e "\n--- Testing Cross Cluster Search for indexB (should now succeed) ---"
curl -s -X GET "$LOCAL_ENDPOINT/remote-cluster:index_b/_search?pretty" \
  -u "$CCS_USER:$CCS_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "match_all": {}
    }
  }'

# 5. Test wildcard access to all remote indices
echo -e "\n--- Testing wildcard access to all remote indices ---"
curl -s -X GET "$LOCAL_ENDPOINT/remote-cluster:*/_search?pretty" \
  -u "$CCS_USER:$CCS_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "match_all": {}
    },
    "size": 3
  }'

# 6. Check data view info
echo -e "\n--- Checking data view info ---"
curl -s -X GET "$LOCAL_KIBANA_ENDPOINT/api/data_views/data_view/remote_all_indices" \
  -u "$CCS_USER:$CCS_PASSWORD" \
  -H "kbn-xsrf: true"

# 7. Check Kibana access (should return 200 OK if permissions are correct)
echo -e "\n--- Testing Kibana access ---"
curl -s -I -X GET "$LOCAL_KIBANA_ENDPOINT/api/status" \
  -u "$CCS_USER:$CCS_PASSWORD" \
  -H "kbn-xsrf: true"

# 8. Check cluster info - verify remote clusters are connected
echo -e "\n--- Verifying remote clusters connection ---"
curl -s -X GET "$LOCAL_ENDPOINT/_remote/info?pretty" \
  -u "elastic:$LOCAL_PASSWORD"

# Add summary section
echo -e "\n\n===================================================="
echo -e "              TEST SUMMARY"
echo -e "===================================================="
echo -e "Running summary checks to determine test results...\n"

# Test summaries with status checks

# Check if indexA exists in remote deployment
INDEX_A_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$REMOTE_ENDPOINT/index_a" \
  -u "elastic:$REMOTE_PASSWORD")
if [ "$INDEX_A_CHECK" -eq 200 ]; then
  echo -e "✅ PASS: Index A exists in remote deployment"
else
  echo -e "❌ FAIL: Index A does not exist or is not accessible in remote deployment"
fi

# Check if indexB exists in remote deployment
INDEX_B_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$REMOTE_ENDPOINT/index_b" \
  -u "elastic:$REMOTE_PASSWORD")
if [ "$INDEX_B_CHECK" -eq 200 ]; then
  echo -e "✅ PASS: Index B exists in remote deployment"
else
  echo -e "❌ FAIL: Index B does not exist or is not accessible in remote deployment"
fi

# Check if CCS works for indexA
CCS_A_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$LOCAL_ENDPOINT/remote-cluster:index_a/_search" \
  -u "$CCS_USER:$CCS_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"query":{"match_all":{}}}')
if [ "$CCS_A_CHECK" -eq 200 ]; then
  echo -e "✅ PASS: Cross Cluster Search works for Index A"
else
  echo -e "❌ FAIL: Cross Cluster Search failed for Index A"
fi

# Check if CCS works for indexB
CCS_B_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$LOCAL_ENDPOINT/remote-cluster:index_b/_search" \
  -u "$CCS_USER:$CCS_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"query":{"match_all":{}}}')
if [ "$CCS_B_CHECK" -eq 200 ]; then
  echo -e "✅ PASS: Cross Cluster Search works for Index B"
else
  echo -e "❌ FAIL: Cross Cluster Search failed for Index B"
fi

# Check if wildcard search works
WILDCARD_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$LOCAL_ENDPOINT/remote-cluster:*/_search" \
  -u "$CCS_USER:$CCS_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"query":{"match_all":{}}}')
if [ "$WILDCARD_CHECK" -eq 200 ]; then
  echo -e "✅ PASS: Wildcard search across all remote indices works"
else
  echo -e "❌ FAIL: Wildcard search across all remote indices failed"
fi

# Check if data view exists
DATA_VIEW_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$LOCAL_KIBANA_ENDPOINT/api/data_views/data_view/remote_all_indices" \
  -u "$CCS_USER:$CCS_PASSWORD" \
  -H "kbn-xsrf: true")
if [ "$DATA_VIEW_CHECK" -eq 200 ]; then
  echo -e "✅ PASS: Data View for remote indices exists"
else
  echo -e "❌ FAIL: Data View for remote indices does not exist or is not accessible"
fi

# Check Kibana access
KIBANA_CHECK=$(curl -s -o /dev/null -w "%{http_code}" "$LOCAL_KIBANA_ENDPOINT/api/status" \
  -u "$CCS_USER:$CCS_PASSWORD" \
  -H "kbn-xsrf: true")
if [ "$KIBANA_CHECK" -eq 200 ]; then
  echo -e "✅ PASS: CCS User has Kibana access"
else
  echo -e "❌ FAIL: CCS User does not have Kibana access"
fi

# Check remote cluster connection
REMOTE_INFO=$(curl -s "$LOCAL_ENDPOINT/_remote/info" \
  -u "elastic:$LOCAL_PASSWORD")
if [[ $REMOTE_INFO == *"remote-cluster"* ]]; then
  echo -e "✅ PASS: Remote cluster connection is established"
else
  echo -e "❌ FAIL: Remote cluster connection is not established"
fi

echo -e "\n===================================================="
echo -e "              OVERALL RESULT"
echo -e "===================================================="

# Count total passed and failed tests
PASSED=$(echo -e "$INDEX_A_CHECK\n$INDEX_B_CHECK\n$CCS_A_CHECK\n$CCS_B_CHECK\n$WILDCARD_CHECK\n$DATA_VIEW_CHECK\n$KIBANA_CHECK" | grep -c "200")
TOTAL=8

if [ "$PASSED" -eq "$TOTAL" ]; then
  echo -e "✅ ALL TESTS PASSED: Elasticsearch Cross Cluster Search is working correctly!"
else
  echo -e "⚠️ SOME TESTS FAILED: $PASSED out of $TOTAL tests passed."
  echo -e "Review the detailed test results above for more information."
fi
echo -e "====================================================\n"