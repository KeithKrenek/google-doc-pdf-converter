#!/bin/bash

# Test script for Google Doc to PDF Converter
# This script tests the deployed service

set -e

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Testing Google Doc to PDF Converter${NC}"
echo -e "${BLUE}========================================${NC}"

# Get service URL
if [ -z "$SERVICE_URL" ]; then
    echo -e "${YELLOW}Getting service URL...${NC}"
    SERVICE_URL=$(gcloud run services describe doc-to-pdf-converter --region=us-central1 --format="value(status.url)" 2>/dev/null)
    
    if [ -z "$SERVICE_URL" ]; then
        echo -e "${RED}❌ Could not get service URL. Make sure the service is deployed.${NC}"
        echo "Try: gcloud run services list"
        exit 1
    fi
fi

echo -e "${BLUE}Service URL: $SERVICE_URL${NC}"

# Test 1: Health Check
echo -e "\n${YELLOW}🔍 Test 1: Health Check${NC}"
echo "Testing: $SERVICE_URL/health"

if curl -s -f "$SERVICE_URL/health" > /dev/null; then
    echo -e "${GREEN}✅ Health check passed${NC}"
    curl -s "$SERVICE_URL/health" | python -m json.tool
else
    echo -e "${RED}❌ Health check failed${NC}"
    echo "Service might not be ready yet. Wait a few minutes and try again."
    exit 1
fi

# Test 2: Sample Document Conversion
echo -e "\n${YELLOW}🔍 Test 2: Document Conversion${NC}"

# You can replace this with any public Google Doc
# This is a sample public document
DOC_URL="https://docs.google.com/document/d/1zByXFPhVznKanor06iRs5qLh5Mi7A7Ok_0Ph9eps-yA/edit"
CUSTOM_INPUT="Test Company"

echo "Testing document conversion..."
echo "Doc URL: $DOC_URL"
echo "Brand: $CUSTOM_INPUT"

# Make the API call
echo -e "\n${YELLOW}Making API request...${NC}"

RESPONSE=$(curl -s -X POST "$SERVICE_URL/convert" \
  -H "Content-Type: application/json" \
  -d "{
    \"doc_url\": \"$DOC_URL\",
    \"custom_input\": \"$CUSTOM_INPUT\"
  }")

# Check if request was successful
if echo "$RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✅ Conversion successful!${NC}"
    
    # Pretty print the response
    echo -e "\n${BLUE}Response:${NC}"
    echo "$RESPONSE" | python -m json.tool
    
    # Extract download URL
    DOWNLOAD_URL=$(echo "$RESPONSE" | python -c "import sys, json; print(json.load(sys.stdin)['download_url'])" 2>/dev/null)
    
    if [ ! -z "$DOWNLOAD_URL" ]; then
        echo -e "\n${GREEN}📄 PDF Download URL:${NC}"
        echo "$DOWNLOAD_URL"
        
        # Test if PDF is accessible
        echo -e "\n${YELLOW}Testing PDF download...${NC}"
        if curl -s -f -I "$DOWNLOAD_URL" > /dev/null; then
            echo -e "${GREEN}✅ PDF is accessible${NC}"
            
            # Option to download the PDF
            read -p "Download the PDF to test locally? (y/N): " DOWNLOAD_CONFIRM
            if [[ $DOWNLOAD_CONFIRM == [yY] ]]; then
                FILENAME=$(basename "$DOWNLOAD_URL" | cut -d'?' -f1)
                echo "Downloading: $FILENAME"
                curl -s -o "$FILENAME" "$DOWNLOAD_URL"
                echo -e "${GREEN}✅ Downloaded: $FILENAME${NC}"
                
                # Check file size
                FILE_SIZE=$(ls -lh "$FILENAME" | awk '{print $5}')
                echo "File size: $FILE_SIZE"
            fi
        else
            echo -e "${RED}❌ PDF is not accessible${NC}"
        fi
    fi
else
    echo -e "${RED}❌ Conversion failed${NC}"
    echo -e "\n${RED}Error response:${NC}"
    echo "$RESPONSE" | python -m json.tool
fi

# Test 3: Error Handling
echo -e "\n${YELLOW}🔍 Test 3: Error Handling${NC}"
echo "Testing with invalid URL..."

ERROR_RESPONSE=$(curl -s -X POST "$SERVICE_URL/convert" \
  -H "Content-Type: application/json" \
  -d '{"doc_url": "invalid-url", "custom_input": "Test"}')

if echo "$ERROR_RESPONSE" | grep -q '"error"'; then
    echo -e "${GREEN}✅ Error handling works correctly${NC}"
    echo "Error response: $(echo "$ERROR_RESPONSE" | python -c "import sys, json; print(json.load(sys.stdin)['error'])" 2>/dev/null)"
else
    echo -e "${YELLOW}⚠️  Unexpected error response${NC}"
    echo "$ERROR_RESPONSE"
fi

# Test 4: Performance Test
echo -e "\n${YELLOW}🔍 Test 4: Performance Test${NC}"
echo "Testing response time..."

START_TIME=$(date +%s)
curl -s "$SERVICE_URL/health" > /dev/null
END_TIME=$(date +%s)

RESPONSE_TIME=$((END_TIME - START_TIME))
echo "Health check response time: ${RESPONSE_TIME}s"

if [ $RESPONSE_TIME -lt 5 ]; then
    echo -e "${GREEN}✅ Good response time${NC}"
else
    echo -e "${YELLOW}⚠️  Slow response time (may need optimization)${NC}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Testing Complete!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}Service Information:${NC}"
echo "URL: $SERVICE_URL"
echo "Health: $SERVICE_URL/health"
echo "Convert: $SERVICE_URL/convert"

echo -e "\n${YELLOW}Quick Test Commands:${NC}"
echo "Health: curl $SERVICE_URL/health"
echo ""
echo "Convert: curl -X POST $SERVICE_URL/convert \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"doc_url\": \"YOUR_DOC_URL\", \"custom_input\": \"Your Brand\"}'"