# Google Doc to PDF Converter

A production-ready application that converts Google Docs to professionally formatted PDFs with custom branding and styling. Built on Google Cloud Run with native Google Docs style detection.

## Features

✅ **Native Google Docs Integration**
- Converts any Google Doc using its URL
- Preserves native formatting (headings, bold, italic, lists)
- Supports tables with professional styling
- No markdown knowledge required

✅ **Professional PDF Generation**
- Custom branded cover page with company name
- Consistent typography and spacing
- Automatic page numbering and footers
- Table formatting with alternating row colors
- Hierarchical heading styles (H1, H2, H3)
- Bullet and numbered lists with proper indentation

✅ **Enterprise-Grade Infrastructure**
- Deployed on Google Cloud Run (serverless, auto-scaling)
- Handles large documents (up to 2GB memory)
- Secure service account authentication
- Automated deployment with Cloud Build
- Health monitoring and logging

✅ **Brand Customization**
- Cover page with company name overlay
- Optional cover images and logos
- Footer branding with logo placement
- Configurable color schemes and fonts

## Quick Start

### Prerequisites

1. **Google Cloud Account** with billing enabled
2. **Google Cloud CLI** installed ([Installation Guide](https://cloud.google.com/sdk/docs/install))
3. **Docker** (optional, for local development)

### Automated Setup (Recommended)

Run the automated setup script:

```bash
chmod +x setup.sh
./setup.sh
```

The script will:
- Configure your Google Cloud project
- Enable required APIs
- Create storage buckets
- Set up service accounts
- Build and deploy the application
- Provide you with the service URL

### Manual Setup

If you prefer manual control:

#### 1. Enable APIs

```bash
gcloud services enable \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    storage.googleapis.com \
    docs.googleapis.com \
    secretmanager.googleapis.com
```

#### 2. Create Storage Bucket

```bash
export PROJECT_ID="your-project-id"
export BUCKET_NAME="${PROJECT_ID}-pdf-assets"
gsutil mb -p $PROJECT_ID gs://$BUCKET_NAME
gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME
```

#### 3. Upload Assets (Optional)

```bash
# Upload logos and cover images
gsutil cp assets/stylized-logo.png gs://$BUCKET_NAME/assets/
gsutil cp assets/black-logo.png gs://$BUCKET_NAME/assets/
```

#### 4. Setup Service Account

```bash
# Create service account
gcloud iam service-accounts create doc-pdf-converter \
    --description="Service account for Google Doc to PDF converter"

# Grant permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:doc-pdf-converter@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/storage.admin"

# Create key
gcloud iam service-accounts keys create service-account-key.json \
    --iam-account=doc-pdf-converter@${PROJECT_ID}.iam.gserviceaccount.com

# Store in Secret Manager
gcloud secrets create google-doc-converter-credentials \
    --data-file=service-account-key.json
```

#### 5. Deploy Application

```bash
gcloud builds submit --config cloudbuild.yaml
```

## Usage

### API Endpoints

#### Health Check
```bash
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "service": "google-doc-pdf-converter",
  "version": "2.0.0"
}
```

#### Convert Document
```bash
POST /convert
Content-Type: application/json

{
  "doc_url": "https://docs.google.com/document/d/YOUR_DOC_ID/edit",
  "company_name": "ACME Corporation",
  "use_cover_image": true
}
```

**Response:**
```json
{
  "success": true,
  "document_title": "Brand Strategy Report",
  "company_name": "ACME Corporation",
  "pdf_filename": "Brand_Strategy_Report_20240115_103000.pdf",
  "download_url": "https://storage.googleapis.com/...",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "elements_processed": 45
}
```

### Example Usage

#### Using cURL

```bash
curl -X POST https://your-service-url/convert \
  -H "Content-Type: application/json" \
  -d '{
    "doc_url": "https://docs.google.com/document/d/1ABC...XYZ/edit",
    "company_name": "My Company"
  }'
```

#### Using JavaScript

```javascript
async function convertDocument(docUrl, companyName) {
  const response = await fetch('https://your-service-url/convert', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      doc_url: docUrl,
      company_name: companyName,
      use_cover_image: true
    })
  });

  const result = await response.json();

  if (result.success) {
    console.log('PDF generated:', result.download_url);
    window.open(result.download_url, '_blank');
  } else {
    console.error('Conversion failed:', result.error);
  }
}
```

#### Using Python

```python
import requests

def convert_google_doc(doc_url, company_name, service_url):
    payload = {
        "doc_url": doc_url,
        "company_name": company_name,
        "use_cover_image": True
    }

    response = requests.post(
        f"{service_url}/convert",
        json=payload
    )

    if response.status_code == 200:
        result = response.json()
        print(f"PDF generated: {result['download_url']}")
        return result['download_url']
    else:
        print(f"Error: {response.json()}")
        return None
```

## Document Formatting Guide

The converter automatically detects and formats Google Doc styles:

### Headings

- **Heading 1**: Large section titles (24pt, bold, primary color)
- **Heading 2**: Subsection headers (18pt, bold, primary color)
- **Heading 3**: Sub-subsection headers (14pt, bold, secondary color)

### Text Formatting

- **Bold text**: Preserved in PDF
- **Italic text**: Preserved in PDF
- **Links**: Blue, underlined, clickable
- Regular paragraphs: Justified, 11pt

### Lists

- **Bullet lists**: Proper indentation with bullet points
- **Numbered lists**: Sequential numbering
- **Nested lists**: Multi-level indentation support

### Tables

- Header row: Grey background, bold text
- Data rows: Alternating white/light grey background
- Borders: Subtle grey lines
- Cell padding: Consistent spacing

## Customization

### Styling Configuration

Edit `STYLE_CONFIG` in `main.py` to customize:

```python
STYLE_CONFIG = {
    'fonts': {
        'title': 'Helvetica-Bold',
        'heading': 'Helvetica-Bold',
        'body': 'Helvetica',
    },
    'sizes': {
        'cover_title': 36,
        'heading1': 24,
        'heading2': 18,
        'body': 11,
    },
    'colors': {
        'primary': HexColor('#2c3e50'),
        'accent': HexColor('#3498db'),
    }
}
```

### Custom Fonts

To add custom fonts:

1. Install TTF fonts in Docker image
2. Update `STYLE_CONFIG['fonts']`
3. Rebuild and redeploy

### Brand Assets

Upload custom images to Cloud Storage:

```bash
# Cover page image (full page, 595x842px recommended)
gsutil cp my-cover.png gs://$BUCKET_NAME/assets/stylized-logo.png

# Footer logo (small, 117x12px recommended)
gsutil cp my-logo.png gs://$BUCKET_NAME/assets/black-logo.png
```

## Local Development

### Setup

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
cp .env.example .env
# Edit .env with your configuration
```

### Run Locally

```bash
# Set credentials
export GOOGLE_APPLICATION_CREDENTIALS=./service-account-key.json
export BUCKET_NAME=your-bucket-name
export PROJECT_ID=your-project-id

# Run application
python main.py
```

The service will be available at `http://localhost:8080`

### Test Locally

```bash
# Health check
curl http://localhost:8080/health

# Convert document
curl -X POST http://localhost:8080/convert \
  -H "Content-Type: application/json" \
  -d '{
    "doc_url": "YOUR_GOOGLE_DOC_URL",
    "company_name": "Test Company"
  }'
```

### Docker Build

```bash
# Build image
docker build -t google-doc-pdf-converter .

# Run container
docker run -p 8080:8080 \
  -e GOOGLE_CREDENTIALS_JSON="$(cat service-account-key.json | base64)" \
  -e BUCKET_NAME=your-bucket-name \
  -e PROJECT_ID=your-project-id \
  google-doc-pdf-converter
```

## Monitoring and Maintenance

### View Logs

```bash
# Cloud Run logs
gcloud run services logs read google-doc-pdf-converter \
  --region=us-central1 \
  --limit=100

# Follow logs in real-time
gcloud run services logs tail google-doc-pdf-converter \
  --region=us-central1
```

### Monitor Performance

```bash
# Service status
gcloud run services describe google-doc-pdf-converter \
  --region=us-central1

# View metrics in Cloud Console
https://console.cloud.google.com/run
```

### Update Deployment

```bash
# After code changes, rebuild and redeploy
gcloud builds submit --config cloudbuild.yaml
```

### Scale Configuration

```bash
# Adjust resources
gcloud run services update google-doc-pdf-converter \
  --region=us-central1 \
  --memory=4Gi \
  --cpu=2 \
  --max-instances=20
```

## Troubleshooting

### Common Issues

#### "Document not found" Error

**Cause**: Document is private or URL is incorrect

**Solution**:
- Share the Google Doc: `File → Share → Anyone with the link can view`
- Verify URL format: `https://docs.google.com/document/d/DOC_ID/edit`

#### "Permission denied" Error

**Cause**: Service account lacks access to Google Docs

**Solution**:
- For private docs: Share with service account email
- Check service account has `docs.reader` role

#### "Upload failed" Error

**Cause**: Storage bucket permissions issue

**Solution**:
```bash
# Grant storage permissions
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:YOUR_SA@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"
```

#### Large Document Timeout

**Cause**: Document processing exceeds timeout

**Solution**:
```bash
# Increase timeout and memory
gcloud run services update google-doc-pdf-converter \
  --region=us-central1 \
  --timeout=900 \
  --memory=4Gi
```

#### Memory Errors

**Cause**: Document too large for allocated memory

**Solution**:
- Increase Cloud Run memory allocation (up to 8GB)
- Split document into smaller parts
- Optimize images in the document

### Debug Mode

Enable detailed logging:

```bash
gcloud run services update google-doc-pdf-converter \
  --region=us-central1 \
  --set-env-vars LOG_LEVEL=DEBUG
```

## Cost Estimation

**Monthly costs for typical usage (1000 conversions):**

- Cloud Run: $5-15 (depends on CPU/memory/time)
- Cloud Storage: $1-3 (storage + data transfer)
- Cloud Build: $0-2 (first 120 min/day free)
- **Total**: ~$6-20/month

**Cost optimization:**
- Cloud Run charges only for actual usage (per-request)
- First 2 million requests/month have free tier
- Storage costs minimal for temporary PDFs
- Set up billing alerts in Cloud Console

## Security Considerations

✅ **Service Account**: Minimal permissions (docs.reader, storage.admin)
✅ **Secret Management**: Credentials stored in Secret Manager
✅ **Non-root Container**: Runs as unprivileged user
✅ **Input Validation**: All inputs sanitized
✅ **HTTPS Only**: Cloud Run enforces TLS
✅ **Rate Limiting**: Configure via Cloud Armor (optional)

**Recommendations for Production:**
- Enable Cloud Armor for DDoS protection
- Implement API key authentication
- Set up VPC Service Controls
- Enable audit logging
- Regular security scanning of container images

## Architecture

```
┌─────────────┐
│   User      │
└──────┬──────┘
       │ POST /convert
       │ {doc_url, company_name}
       ▼
┌─────────────────────────────┐
│   Cloud Run Service         │
│  (google-doc-pdf-converter) │
└──────┬──────────────┬───────┘
       │              │
       │ ┌────────────▼──────────────┐
       │ │  Google Docs API          │
       │ │  (Fetch document content) │
       │ └───────────────────────────┘
       │
       │ ┌────────────────────────────┐
       │ │  ReportLab PDF Generator   │
       │ │  (Format & style document) │
       │ └───────────────────────────┘
       │
       ▼
┌───────────────────────┐
│  Cloud Storage        │
│  (Store generated PDF)│
└───────────────────────┘
       │
       │ Public URL
       ▼
┌─────────────┐
│   User      │
│  (Download) │
└─────────────┘
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Submit a pull request

## License

This project is licensed under the CC0 1.0 Universal License - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Cloud Errors**: Check Cloud Run logs
- **API Errors**: Verify Google Docs API quotas

---

**Ready to get started?**

Run `./setup.sh` and you'll have a fully functional Google Doc to PDF converter in minutes! 🚀
