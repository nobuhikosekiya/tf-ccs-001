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
echo "Local Kibana Endpoint: $LOCAL_KIBANA_ENDPOINT" 
echo "Remote Elasticsearch Endpoint: $REMOTE_ENDPOINT"
echo "CCS User: $CCS_USER"

# Initialize arrays for test results
declare -a TEST_NAMES
declare -a TEST_RESULTS

# Function for Elasticsearch API test
run_es_test() {
  local test_name=$1
  local endpoint=$2
  local auth=$3
  local path=$4
  local query=$5
  
  local test_id=${#TEST_NAMES[@]}
  TEST_NAMES[$test_id]="$test_name"
  
  echo -e "\n--- $test_name ---"
  
  # Execute request and capture output
  local response=$(curl -s -X GET "$endpoint$path" \
    -u "$auth" \
    -H "Content-Type: application/json" \
    -d "$query")
  
  # Show response
  echo "$response"
  
  # Check status
  local status=$(curl -s -o /dev/null -w "%{http_code}" -X GET "$endpoint$path" \
    -u "$auth" \
    -H "Content-Type: application/json" \
    -d "$query")
  
  TEST_RESULTS[$test_id]=$status
}

# Function for Kibana API test
run_kibana_test() {
  local test_name=$1
  local endpoint=$2
  local auth=$3
  local path=$4
  local method=${5:-GET}
  
  local test_id=${#TEST_NAMES[@]}
  TEST_NAMES[$test_id]="$test_name"
  
  echo -e "\n--- $test_name ---"
  
  # For HEAD requests, show headers
  if [ "$method" = "HEAD" ]; then
    local response=$(curl -s -I -X "$method" "$endpoint$path" \
      -u "$auth" \
      -H "kbn-xsrf: true")
    echo "$response"
    
    # Extract status from header response
    local status=$(echo "$response" | head -n 1 | cut -d' ' -f2)
  else
    # For other requests, show body
    local response=$(curl -s -X "$method" "$endpoint$path" \
      -u "$auth" \
      -H "kbn-xsrf: true")
    echo "$response"
    
    # Get status code separately
    local status=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" "$endpoint$path" \
      -u "$auth" \
      -H "kbn-xsrf: true")
  fi
  
  TEST_RESULTS[$test_id]=$status
}

# Function to check remote cluster connection
run_remote_cluster_test() {
  local test_name=$1
  local endpoint=$2
  local auth=$3
  
  local test_id=${#TEST_NAMES[@]}
  TEST_NAMES[$test_id]="$test_name"
  
  echo -e "\n--- $test_name ---"
  
  local response=$(curl -s "$endpoint/_remote/info" -u "$auth")
  echo "$response"
  
  if [[ "$response" == *"remote-cluster"* ]]; then
    TEST_RESULTS[$test_id]=200
  else
    TEST_RESULTS[$test_id]=404
  fi
}

# Run tests

# 1. Verify indices in remote deployment
run_es_test "Index A exists in remote deployment" "$REMOTE_ENDPOINT" "elastic:$REMOTE_PASSWORD" "/index_a/_search?pretty" '{"query":{"match_all":{}},"size":2}'
run_es_test "Index B exists in remote deployment" "$REMOTE_ENDPOINT" "elastic:$REMOTE_PASSWORD" "/index_b/_search?pretty" '{"query":{"match_all":{}},"size":2}'

# 2. Test Cross Cluster Search capabilities
run_es_test "Cross Cluster Search works for Index A" "$LOCAL_ENDPOINT" "$CCS_USER:$CCS_PASSWORD" "/remote-cluster:index_a/_search?pretty" '{"query":{"match_all":{}},"size":2}'
run_es_test "Cross Cluster Search works for Index B" "$LOCAL_ENDPOINT" "$CCS_USER:$CCS_PASSWORD" "/remote-cluster:index_b/_search?pretty" '{"query":{"match_all":{}},"size":2}'
run_es_test "Wildcard search across all remote indices" "$LOCAL_ENDPOINT" "$CCS_USER:$CCS_PASSWORD" "/remote-cluster:*/_search?pretty" '{"query":{"match_all":{}},"size":3}'

# 3. Check Kibana data view and access
echo -e "\n--- Data View for remote indices exists ---"
echo "Testing data view access and listing all available views..."

# List all data views
run_kibana_test "List all data views" "$LOCAL_KIBANA_ENDPOINT" "$CCS_USER:$CCS_PASSWORD" "/api/data_views"

# Try accessing our data view by ID
run_kibana_test "Access data view by ID" "$LOCAL_KIBANA_ENDPOINT" "$CCS_USER:$CCS_PASSWORD" "/api/data_views/data_view/remote_all_indices"

# Check if data view test passed
if [ "${TEST_RESULTS[${#TEST_RESULTS[@]}-1]}" -eq 200 ]; then
  data_view_status=200
else
  # Try by title instead
  run_kibana_test "Access data view by title" "$LOCAL_KIBANA_ENDPOINT" "$CCS_USER:$CCS_PASSWORD" "/api/data_views/data_view?title=remote-cluster:*"
  data_view_status=${TEST_RESULTS[${#TEST_RESULTS[@]}-1]}
fi

# Add the final data view test result
test_id=${#TEST_NAMES[@]}
TEST_NAMES[$test_id]="Data View for remote indices exists"
TEST_RESULTS[$test_id]=$data_view_status

# 4. Check Kibana access
run_kibana_test "CCS User has Kibana access" "$LOCAL_KIBANA_ENDPOINT" "$CCS_USER:$CCS_PASSWORD" "/api/status" "HEAD"

# 5. Verify remote clusters connection
run_remote_cluster_test "Remote cluster connection is established" "$LOCAL_ENDPOINT" "elastic:$LOCAL_PASSWORD"

# Display summary section
echo -e "\n\n===================================================="
echo "              TEST SUMMARY"
echo "===================================================="
echo "Results from test execution:"

# Display test results
for i in "${!TEST_NAMES[@]}"; do
  test_name=${TEST_NAMES[$i]}
  status=${TEST_RESULTS[$i]}
  
  # Special handling for the Index B CCS test which is expected to fail
  if [ "$test_name" = "Cross Cluster Search works for Index B" ]; then
    if [ "$status" -eq 200 ]; then
      echo "⚠️ UNEXPECTED PASS: $test_name (This test was expected to fail because access to Index B should be restricted)"
    else
      echo "✅ EXPECTED FAILURE: $test_name (status: $status) - This is correct, as access to Index B should be restricted"
    fi
  else
    # Normal test result display
    if [ "$status" -eq 200 ]; then
      echo "✅ PASS: $test_name"
    else
      echo "❌ FAIL: $test_name (status: $status)"
    fi
  fi
done

# Calculate overall results
echo -e "\n===================================================="
echo "              OVERALL RESULT"
echo "===================================================="

# Count total passed and failed tests
PASSED=0
TOTAL=${#TEST_NAMES[@]}
EXPECTED_FAILURES=0

for i in "${!TEST_NAMES[@]}"; do
  test_name=${TEST_NAMES[$i]}
  status=${TEST_RESULTS[$i]}
  
  # Handle the expected failure specially
  if [ "$test_name" = "Cross Cluster Search works for Index B" ]; then
    if [ "$status" -ne 200 ]; then
      # This is an expected failure, count it as a pass for the overall result
      ((PASSED++))
      ((EXPECTED_FAILURES++))
    fi
  elif [ "$status" -eq 200 ]; then
    ((PASSED++))
  fi
done

# Adjust the total count to account for expected failures
ADJUSTED_TOTAL=$((TOTAL))

if [ "$PASSED" -eq "$ADJUSTED_TOTAL" ]; then
  echo "✅ ALL TESTS PASSED: Elasticsearch Cross Cluster Search is working correctly!"
  if [ "$EXPECTED_FAILURES" -gt 0 ]; then
    echo "   Note: $EXPECTED_FAILURES test(s) were expected to fail and did fail as intended."
  fi
else
  echo "⚠️ SOME TESTS FAILED: $PASSED out of $ADJUSTED_TOTAL tests passed."
  if [ "$EXPECTED_FAILURES" -gt 0 ]; then
    echo "   Note: $EXPECTED_FAILURES test(s) were expected to fail and did fail as intended."
  fi
  echo "   Review the detailed test results above for more information."
fi
echo "===================================================="