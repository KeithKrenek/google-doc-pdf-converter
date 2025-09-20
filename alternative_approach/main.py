from flask import Flask, request, jsonify, send_file
from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build
from google.cloud import storage
import os
import json
import tempfile
import logging
from datetime import datetime
from urllib.parse import urlparse, parse_qs

# Import ReportLab for PDF generation
try:
    from reportlab.lib.pagesizes import A4
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import inch
    from reportlab.lib.colors import HexColor, black, white
    from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY
    from reportlab.pdfgen import canvas
    PDF_LIBRARY = "reportlab"
except ImportError:
    PDF_LIBRARY = "none"

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
SCOPES = ['https://www.googleapis.com/auth/documents.readonly']
BUCKET_NAME = os.environ.get('BUCKET_NAME', 'your-pdf-assets-bucket')

class GoogleDocToPDFConverter:
    def __init__(self):
        self.setup_google_services()
        self.storage_client = storage.Client()
        
    def setup_google_services(self):
        """Initialize Google API services"""
        try:
            credentials_json = os.environ.get('GOOGLE_CREDENTIALS_JSON')
            if credentials_json:
                credentials_info = json.loads(credentials_json)
                credentials = Credentials.from_service_account_info(
                    credentials_info, scopes=SCOPES
                )
            else:
                credentials = None
                
            self.docs_service = build('docs', 'v1', credentials=credentials)
            logger.info("Google Docs service initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize Google services: {e}")
            raise
    
    def extract_document_id(self, doc_url):
        """Extract document ID from Google Docs URL"""
        try:
            if '/document/d/' in doc_url:
                doc_id = doc_url.split('/document/d/')[1].split('/')[0]
            else:
                parsed = urlparse(doc_url)
                if 'id' in parse_qs(parsed.query):
                    doc_id = parse_qs(parsed.query)['id'][0]
                else:
                    raise ValueError("Cannot extract document ID from URL")
            
            logger.info(f"Extracted document ID: {doc_id}")
            return doc_id
        except Exception as e:
            logger.error(f"Error extracting document ID: {e}")
            raise ValueError(f"Invalid Google Docs URL: {e}")
    
    def get_document_content(self, document_id):
        """Retrieve document content from Google Docs API"""
        try:
            document = self.docs_service.documents().get(documentId=document_id).execute()
            logger.info(f"Retrieved document: {document.get('title', 'Untitled')}")
            return document
        except Exception as e:
            logger.error(f"Error retrieving document: {e}")
            raise ValueError(f"Failed to retrieve document: {e}")
    
    def extract_text_and_structure(self, document):
        """Extract text content and structure from document"""
        content = document.get('body', {}).get('content', [])
        extracted_data = {
            'title': document.get('title', 'Untitled Document'),
            'sections': []
        }
        
        for element in content:
            if 'paragraph' in element:
                paragraph = element['paragraph']
                text_content = ''
                style = 'normal'
                
                for text_element in paragraph.get('elements', []):
                    if 'textRun' in text_element:
                        text_run = text_element['textRun']
                        text_content += text_run.get('content', '')
                        
                        text_style = text_run.get('textStyle', {})
                        if text_style.get('bold', False):
                            if text_style.get('fontSize', {}).get('magnitude', 0) > 14:
                                style = 'heading'
                            else:
                                style = 'bold'
                
                text_content = text_content.strip()
                if text_content:
                    extracted_data['sections'].append({
                        'type': 'paragraph',
                        'content': text_content,
                        'style': style
                    })
        
        return extracted_data
    
    def create_pdf_with_reportlab(self, document_data, custom_input=None):
        """Create PDF using ReportLab"""
        if PDF_LIBRARY != "reportlab":
            raise ValueError("ReportLab not available")
            
        try:
            # Create temporary file
            temp_pdf = tempfile.NamedTemporaryFile(suffix='.pdf', delete=False)
            temp_pdf.close()
            
            # Create PDF document
            doc = SimpleDocTemplate(temp_pdf.name, pagesize=A4)
            styles = getSampleStyleSheet()
            
            # Custom styles
            title_style = ParagraphStyle(
                'CustomTitle',
                parent=styles['Heading1'],
                fontSize=28,
                spaceAfter=30,
                alignment=TA_CENTER,
                textColor=HexColor('#000000')
            )
            
            subtitle_style = ParagraphStyle(
                'CustomSubtitle',
                parent=styles['Heading2'],
                fontSize=16,
                spaceAfter=20,
                alignment=TA_CENTER,
                textColor=HexColor('#666666')
            )
            
            heading_style = ParagraphStyle(
                'CustomHeading',
                parent=styles['Heading2'],
                fontSize=14,
                spaceAfter=12,
                textColor=HexColor('#2c3e50')
            )
            
            content_style = ParagraphStyle(
                'CustomContent',
                parent=styles['Normal'],
                fontSize=11,
                spaceAfter=12,
                alignment=TA_JUSTIFY
            )
            
            # Build document
            story = []
            
            # Cover page
            title = self.extract_main_title(document_data)
            subtitle = self.extract_subtitle(document_data, custom_input)
            brand = custom_input if custom_input else "PROFESSIONAL BRAND"
            
            story.append(Spacer(1, 2*inch))
            story.append(Paragraph(title, title_style))
            story.append(Spacer(1, 0.5*inch))
            story.append(Paragraph(subtitle, subtitle_style))
            story.append(Spacer(1, 1*inch))
            story.append(Paragraph(brand, subtitle_style))
            story.append(PageBreak())
            
            # Content
            for section in document_data['sections']:
                if section['style'] == 'heading':
                    story.append(Paragraph(section['content'], heading_style))
                elif section['style'] == 'bold':
                    bold_style = ParagraphStyle('Bold', parent=content_style, fontName='Helvetica-Bold')
                    story.append(Paragraph(section['content'], bold_style))
                else:
                    story.append(Paragraph(section['content'], content_style))
                story.append(Spacer(1, 12))
            
            # Build PDF
            doc.build(story)
            logger.info(f"PDF created successfully: {temp_pdf.name}")
            return temp_pdf.name
            
        except Exception as e:
            logger.error(f"ReportLab PDF creation failed: {e}")
            raise
    
    def create_simple_pdf(self, document_data, custom_input=None):
        """Create simple PDF as fallback"""
        try:
            temp_pdf = tempfile.NamedTemporaryFile(suffix='.pdf', delete=False)
            temp_pdf.close()
            
            c = canvas.Canvas(temp_pdf.name, pagesize=A4)
            width, height = A4
            
            # Title page
            title = self.extract_main_title(document_data)
            subtitle = self.extract_subtitle(document_data, custom_input)
            brand = custom_input if custom_input else "PROFESSIONAL BRAND"
            
            c.setFont("Helvetica-Bold", 20)
            c.drawCentredText(width/2, height-150, title[:50])  # Limit title length
            
            c.setFont("Helvetica", 14)
            c.drawCentredText(width/2, height-200, subtitle[:60])  # Limit subtitle length
            
            c.setFont("Helvetica-Bold", 16)
            c.drawCentredText(width/2, height-300, brand[:40])  # Limit brand length
            
            c.showPage()
            
            # Content
            y_position = height - 80
            c.setFont("Helvetica", 11)
            
            for section in document_data['sections']:
                if y_position < 80:
                    c.showPage()
                    y_position = height - 80
                
                if section['style'] == 'heading':
                    c.setFont("Helvetica-Bold", 13)
                else:
                    c.setFont("Helvetica", 11)
                
                # Simple text handling
                text = section['content'][:100]  # Limit text length
                c.drawString(50, y_position, text)
                y_position -= 25
            
            c.save()
            logger.info(f"Simple PDF created: {temp_pdf.name}")
            return temp_pdf.name
            
        except Exception as e:
            logger.error(f"Simple PDF creation failed: {e}")
            raise
    
    def convert_to_pdf(self, document_data, custom_input=None):
        """Convert to PDF using available method"""
        try:
            if PDF_LIBRARY == "reportlab":
                return self.create_pdf_with_reportlab(document_data, custom_input)
            else:
                return self.create_simple_pdf(document_data, custom_input)
        except Exception as e:
            logger.error(f"PDF conversion failed: {e}")
            raise ValueError(f"PDF conversion failed: {e}")
    
    def extract_main_title(self, document_data):
        """Extract main title"""
        for section in document_data['sections']:
            if section['style'] == 'heading':
                return section['content'].upper()
        title = document_data['title'].upper()
        return title if len(title) <= 50 else "PROFESSIONAL DOCUMENT"
    
    def extract_subtitle(self, document_data, custom_input):
        """Extract subtitle"""
        headings = [s for s in document_data['sections'] if s['style'] == 'heading']
        if len(headings) > 1:
            return headings[1]['content']
        if custom_input:
            return f"Insights: {custom_input}"
        return "Preliminary Insights: Defining the Core"
    
    def upload_to_storage(self, file_path, destination_name):
        """Upload PDF to storage"""
        try:
            bucket = self.storage_client.bucket(BUCKET_NAME)
            blob = bucket.blob(f'generated/{destination_name}')
            blob.upload_from_filename(file_path)
            blob.make_public()
            logger.info(f"PDF uploaded: {destination_name}")
            return blob.public_url
        except Exception as e:
            logger.error(f"Upload failed: {e}")
            return None

# Initialize converter
converter = GoogleDocToPDFConverter()

@app.route('/health', methods=['GET'])
def health_check():
    """Health check"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'pdf_library': PDF_LIBRARY
    })

@app.route('/convert', methods=['POST'])
def convert_document():
    """Convert document to PDF"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400
        
        doc_url = data.get('doc_url')
        custom_input = data.get('custom_input', '')
        
        if not doc_url:
            return jsonify({'error': 'doc_url is required'}), 400
        
        logger.info(f"Converting: {doc_url} with {PDF_LIBRARY}")
        
        # Process document
        document_id = converter.extract_document_id(doc_url)
        document = converter.get_document_content(document_id)
        document_data = converter.extract_text_and_structure(document)
        
        # Convert to PDF
        pdf_path = converter.convert_to_pdf(document_data, custom_input)
        
        # Upload
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        pdf_filename = f"document_{document_id}_{timestamp}.pdf"
        public_url = converter.upload_to_storage(pdf_path, pdf_filename)
        
        # Cleanup
        os.unlink(pdf_path)
        
        return jsonify({
            'success': True,
            'document_title': document_data['title'],
            'pdf_filename': pdf_filename,
            'download_url': public_url,
            'timestamp': datetime.utcnow().isoformat(),
            'pdf_library': PDF_LIBRARY
        })
        
    except Exception as e:
        logger.error(f"Conversion error: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/download/<filename>', methods=['GET'])
def download_file(filename):
    """Download PDF"""
    try:
        bucket = converter.storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(f'generated/{filename}')
        
        if not blob.exists():
            return jsonify({'error': 'File not found'}), 404
        
        temp_file = tempfile.NamedTemporaryFile(delete=False)
        blob.download_to_filename(temp_file.name)
        
        return send_file(temp_file.name, as_attachment=True, download_name=filename, mimetype='application/pdf')
    except Exception as e:
        logger.error(f"Download error: {e}")
        return jsonify({'error': 'Download failed'}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
