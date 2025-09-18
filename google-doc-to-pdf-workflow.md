# Google Doc to PDF Conversion Workflow

## Architecture Overview

This solution creates a serverless workflow using Google Cloud services to convert Google Docs into professional PDFs with custom formatting.

### Components:
1. **Web Interface** - Simple form for users to input Google Doc URLs
2. **Cloud Function** - Backend processing and PDF generation
3. **Google Docs API** - Document content extraction
4. **Custom PDF Generator** - Formatted output matching your existing style

## Required Google Cloud APIs

Before deployment, enable these APIs in your Google Cloud Console:
- Google Docs API
- Cloud Functions API
- Cloud Storage API
- Cloud Build API

## Setup Instructions

### 1. Project Structure
```
google-doc-pdf-converter/
├── frontend/
│   ├── index.html
│   ├── style.css
│   └── script.js
├── backend/
│   ├── package.json
│   ├── index.js
│   ├── pdfGenerator.js
│   └── fonts/
│       ├── CaslonGrad-Regular.js
│       └── IbarraRealNova-Bold.js
├── assets/
│   ├── stylized-logo.png
│   ├── black-logo.png
│   └── page-2.png
└── deploy.sh
```

### 2. Deployment Steps

1. **Clone and setup the project:**
```bash
git clone <your-repo>
cd google-doc-pdf-converter
```

2. **Deploy Cloud Function:**
```bash
cd backend
npm install
gcloud functions deploy convertDocToPdf \
  --runtime nodejs18 \
  --trigger-http \
  --allow-unauthenticated \
  --memory 512MB \
  --timeout 300s
```

3. **Deploy Frontend to Cloud Storage:**
```bash
cd ../frontend
gsutil mb gs://your-bucket-name-pdf-converter
gsutil cp -r * gs://your-bucket-name-pdf-converter/
gsutil web set -m index.html gs://your-bucket-name-pdf-converter
```

### 3. Configuration

Update the service account credentials in your Cloud Function environment variables or use Google Cloud's default service account with appropriate permissions.

## Usage

1. **Access the web interface** at your Cloud Storage bucket's public URL
2. **Paste the Google Doc URL** in the input field
3. **Click "Convert to PDF"** - the system will:
   - Extract content from the Google Doc
   - Process formatting and structure
   - Generate a professional PDF
   - Provide download link

## Features

### Document Processing
- ✅ Extracts text, headings, and basic formatting from Google Docs
- ✅ Preserves document structure (headings, paragraphs, lists)
- ✅ Handles tables and bullet points
- ✅ Processes inline formatting (bold, italic)

### PDF Generation
- ✅ Custom fonts matching your existing design
- ✅ Professional layout with logos and branding
- ✅ Automatic page breaks and spacing
- ✅ Table formatting with proper alignment
- ✅ Consistent header/footer styling

### User Experience
- ✅ Simple web interface
- ✅ Real-time progress feedback
- ✅ Error handling and user messages
- ✅ Direct PDF download

## Customization

### Fonts and Styling
Modify `pdfGenerator.js` to adjust:
- Font families and sizes
- Color schemes
- Spacing and margins
- Logo placement

### Document Processing
Update the content processing logic to handle:
- Custom Google Doc formatting
- Specific heading structures
- Table layouts
- Image extraction (requires additional setup)

## Security Considerations

- The workflow uses your service account credentials
- Consider implementing authentication for production use
- Validate and sanitize input URLs
- Set up proper CORS policies

## Cost Estimation

For moderate usage (100 conversions/month):
- Cloud Functions: ~$0.50/month
- Cloud Storage: ~$0.10/month
- API calls: Minimal cost

## Troubleshooting

### Common Issues:
1. **403 Forbidden**: Check document sharing permissions
2. **Font loading errors**: Verify font files are properly encoded
3. **Memory limits**: Increase Cloud Function memory for large documents
4. **Timeout errors**: Increase function timeout for complex documents

### Debug Steps:
1. Check Cloud Function logs in Google Cloud Console
2. Verify Google Doc is publicly accessible or shared with service account
3. Test with simple documents first
4. Monitor API quotas and limits

## Support

For issues:
1. Check Cloud Function logs for detailed error messages
2. Verify all required APIs are enabled
3. Ensure service account has proper permissions
4. Test with different document types and sizes