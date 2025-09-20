#!/bin/bash

# Quick fixes for Cloud Run service not responding
# This script applies common fixes for startup issues

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
echo -e "${BLUE}Quick Fixes for Service Issues${NC}"
echo -e "${BLUE}========================================${NC}"

# Get project ID
PROJECT_ID=$(gcloud config get-value project)
echo "Project ID: $PROJECT_ID"

# Fix 1: Ensure service allows unauthenticated access
echo -e "\n${YELLOW}🔧 Fix 1: Setting up public access...${NC}"
gcloud run services add-iam-policy-binding $SERVICE_NAME \
    --region=$REGION \
    --member="allUsers" \
    --role="roles/run.invoker" \
    --quiet

echo -e "${GREEN}✅ Public access configured${NC}"

# Fix 2: Update service with better resource allocation and timeout
echo -e "\n${YELLOW}🔧 Fix 2: Updating service configuration...${NC}"
gcloud run services update $SERVICE_NAME \
    --region=$REGION \
    --memory=2Gi \
    --cpu=1 \
    --timeout=900 \
    --max-instances=10 \
    --concurrency=5 \
    --no-use-http2 \
    --execution-environment=gen2 \
    --quiet

echo -e "${GREEN}✅ Service configuration updated${NC}"

# Fix 3: Check and set required environment variables
echo -e "\n${YELLOW}🔧 Fix 3: Checking environment variables...${NC}"

# Get current bucket name
BUCKET_NAME="${PROJECT_ID}-pdf-assets"

# Check if bucket exists
if gsutil ls -b gs://$BUCKET_NAME > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Bucket exists: gs://$BUCKET_NAME${NC}"
else
    echo -e "${YELLOW}Creating bucket...${NC}"
    gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$BUCKET_NAME
    gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME
    echo -e "${GREEN}✅ Bucket created${NC}"
fi

# Set environment variables
echo -e "${YELLOW}Setting environment variables...${NC}"
gcloud run services update $SERVICE_NAME \
    --region=$REGION \
    --set-env-vars="BUCKET_NAME=$BUCKET_NAME" \
    --quiet

echo -e "${GREEN}✅ Environment variables set${NC}"

# Fix 4: Force a new revision deployment
echo -e "\n${YELLOW}🔧 Fix 4: Forcing new deployment...${NC}"
gcloud run deploy $SERVICE_NAME \
    --image="gcr.io/$PROJECT_ID/doc-to-pdf-converter:latest" \
    --region=$REGION \
    --memory=2Gi \
    --cpu=1 \
    --timeout=900 \
    --allow-unauthenticated \
    --set-env-vars="BUCKET_NAME=$BUCKET_NAME" \
    --quiet

echo -e "${GREEN}✅ New revision deployed${NC}"

# Fix 5: Wait for service to be ready
echo -e "\n${YELLOW}🔧 Fix 5: Waiting for service to be ready...${NC}"
echo "This may take 2-3 minutes..."

# Wait for service to be ready
for i in {1..12}; do
    echo -n "Checking readiness... attempt $i/12: "
    
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)")
    
    if curl -s -f --max-time 10 "$SERVICE_URL/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Service is ready!${NC}"
        break
    else
        echo -e "${YELLOW}⏳ Not ready yet...${NC}"
        sleep 15
    fi
    
    if [ $i -eq 12 ]; then
        echo -e "${RED}❌ Service still not ready after 3 minutes${NC}"
        echo "Let's check what's happening..."
        
        # Show recent logs
        echo -e "\n${YELLOW}Recent logs:${NC}"
        gcloud logs read $SERVICE_NAME --region=$REGION --limit=10 --format="table(timestamp, severity, textPayload)"
    fi
done

# Final test
echo -e "\n${YELLOW}🔧 Final Test: Testing the service...${NC}"
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)")

echo "Service URL: $SERVICE_URL"

# Test health endpoint
echo -e "\n${YELLOW}Testing health endpoint...${NC}"
if curl -s -f "$SERVICE_URL/health"; then
    echo -e "\n${GREEN}✅ Health check passed!${NC}"
else
    echo -e "\n${RED}❌ Health check still failing${NC}"
    echo -e "${YELLOW}Let's check the logs for errors:${NC}"
    
    # Show error logs
    gcloud logs read $SERVICE_NAME --region=$REGION --limit=5 --filter="severity>=ERROR" --format="table(timestamp, textPayload)"
fi

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Quick Fixes Complete${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "\n${YELLOW}Service Information:${NC}"
echo "URL: $SERVICE_URL"
echo "Health: $SERVICE_URL/health"
echo "Bucket: gs://$BUCKET_NAME"

echo -e "\n${YELLOW}If issues persist, run:${NC}"
echo "./debug-service.sh"
echo ""
echo -e "${YELLOW}Or check build logs:${NC}"
echo "gcloud builds list --limit=3"