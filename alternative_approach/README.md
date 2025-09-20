# Google Doc to PDF Converter

A production-ready workflow that converts Google Docs to professionally formatted PDFs with custom branding and styling. Built for users with minimal programming experience, this solution provides a robust, scalable, and user-friendly API.

## Features

- ✅ **Google Docs Integration**: Direct conversion from Google Doc URLs
- ✅ **Professional Formatting**: Custom styling similar to high-quality business documents
- ✅ **Custom Branding**: Add custom titles, subtitles, and brand names
- ✅ **Scalable Infrastructure**: Built on Google Cloud Run with auto-scaling
- ✅ **Large File Support**: Handles large PDFs with optimized memory management
- ✅ **Robust Error Handling**: Comprehensive logging and error management
- ✅ **Security**: Service account-based authentication with minimal permissions

## Architecture

```
User Request → Cloud Run → Google Docs API → PDF Generation → Cloud Storage → Response
```

### Key Components
- **Google Cloud Run**: Serverless container platform for the main application
- **Google Docs API**: For accessing and reading Google Documents
- **WeasyPrint**: HTML to PDF conversion with professional styling
- **Cloud Storage**: Asset storage and generated PDF hosting
- **Cloud Build**: Automated CI/CD pipeline

## Quick Start

### Prerequisites

1. **Google Cloud Account** with billing enabled
2. **Google Cloud SDK** installed and configured
3. **Docker** (optional, for local development)
4. **curl** for testing

### One-Click Setup

1. **Clone and navigate to the project:**
   ```bash
   git clone <repository-url>
   cd google-doc-to-pdf-converter
   ```

2. **Run the setup script:**
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

3. **Follow the prompts** to configure your project settings.

The setup script will:
- Enable required Google Cloud APIs
- Create storage buckets
- Set up service accounts and permissions  
- Build and deploy the application
- Provide you with the service URL

### Manual Setup (Alternative)

If you prefer manual setup or need to customize the deployment:

#### 1. Enable APIs
```bash
gcloud services enable cloudbuild.googleapis.com run.googleapis.com storage.googleapis.com docs.googleapis.com
```

#### 2. Create Storage Bucket
```bash
export PROJECT_ID="your-project-id"
export BUCKET_NAME="${PROJECT_ID}-pdf-assets"
gsutil mb -p $PROJECT_ID gs://$BUCKET_NAME
gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME
```

#### 3. Create Service Account
```bash
gcloud iam service-accounts create doc-pdf-converter \
    --description="Service account for Google Doc to PDF converter" \
    --display-name="Doc to PDF Converter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:doc-pdf-converter@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/storage.admin"

gcloud iam service-accounts keys create service-account-key.json \
    --iam-account=doc-pdf-converter@${PROJECT_ID}.iam.gserviceaccount.com
```

#### 4. Deploy Application
```bash
gcloud builds submit --config cloudbuild.yaml \
    --substitutions=_REGION=us-central1,_BUCKET_NAME=$BUCKET_NAME
```

## Usage

### API Endpoints

#### Convert Document
```bash
POST /convert
Content-Type: application/json

{
  "doc_url": "https://docs.google.com/document/d/YOUR_DOC_ID/edit",
  "custom_input": "Your Brand Name"
}
```

**Response:**
```json
{
  "success": true,
  "document_title": "Your Document Title",
  "pdf_filename": "document_12345_20240101_120000.pdf",
  "download_url": "https://storage.googleapis.com/...",
  "timestamp": "2024-01-01T12:00:00.000Z"
}
```

#### Health Check
```bash
GET /health
```

### Example Usage

#### Basic Conversion
```bash
curl -X POST https://your-service-url/convert \
  -H "Content-Type: application/json" \
  -d '{
    "doc_url": "https://docs.google.com/document/d/1zByXFPhVznKanor06iRs5qLh5Mi7A7Ok_0Ph9eps-yA/edit",
    "custom_input": "ACME Corporation"
  }'
```

#### Using with JavaScript
```javascript
const convertDocument = async (docUrl, brandName) => {
  const response = await fetch('https://your-service-url/convert', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      doc_url: docUrl,
      custom_input: brandName
    })
  });
  
  const result = await response.json();
  
  if (result.success) {
    console.log('PDF generated:', result.download_url);
    return result.download_url;
  } else {
    throw new Error(result.error);
  }
};

// Usage
convertDocument(
  'https://docs.google.com/document/d/YOUR_DOC_ID/edit',
  'Your Company Name'
).then(url => {
  console.log('Download PDF:', url);
}).catch(error => {
  console.error('Conversion failed:', error);
});
```

#### Python Example
```python
import requests
import json

def convert_google_doc(doc_url, brand_name, service_url):
    payload = {
        "doc_url": doc_url,
        "custom_input": brand_name
    }
    
    response = requests.post(
        f"{service_url}/convert",
        json=payload,
        headers={"Content-Type": "application/json"}
    )
    
    if response.status_code == 200:
        result = response.json()
        if result["success"]:
            print(f"PDF generated: {result['download_url']}")
            return result["download_url"]
        else:
            print(f"Error: {result['error']}")
    else:
        print(f"HTTP Error: {response.status_code}")
    
    return None

# Usage
pdf_url = convert_google_doc(
    "https://docs.google.com/document/d/YOUR_DOC_ID/edit",
    "Your Company Name",
    "https://your-service-url"
)
```

## Customization

### PDF Styling

The PDF styling is controlled by the HTML/CSS template in `main.py`. Key customization areas:

1. **Colors and Fonts**: Modify the CSS variables in the template
2. **Layout**: Adjust page margins, spacing, and structure
3. **Cover Page**: Customize the cover page design and graphics
4. **Branding**: Add logos and brand elements

### Custom Assets

Upload custom assets to your storage bucket:

```bash
# Upload logo
gsutil cp your-logo.png gs://$BUCKET_NAME/assets/

# Upload cover images
gsutil cp cover-image.jpg gs://$BUCKET_NAME/assets/
```

Update the template code to reference your custom assets.

### Environment Variables

Key configuration options:

| Variable | Description | Default |
|----------|-------------|---------|
| `BUCKET_NAME` | Google Cloud Storage bucket name | `{PROJECT_ID}-pdf-assets` |
| `GOOGLE_CREDENTIALS_JSON` | Base64-encoded service account key | Required |
| `PORT` | Application port | `8080` |

## Monitoring and Logging

### View Logs
```bash
gcloud logs tail doc-to-pdf-converter --region=us-central1
```

### Monitor Performance
```bash
gcloud run services describe doc-to-pdf-converter --region=us-central1
```

### Check Service Status
```bash
curl https://your-service-url/health
```

## Troubleshooting

### Common Issues

#### "Permission Denied" Errors
- Verify service account has correct permissions
- Check that the Google Doc is publicly accessible or shared with the service account

#### "Document Not Found" Errors  
- Verify the Google Doc URL format
- Ensure the document exists and is accessible
- Check that the Google Docs API is enabled

#### PDF Generation Fails
- Check Cloud Run logs for detailed error messages
- Verify WeasyPrint dependencies are installed correctly
- Monitor memory usage (increase if needed)

#### Large File Issues
- Increase Cloud Run memory allocation:
  ```bash
  gcloud run services update doc-to-pdf-converter \
    --memory 4Gi --region us-central1
  ```

### Debug Mode

Enable debug logging by setting environment variable:
```bash
gcloud run services update doc-to-pdf-converter \
  --set-env-vars LOG_LEVEL=DEBUG --region us-central1
```

## Security Considerations

1. **Service Account Permissions**: Uses minimal required permissions
2. **Public Access**: PDFs are temporarily made public for download
3. **Input Validation**: All inputs are validated and sanitized
4. **Rate Limiting**: Consider implementing rate limiting for production use

## Performance Optimization

### For High Volume Usage

1. **Increase Resources**:
   ```bash
   gcloud run services update doc-to-pdf-converter \
     --memory 2Gi --cpu 2 --max-instances 20
   ```

2. **Enable Request Concurrency**:
   ```bash
   gcloud run services update doc-to-pdf-converter \
     --concurrency 10
   ```

3. **Implement Caching**: Add Redis for caching frequent conversions

## Development

### Local Development
1. Set up environment:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Run locally:
   ```bash
   python main.py
   ```

### Testing
```bash
# Test health endpoint
curl http://localhost:8080/health

# Test conversion
curl -X POST http://localhost:8080/convert \
  -H "Content-Type: application/json" \
  -d '{"doc_url": "YOUR_DOC_URL", "custom_input": "Test Brand"}'
```

## Cost Estimation

**Monthly costs for moderate usage (100 conversions/day):**
- Cloud Run: ~$5-15
- Cloud Storage: ~$1-5
- Cloud Build: ~$1-2
- **Total: ~$7-22/month**

Costs scale with usage. Monitor using Google Cloud Console.

## Support

### Getting Help
1. Check the troubleshooting section above
2. Review Google Cloud Run documentation
3. Check service logs for detailed error messages

### Contributing
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License. See LICENSE file for details.

---

**Ready to get started?** Run `./setup.sh` and you'll have a fully functional Google Doc to PDF converter in minutes!