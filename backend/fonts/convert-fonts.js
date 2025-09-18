const fs = require('fs');
const font1 = fs.readFileSync('CaslonGrad-Regular-normal.ttf');
const base641 = font1.toString('base64');
fs.writeFileSync('CaslonGrad-Regular.js', 'module.exports = `' + base641 + '`;');
console.log('✅ CaslonGrad-Regular.js created');

const font2 = fs.readFileSync('IbarraRealNova-Bold-bold.ttf');
const base642 = font2.toString('base64');
fs.writeFileSync('IbarraRealNova-Bold.js', 'module.exports = `' + base642 + '`;');
console.log('✅ IbarraRealNova-Bold.js created');