#!/bin/bash

# Debug script for Google Doc to PDF Converter service issues
# This script helps diagnose why the service isn't responding

set -e

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SERVICE_NAME="doc-to-pdf-converter"
REGION="us-central1"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Service Debugging - Cloud Run${NC}"
echo -e "${BLUE}========================================${NC}"

# Step 1: Check if service exists
echo -e "\n${YELLOW}🔍 Step 1: Checking service status...${NC}"

if gcloud run services describe $SERVICE_NAME --region=$REGION > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Service exists${NC}"
    
    # Get detailed service info
    echo -e "\n${YELLOW}Service Details:${NC}"
    gcloud run services describe $SERVICE_NAME --region=$REGION --format="table(
        status.url,
        status.conditions[0].type,
        status.conditions[0].status,
        spec.template.spec.containers[0].image,
        status.latestCreatedRevisionName
    )"
else
    echo -e "${RED}❌ Service does not exist${NC}"
    echo "Available services:"
    gcloud run services list
    exit 1
fi

# Step 2: Check service logs
echo -e "\n${YELLOW}🔍 Step 2: Checking recent logs...${NC}"
echo "Recent logs (last 10 entries):"
echo "----------------------------------------"

# Get recent logs
gcloud logs read $SERVICE_NAME --region=$REGION --limit=10 --format="table(timestamp, severity, textPayload)" 2>/dev/null || {
    echo -e "${YELLOW}⚠️  No logs found or logging not accessible${NC}"
}

# Step 3: Check for errors in logs
echo -e "\n${YELLOW}🔍 Step 3: Checking for errors...${NC}"
echo "Error logs (last 20 entries):"
echo "----------------------------------------"

gcloud logs read $SERVICE_NAME --region=$REGION --limit=20 --filter="severity>=ERROR" --format="table(timestamp, severity, textPayload)" 2>/dev/null || {
    echo -e "${YELLOW}⚠️  No error logs found${NC}"
}

# Step 4: Check container startup logs
echo -e "\n${YELLOW}🔍 Step 4: Checking container startup...${NC}"
echo "Startup logs:"
echo "----------------------------------------"

gcloud logs read $SERVICE_NAME --region=$REGION --limit=20 --filter="textPayload:\"Starting\"" --format="table(timestamp, textPayload)" 2>/dev/null || {
    echo -e "${YELLOW}⚠️  No startup logs found${NC}"
}

# Step 5: Check revision status
echo -e "\n${YELLOW}🔍 Step 5: Checking current revision...${NC}"

LATEST_REVISION=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.latestCreatedRevisionName)")
echo "Latest revision: $LATEST_REVISION"

if [ ! -z "$LATEST_REVISION" ]; then
    echo -e "\n${YELLOW}Revision details:${NC}"
    gcloud run revisions describe $LATEST_REVISION --region=$REGION --format="table(
        status.conditions[0].type,
        status.conditions[0].status,
        status.conditions[0].reason,
        status.conditions[0].message
    )"
fi

# Step 6: Check environment variables
echo -e "\n${YELLOW}🔍 Step 6: Checking environment variables...${NC}"
echo "Service environment variables:"
gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(spec.template.spec.containers[0].env[].name, spec.template.spec.containers[0].env[].value)"

# Step 7: Test different endpoints
echo -e "\n${YELLOW}🔍 Step 7: Testing connectivity...${NC}"

SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)")
echo "Service URL: $SERVICE_URL"

if [ ! -z "$SERVICE_URL" ]; then
    echo -e "\n${YELLOW}Testing basic connectivity...${NC}"
    
    # Test with timeout and verbose output
    echo "Testing: $SERVICE_URL/health"
    curl -v --max-time 30 "$SERVICE_URL/health" 2>&1 || {
        echo -e "${RED}❌ Connection failed${NC}"
    }
    
    echo -e "\n${YELLOW}Testing root endpoint...${NC}"
    curl -v --max-time 30 "$SERVICE_URL/" 2>&1 || {
        echo -e "${RED}❌ Root endpoint failed${NC}"
    }
else
    echo -e "${RED}❌ No service URL found${NC}"
fi

# Step 8: Check Cloud Run permissions
echo -e "\n${YELLOW}🔍 Step 8: Checking permissions...${NC}"
echo "Checking if service allows unauthenticated requests..."

POLICY=$(gcloud run services get-iam-policy $SERVICE_NAME --region=$REGION --format="value(bindings[].members)" 2>/dev/null)
if echo "$POLICY" | grep -q "allUsers"; then
    echo -e "${GREEN}✅ Service allows unauthenticated access${NC}"
else
    echo -e "${RED}❌ Service requires authentication${NC}"
    echo -e "${YELLOW}Fixing permissions...${NC}"
    gcloud run services add-iam-policy-binding $SERVICE_NAME \
        --region=$REGION \
        --member="allUsers" \
        --role="roles/run.invoker"
    echo -e "${GREEN}✅ Fixed permissions${NC}"
fi

# Step 9: Resource check
echo -e "\n${YELLOW}🔍 Step 9: Checking resource allocation...${NC}"
echo "Service resource configuration:"
gcloud run services describe $SERVICE_NAME --region=$REGION --format="table(
    spec.template.spec.containers[0].resources.limits.memory,
    spec.template.spec.containers[0].resources.limits.cpu,
    spec.template.spec.timeoutSeconds
)"

# Step 10: Live log monitoring
echo -e "\n${YELLOW}🔍 Step 10: Live log monitoring${NC}"
echo "Monitoring logs for 30 seconds (press Ctrl+C to stop)..."
echo "Try accessing the service now to see real-time logs."
echo "Service URL: $SERVICE_URL/health"

echo -e "\n${BLUE}Starting live log monitoring...${NC}"
timeout 30s gcloud logs tail $SERVICE_NAME --region=$REGION 2>/dev/null || {
    echo -e "\n${YELLOW}⚠️  Live monitoring ended${NC}"
}

# Summary and recommendations
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Debug Summary & Recommendations${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "\n${YELLOW}Common Issues & Solutions:${NC}"
echo "1. Service starting up: Wait 2-3 minutes and retry"
echo "2. Missing environment variables: Check BUCKET_NAME and GOOGLE_CREDENTIALS_JSON"
echo "3. Container image issues: Rebuild and redeploy"
echo "4. Memory/CPU limits: Increase resources if needed"
echo "5. Application errors: Check application logs above"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. If logs show Python/import errors: Rebuild with fixed dependencies"
echo "2. If memory issues: Increase memory limit"
echo "3. If authentication errors: Check service account permissions"
echo "4. If timeout issues: Increase timeout or optimize code"

echo -e "\n${YELLOW}Quick Fixes to Try:${NC}"
echo "# Redeploy with more resources:"
echo "gcloud run deploy $SERVICE_NAME --image gcr.io/\$PROJECT_ID/doc-to-pdf-converter:latest --region=$REGION --memory=2Gi --timeout=900"
echo ""
echo "# Force new revision:"
echo "gcloud run deploy $SERVICE_NAME --image gcr.io/\$PROJECT_ID/doc-to-pdf-converter:latest --region=$REGION --no-use-http2"
echo ""
echo "# Check build logs:"
echo "gcloud builds list --limit=5"