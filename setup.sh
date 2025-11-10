#!/bin/bash

#####################################################################
# Google Doc to PDF Converter - Complete Setup Script
# This script automates the entire deployment process
#####################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_REGION="us-central1"
SECRET_NAME="google-doc-converter-credentials"

#####################################################################
# Helper Functions
#####################################################################

print_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

#####################################################################
# Prerequisites Check
#####################################################################

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "Google Cloud CLI is not installed."
        print_status "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    print_success "Google Cloud CLI found"

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "Not authenticated with Google Cloud"
        print_status "Run: gcloud auth login"
        exit 1
    fi
    print_success "Google Cloud authentication verified"

    # Check docker (optional but recommended for local testing)
    if command -v docker &> /dev/null; then
        print_success "Docker found (optional)"
    else
        print_warning "Docker not found (optional for local testing)"
    fi

    print_success "All prerequisites met!"
}

#####################################################################
# Project Configuration
#####################################################################

configure_project() {
    print_header "Project Configuration"

    # Get project ID
    if [ -z "$PROJECT_ID" ]; then
        CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
        echo -e "${CYAN}Current project: ${CURRENT_PROJECT:-none}${NC}"
        read -p "Enter Google Cloud Project ID [$CURRENT_PROJECT]: " PROJECT_ID
        PROJECT_ID=${PROJECT_ID:-$CURRENT_PROJECT}
    fi

    if [ -z "$PROJECT_ID" ]; then
        print_error "Project ID is required!"
        exit 1
    fi

    # Get region
    read -p "Enter deployment region [$DEFAULT_REGION]: " REGION
    REGION=${REGION:-$DEFAULT_REGION}

    # Set bucket name
    BUCKET_NAME="${PROJECT_ID}-pdf-assets"

    # Set project
    gcloud config set project $PROJECT_ID

    print_success "Configuration:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Bucket: $BUCKET_NAME"
}

#####################################################################
# Enable Required APIs
#####################################################################

enable_apis() {
    print_header "Enabling Required APIs"

    APIS=(
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
        "storage.googleapis.com"
        "docs.googleapis.com"
        "secretmanager.googleapis.com"
        "containerregistry.googleapis.com"
    )

    for api in "${APIS[@]}"; do
        print_status "Enabling $api..."
        gcloud services enable $api --project=$PROJECT_ID
    done

    print_success "All required APIs enabled!"
}

#####################################################################
# Create Storage Bucket
#####################################################################

create_storage_bucket() {
    print_header "Setting Up Cloud Storage"

    if gsutil ls -b gs://$BUCKET_NAME &> /dev/null; then
        print_warning "Bucket $BUCKET_NAME already exists"
    else
        print_status "Creating bucket: $BUCKET_NAME"
        gsutil mb -p $PROJECT_ID -l $REGION gs://$BUCKET_NAME
        print_success "Bucket created"
    fi

    # Make bucket publicly readable for generated PDFs
    print_status "Setting bucket permissions..."
    gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME

    # Upload assets if they exist
    if [ -d "assets" ]; then
        print_status "Uploading assets to bucket..."
        gsutil -m cp -r assets/* gs://$BUCKET_NAME/assets/ 2>/dev/null || true
        print_success "Assets uploaded"
    else
        print_warning "No assets directory found. You can add logos later."
    fi
}

#####################################################################
# Setup Service Account
#####################################################################

setup_service_account() {
    print_header "Service Account Setup"

    echo -e "${YELLOW}Service account credentials are needed for Google Docs API access.${NC}"
    echo ""
    echo "You have two options:"
    echo "  1. Use existing service account key file"
    echo "  2. Create a new service account"
    echo ""
    read -p "Choose option (1 or 2): " SA_OPTION

    if [ "$SA_OPTION" = "2" ]; then
        # Create new service account
        SA_NAME="doc-pdf-converter"
        SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

        print_status "Creating service account: $SA_NAME"

        if gcloud iam service-accounts describe $SA_EMAIL --project=$PROJECT_ID &>/dev/null; then
            print_warning "Service account already exists"
        else
            gcloud iam service-accounts create $SA_NAME \
                --description="Service account for Google Doc to PDF converter" \
                --display-name="Doc to PDF Converter" \
                --project=$PROJECT_ID
        fi

        # Grant permissions
        print_status "Granting permissions..."
        gcloud projects add-iam-policy-binding $PROJECT_ID \
            --member="serviceAccount:$SA_EMAIL" \
            --role="roles/storage.admin" \
            --quiet

        # Create key file
        KEY_FILE="service-account-key.json"
        print_status "Creating key file..."
        gcloud iam service-accounts keys create $KEY_FILE \
            --iam-account=$SA_EMAIL \
            --project=$PROJECT_ID

        print_success "Service account created and key saved to $KEY_FILE"
        print_warning "Keep this key file secure and do not commit it to version control!"

    else
        # Use existing key file
        read -p "Enter path to service account key file: " KEY_FILE

        if [ ! -f "$KEY_FILE" ]; then
            print_error "Key file not found: $KEY_FILE"
            exit 1
        fi
    fi

    # Store credentials in Secret Manager
    print_status "Storing credentials in Secret Manager..."

    # Check if secret exists
    if gcloud secrets describe $SECRET_NAME --project=$PROJECT_ID &>/dev/null; then
        print_warning "Secret already exists, creating new version..."
        gcloud secrets versions add $SECRET_NAME \
            --data-file="$KEY_FILE" \
            --project=$PROJECT_ID
    else
        gcloud secrets create $SECRET_NAME \
            --data-file="$KEY_FILE" \
            --replication-policy="automatic" \
            --project=$PROJECT_ID
    fi

    print_success "Credentials stored in Secret Manager"

    # Grant Cloud Run access to the secret
    PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
    COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

    print_status "Granting Cloud Run access to secret..."
    gcloud secrets add-iam-policy-binding $SECRET_NAME \
        --member="serviceAccount:$COMPUTE_SA" \
        --role="roles/secretmanager.secretAccessor" \
        --project=$PROJECT_ID \
        --quiet

    print_success "Service account setup complete!"
}

#####################################################################
# Build and Deploy
#####################################################################

build_and_deploy() {
    print_header "Building and Deploying Application"

    print_status "Submitting build to Cloud Build..."
    print_warning "This may take 5-10 minutes..."

    gcloud builds submit \
        --config cloudbuild.yaml \
        --project=$PROJECT_ID \
        --substitutions=_REGION=$REGION,_BUCKET_NAME=$BUCKET_NAME,_SECRET_NAME=$SECRET_NAME

    print_success "Application deployed successfully!"
}

#####################################################################
# Get Service URL
#####################################################################

get_service_url() {
    print_header "Getting Service URL"

    SERVICE_URL=$(gcloud run services describe google-doc-pdf-converter \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format="value(status.url)" 2>/dev/null || echo "")

    if [ -z "$SERVICE_URL" ]; then
        print_error "Could not retrieve service URL"
        return 1
    fi

    echo -e "${GREEN}Service URL: ${SERVICE_URL}${NC}"
    return 0
}

#####################################################################
# Test Deployment
#####################################################################

test_deployment() {
    print_header "Testing Deployment"

    if [ -z "$SERVICE_URL" ]; then
        print_warning "Service URL not available, skipping test"
        return
    fi

    print_status "Testing health endpoint..."

    HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${SERVICE_URL}/health")

    if [ "$HEALTH_RESPONSE" = "200" ]; then
        print_success "Health check passed!"
    else
        print_warning "Health check returned: $HEALTH_RESPONSE"
    fi
}

#####################################################################
# Display Summary
#####################################################################

display_summary() {
    print_header "Deployment Complete! 🎉"

    echo -e "${GREEN}Your Google Doc to PDF Converter is ready!${NC}"
    echo ""
    echo "📋 Configuration Summary:"
    echo "  Project ID:     $PROJECT_ID"
    echo "  Region:         $REGION"
    echo "  Bucket:         gs://$BUCKET_NAME"
    echo "  Service:        google-doc-pdf-converter"
    echo ""
    echo "🔗 Service URL:"
    echo "  $SERVICE_URL"
    echo ""
    echo "📚 API Endpoints:"
    echo "  Health Check:   ${SERVICE_URL}/health"
    echo "  Convert Doc:    ${SERVICE_URL}/convert"
    echo ""
    echo "🧪 Test Conversion:"
    echo "  curl -X POST ${SERVICE_URL}/convert \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"doc_url\": \"YOUR_GOOGLE_DOC_URL\", \"company_name\": \"Your Company\"}'"
    echo ""
    echo "📖 Next Steps:"
    echo "  1. Share a Google Doc with 'Anyone with the link can view'"
    echo "  2. Use the /convert endpoint to generate PDFs"
    echo "  3. Monitor logs: gcloud run services logs read google-doc-pdf-converter --region=$REGION"
    echo ""
    echo "💡 Tips:"
    echo "  • Assets (logos) can be uploaded to: gs://$BUCKET_NAME/assets/"
    echo "  • Service account must have access to private Google Docs"
    echo "  • Generated PDFs are stored in: gs://$BUCKET_NAME/generated/"
    echo ""
    print_success "Setup complete! Happy converting! 🚀"
}

#####################################################################
# Main Execution
#####################################################################

main() {
    print_header "Google Doc to PDF Converter - Setup & Deployment"

    echo "This script will:"
    echo "  ✓ Check prerequisites"
    echo "  ✓ Configure Google Cloud project"
    echo "  ✓ Enable required APIs"
    echo "  ✓ Create storage bucket"
    echo "  ✓ Setup service account"
    echo "  ✓ Build and deploy application"
    echo "  ✓ Test deployment"
    echo ""
    read -p "Continue? (y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Setup cancelled"
        exit 0
    fi

    # Run setup steps
    check_prerequisites
    configure_project
    enable_apis
    create_storage_bucket
    setup_service_account
    build_and_deploy
    get_service_url
    test_deployment
    display_summary
}

# Run main function
main "$@"
