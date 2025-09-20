#!/bin/bash

# Deep debugging for PDF conversion errors
# This script investigates the exact cause of the PDF issue

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
echo -e "${BLUE}Deep PDF Error Debugging${NC}"
echo -e "${BLUE}========================================${NC}"

# Get service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)")
echo "Service URL: $SERVICE_URL"

# Step 1: Test with a simple conversion and capture detailed logs
echo -e "\n${YELLOW}🔍 Step 1: Testing conversion with detailed logging...${NC}"

# Make a test request
TEST_RESPONSE=$(curl -s -X POST "$SERVICE_URL/convert" \
  -H "Content-Type: application/json" \
  -d '{
    "doc_url": "https://docs.google.com/document/d/1zByXFPhVznKanor06iRs5qLh5Mi7A7Ok_0Ph9eps-yA/edit",
    "custom_input": "Debug Test"
  }')

echo "Response: $TEST_RESPONSE"

# Step 2: Get detailed error logs immediately after the request
echo -e "\n${YELLOW}🔍 Step 2: Checking detailed error logs...${NC}"
sleep 5

echo "Recent error logs:"
gcloud logs read $SERVICE_NAME \
    --region=$REGION \
    --limit=20 \
    --filter="severity>=ERROR OR textPayload:\"PDF\" OR textPayload:\"WeasyPrint\" OR textPayload:\"conversion\"" \
    --format="table(timestamp, severity, textPayload)"

# Step 3: Check the full stack trace
echo -e "\n${YELLOW}🔍 Step 3: Looking for stack traces...${NC}"
gcloud logs read $SERVICE_NAME \
    --region=$REGION \
    --limit=30 \
    --filter="textPayload:\"Traceback\" OR textPayload:\"File \"" \
    --format="value(textPayload)"

# Step 4: Check WeasyPrint specific logs
echo -e "\n${YELLOW}🔍 Step 4: WeasyPrint specific logs...${NC}"
gcloud logs read $SERVICE_NAME \
    --region=$REGION \
    --limit=20 \
    --filter="textPayload:\"weasyprint\" OR textPayload:\"HTML\" OR textPayload:\"CSS\"" \
    --format="table(timestamp, textPayload)"

# Step 5: Check Python environment in the container
echo -e "\n${YELLOW}🔍 Step 5: Testing Python environment (will make a special test request)...${NC}"

# We'll create a test endpoint to check the environment
echo "Making environment check request..."
ENV_RESPONSE=$(curl -s -X POST "$SERVICE_URL/convert" \
  -H "Content-Type: application/json" \
  -d '{
    "doc_url": "test-environment",
    "custom_input": "env-check"
  }')

echo "Environment check response: $ENV_RESPONSE"

echo -e "\n${YELLOW}🔍 Step 6: Checking recent deployment logs...${NC}"
# Check build logs for the latest build
BUILD_ID=$(gcloud builds list --limit=1 --format="value(id)")
echo "Latest build ID: $BUILD_ID"

echo "Build logs (last 20 lines):"
gcloud builds log $BUILD_ID | tail -20

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Debug Information Complete${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}Analysis Summary:${NC}"
echo "1. Look for 'PDF.__init__' errors in the logs above"
echo "2. Check for WeasyPrint import or initialization errors"
echo "3. Look for Python module conflicts"
echo "4. Check if there are dependency version mismatches"

echo -e "\n${YELLOW}Next Steps Based on Findings:${NC}"
echo "If you see:"
echo "  - Import errors: We'll fix dependencies"
echo "  - WeasyPrint API errors: We'll switch to alternative PDF library"
echo "  - Memory errors: We'll increase container resources"
echo "  - File permission errors: We'll fix file handling"