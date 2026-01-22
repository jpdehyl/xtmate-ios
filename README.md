# XtMate iOS

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17.0+-blue.svg" alt="iOS 17.0+">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Xcode-15.0+-blue.svg" alt="Xcode 15.0+">
  <img src="https://img.shields.io/badge/SwiftUI-Yes-green.svg" alt="SwiftUI">
</p>

**XtMate iOS** is a professional field-optimized mobile app for Project Managers to capture insurance claims data quickly and efficiently. Built with SwiftUI and designed for one-handed operation in challenging field conditions.

## ✨ Features

### 🏠 Enhanced Dashboard
- **Status Cards** - Quick overview of claims (Total, In Progress, Completed)
- **Smart Filtering** - Filter by type, status, sync state
- **Real-time Search** - Find claims by number, address, or insured name
- **Quick Actions** - Sync, call, navigate directly from claim cards

### 📱 LiDAR Room Scanning
- Capture room dimensions using iPhone/iPad Pro LiDAR sensor
- Generate isometric AI renderings via Gemini AI
- Automatic square footage calculation
- Cloud sync to web platform

### 🏷️ Voice-First Damage Tagging
- Large touch targets (56-72pt) optimized for field use
- Voice input for hands-free operation
- Quick damage categorization (water, fire, mold, structural, etc.)
- Material tracking with quantity and cost estimates

### 📊 Preliminary Reports
- Professional PDF generation with company branding
- Room-by-room damage breakdown
- Material cost estimates
- Square footage summaries
- Email/share directly from the app

### ☁️ Cloud Sync
- Automatic background sync to web platform
- Offline-first architecture
- Pending sync indicators
- Pull-to-refresh manual sync

### 🎨 Professional UI/UX
- **Paul Davis branding** - Red (#E31C23), Dark (#1C1C1E), Cream (#F5F1E8)
- **One-handed operation** - Bottom sheet actions, accessible buttons
- **Dark mode support** - Fully optimized for low-light field conditions
- **Onboarding flow** - First-time user guidance

## 🚀 Getting Started

### Prerequisites

- **Xcode 15.0+**
- **iOS 17.0+** deployment target
- **Swift 5.9+**
- **LiDAR-enabled device** (iPhone 12 Pro+ or iPad Pro) for room scanning features

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/xtmate-ios.git
   cd xtmate-ios
   ```

2. **Configure API Keys**
   
   ⚠️ **IMPORTANT**: API keys should NEVER be committed to Git.
   
   **Option 1: Info.plist (Recommended for Development)**
   
   Add these keys to your app target's `Info.plist`:
   ```xml
   <key>GEMINI_API_KEY</key>
   <string>YOUR_GEMINI_API_KEY_HERE</string>
   <key>ANTHROPIC_API_KEY</key>
   <string>YOUR_ANTHROPIC_API_KEY_HERE</string>
   ```
   
   **Option 2: Environment Variables**
   
   In Xcode: Edit Scheme → Run → Arguments → Environment Variables
   - Add `GEMINI_API_KEY` with your key value
   - Add `ANTHROPIC_API_KEY` with your key value
   
   **Option 3: .xcconfig file (Ignored by Git)**
   
   Create `Secrets.xcconfig` in the project root:
   ```
   GEMINI_API_KEY = your_gemini_key_here
   ANTHROPIC_API_KEY = your_anthropic_key_here
   ```
   
   See [README-APIKeys.md](README-APIKeys.md) for detailed configuration instructions.

3. **Open in Xcode**
   ```bash
   open XtMate.xcodeproj
   # or if using Swift Package Manager
   open Package.swift
   ```

4. **Build and Run**
   - Select your target device (LiDAR-enabled for full features)
   - Press `⌘ + R` to build and run

## 🏗️ Architecture

### Tech Stack
- **SwiftUI** - Modern declarative UI framework
- **Swift Concurrency** - async/await for network and background tasks
- **ARKit & RoomPlan** - LiDAR scanning and room capture
- **Core Data / SwiftData** - Local persistence
- **URLSession** - REST API communication with web platform
- **PDFKit** - Professional report generation

### Project Structure
```
XtMate/
├── App/                    # App entry point and configuration
├── Views/                  # SwiftUI views
│   ├── Onboarding/        # First-time user experience
│   ├── Dashboard/         # Home screen and claim list
│   ├── Claims/            # Claim detail and management
│   ├── Rooms/             # Room scanning and detail
│   ├── Damage/            # Damage tagging and entry
│   └── Reports/           # PDF report generation
├── ViewModels/            # Business logic and state management
├── Models/                # Data models
├── Services/              # API, sync, and external service handlers
├── Utilities/             # Helpers, extensions, and constants
└── Resources/             # Assets, themes, and configuration files
```

### Key Components

**APIKeys.swift** - Secure API key management (never hardcode keys!)

**PaulDavisTheme.swift** - Centralized branding and design system

**OnboardingView.swift** - First-launch user guidance

**HomeDashboardView.swift** - Enhanced dashboard with filtering and search

**ClaimDetailView.swift** - Comprehensive claim overview

**PreliminaryReportView.swift** - PDF report generation

## 🔗 Web Platform Integration

The iOS app syncs data with the XtMate web platform:
- **Development**: `http://localhost:3001/api`
- **Production**: `https://xtmate.vercel.app/api`

### API Endpoints
- `POST /claims` - Create/update claims
- `POST /rooms` - Upload room scans
- `POST /damage` - Submit damage entries
- `GET /claims/:id` - Fetch claim details
- `POST /sync` - Batch sync pending data

## 🧪 Testing

### Running Tests
```bash
# Run all tests
⌘ + U in Xcode

# Run specific test
⌘ + Ctrl + U on test method
```

### Test Structure
- Unit tests for ViewModels and business logic
- UI tests for critical user flows
- Mock API responses for offline testing

## 📱 Deployment

### TestFlight (Beta)
1. Archive the app: Product → Archive
2. Upload to App Store Connect
3. Create new TestFlight build
4. Add internal/external testers

### App Store
1. Ensure all API keys are loaded from server (not Info.plist)
2. Update version and build number
3. Archive and upload to App Store Connect
4. Submit for review with App Privacy details

## 🤝 Contributing

We welcome contributions! Here's how to get started:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style
- Follow Swift API Design Guidelines
- Use SwiftLint for consistent formatting
- Write meaningful commit messages
- Add tests for new features

## 📄 License

This project is proprietary and confidential. Unauthorized copying, distribution, or use is strictly prohibited.

## 🔐 Security

- **Never commit API keys** - Use Info.plist or environment variables
- **Never commit secrets** - Add sensitive files to `.gitignore`
- **Review dependencies** - Audit third-party packages regularly
- **Report vulnerabilities** - Contact security@xtmate.com

## 📞 Support

- **Documentation**: [ENHANCED_WORKFLOW.md](ENHANCED_WORKFLOW.md)
- **API Keys Setup**: [README-APIKeys.md](README-APIKeys.md)
- **Issues**: [GitHub Issues](https://github.com/YOUR_USERNAME/xtmate-ios/issues)
- **Email**: support@xtmate.com

## 🗺️ Roadmap

- [ ] Offline photo capture and sync
- [ ] Advanced damage categorization with AI
- [ ] Multi-claim batch operations
- [ ] Integration with third-party estimating tools
- [ ] Apple Watch companion app for quick voice notes
- [ ] iPad split-view optimization

---

**Built with ❤️ for field professionals**
