# Setting Up Credentials for MindX

This document explains how to set up the various credentials needed for the MindX system.

## Google Credentials

Two credential files need to be properly set up:

1. **Root Google Credentials** (`google-credentials.json`)
   - Used for general Google API access
   - Template is provided, but you need to fill in your own credentials

2. **Backend Google Credentials** (`backend/google-credentials.json`)
   - Service account credentials for Firebase and other backend services
   - Template is provided, but you need to fill in your own service account details

### How to Set Up

1. **OAuth Credentials**:
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Navigate to "APIs & Services" > "Credentials"
   - Create OAuth 2.0 Client ID
   - Download the JSON and save as `google-credentials.json`

2. **Service Account**:
   - In Google Cloud Console, navigate to "IAM & Admin" > "Service Accounts"
   - Create a new service account with appropriate permissions
   - Generate a key and download the JSON
   - Save as `backend/google-credentials.json`

## Security Notes

- **NEVER commit real credentials to GitHub**
- Credential files are ignored in `.gitignore`
- Only template files with placeholder values are committed
- Each developer should create their own credentials locally
- For production deployment, use environment variables or secure secrets management" 