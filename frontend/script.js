// Google Doc to PDF Converter - Frontend JavaScript
// This file handles the user interface interactions and API calls

// --- Configuration ---
// TODO: Update this URL after deploying your Google Cloud Function
const CLOUD_FUNCTION_URL = 'https://us-central1-brand-strategy-report-pdf.cloudfunctions.net/convertDocToPdf';

// --- DOM Elements ---
const converterForm = document.getElementById('converterForm');
const docUrlInput = document.getElementById('docUrl');
const brandNameInput = document.getElementById('brandName');
const convertBtn = document.getElementById('convertBtn');
const loading = document.getElementById('loading');
const progressBar = document.getElementById('progressBar');
const progressFill = document.getElementById('progressFill');
const message = document.getElementById('message');

// --- Event Listeners ---
document.addEventListener('DOMContentLoaded', () => {
    converterForm.addEventListener('submit', handleFormSubmit);
    docUrlInput.addEventListener('input', handleUrlValidation);
    setupMessageAutoHide();
});

/**
 * Handles the main form submission event.
 * @param {Event} e The form submission event.
 */
async function handleFormSubmit(e) {
    e.preventDefault();
    const docUrl = docUrlInput.value.trim();
    const brandName = brandNameInput.value.trim();

    if (!docUrl || !isValidGoogleDocUrl(docUrl)) {
        showMessage('Please enter a valid Google Docs URL.', 'error');
        docUrlInput.focus();
        return;
    }
    await convertDocument(docUrl, brandName);
}

/**
 * Main function to call the backend and handle the conversion process.
 * @param {string} docUrl The URL of the Google Doc.
 * @param {string} brandName The optional custom name for the PDF.
 */
async function convertDocument(docUrl, brandName) {
    setLoadingState(true);
    try {
        const response = await fetch(CLOUD_FUNCTION_URL, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ docUrl, brandName }),
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(errorText || `Server error: ${response.status}`);
        }

        const blob = await response.blob();
        const filename = (brandName || 'document').replace(/[^a-zA-Z0-9]/g, '_') + '.pdf';
        downloadFile(blob, filename);

        showMessage('PDF generated successfully! ✨', 'success');
        resetForm();

    } catch (error) {
        console.error('Conversion failed:', error);
        showMessage(`Conversion failed: ${error.message}`, 'error');
    } finally {
        setLoadingState(false);
    }
}

// --- UI Helper Functions ---

/**
 * Toggles the UI loading state (spinner, button text, etc.).
 * @param {boolean} isLoading Whether to enter the loading state.
 */
function setLoadingState(isLoading) {
    if (isLoading) {
        convertBtn.disabled = true;
        convertBtn.textContent = 'Converting...';
        loading.classList.add('show');
        progressBar.classList.add('show');
        simulateProgress();
        hideMessage();
    } else {
        convertBtn.disabled = false;
        convertBtn.textContent = 'Convert to PDF';
        loading.classList.remove('show');
        progressBar.classList.remove('show');
        progressFill.style.width = '0%';
    }
}

/** Animates the progress bar to give user feedback. */
function simulateProgress() {
    let width = 0;
    const interval = setInterval(() => {
        if (width >= 95) clearInterval(interval);
        else {
            width += 5 + Math.random() * 10;
            progressFill.style.width = Math.min(width, 95) + '%';
        }
    }, 250);
}

/**
 * Creates a link and clicks it to trigger a file download.
 * @param {Blob} blob The file data to download.
 * @param {string} filename The name for the downloaded file.
 */
function downloadFile(blob, filename) {
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.style.display = 'none';
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    window.URL.revokeObjectURL(url);
    document.body.removeChild(a);
}

/**
 * Validates the input URL in real-time and provides visual feedback.
 * @param {Event} e The input event.
 */
function handleUrlValidation(e) {
    const url = e.target.value.trim();
    if (!url) {
        resetInputStyling(e.target);
        return;
    }
    if (isValidGoogleDocUrl(url)) {
        e.target.style.borderColor = '#28a745'; // Green for valid
        hideMessage();
    } else {
        e.target.style.borderColor = '#dc3545'; // Red for invalid
    }
}

/** Resets input field styling to default. */
function resetInputStyling(input) {
    input.style.borderColor = '#e1e5e9';
}

/** Resets the form to its initial state. */
function resetForm() {
    converterForm.reset();
    resetInputStyling(docUrlInput);
}

/**
 * Validates if a string is a proper Google Docs URL.
 * @param {string} url The URL to validate.
 * @returns {boolean}
 */
function isValidGoogleDocUrl(url) {
    return /^https:\/\/docs\.google\.com\/document\/d\/[a-zA-Z0-9-_]+/.test(url);
}

/** Displays a status message to the user. */
function showMessage(text, type) {
    message.textContent = text;
    message.className = `message show ${type}`;
}

/** Hides the status message. */
function hideMessage() {
    message.classList.remove('show');
}

/** Sets up a listener to automatically hide messages after 5 seconds. */
function setupMessageAutoHide() {
    let timeout;
    const observer = new MutationObserver(() => {
        if (message.classList.contains('show')) {
            clearTimeout(timeout);
            timeout = setTimeout(() => hideMessage(), 5000);
        }
    });
    observer.observe(message, { attributes: true, attributeFilter: ['class'] });
}