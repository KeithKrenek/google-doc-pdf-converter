# Quick Start Guide

Get your Google Doc to PDF converter running in 10 minutes.

## Prerequisites Check

✅ Google Cloud account with billing enabled
✅ Google Cloud CLI installed ([get it here](https://cloud.google.com/sdk/docs/install))
✅ Authenticated: `gcloud auth login`

## One-Command Setup

```bash
./setup.sh
```

That's it! The script handles everything automatically.

## Manual Quick Setup

If you prefer manual control:

### 1. Set Variables

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
gcloud config set project $PROJECT_ID
```

### 2. Enable APIs

```bash
gcloud services enable \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    storage.googleapis.com \
    docs.googleapis.com \
    secretmanager.googleapis.com
```

### 3. Create Bucket

```bash
gsutil mb -l $REGION gs://${PROJECT_ID}-pdf-assets
gsutil iam ch allUsers:objectViewer gs://${PROJECT_ID}-pdf-assets
```

### 4. Store Credentials

```bash
# If you have a service account key file:
gcloud secrets create google-doc-converter-credentials \
    --data-file=service-account-key.json
```

### 5. Deploy

```bash
gcloud builds submit --config cloudbuild.yaml
```

### 6. Get Service URL

```bash
gcloud run services describe google-doc-pdf-converter \
    --region=$REGION \
    --format="value(status.url)"
```

## Test It

```bash
# Replace YOUR_SERVICE_URL with the URL from step 6
curl -X POST https://YOUR_SERVICE_URL/convert \
  -H "Content-Type: application/json" \
  -d '{
    "doc_url": "https://docs.google.com/document/d/YOUR_DOC_ID/edit",
    "company_name": "My Company"
  }'
```

## Prepare Your Google Doc

1. Open your Google Doc
2. Click "Share" → "Anyone with the link can view"
3. Copy the document URL
4. Format your document using:
   - **Heading 1** for main sections
   - **Heading 2** for subsections
   - **Heading 3** for sub-subsections
   - **Bold** and *italic* for emphasis
   - Bullet lists and numbered lists
   - Tables for data

## Add Branding (Optional)

```bash
# Upload your logo images to Cloud Storage
gsutil cp my-cover-image.png gs://${PROJECT_ID}-pdf-assets/assets/stylized-logo.png
gsutil cp my-small-logo.png gs://${PROJECT_ID}-pdf-assets/assets/black-logo.png
```

## Common Issues

### "Permission denied" error

Make sure your Google Doc is shared publicly or with the service account:
```
File → Share → Anyone with the link can view
```

### Can't find service URL

```bash
gcloud run services list --region=$REGION
```

### Service not responding

Check logs:
```bash
gcloud run services logs read google-doc-pdf-converter --region=$REGION
```

## Next Steps

- Read the full [README.md](README.md) for detailed documentation
- Customize PDF styling in `main.py`
- Set up monitoring and alerts
- Add authentication for production use

## Getting Help

- Check logs: `gcloud run services logs read google-doc-pdf-converter`
- View service details: `gcloud run services describe google-doc-pdf-converter`
- Review documentation: [README.md](README.md)

---

**Happy converting! 🚀**
