#!/bin/bash

# Google Doc to PDF Converter - Deployment Script
# This script sets up and deploys the complete workflow

set -e  # Exit on any error

# Configuration
PROJECT_ID="brand-strategy-report-pdf"
REGION="us-central1"
BUCKET_NAME="${PROJECT_ID}-converter"
FUNCTION_NAME="convertDocToPdf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "Google Cloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        print_error "Please authenticate with Google Cloud: gcloud auth login"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        print_error "gsutil is not available. Please ensure Google Cloud CLI is properly installed."
        exit 1
    fi
    
    print_success "Prerequisites check passed!"
}

setup_project() {
    print_status "Setting up Google Cloud project..."
    
    # Set the project
    gcloud config set project $PROJECT_ID
    
    # Enable required APIs
    print_status "Enabling required APIs..."
    gcloud services enable cloudfunctions.googleapis.com
    gcloud services enable docs.googleapis.com
    gcloud services enable storage.googleapis.com
    gcloud services enable cloudbuild.googleapis.com
    
    print_success "APIs enabled successfully!"
}

create_bucket() {
    print_status "Creating Cloud Storage bucket for frontend..."
    
    # Create bucket if it doesn't exist
    if gsutil ls -b gs://$BUCKET_NAME &> /dev/null; then
        print_warning "Bucket $BUCKET_NAME already exists, skipping creation."
    else
        gsutil mb -l $REGION gs://$BUCKET_NAME
        
        # Make bucket public for web hosting
        gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME
        
        # Set up web configuration
        gsutil web set -m index.html -e index.html gs://$BUCKET_NAME
        
        print_success "Bucket created and configured for web hosting!"
    fi
}

deploy_backend() {
    print_status "Deploying Cloud Function..."
    
    # Navigate to backend directory
    cd backend
    
    # Install dependencies
    npm install
    
    # Deploy the function
    gcloud functions deploy $FUNCTION_NAME \
        --runtime nodejs18 \
        --trigger-http \
        --allow-unauthenticated \
        --memory 512MB \
        --timeout 300s \
        --region $REGION \
        --source . \
        --entry-point $FUNCTION_NAME
    
    # Get the function URL
    FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --format="value(httpsTrigger.url)")
    
    cd ..
    
    print_success "Cloud Function deployed successfully!"
    print_status "Function URL: $FUNCTION_URL"
    
    # Update frontend with function URL
    update_frontend_url $FUNCTION_URL
}

update_frontend_url() {
    local function_url=$1
    print_status "Updating frontend with Cloud Function URL..."
    
    # Update the CLOUD_FUNCTION_URL in the HTML file
    sed -i.bak "s|const CLOUD_FUNCTION_URL = '.*';|const CLOUD_FUNCTION_URL = '$function_url';|" frontend/index.html
    
    print_success "Frontend updated with function URL!"
}

deploy_frontend() {
    print_status "Deploying frontend to Cloud Storage..."
    
    # Upload frontend files
    gsutil -m cp -r frontend/* gs://$BUCKET_NAME/
    
    # Set proper MIME types
    gsutil -m setmeta -h "Content-Type:text/html" gs://$BUCKET_NAME/*.html
    gsutil -m setmeta -h "Content-Type:text/css" gs://$BUCKET_NAME/*.css
    gsutil -m setmeta -h "Content-Type:application/javascript" gs://$BUCKET_NAME/*.js
    
    FRONTEND_URL="https://storage.googleapis.com/$BUCKET_NAME/index.html"
    
    print_success "Frontend deployed successfully!"
    print_status "Frontend URL: $FRONTEND_URL"
}

verify_fonts_and_assets() {
    print_status "Verifying fonts and assets..."
    
    # Check if font files exist
    if [ ! -f "backend/fonts/CaslonGrad-Regular.js" ] || [ ! -f "backend/fonts/IbarraRealNova-Bold.js" ]; then
        print_warning "Font files not found. Please convert your TTF fonts to base64 and place them in backend/fonts/"
        print_warning "See the font template files for guidance."
    fi
    
    # Check if asset images exist
    if [ ! -f "assets/stylized-logo.png" ] || [ ! -f "assets/black-logo.png" ] || [ ! -f "assets/page-2.png" ]; then
        print_warning "Asset images not found. Please place your images in the assets/ directory:"
        print_warning "- stylized-logo.png (cover page logo)"
        print_warning "- black-logo.png (footer logo)"
        print_warning "- page-2.png (second page background)"
    fi
}

setup_service_account_permissions() {
    print_status "Setting up service account permissions..."
    
    # Get the Cloud Function's service account
    SERVICE_ACCOUNT=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")-compute@developer.gserviceaccount.com
    
    # Grant necessary permissions
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SERVICE_ACCOUNT" \
        --role="roles/storage.objectViewer"
    
    print_success "Service account permissions configured!"
}

run_tests() {
    print_status "Running basic tests..."
    
    # Test the Cloud Function URL
    FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --format="value(httpsTrigger.url)")
    
    # Basic connectivity test
    if curl -s -o /dev/null -w "%{http_code}" "$FUNCTION_URL" | grep -q "405\|400"; then
        print_success "Cloud Function is accessible!"
    else
        print_warning "Cloud Function might not be responding correctly. Check the deployment."
    fi
}

display_summary() {
    print_success "🎉 Deployment completed successfully!"
    echo ""
    echo "📋 Summary:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Cloud Function: $FUNCTION_NAME"
    echo "  Storage Bucket: $BUCKET_NAME"
    echo ""
    echo "🔗 URLs:"
    
    FUNCTION_URL=$(gcloud functions describe $FUNCTION_NAME --region=$REGION --format="value(httpsTrigger.url)" 2>/dev/null || echo "Unable to retrieve")
    FRONTEND_URL="https://storage.googleapis.com/$BUCKET_NAME/index.html"
    
    echo "  Frontend: $FRONTEND_URL"
    echo "  Backend: $FUNCTION_URL"
    echo ""
    echo "🛠️  Next steps:"
    echo "  1. Add your font files to backend/fonts/ and redeploy if needed"
    echo "  2. Add your logo images to assets/ and redeploy if needed"
    echo "  3. Test the conversion with a sample Google Doc"
    echo "  4. Monitor Cloud Function logs: gcloud functions logs read $FUNCTION_NAME --region=$REGION"
    echo ""
    print_status "Happy converting! 🚀"
}

# Main execution
main() {
    print_status "Starting Google Doc to PDF Converter deployment..."
    
    # Prompt for project ID if not set
    if [ "$PROJECT_ID" = "your-project-id" ]; then
        read -p "Enter your Google Cloud Project ID: " PROJECT_ID
        if [ -z "$PROJECT_ID" ]; then
            print_error "Project ID is required!"
            exit 1
        fi
        BUCKET_NAME="${PROJECT_ID}-pdf-converter"
    fi
    
    check_prerequisites
    setup_project
    verify_fonts_and_assets
    create_bucket
    deploy_backend
    deploy_frontend
    setup_service_account_permissions
    run_tests
    display_summary
}

# Run with command line arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "backend-only")
        setup_project
        deploy_backend
        print_success "Backend deployment completed!"
        ;;
    "frontend-only")
        create_bucket
        deploy_frontend
        print_success "Frontend deployment completed!"
        ;;
    "test")
        run_tests
        ;;
    "clean")
        print_status "Cleaning up resources..."
        gcloud functions delete $FUNCTION_NAME --region=$REGION --quiet || true
        gsutil -m rm -r gs://$BUCKET_NAME || true
        print_success "Cleanup completed!"
        ;;
    *)
        echo "Usage: $0 [deploy|backend-only|frontend-only|test|clean]"
        echo "  deploy:       Full deployment (default)"
        echo "  backend-only: Deploy only the Cloud Function"
        echo "  frontend-only: Deploy only the frontend"
        echo "  test:         Test the deployment"
        echo "  clean:        Remove all deployed resources"
        exit 1
        ;;
esac