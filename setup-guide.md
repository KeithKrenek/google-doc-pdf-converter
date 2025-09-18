# Complete Setup Guide

## Quick Start (5 minutes)

1. **Clone this repository** and navigate to it
2. **Set your project ID** in `deploy.sh` (line 8)
3. **Run the deployment script**:
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```
4. **Access your converter** at the provided frontend URL
5. **Test with a public Google Doc**

## Detailed Setup Instructions

### Prerequisites

1. **Google Cloud Account** with billing enabled
2. **Google Cloud CLI** installed and authenticated
3. **Node.js 18+** installed locally (for development)

### Step-by-Step Setup

#### 1. Project Configuration

Create a new Google Cloud project or use an existing one:
```bash
gcloud projects create your-project-id --name="Doc to PDF Converter"
gcloud config set project your-project-id
gcloud auth application-default login
```

#### 2. Service Account Setup

The deployment script uses your provided service account. To use a different one:

```bash
# Create a new service account
gcloud iam service-accounts create pdf-converter \
  --display-name="PDF Converter Service Account"

# Grant necessary permissions
gcloud projects add-iam-policy-binding your-project-id \
  --member="serviceAccount:pdf-converter@your-project-id.iam.gserviceaccount.com" \
  --role="roles/docs.reader"

# Create and download key
gcloud iam service-accounts keys create service-account-key.json \
  --iam-account=pdf-converter@your-project-id.iam.gserviceaccount.com
```

Then update the credentials object in `backend/index.js`.

#### 3. Font and Asset Preparation

##### Fonts
Convert your TTF fonts to base64:

```bash
cd backend/fonts
node -e "
const fs = require('fs');
const font = fs.readFileSync('CaslonGrad-Regular.ttf');
const base64 = font.toString('base64');
fs.writeFileSync('CaslonGrad-Regular.js', 'module.exports = `' + base64 + '`;');
console.log('✅ CaslonGrad-Regular.js created');
"
```

Repeat for IbarraRealNova-Bold.ttf.

##### Assets
Place these PNG files in the `assets/` directory:
- `stylized-logo.png` - Full-page cover logo (595x842px recommended)
- `black-logo.png` - Small footer logo (117x12px recommended)  
- `page-2.png` - Second page background (595x842px)

#### 4. Custom Deployment

For advanced users who want to modify the deployment:

```bash
# Deploy only the backend
./deploy.sh backend-only

# Deploy only the frontend
./deploy.sh frontend-only

# Clean up everything
./deploy.sh clean
```

### Environment Variables

The following can be configured in `backend/index.js`:

```javascript
const CONFIG = {
  // Font settings
  DEFAULT_FONT_SIZE: 12,
  TITLE_FONT_SIZE: 32,
  SUBTITLE_FONT_SIZE: 22,
  
  // Layout settings
  PAGE_MARGIN: 50,
  HEADER_HEIGHT: 80,
  FOOTER_HEIGHT: 80,
  
  // PDF settings
  MAX_FILE_SIZE: '10MB',
  TIMEOUT_SECONDS: 300
};
```

## API Documentation

### Cloud Function Endpoint

**URL:** `https://your-region-your-project.cloudfunctions.net/convertDocToPdf`
**Method:** POST
**Content-Type:** application/json

#### Request Body:
```json
{
  "docUrl": "https://docs.google.com/document/d/YOUR_DOC_ID/edit",
  "brandName": "Optional Brand Name"
}
```

#### Response:
- **Success:** PDF file download (application/pdf)
- **Error:** JSON with error message

#### Example with curl:
```bash
curl -X POST \
  https://your-region-your-project.cloudfunctions.net/convertDocToPdf \
  -H "Content-Type: application/json" \
  -d '{
    "docUrl": "https://docs.google.com/document/d/1fkbnE4pVltFB-8W6bSdDCs1h1fk1e4WNph3CFYmkghw/edit",
    "brandName": "My Company"
  }' \
  --output converted.pdf
```

## Troubleshooting

### Common Issues

#### 1. "Document not found" Error
**Cause:** Document is private or URL is incorrect
**Solution:**
- Share the Google Doc: File → Share → "Anyone with the link can view"
- Verify the URL format matches: `https://docs.google.com/document/d/.../edit`

#### 2. "Access denied" Error
**Cause:** Service account lacks permissions
**Solution:**
```bash
# Grant additional permissions
gcloud projects add-iam-policy-binding your-project-id \
  --member="serviceAccount:your-service-account@your-project-id.iam.gserviceaccount.com" \
  --role="roles/docs.reader"
```

#### 3. Function Timeout
**Cause:** Large documents or slow processing
**Solution:**
- Increase timeout: `--timeout 540s` (max 9 minutes for HTTP functions)
- Reduce document size or complexity
- Check Cloud Function logs

#### 4. Font Loading Issues
**Cause:** Font files not properly encoded or missing
**Solution:**
- Verify font files exist in `backend/fonts/`
- Check base64 encoding is valid
- Use the font conversion script provided

#### 5. Memory Errors
**Cause:** Large documents exceed memory limits
**Solution:**
```bash
# Increase memory allocation
gcloud functions deploy convertDocToPdf \
  --memory 1GB \
  --timeout 300s
```

#### 6. CORS Issues
**Cause:** Frontend and backend on different domains
**Solution:** The function includes CORS headers, but if issues persist:
```javascript
// Add to Cloud Function
res.set('Access-Control-Allow-Origin', 'https://your-frontend-domain.com');
```

### Debug Steps

#### 1. Check Cloud Function Logs
```bash
gcloud functions logs read convertDocToPdf --region=your-region --limit=50
```

#### 2. Test Document Access
```bash
# Test if document is publicly accessible
curl -I "https://docs.google.com/document/d/YOUR_DOC_ID/export?format=txt"
```

#### 3. Validate Service Account
```bash
# Test authentication
gcloud auth activate-service-account --key-file=service-account-key.json
gcloud auth list
```

#### 4. Monitor Resource Usage
- Open Cloud Console → Cloud Functions → convertDocToPdf → Metrics
- Check memory usage, execution time, and error rates

### Performance Optimization

1. **Caching:** Implement Redis for frequent conversions
2. **Streaming:** Process large documents in chunks
3. **Compression:** Enable gzip compression for responses
4. **CDN:** Use Cloud CDN for static assets

### Security Best Practices

1. **API Authentication:** Add API keys for production
2. **Rate Limiting:** Implement request throttling
3. **Input Validation:** Sanitize all inputs
4. **Monitoring:** Set up alerts for unusual activity

## Cost Estimation

### Monthly costs for moderate usage (500 conversions):
- **Cloud Functions:** ~$2.50
- **Cloud Storage:** ~$0.50
- **API Calls:** ~$0.10
- **Data Transfer:** ~$0.50
- **Total:** ~$3.60/month

### Cost optimization tips:
- Use Cloud Scheduler to manage function warm-up
- Implement caching to reduce duplicate processing
- Set up billing alerts

## Support and Maintenance

### Regular Maintenance Tasks:
1. **Update Dependencies:** Monthly security updates
2. **Monitor Logs:** Weekly error log review
3. **Performance Review:** Monthly metrics analysis
4. **Backup Configuration:** Quarterly config backup

### Getting Help:
1. **Cloud Function Issues:** Check Google Cloud Status page
2. **Google Docs API:** Review API quotas and limits
3. **PDF Generation:** Test with minimal documents first
4. **General Issues:** Check Cloud Function logs for detailed errors

## Extending the System

### Add New Features:
1. **Multiple Output Formats:** Add Word, HTML export
2. **Batch Processing:** Convert multiple documents
3. **Template Selection:** Multiple PDF templates
4. **Integration:** Webhooks, Slack bots, etc.

### Custom Styling:
1. **Modify CSS:** Update frontend styles
2. **PDF Layout:** Adjust margins, fonts in `pdfGenerator.js`
3. **Branding:** Replace logos and colors
4. **Templates:** Create multiple PDF templates

This setup provides a robust, scalable solution for converting Google Docs to professionally formatted PDFs with minimal user technical knowledge required.