from flask import Flask, request, jsonify, send_file
from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build
from google.cloud import storage
import os
import json
import re
import tempfile
import logging
from datetime import datetime
from jinja2 import Template
import requests
from urllib.parse import urlparse, parse_qs
import base64
from io import BytesIO

# Import PDF generation libraries
try:
    from reportlab.lib.pagesizes import A4
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak, Image
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import inch
    from reportlab.lib.colors import HexColor, black, white
    from reportlab.platypus.frames import Frame
    from reportlab.platypus.doctemplate import PageTemplate, BaseDocTemplate
    from reportlab.platypus.tableofcontents import TableOfContents
    from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
    from reportlab.pdfgen import canvas
    PDF_LIBRARY = "reportlab"
    print("Using ReportLab for PDF generation")
except ImportError:
    print("ReportLab not available, will try pdfkit")
    PDF_LIBRARY = None

if not PDF_LIBRARY:
    try:
        import pdfkit
        PDF_LIBRARY = "pdfkit"
        print("Using pdfkit for PDF generation")
    except ImportError:
        print("Neither ReportLab nor pdfkit available")
        PDF_LIBRARY = None

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
            # Use service account credentials from environment
            credentials_json = os.environ.get('GOOGLE_CREDENTIALS_JSON')
            if credentials_json:
                credentials_info = json.loads(credentials_json)
                credentials = Credentials.from_service_account_info(
                    credentials_info, scopes=SCOPES
                )
            else:
                # Fallback to default credentials
                credentials = None
                
            self.docs_service = build('docs', 'v1', credentials=credentials)
            logger.info("Google Docs service initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize Google services: {e}")
            raise
    
    def extract_document_id(self, doc_url):
        """Extract document ID from Google Docs URL"""
        # Special handling for environment check
        if doc_url == "test-environment":
            return "test-environment"
            
        try:
            # Handle various Google Docs URL formats
            if '/document/d/' in doc_url:
                doc_id = doc_url.split('/document/d/')[1].split('/')[0]
            else:
                # Try to extract from other formats
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
        # Special handling for environment check
        if document_id == "test-environment":
            return {
                'title': 'Environment Test Document',
                'body': {
                    'content': [
                        {
                            'paragraph': {
                                'elements': [
                                    {
                                        'textRun': {
                                            'content': f'PDF Library Available: {PDF_LIBRARY}\n'
                                        }
                                    }
                                ]
                            }
                        }
                    ]
                }
            }
            
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
            'sections': [],
            'images': []
        }
        
        for element in content:
            if 'paragraph' in element:
                paragraph = element['paragraph']
                text_content = ''
                style = 'normal'
                
                # Extract text from paragraph elements
                for text_element in paragraph.get('elements', []):
                    if 'textRun' in text_element:
                        text_run = text_element['textRun']
                        text_content += text_run.get('content', '')
                        
                        # Determine style based on formatting
                        text_style = text_run.get('textStyle', {})
                        if text_style.get('bold', False):
                            if text_style.get('fontSize', {}).get('magnitude', 0) > 14:
                                style = 'heading'
                            else:
                                style = 'bold'
                
                # Clean up text content
                text_content = text_content.strip()
                if text_content:
                    extracted_data['sections'].append({
                        'type': 'paragraph',
                        'content': text_content,
                        'style': style
                    })
        
        return extracted_data
    
    def create_pdf_with_reportlab(self, document_data, custom_input=None):
        """Create PDF using ReportLab library"""
        try:
            # Create temporary file for PDF
            temp_pdf = tempfile.NamedTemporaryFile(suffix='.pdf', delete=False)
            temp_pdf.close()
            
            # Create PDF document
            doc = SimpleDocTemplate(temp_pdf.name, pagesize=A4)
            
            # Get styles
            styles = getSampleStyleSheet()
            
            # Create custom styles
            title_style = ParagraphStyle(
                'CustomTitle',
                parent=styles['Heading1'],
                fontSize=36,
                spaceAfter=30,
                alignment=TA_CENTER,
                textColor=white,
                backColor=HexColor('#000000'),
                borderPadding=20
            )
            
            subtitle_style = ParagraphStyle(
                'CustomSubtitle',
                parent=styles['Heading2'],
                fontSize=18,
                spaceAfter=20,
                alignment=TA_CENTER,
                textColor=HexColor('#666666')
            )
            
            heading_style = ParagraphStyle(
                'CustomHeading',
                parent=styles['Heading2'],
                fontSize=16,
                spaceAfter=12,
                textColor=HexColor('#2c3e50'),
                borderWidth=2,
                borderColor=HexColor('#3498db'),
                borderPadding=5
            )
            
            content_style = ParagraphStyle(
                'CustomContent',
                parent=styles['Normal'],
                fontSize=11,
                spaceAfter=12,
                alignment=TA_JUSTIFY,
                leftIndent=0,
                rightIndent=0
            )
            
            # Build document content
            story = []
            
            # Cover page
            main_title = self.extract_main_title(document_data)
            subtitle = self.extract_subtitle(document_data, custom_input)
            brand_name = custom_input if custom_input else "PROFESSIONAL BRAND"
            
            # Add cover content
            story.append(Spacer(1, 2*inch))
            story.append(Paragraph(main_title, title_style))
            story.append(Spacer(1, 0.5*inch))
            story.append(Paragraph(subtitle, subtitle_style))
            story.append(Spacer(1, 2*inch))
            story.append(Paragraph(brand_name, subtitle_style))
            story.append(PageBreak())
            
            # Add document content
            for section in document_data['sections']:
                if section['style'] == 'heading':
                    story.append(Paragraph(section['content'], heading_style))
                elif section['style'] == 'bold':
                    bold_style = ParagraphStyle(
                        'Bold',
                        parent=content_style,
                        fontName='Helvetica-Bold'
                    )
                    story.append(Paragraph(section['content'], bold_style))
                else:
                    story.append(Paragraph(section['content'], content_style))
                
                story.append(Spacer(1, 12))
            
            # Build PDF
            doc.build(story)
            
            logger.info(f"PDF generated successfully with ReportLab: {temp_pdf.name}")
            return temp_pdf.name
            
        except Exception as e:
            logger.error(f"Error creating PDF with ReportLab: {e}")
            raise ValueError(f"PDF creation failed: {e}")
    
    def create_pdf_with_pdfkit(self, document_data, custom_input=None):
        """Create PDF using pdfkit (wkhtmltopdf)"""
        try:
            # Generate HTML content (simplified version)
            html_content = self.generate_simple_html(document_data, custom_input)
            
            # Configure pdfkit options
            options = {
                'page-size': 'A4',
                'margin-top': '0.75in',
                'margin-right': '0.75in',
                'margin-bottom': '0.75in',
                'margin-left': '0.75in',
                'encoding': "UTF-8",
                'no-outline': None
            }
            
            # Create temporary file for PDF
            temp_pdf = tempfile.NamedTemporaryFile(suffix='.pdf', delete=False)
            temp_pdf.close()
            
            # Generate PDF
            pdfkit.from_string(html_content, temp_pdf.name, options=options)
            
            logger.info(f"PDF generated successfully with pdfkit: {temp_pdf.name}")
            return temp_pdf.name
            
        except Exception as e:
            logger.error(f"Error creating PDF with pdfkit: {e}")
            raise ValueError(f"PDF creation failed: {e}")
    
    def generate_simple_html(self, document_data, custom_input=None):
        """Generate simple HTML for fallback PDF generation"""
        main_title = self.extract_main_title(document_data)
        subtitle = self.extract_subtitle(document_data, custom_input)
        brand_name = custom_input if custom_input else "PROFESSIONAL BRAND"
        
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <style>
                body {{ font-family: Arial, sans-serif; margin: 40px; }}
                .cover {{ text-align: center; page-break-after: always; }}
                .title {{ font-size: 36px; font-weight: bold; margin: 100px 0 20px 0; }}
                .subtitle {{ font-size: 18px; margin: 20px 0; color: #666; }}
                .brand {{ font-size: 24px; margin-top: 100px; }}
                .heading {{ font-size: 18px; font-weight: bold; margin: 20px 0 10px 0; color: #2c3e50; }}
                .content {{ font-size: 12px; line-height: 1.6; margin: 10px 0; }}
                .bold {{ font-weight: bold; }}
            </style>
        </head>
        <body>
            <div class="cover">
                <div class="title">{main_title}</div>
                <div class="subtitle">{subtitle}</div>
                <div class="brand">{brand_name}</div>
            </div>
            <div class="content-page">
        """
        
        for section in document_data['sections']:
            if section['style'] == 'heading':
                html += f'<div class="heading">{section["content"]}</div>'
            elif section['style'] == 'bold':
                html += f'<div class="content bold">{section["content"]}</div>'
            else:
                html += f'<div class="content">{section["content"]}</div>'
        
        html += """
            </div>
        </body>
        </html>
        """
        
        return html
    
    def convert_to_pdf(self, document_data, custom_input=None):
        """Convert document to PDF using available library"""
        try:
            if PDF_LIBRARY == "reportlab":
                return self.create_pdf_with_reportlab(document_data, custom_input)
            elif PDF_LIBRARY == "pdfkit":
                return self.create_pdf_with_pdfkit(document_data, custom_input)
            else:
                # Fallback: create a simple text-based PDF with ReportLab basics
                return self.create_simple_text_pdf(document_data, custom_input)
                
        except Exception as e:
            logger.error(f"Error converting to PDF: {e}")
            raise ValueError(f"PDF conversion failed: {e}")
    
    def create_simple_text_pdf(self, document_data, custom_input=None):
        """Create a very simple PDF as ultimate fallback"""
        try:
            from reportlab.pdfgen import canvas
            from reportlab.lib.pagesizes import A4
            
            temp_pdf = tempfile.NamedTemporaryFile(suffix='.pdf', delete=False)
            temp_pdf.close()
            
            c = canvas.Canvas(temp_pdf.name, pagesize=A4)
            width, height = A4
            
            # Title page
            title = self.extract_main_title(document_data)
            subtitle = self.extract_subtitle(document_data, custom_input)
            brand = custom_input if custom_input else "PROFESSIONAL BRAND"
            
            c.setFont("Helvetica-Bold", 24)
            c.drawCentredText(width/2, height-200, title)
            
            c.setFont("Helvetica", 16)
            c.drawCentredText(width/2, height-250, subtitle)
            
            c.setFont("Helvetica-Bold", 18)
            c.drawCentredText(width/2, height-400, brand)
            
            c.showPage()
            
            # Content pages
            y_position = height - 100
            c.setFont("Helvetica", 12)
            
            for section in document_data['sections']:
                if y_position < 100:
                    c.showPage()
                    y_position = height - 100
                
                if section['style'] == 'heading':
                    c.setFont("Helvetica-Bold", 14)
                else:
                    c.setFont("Helvetica", 12)
                
                # Simple text wrapping
                text = section['content']
                if len(text) > 80:
                    words = text.split(' ')
                    lines = []
                    current_line = []
                    for word in words:
                        current_line.append(word)
                        if len(' '.join(current_line)) > 80:
                            current_line.pop()
                            lines.append(' '.join(current_line))
                            current_line = [word]
                    if current_line:
                        lines.append(' '.join(current_line))
                    
                    for line in lines:
                        c.drawString(50, y_position, line)
                        y_position -= 15
                else:
                    c.drawString(50, y_position, text)
                    y_position -= 20
            
            c.save()
            
            logger.info(f"Simple PDF generated: {temp_pdf.name}")
            return temp_pdf.name
            
        except Exception as e:
            logger.error(f"Error creating simple PDF: {e}")
            raise ValueError(f"Simple PDF creation failed: {e}")
    
    def extract_main_title(self, document_data):
        """Extract main title from document data"""
        # Look for the first heading or use document title
        for section in document_data['sections']:
            if section['style'] == 'heading':
                return section['content'].upper()
        
        # Fallback to document title
        title = document_data['title'].upper()
        if len(title) > 50:
            title = "PROFESSIONAL DOCUMENT"
        return title
    
    def extract_subtitle(self, document_data, custom_input):
        """Extract subtitle from document data"""
        # Look for second heading or create from first paragraph
        headings = [s for s in document_data['sections'] if s['style'] == 'heading']
        
        if len(headings) > 1:
            return headings[1]['content']
        
        # Create subtitle from first paragraph or custom input
        if custom_input:
            return f"Insights: {custom_input}"
        
        paragraphs = [s for s in document_data['sections'] if s['style'] == 'paragraph']
        if paragraphs:
            first_para = paragraphs[0]['content'][:100]
            return f"Preliminary Insights: {first_para.split('.')[0]}"
        
        return "Preliminary Insights: Defining the Core"
    
    def upload_to_storage(self, file_path, destination_name):
        """Upload generated PDF to Cloud Storage"""
        try:
            bucket = self.storage_client.bucket(BUCKET_NAME)
            blob = bucket.blob(f'generated/{destination_name}')
            
            blob.upload_from_filename(file_path)
            blob.make_public()
            
            logger.info(f"PDF uploaded to storage: {destination_name}")
            return blob.public_url
        except Exception as e:
            logger.error(f"Error uploading to storage: {e}")
            return None

# Initialize converter
converter = GoogleDocToPDFConverter()

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy', 
        'timestamp': datetime.utcnow().isoformat(),
        'pdf_library': PDF_LIBRARY
    })

@app.route('/convert', methods=['POST'])
def convert_document():
    """Main endpoint for document conversion"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400
        
        doc_url = data.get('doc_url')
        custom_input = data.get('custom_input', '')
        
        if not doc_url:
            return jsonify({'error': 'doc_url is required'}), 400
        
        logger.info(f"Starting conversion for URL: {doc_url} using {PDF_LIBRARY}")
        
        # Extract document ID
        document_id = converter.extract_document_id(doc_url)
        
        # Get document content
        document = converter.get_document_content(document_id)
        
        # Extract text and structure
        document_data = converter.extract_text_and_structure(document)
        
        # Convert to PDF using alternative method
        pdf_path = converter.convert_to_pdf(document_data, custom_input)
        
        # Generate unique filename
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        pdf_filename = f"document_{document_id}_{timestamp}.pdf"
        
        # Upload to storage
        public_url = converter.upload_to_storage(pdf_path, pdf_filename)
        
        # Clean up temporary file
        os.unlink(pdf_path)
        
        response_data = {
            'success': True,
            'document_title': document_data['title'],
            'pdf_filename': pdf_filename,
            'download_url': public_url,
            'timestamp': datetime.utcnow().isoformat(),
            'pdf_library': PDF_LIBRARY
        }
        
        logger.info(f"Conversion completed successfully: {pdf_filename}")
        return jsonify(response_data)
        
    except ValueError as e:
        logger.error(f"Validation error: {e}")
        return jsonify({'error': str(e)}), 400
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return jsonify({'error': 'Internal server error', 'details': str(e)}), 500

@app.route('/download/<filename>', methods=['GET'])
def download_file(filename):
    """Download generated PDF file"""
    try:
        bucket = converter.storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(f'generated/{filename}')
        
        if not blob.exists():
            return jsonify({'error': 'File not found'}), 404
        
        # Download to temporary file and serve
        temp_file = tempfile.NamedTemporaryFile(delete=False)
        blob.download_to_filename(temp_file.name)
        
        return send_file(
            temp_file.name,
            as_attachment=True,
            download_name=filename,
            mimetype='application/pdf'
        )
    except Exception as e:
        logger.error(f"Error downloading file: {e}")
        return jsonify({'error': 'Download failed'}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)