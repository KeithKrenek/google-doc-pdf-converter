// Correct jsPDF import for Node.js
const { jsPDF } = require('jspdf');

const processContentLine = (pdf, line, x, y, usableWidth, margin) => {
  const pageHeight = pdf.internal.pageSize.getHeight();
  const footerHeight = 80;
  const effectivePageHeight = pageHeight - footerHeight;
  
  const checkForPageBreak = (requiredHeight, lineHeight = 20) => {
    if (effectivePageHeight - y < requiredHeight) {
      pdf.addPage();
      return margin;
    }
    return y;
  };

  // Handle different markdown-style content
  const heading2Regex = /^## (.*)/;
  const heading3Regex = /^### (.*)/;
  const bulletRegex = /^[\s]*[-*]\s+(.*)/;
  
  if (heading2Regex.test(line)) {
    y = checkForPageBreak(40);
    y += 15;
    pdf.setFont('helvetica', 'bold');
    pdf.setFontSize(18);
    const text = line.match(heading2Regex)?.[1] || '';
    const cleanText = text.replace(/\*\*(.*?)\*\*/g, '$1');
    pdf.text(cleanText, x, y);
    return { y: y + 25, newPage: false };
  }

  if (heading3Regex.test(line)) {
    y = checkForPageBreak(35);
    y += 12;
    pdf.setFont('helvetica', 'bold');
    pdf.setFontSize(14);
    const text = line.match(heading3Regex)?.[1] || '';
    const cleanText = text.replace(/\*\*(.*?)\*\*/g, '$1');
    pdf.text(cleanText, x, y);
    return { y: y + 22, newPage: false };
  }

  if (bulletRegex.test(line)) {
    const match = line.match(bulletRegex);
    if (match) {
      const content = match[1];
      y = checkForPageBreak(18);
      
      pdf.setFont('helvetica', 'normal');
      pdf.setFontSize(12);
      pdf.text('•', x + 15, y);
      
      // Handle bold text in bullet content
      addFormattedText(pdf, content, x + 35, y);
      
      return { y: y + 23, newPage: false };
    }
  }

  if (line.trim() === '') {
    return { y: y + 12, newPage: false };
  }

  // Regular paragraph text
  pdf.setFont('helvetica', 'normal');
  pdf.setFontSize(12);
  const lineHeight = 18;
  
  const wrappedLines = pdf.splitTextToSize(line, usableWidth);
  
  for (let i = 0; i < wrappedLines.length; i++) {
    y = checkForPageBreak(lineHeight);
    addFormattedText(pdf, wrappedLines[i], x, y);
    y += lineHeight;
  }

  return { y: y + 10, newPage: false };
};

// Function to handle bold text formatting
const addFormattedText = (pdf, text, x, y) => {
  const boldTextRegex = /\*\*(.*?)\*\*/g;
  let currentX = x;
  let lastIndex = 0;
  let match;
  
  boldTextRegex.lastIndex = 0;

  while ((match = boldTextRegex.exec(text)) !== null) {
    // Add text before bold
    const beforeBold = text.substring(lastIndex, match.index);
    if (beforeBold) {
      pdf.setFont('helvetica', 'normal');
      pdf.text(beforeBold, currentX, y);
      currentX += pdf.getTextWidth(beforeBold);
    }
    
    // Add bold text
    const boldText = match[1];
    pdf.setFont('helvetica', 'bold');
    pdf.text(boldText, currentX, y);
    currentX += pdf.getTextWidth(boldText);
    
    lastIndex = match.index + match[0].length;
  }
  
  // Add remaining text
  const remaining = text.substring(lastIndex);
  if (remaining) {
    pdf.setFont('helvetica', 'normal');
    pdf.text(remaining, currentX, y);
  }
  
  // If no bold text found, just add the text normally
  if (lastIndex === 0) {
    pdf.setFont('helvetica', 'normal');
    pdf.text(text, currentX, y);
  }
};

const processSectionContent = (pdf, section, margin, usableWidth, isFirstSection = false) => {
  const pageWidth = pdf.internal.pageSize.getWidth();
  
  if (!isFirstSection) {
    pdf.addPage();
  }
  
  let yPosition = margin;

  // Section title - centered and bold
  pdf.setFont('helvetica', 'bold');
  pdf.setFontSize(24);
  yPosition += 30;
  
  const titleLines = pdf.splitTextToSize(section.title, usableWidth);
  titleLines.forEach(line => {
    const titleWidth = pdf.getTextWidth(line);
    const titleIndent = (pageWidth - titleWidth) / 2;
    pdf.text(line, titleIndent, yPosition);
    yPosition += 30;
  });
  
  // Section subtitle - centered and normal
  pdf.setFont('helvetica', 'normal');
  pdf.setFontSize(16);
  
  const subtitleLines = pdf.splitTextToSize(section.subtitle, usableWidth);
  subtitleLines.forEach(line => {
    const subtitleWidth = pdf.getTextWidth(line);
    const subtitleIndent = (pageWidth - subtitleWidth) / 2;
    pdf.text(line, subtitleIndent, yPosition);
    yPosition += 20;
  });
  
  yPosition += 20;
  
  // Process content line by line
  const lines = section.content.split('\n');
  for (const line of lines) {
    const result = processContentLine(pdf, line, margin, yPosition, usableWidth, margin);
    yPosition = result.y;
  }

  return yPosition;
};

const generatePDF = async ({ brandName, sections }) => {
  try {
    console.log(`Generating PDF for ${brandName} with ${sections.length} sections`);

    // Create PDF with correct constructor
    const pdf = new jsPDF({
      orientation: 'portrait',
      unit: 'pt',
      format: 'a4'
    });

    const pageWidth = pdf.internal.pageSize.getWidth();
    const pageHeight = pdf.internal.pageSize.getHeight();
    const margin = 50;
    const usableWidth = pageWidth - 2 * margin;

    // Create cover page
    pdf.setFont('helvetica', 'bold');
    pdf.setFontSize(36);
    
    const brandNameLines = pdf.splitTextToSize(brandName.toUpperCase(), usableWidth);
    let brandNameY = pageHeight / 2 - 50;
    
    brandNameLines.forEach((line) => {
      const brandNameWidth = pdf.getTextWidth(line);
      const brandNameIndent = (pageWidth - brandNameWidth) / 2;
      pdf.text(line, brandNameIndent, brandNameY);
      brandNameY += 45;
    });

    // Add subtitle
    pdf.setFont('helvetica', 'normal');
    pdf.setFontSize(20);
    const subtitle = 'Brand Strategy Report';
    const subtitleWidth = pdf.getTextWidth(subtitle);
    const subtitleIndent = (pageWidth - subtitleWidth) / 2;
    pdf.text(subtitle, subtitleIndent, brandNameY + 30);

    // Add date
    pdf.setFontSize(12);
    const dateStr = new Date().toLocaleDateString();
    const dateWidth = pdf.getTextWidth(dateStr);
    const dateIndent = (pageWidth - dateWidth) / 2;
    pdf.text(dateStr, dateIndent, brandNameY + 80);

    // Process all sections
    let isFirstSection = true;
    
    for (const section of sections) {
      if (isFirstSection) {
        pdf.addPage();
      }
      console.log(`Processing section ${section.sectionNumber}: ${section.title}`);
      processSectionContent(pdf, section, margin, usableWidth, isFirstSection);
      isFirstSection = false;
    }

    // Add page numbers to all pages except cover
    const pageCount = pdf.getNumberOfPages();
    
    for (let i = 2; i <= pageCount; i++) {
      pdf.setPage(i);
      pdf.setFontSize(10);
      pdf.setFont('helvetica', 'normal');
      pdf.setTextColor(128, 128, 128); // Gray color
      
      // Page number at bottom
      const pageText = `Page ${i - 1} of ${pageCount - 1}`;
      pdf.text(pageText, margin, pageHeight - margin / 2);
      
      // Reset color for content
      pdf.setTextColor(0, 0, 0);
    }

    // Return the PDF as array buffer
    return pdf.output('arraybuffer');
    
  } catch (error) {
    console.error('PDF generation failed:', error);
    throw new Error(`Failed to generate PDF: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
};

module.exports = { generatePDF };
