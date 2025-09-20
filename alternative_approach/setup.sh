#!/bin/bash

# Google Doc to PDF Converter - Setup Script
# This script sets up the complete infrastructure for the workflow

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_PROJECT_ID=""
DEFAULT_REGION="us-central1"
DEFAULT_BUCKET_SUFFIX="pdf-assets"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Google Doc to PDF Converter Setup${NC}"
echo -e "${BLUE}========================================${NC}"

# Get project configuration
read -p "Enter your Google Cloud Project ID [$DEFAULT_PROJECT_ID]: " PROJECT_ID
PROJECT_ID=${PROJECT_ID:-$DEFAULT_PROJECT_ID}

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: Project ID is required${NC}"
    exit 1
fi

read -p "Enter your preferred region [$DEFAULT_REGION]: " REGION
REGION=${REGION:-$DEFAULT_REGION}

BUCKET_NAME="${PROJECT_ID}-${DEFAULT_BUCKET_SUFFIX}"
SERVICE_NAME="doc-to-pdf-converter"

echo -e "${YELLOW}Configuration:${NC}"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Bucket Name: $BUCKET_NAME"
echo "Service Name: $SERVICE_NAME"
echo ""

# Confirm setup
read -p "Continue with this configuration? (y/N): " CONFIRM
if [[ $CONFIRM != [yY] ]]; then
    echo "Setup cancelled."
    exit 0
fi

echo -e "${BLUE}Starting setup...${NC}"

# Set the project
echo -e "${YELLOW}Setting Google Cloud project...${NC}"
gcloud config set project $PROJECT_ID

# Enable required APIs
echo -e "${YELLOW}Enabling required APIs...${NC}"
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable docs.googleapis.com
gcloud services enable containerregistry.googleapis.com

# Create storage bucket
echo -e "${YELLOW}Creating storage bucket...${NC}"
if ! gsutil ls -b gs://$BUCKET_NAME > /dev/null 2>&1; then
    gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$BUCKET_NAME
    echo -e "${GREEN}Bucket created: gs://$BUCKET_NAME${NC}"
else
    echo -e "${GREEN}Bucket already exists: gs://$BUCKET_NAME${NC}"
fi

# Set up bucket permissions
echo -e "${YELLOW}Setting bucket permissions...${NC}"
gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME

# Create assets directory structure
echo -e "${YELLOW}Creating bucket directory structure...${NC}"
echo "Creating assets directory..." | gsutil cp - gs://$BUCKET_NAME/assets/.gitkeep
echo "Creating generated directory..." | gsutil cp - gs://$BUCKET_NAME/generated/.gitkeep

# Create service account for the application
echo -e "${YELLOW}Creating service account...${NC}"
SERVICE_ACCOUNT_NAME="doc-pdf-converter"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL > /dev/null 2>&1; then
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --description="Service account for Google Doc to PDF converter" \
        --display-name="Doc to PDF Converter"
    echo -e "${GREEN}Service account created${NC}"
else
    echo -e "${GREEN}Service account already exists${NC}"
fi

# Grant necessary permissions
echo -e "${YELLOW}Granting permissions to service account...${NC}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/storage.admin"

# Create and download service account key
echo -e "${YELLOW}Creating service account key...${NC}"
KEY_FILE="service-account-key.json"
if [ ! -f "$KEY_FILE" ]; then
    gcloud iam service-accounts keys create $KEY_FILE \
        --iam-account=$SERVICE_ACCOUNT_EMAIL
    echo -e "${GREEN}Service account key created: $KEY_FILE${NC}"
else
    echo -e "${GREEN}Service account key already exists: $KEY_FILE${NC}"
fi

# Convert key to base64 for environment variable
echo -e "${YELLOW}Preparing credentials for deployment...${NC}"
GOOGLE_CREDENTIALS_JSON=$(cat $KEY_FILE | base64 -w 0)

# Create environment file
echo -e "${YELLOW}Creating environment configuration...${NC}"
cat > .env << EOF
PROJECT_ID=$PROJECT_ID
BUCKET_NAME=$BUCKET_NAME
REGION=$REGION
GOOGLE_CREDENTIALS_JSON=$GOOGLE_CREDENTIALS_JSON
EOF

# Build and deploy
echo -e "${YELLOW}Building and deploying application...${NC}"
gcloud builds submit --config cloudbuild.yaml \
    --substitutions=_REGION=$REGION,_BUCKET_NAME=$BUCKET_NAME,_GOOGLE_CREDENTIALS_JSON="$GOOGLE_CREDENTIALS_JSON"

# Get the service URL
echo -e "${YELLOW}Getting service URL...${NC}"
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)")

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Service URL: ${BLUE}$SERVICE_URL${NC}"
echo -e "Bucket Name: ${BLUE}gs://$BUCKET_NAME${NC}"
echo -e "Service Account: ${BLUE}$SERVICE_ACCOUNT_EMAIL${NC}"
echo ""
echo -e "${YELLOW}Test your deployment:${NC}"
echo "curl -X POST $SERVICE_URL/convert \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"doc_url\": \"YOUR_GOOGLE_DOC_URL\", \"custom_input\": \"Your Brand Name\"}'"
echo ""
echo -e "${YELLOW}Health check:${NC}"
echo "curl $SERVICE_URL/health"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Test the API with a Google Doc URL"
echo "2. Upload custom assets to gs://$BUCKET_NAME/assets/"
echo "3. Monitor logs: gcloud logs tail $SERVICE_NAME --region=$REGION"
echo ""
echo -e "${RED}Important: Keep your service-account-key.json file secure!${NC}"