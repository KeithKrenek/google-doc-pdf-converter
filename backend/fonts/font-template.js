// fonts/CaslonGrad-Regular.js
// This file should contain the base64 encoded font data
// To generate this file:
// 1. Convert your CaslonGrad-Regular.ttf font to base64
// 2. Replace the placeholder below with the actual base64 string

module.exports = `
// Base64 encoded font data goes here
// You can use online tools to convert TTF to base64
// or use Node.js: Buffer.from(fs.readFileSync('font.ttf')).toString('base64')

AAEAAAALAIAAAwAwT1MvMjVAg[...YOUR_FONT_BASE64_DATA_HERE...]ZpbA==
`;

// fonts/IbarraRealNova-Bold.js
// This file should contain the base64 encoded font data
// To generate this file:
// 1. Convert your IbarraRealNova-Bold.ttf font to base64
// 2. Replace the placeholder below with the actual base64 string

module.exports = `
// Base64 encoded font data goes here
// You can use online tools to convert TTF to base64
// or use Node.js: Buffer.from(fs.readFileSync('font.ttf')).toString('base64')

AAEAAAALAIAAAwAwT1MvMjVAg[...YOUR_FONT_BASE64_DATA_HERE...]ZpbA==
`;

// Font conversion utility (optional helper)
// fonts/convert-fonts.js
const fs = require('fs');
const path = require('path');

function convertFontToBase64(fontPath, outputPath) {
    try {
        const fontBuffer = fs.readFileSync(fontPath);
        const base64Font = fontBuffer.toString('base64');
        
        const jsContent = `module.exports = \`${base64Font}\`;`;
        
        fs.writeFileSync(outputPath, jsContent);
        console.log(`✅ Converted ${fontPath} to ${outputPath}`);
    } catch (error) {
        console.error(`❌ Error converting ${fontPath}:`, error.message);
    }
}

// Usage examples:
// convertFontToBase64('./CaslonGrad-Regular.ttf', './CaslonGrad-Regular.js');
// convertFontToBase64('./IbarraRealNova-Bold.ttf', './IbarraRealNova-Bold.js');