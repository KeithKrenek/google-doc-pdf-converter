#!/usr/bin/env python3
"""
Test script for Google Doc to PDF Converter
Tests various document structures and edge cases
"""

import requests
import json
import sys
import time
from datetime import datetime

# Test configuration
SERVICE_URL = "http://localhost:8080"  # Change to your Cloud Run URL for production testing

# Test documents (replace with actual Google Doc URLs)
TEST_DOCS = {
    "simple": {
        "url": "https://docs.google.com/document/d/YOUR_SIMPLE_DOC_ID/edit",
        "company": "Simple Test Company"
    },
    "complex": {
        "url": "https://docs.google.com/document/d/YOUR_COMPLEX_DOC_ID/edit",
        "company": "Complex Test Company"
    },
    "with_tables": {
        "url": "https://docs.google.com/document/d/YOUR_TABLE_DOC_ID/edit",
        "company": "Table Test Company"
    }
}


def print_header(text):
    """Print formatted header"""
    print("\n" + "=" * 60)
    print(f"  {text}")
    print("=" * 60)


def test_health_check():
    """Test the health endpoint"""
    print_header("Testing Health Endpoint")

    try:
        response = requests.get(f"{SERVICE_URL}/health", timeout=10)

        print(f"Status Code: {response.status_code}")

        if response.status_code == 200:
            data = response.json()
            print("✅ Health check passed")
            print(f"   Service: {data.get('service', 'unknown')}")
            print(f"   Version: {data.get('version', 'unknown')}")
            print(f"   Status: {data.get('status', 'unknown')}")
            return True
        else:
            print(f"❌ Health check failed: {response.status_code}")
            return False

    except Exception as e:
        print(f"❌ Health check error: {e}")
        return False


def test_conversion(doc_url, company_name, test_name="Test"):
    """Test document conversion"""
    print_header(f"Testing Conversion: {test_name}")

    payload = {
        "doc_url": doc_url,
        "company_name": company_name,
        "use_cover_image": True
    }

    print(f"Document URL: {doc_url}")
    print(f"Company Name: {company_name}")
    print("Sending request...")

    try:
        start_time = time.time()

        response = requests.post(
            f"{SERVICE_URL}/convert",
            json=payload,
            timeout=300  # 5 minute timeout
        )

        elapsed_time = time.time() - start_time

        print(f"\nStatus Code: {response.status_code}")
        print(f"Processing Time: {elapsed_time:.2f} seconds")

        if response.status_code == 200:
            data = response.json()

            if data.get('success'):
                print("✅ Conversion successful!")
                print(f"   Document Title: {data.get('document_title', 'N/A')}")
                print(f"   PDF Filename: {data.get('pdf_filename', 'N/A')}")
                print(f"   Elements Processed: {data.get('elements_processed', 0)}")
                print(f"   Download URL: {data.get('download_url', 'N/A')}")
                return True
            else:
                print(f"❌ Conversion failed: {data.get('error', 'Unknown error')}")
                return False
        else:
            print(f"❌ Request failed: {response.status_code}")
            try:
                error_data = response.json()
                print(f"   Error: {error_data.get('error', 'Unknown error')}")
            except:
                print(f"   Response: {response.text[:200]}")
            return False

    except requests.Timeout:
        print("❌ Request timeout (>5 minutes)")
        return False
    except Exception as e:
        print(f"❌ Conversion error: {e}")
        return False


def test_invalid_url():
    """Test with invalid URL"""
    print_header("Testing Invalid URL Handling")

    payload = {
        "doc_url": "https://invalid-url.com/document/123",
        "company_name": "Test Company"
    }

    try:
        response = requests.post(
            f"{SERVICE_URL}/convert",
            json=payload,
            timeout=30
        )

        if response.status_code == 400:
            print("✅ Invalid URL correctly rejected")
            return True
        else:
            print(f"❌ Expected 400, got {response.status_code}")
            return False

    except Exception as e:
        print(f"❌ Error: {e}")
        return False


def test_missing_parameters():
    """Test with missing required parameters"""
    print_header("Testing Missing Parameters")

    # Missing doc_url
    payload = {"company_name": "Test Company"}

    try:
        response = requests.post(
            f"{SERVICE_URL}/convert",
            json=payload,
            timeout=30
        )

        if response.status_code == 400:
            print("✅ Missing parameters correctly rejected")
            return True
        else:
            print(f"❌ Expected 400, got {response.status_code}")
            return False

    except Exception as e:
        print(f"❌ Error: {e}")
        return False


def run_all_tests():
    """Run all tests"""
    print_header("Google Doc to PDF Converter - Test Suite")
    print(f"Service URL: {SERVICE_URL}")
    print(f"Test Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    results = {
        "total": 0,
        "passed": 0,
        "failed": 0
    }

    # Test 1: Health check
    results["total"] += 1
    if test_health_check():
        results["passed"] += 1
    else:
        results["failed"] += 1
        print("\n⚠️  Service health check failed. Stopping tests.")
        return results

    # Test 2: Invalid URL
    results["total"] += 1
    if test_invalid_url():
        results["passed"] += 1
    else:
        results["failed"] += 1

    # Test 3: Missing parameters
    results["total"] += 1
    if test_missing_parameters():
        results["passed"] += 1
    else:
        results["failed"] += 1

    # Test 4+: Document conversions
    print("\n" + "=" * 60)
    print("Note: Document conversion tests require valid Google Doc URLs")
    print("Update TEST_DOCS dictionary with your test document URLs")
    print("=" * 60)

    for test_name, test_config in TEST_DOCS.items():
        if "YOUR_" not in test_config["url"]:  # Skip placeholder URLs
            results["total"] += 1
            if test_conversion(test_config["url"], test_config["company"], test_name):
                results["passed"] += 1
            else:
                results["failed"] += 1

    return results


def print_summary(results):
    """Print test summary"""
    print_header("Test Summary")

    print(f"Total Tests: {results['total']}")
    print(f"✅ Passed: {results['passed']}")
    print(f"❌ Failed: {results['failed']}")

    if results['failed'] == 0:
        print("\n🎉 All tests passed!")
    else:
        print(f"\n⚠️  {results['failed']} test(s) failed")

    success_rate = (results['passed'] / results['total'] * 100) if results['total'] > 0 else 0
    print(f"Success Rate: {success_rate:.1f}%")


def main():
    """Main test runner"""
    if len(sys.argv) > 1:
        global SERVICE_URL
        SERVICE_URL = sys.argv[1]
        print(f"Using custom service URL: {SERVICE_URL}")

    results = run_all_tests()
    print_summary(results)

    # Exit with non-zero code if any tests failed
    sys.exit(0 if results['failed'] == 0 else 1)


if __name__ == "__main__":
    main()
