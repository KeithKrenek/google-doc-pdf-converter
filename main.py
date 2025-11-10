"""
Google Doc to PDF Converter - Production Ready
Converts Google Docs to professionally formatted PDFs with custom branding
"""

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
from io import BytesIO
import base64

# ReportLab imports for PDF generation
from reportlab.lib.pagesizes import A4, letter
from reportlab.lib.units import inch, cm
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_JUSTIFY, TA_RIGHT
from reportlab.lib.colors import HexColor, black, white, grey
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak,
    Table, TableStyle, Image, KeepTogether, ListFlowable, ListItem
)
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
SCOPES = ['https://www.googleapis.com/auth/documents.readonly']
BUCKET_NAME = os.environ.get('BUCKET_NAME', 'your-pdf-assets-bucket')
PROJECT_ID = os.environ.get('PROJECT_ID', 'your-project-id')

# Styling configuration
STYLE_CONFIG = {
    'fonts': {
        'title': 'Helvetica-Bold',
        'heading': 'Helvetica-Bold',
        'body': 'Helvetica',
        'bold': 'Helvetica-Bold',
        'italic': 'Helvetica-Oblique'
    },
    'sizes': {
        'cover_title': 36,
        'cover_subtitle': 20,
        'cover_date': 12,
        'heading1': 24,
        'heading2': 18,
        'heading3': 14,
        'body': 11,
        'footer': 9
    },
    'colors': {
        'primary': HexColor('#2c3e50'),
        'secondary': HexColor('#34495e'),
        'accent': HexColor('#3498db'),
        'text': black,
        'grey': HexColor('#7f8c8d'),
        'light_grey': HexColor('#ecf0f1')
    },
    'spacing': {
        'heading1_before': 24,
        'heading1_after': 12,
        'heading2_before': 18,
        'heading2_after': 10,
        'heading3_before': 14,
        'heading3_after': 8,
        'paragraph': 12,
        'list_item': 6
    }
}


class PageNumberCanvas(canvas.Canvas):
    """Custom canvas for adding page numbers and footers"""

    def __init__(self, *args, **kwargs):
        self.logo_path = kwargs.pop('logo_path', None)
        canvas.Canvas.__init__(self, *args, **kwargs)
        self.pages = []

    def showPage(self):
        self.pages.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        page_count = len(self.pages)
        for page_num, page in enumerate(self.pages, start=1):
            self.__dict__.update(page)
            # Skip footer on first page (cover)
            if page_num > 1:
                self.draw_page_footer(page_num - 1, page_count - 1)
            canvas.Canvas.showPage(self)
        canvas.Canvas.save(self)

    def draw_page_footer(self, page_num, total_pages):
        """Draw footer with page numbers and optional logo"""
        self.saveState()
        self.setFont(STYLE_CONFIG['fonts']['body'], STYLE_CONFIG['sizes']['footer'])
        self.setFillColor(STYLE_CONFIG['colors']['grey'])

        # Page number
        page_text = f"Page {page_num} of {total_pages}"
        self.drawString(1*inch, 0.5*inch, page_text)

        # Logo in footer (if provided)
        if self.logo_path and os.path.exists(self.logo_path):
            try:
                # Place small logo in bottom right
                self.drawImage(self.logo_path,
                             A4[0] - 2*inch, 0.4*inch,
                             width=1*inch, height=0.3*inch,
                             preserveAspectRatio=True, mask='auto')
            except Exception as e:
                logger.warning(f"Could not add footer logo: {e}")

        self.restoreState()


class GoogleDocPDFConverter:
    """Main converter class for Google Docs to PDF"""

    def __init__(self):
        self.setup_google_services()
        self.storage_client = storage.Client()
        self.styles = self.create_custom_styles()

    def setup_google_services(self):
        """Initialize Google API services with service account"""
        try:
            credentials_json = os.environ.get('GOOGLE_CREDENTIALS_JSON')
            if credentials_json:
                # Handle base64 encoded credentials
                try:
                    decoded = base64.b64decode(credentials_json)
                    credentials_info = json.loads(decoded)
                except:
                    credentials_info = json.loads(credentials_json)

                credentials = Credentials.from_service_account_info(
                    credentials_info, scopes=SCOPES
                )
            else:
                # Fall back to application default credentials for local dev
                credentials = None
                logger.warning("No GOOGLE_CREDENTIALS_JSON found, using default credentials")

            self.docs_service = build('docs', 'v1', credentials=credentials)
            logger.info("Google Docs service initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize Google services: {e}")
            raise

    def create_custom_styles(self):
        """Create custom paragraph styles for PDF"""
        styles = getSampleStyleSheet()

        # Cover page title
        styles.add(ParagraphStyle(
            name='CoverTitle',
            parent=styles['Heading1'],
            fontName=STYLE_CONFIG['fonts']['title'],
            fontSize=STYLE_CONFIG['sizes']['cover_title'],
            textColor=STYLE_CONFIG['colors']['primary'],
            alignment=TA_CENTER,
            spaceAfter=30,
            spaceBefore=0,
            leading=42
        ))

        # Cover subtitle
        styles.add(ParagraphStyle(
            name='CoverSubtitle',
            parent=styles['Normal'],
            fontName=STYLE_CONFIG['fonts']['body'],
            fontSize=STYLE_CONFIG['sizes']['cover_subtitle'],
            textColor=STYLE_CONFIG['colors']['secondary'],
            alignment=TA_CENTER,
            spaceAfter=20,
            leading=24
        ))

        # Heading 1 (main sections)
        styles.add(ParagraphStyle(
            name='CustomHeading1',
            parent=styles['Heading1'],
            fontName=STYLE_CONFIG['fonts']['heading'],
            fontSize=STYLE_CONFIG['sizes']['heading1'],
            textColor=STYLE_CONFIG['colors']['primary'],
            spaceBefore=STYLE_CONFIG['spacing']['heading1_before'],
            spaceAfter=STYLE_CONFIG['spacing']['heading1_after'],
            keepWithNext=True,
            leading=30
        ))

        # Heading 2 (subsections)
        styles.add(ParagraphStyle(
            name='CustomHeading2',
            parent=styles['Heading2'],
            fontName=STYLE_CONFIG['fonts']['heading'],
            fontSize=STYLE_CONFIG['sizes']['heading2'],
            textColor=STYLE_CONFIG['colors']['primary'],
            spaceBefore=STYLE_CONFIG['spacing']['heading2_before'],
            spaceAfter=STYLE_CONFIG['spacing']['heading2_after'],
            keepWithNext=True,
            leading=22
        ))

        # Heading 3 (sub-subsections)
        styles.add(ParagraphStyle(
            name='CustomHeading3',
            parent=styles['Heading3'],
            fontName=STYLE_CONFIG['fonts']['heading'],
            fontSize=STYLE_CONFIG['sizes']['heading3'],
            textColor=STYLE_CONFIG['colors']['secondary'],
            spaceBefore=STYLE_CONFIG['spacing']['heading3_before'],
            spaceAfter=STYLE_CONFIG['spacing']['heading3_after'],
            keepWithNext=True,
            leading=18
        ))

        # Body text
        styles.add(ParagraphStyle(
            name='CustomBody',
            parent=styles['Normal'],
            fontName=STYLE_CONFIG['fonts']['body'],
            fontSize=STYLE_CONFIG['sizes']['body'],
            textColor=STYLE_CONFIG['colors']['text'],
            alignment=TA_JUSTIFY,
            spaceAfter=STYLE_CONFIG['spacing']['paragraph'],
            leading=16
        ))

        # Bold body text
        styles.add(ParagraphStyle(
            name='CustomBodyBold',
            parent=styles['CustomBody'],
            fontName=STYLE_CONFIG['fonts']['bold']
        ))

        return styles

    def extract_document_id(self, doc_url):
        """Extract document ID from Google Docs URL"""
        try:
            if '/document/d/' in doc_url:
                doc_id = doc_url.split('/document/d/')[1].split('/')[0]
            elif 'id=' in doc_url:
                parsed = urlparse(doc_url)
                doc_id = parse_qs(parsed.query)['id'][0]
            else:
                raise ValueError("Cannot extract document ID from URL")

            logger.info(f"Extracted document ID: {doc_id}")
            return doc_id
        except Exception as e:
            logger.error(f"Error extracting document ID: {e}")
            raise ValueError(f"Invalid Google Docs URL format: {e}")

    def get_document_content(self, document_id):
        """Retrieve document from Google Docs API"""
        try:
            document = self.docs_service.documents().get(documentId=document_id).execute()
            logger.info(f"Retrieved document: {document.get('title', 'Untitled')}")
            return document
        except Exception as e:
            logger.error(f"Error retrieving document: {e}")
            raise ValueError(f"Failed to retrieve document. Ensure it's shared with the service account: {e}")

    def parse_google_doc_content(self, document):
        """Parse Google Doc content with native style detection"""
        content = document.get('body', {}).get('content', [])
        doc_title = document.get('title', 'Untitled Document')

        parsed_content = {
            'title': doc_title,
            'elements': []
        }

        for structural_element in content:
            if 'paragraph' in structural_element:
                paragraph = structural_element['paragraph']
                element_data = self.parse_paragraph(paragraph)
                if element_data:
                    parsed_content['elements'].append(element_data)
            elif 'table' in structural_element:
                table = structural_element['table']
                table_data = self.parse_table(table)
                if table_data:
                    parsed_content['elements'].append(table_data)

        return parsed_content

    def parse_paragraph(self, paragraph):
        """Parse a paragraph with style information"""
        # Get paragraph style
        para_style = paragraph.get('paragraphStyle', {})
        named_style = para_style.get('namedStyleType', 'NORMAL_TEXT')

        # Extract text with inline formatting
        text_parts = []
        for element in paragraph.get('elements', []):
            if 'textRun' in element:
                text_run = element['textRun']
                content = text_run.get('content', '')
                text_style = text_run.get('textStyle', {})

                text_parts.append({
                    'text': content,
                    'bold': text_style.get('bold', False),
                    'italic': text_style.get('italic', False),
                    'underline': text_style.get('underline', False),
                    'link': text_style.get('link', {}).get('url', None)
                })

        # Combine text
        full_text = ''.join([part['text'] for part in text_parts]).strip()

        if not full_text:
            return None

        # Determine element type
        element_type = 'body'
        if named_style == 'HEADING_1':
            element_type = 'heading1'
        elif named_style == 'HEADING_2':
            element_type = 'heading2'
        elif named_style == 'HEADING_3':
            element_type = 'heading3'
        elif named_style == 'TITLE':
            element_type = 'title'
        elif named_style == 'SUBTITLE':
            element_type = 'subtitle'

        # Check if it's a list item
        bullet = paragraph.get('bullet', None)
        if bullet:
            element_type = 'list_item'
            nesting_level = bullet.get('nestingLevel', 0)
        else:
            nesting_level = None

        return {
            'type': element_type,
            'text': full_text,
            'text_parts': text_parts,
            'nesting_level': nesting_level
        }

    def parse_table(self, table):
        """Parse a table structure"""
        rows = []
        for table_row in table.get('tableRows', []):
            cells = []
            for table_cell in table_row.get('tableCells', []):
                cell_content = []
                for content_element in table_cell.get('content', []):
                    if 'paragraph' in content_element:
                        para_data = self.parse_paragraph(content_element['paragraph'])
                        if para_data:
                            cell_content.append(para_data['text'])
                cells.append('\n'.join(cell_content))
            rows.append(cells)

        return {
            'type': 'table',
            'rows': rows
        }

    def format_text_with_styles(self, text_parts):
        """Convert text parts with inline styles to ReportLab markup"""
        formatted = []
        for part in text_parts:
            text = part['text'].replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

            if part['bold'] and part['italic']:
                formatted.append(f'<b><i>{text}</i></b>')
            elif part['bold']:
                formatted.append(f'<b>{text}</b>')
            elif part['italic']:
                formatted.append(f'<i>{text}</i>')
            elif part['underline']:
                formatted.append(f'<u>{text}</u>')
            elif part['link']:
                formatted.append(f'<link href="{part["link"]}" color="blue">{text}</link>')
            else:
                formatted.append(text)

        return ''.join(formatted)

    def create_cover_page(self, company_name, doc_title, cover_image_path=None):
        """Create cover page elements"""
        story = []

        # Add cover image if available
        if cover_image_path and os.path.exists(cover_image_path):
            try:
                # Full page image
                img = Image(cover_image_path, width=A4[0], height=A4[1])
                story.append(img)
                story.append(PageBreak())
            except Exception as e:
                logger.warning(f"Could not load cover image: {e}")

        # Text-based cover page
        story.append(Spacer(1, 2.5*inch))

        # Company name (large, centered)
        company_para = Paragraph(company_name.upper(), self.styles['CoverTitle'])
        story.append(company_para)
        story.append(Spacer(1, 0.5*inch))

        # Document title
        title_para = Paragraph(doc_title, self.styles['CoverSubtitle'])
        story.append(title_para)
        story.append(Spacer(1, 1*inch))

        # Date
        date_style = ParagraphStyle(
            'CoverDate',
            parent=self.styles['CustomBody'],
            fontSize=STYLE_CONFIG['sizes']['cover_date'],
            alignment=TA_CENTER,
            textColor=STYLE_CONFIG['colors']['grey']
        )
        date_text = datetime.now().strftime("%B %d, %Y")
        date_para = Paragraph(date_text, date_style)
        story.append(date_para)

        story.append(PageBreak())

        return story

    def convert_to_pdf(self, parsed_content, company_name='COMPANY NAME',
                       cover_image_path=None, logo_path=None):
        """Convert parsed content to PDF"""
        try:
            # Create temporary PDF file
            temp_pdf = tempfile.NamedTemporaryFile(suffix='.pdf', delete=False)
            temp_pdf.close()

            # Create PDF with custom canvas for page numbers
            pdf = SimpleDocTemplate(
                temp_pdf.name,
                pagesize=A4,
                leftMargin=1*inch,
                rightMargin=1*inch,
                topMargin=1*inch,
                bottomMargin=1*inch
            )

            story = []

            # Add cover page
            story.extend(self.create_cover_page(
                company_name,
                parsed_content['title'],
                cover_image_path
            ))

            # Process content elements
            for element in parsed_content['elements']:
                if element['type'] == 'heading1':
                    text = self.format_text_with_styles(element['text_parts'])
                    para = Paragraph(text, self.styles['CustomHeading1'])
                    story.append(para)

                elif element['type'] == 'heading2':
                    text = self.format_text_with_styles(element['text_parts'])
                    para = Paragraph(text, self.styles['CustomHeading2'])
                    story.append(para)

                elif element['type'] == 'heading3':
                    text = self.format_text_with_styles(element['text_parts'])
                    para = Paragraph(text, self.styles['CustomHeading3'])
                    story.append(para)

                elif element['type'] == 'list_item':
                    text = self.format_text_with_styles(element['text_parts'])
                    # Add bullet with proper indentation
                    indent = element['nesting_level'] * 0.5 * inch
                    list_style = ParagraphStyle(
                        'ListItem',
                        parent=self.styles['CustomBody'],
                        leftIndent=indent + 20,
                        firstLineIndent=-10,
                        bulletIndent=indent + 10
                    )
                    para = Paragraph(f'• {text}', list_style)
                    story.append(para)

                elif element['type'] == 'table':
                    table = self.create_pdf_table(element['rows'])
                    story.append(table)
                    story.append(Spacer(1, 12))

                else:  # body text
                    text = self.format_text_with_styles(element['text_parts'])
                    para = Paragraph(text, self.styles['CustomBody'])
                    story.append(para)

            # Build PDF with custom canvas
            pdf.build(
                story,
                canvasmaker=lambda *args, **kwargs: PageNumberCanvas(
                    *args,
                    logo_path=logo_path,
                    **kwargs
                )
            )

            logger.info(f"PDF created successfully: {temp_pdf.name}")
            return temp_pdf.name

        except Exception as e:
            logger.error(f"PDF generation failed: {e}", exc_info=True)
            raise ValueError(f"Failed to generate PDF: {e}")

    def create_pdf_table(self, rows):
        """Create a formatted table for PDF"""
        if not rows:
            return Spacer(1, 0)

        # Create table
        table = Table(rows, hAlign='LEFT')

        # Style the table
        table_style = TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), STYLE_CONFIG['colors']['light_grey']),
            ('TEXTCOLOR', (0, 0), (-1, 0), STYLE_CONFIG['colors']['primary']),
            ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
            ('FONTNAME', (0, 0), (-1, 0), STYLE_CONFIG['fonts']['bold']),
            ('FONTSIZE', (0, 0), (-1, 0), STYLE_CONFIG['sizes']['body']),
            ('FONTNAME', (0, 1), (-1, -1), STYLE_CONFIG['fonts']['body']),
            ('FONTSIZE', (0, 1), (-1, -1), STYLE_CONFIG['sizes']['body']),
            ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
            ('TOPPADDING', (0, 0), (-1, -1), 8),
            ('BOTTOMPADDING', (0, 1), (-1, -1), 8),
            ('GRID', (0, 0), (-1, -1), 0.5, STYLE_CONFIG['colors']['grey']),
            ('ROWBACKGROUNDS', (0, 1), (-1, -1), [white, STYLE_CONFIG['colors']['light_grey']])
        ])

        table.setStyle(table_style)
        return table

    def upload_to_storage(self, file_path, destination_name):
        """Upload PDF to Google Cloud Storage"""
        try:
            bucket = self.storage_client.bucket(BUCKET_NAME)
            blob = bucket.blob(f'generated/{destination_name}')
            blob.upload_from_filename(file_path)
            blob.make_public()

            logger.info(f"PDF uploaded to storage: {destination_name}")
            return blob.public_url
        except Exception as e:
            logger.error(f"Storage upload failed: {e}")
            raise ValueError(f"Failed to upload PDF: {e}")

    def get_asset_path(self, asset_name):
        """Get path to asset file (local or from storage)"""
        local_path = os.path.join('assets', asset_name)
        if os.path.exists(local_path):
            return local_path

        # Try to download from storage
        try:
            bucket = self.storage_client.bucket(BUCKET_NAME)
            blob = bucket.blob(f'assets/{asset_name}')

            temp_file = tempfile.NamedTemporaryFile(suffix=os.path.splitext(asset_name)[1], delete=False)
            blob.download_to_filename(temp_file.name)
            return temp_file.name
        except Exception as e:
            logger.warning(f"Could not load asset {asset_name}: {e}")
            return None


# Initialize converter
converter = GoogleDocPDFConverter()


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'service': 'google-doc-pdf-converter',
        'version': '2.0.0'
    }), 200


@app.route('/convert', methods=['POST'])
def convert_document():
    """Main endpoint to convert Google Doc to PDF"""
    try:
        # Parse request
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400

        doc_url = data.get('doc_url')
        company_name = data.get('company_name') or data.get('custom_input', 'COMPANY NAME')
        use_cover_image = data.get('use_cover_image', True)

        if not doc_url:
            return jsonify({'error': 'doc_url is required'}), 400

        logger.info(f"Converting document: {doc_url}")
        logger.info(f"Company name: {company_name}")

        # Extract document ID and fetch content
        document_id = converter.extract_document_id(doc_url)
        document = converter.get_document_content(document_id)

        # Parse document content with styles
        parsed_content = converter.parse_google_doc_content(document)
        logger.info(f"Parsed {len(parsed_content['elements'])} elements from document")

        # Get assets
        cover_image = converter.get_asset_path('stylized-logo.png') if use_cover_image else None
        logo = converter.get_asset_path('black-logo.png')

        # Generate PDF
        pdf_path = converter.convert_to_pdf(
            parsed_content,
            company_name=company_name,
            cover_image_path=cover_image,
            logo_path=logo
        )

        # Upload to storage
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        safe_title = ''.join(c for c in parsed_content['title'] if c.isalnum() or c in (' ', '-', '_'))[:50]
        pdf_filename = f"{safe_title}_{timestamp}.pdf"

        public_url = converter.upload_to_storage(pdf_path, pdf_filename)

        # Cleanup temp file
        try:
            os.unlink(pdf_path)
        except:
            pass

        # Return success response
        return jsonify({
            'success': True,
            'document_title': parsed_content['title'],
            'company_name': company_name,
            'pdf_filename': pdf_filename,
            'download_url': public_url,
            'timestamp': datetime.utcnow().isoformat(),
            'elements_processed': len(parsed_content['elements'])
        }), 200

    except ValueError as e:
        logger.error(f"Validation error: {e}")
        return jsonify({'error': str(e)}), 400
    except Exception as e:
        logger.error(f"Conversion error: {e}", exc_info=True)
        return jsonify({'error': f'Internal server error: {str(e)}'}), 500


@app.route('/download/<filename>', methods=['GET'])
def download_file(filename):
    """Download a generated PDF file"""
    try:
        bucket = converter.storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(f'generated/{filename}')

        if not blob.exists():
            return jsonify({'error': 'File not found'}), 404

        # Download to temporary file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        blob.download_to_filename(temp_file.name)

        return send_file(
            temp_file.name,
            as_attachment=True,
            download_name=filename,
            mimetype='application/pdf'
        )
    except Exception as e:
        logger.error(f"Download error: {e}")
        return jsonify({'error': 'Download failed'}), 500


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    logger.info(f"Starting server on port {port}")
    app.run(host='0.0.0.0', port=port, debug=False)
