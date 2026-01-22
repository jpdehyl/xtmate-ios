# API Key Configuration

API keys should NEVER be hardcoded in source files.

## Development Setup

### Option 1: Info.plist (Recommended)
Add these keys to your target's Info.plist:

```xml
<key>GEMINI_API_KEY</key>
<string>YOUR_GEMINI_API_KEY_HERE</string>
<key>ANTHROPIC_API_KEY</key>
<string>YOUR_ANTHROPIC_API_KEY_HERE</string>
```

### Option 2: Xcode Environment Variables
1. Edit Scheme → Run → Arguments → Environment Variables
2. Add `GEMINI_API_KEY` with your key value

### Option 3: .xcconfig files
Create a `Secrets.xcconfig` file (add to .gitignore):
```
GEMINI_API_KEY = your_key_here
ANTHROPIC_API_KEY = your_key_here
```

## Production
In production, fetch keys from a secure server endpoint at app startup.
Never ship API keys in the app bundle.

## Current Keys Needed
- `GEMINI_API_KEY` - For isometric room rendering
- `ANTHROPIC_API_KEY` - For AI scope generation (future)
