# CLAUDE.md - XtMate iOS Project Knowledge Base

## Mission Statement

**Crush the bottlenecks in property restoration claims processing.**

The iOS app captures room geometry via LiDAR, lets PMs annotate damage, tag materials, and syncs to the xtmate web platform for AI scope generation.

---

## Current State (Phase 2 Complete)

### What Works
- RoomPlan LiDAR capture with Done/Cancel buttons
- Room dimension calculation from CapturedRoom geometry
- Auto room type detection (bathroom, kitchen, bedroom, etc.)
- Room naming and category editing
- Estimate management (create, list, delete)
- Local persistence via UserDefaults + Codable
- Basic UI with room cards showing dimensions

### Tech Stack
- **Language:** Swift 5.9+
- **UI:** SwiftUI
- **Room Capture:** RoomPlan framework (requires LiDAR device)
- **Persistence:** UserDefaults with Codable (move to Core Data later)
- **Target:** iOS 16+ / iPadOS 16+

---

## Project Structure

```
XtMate/
├── XtMateApp.swift          # App entry point
├── ContentView.swift        # Main UI + all views + models
├── Info.plist               # Permissions (camera, etc.)
└── Assets.xcassets/         # App icons, colors
```

**Note:** All code is currently in ContentView.swift. As features grow, extract into separate files.

---

## Data Models

### Estimate
```swift
struct Estimate: Identifiable, Codable {
    let id: UUID
    var name: String
    var claimNumber: String?
    var policyNumber: String?
    var insuredName: String?
    var propertyAddress: String?
    var causeOfLoss: String
    var status: EstimateStatus  // draft, inProgress, pendingSync, synced, complete
    var rooms: [Room]
    var createdAt: Date
    var syncedAt: Date?
}
```

### Room
```swift
struct Room: Identifiable, Codable {
    let id: UUID
    var name: String
    var category: RoomCategory  // kitchen, bathroom, bedroom, etc.

    // Dimensions in INCHES (converted from meters)
    let lengthIn: Double
    let widthIn: Double
    let heightIn: Double

    // From RoomPlan
    let wallCount: Int
    let doorCount: Int
    let windowCount: Int

    // Calculated properties
    var squareFeet: Double      // lengthIn * widthIn / 144
    var perimeterLf: Double     // (L + W) * 2 / 12
    var wallSf: Double          // perimeterLf * height
    var ceilingSf: Double       // same as squareFeet
}
```

### RoomCategory Enum
```swift
enum RoomCategory: String, Codable, CaseIterable {
    case kitchen, bathroom, bedroom, livingRoom, diningRoom
    case office, laundry, garage, basement, hallway, closet, other

    var icon: String  // SF Symbol name
}
```

---

## Key Patterns

### RoomPlan Integration
```swift
// UIKit view wrapped for SwiftUI
struct RoomCaptureViewRepresentable: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onRoomCaptured: (CapturedRoom) -> Void

    // Uses Coordinator pattern for delegate
}

class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate {
    // Owns RoomCaptureView
    // Implements captureView(shouldPresent:error:) -> Bool
    // Implements captureView(didPresent:error:) for result
}
```

### Dimension Calculation
```swift
// CapturedRoom provides:
// - walls: [CapturedRoom.Wall] with transform + dimensions (meters)
// - doors: [CapturedRoom.Door]
// - windows: [CapturedRoom.Window]
// - objects: [CapturedRoom.Object] for appliance detection

// Bounding box from wall positions:
let x = wall.transform.columns.3.x  // position
let dimensions = wall.dimensions     // simd_float3 in meters
// Convert meters to inches: * 39.3701
```

### Room Type Detection
```swift
// Check room.objects for category hints:
// .toilet, .bathtub, .sink -> bathroom
// .oven, .refrigerator, .dishwasher -> kitchen
// .bed -> bedroom
// .sofa -> livingRoom
// .washerDryer -> laundry
```

---

## API Integration (Phase 3)

### Web API Base URL
```
Production: https://xtmate.vercel.app/api
Local dev:  http://localhost:3000/api
```

### Sync Endpoint
```
POST /api/sync/capture
Content-Type: application/json
Authorization: Bearer <clerk_jwt>

{
  "estimate": {
    "id": "uuid",
    "name": "string",
    "claimNumber": "string",
    "rooms": [
      {
        "id": "uuid",
        "name": "string",
        "category": "kitchen",
        "lengthIn": 144,
        "widthIn": 120,
        "heightIn": 96,
        "floorMaterial": "LVP",
        "wallMaterial": "Orange Peel",
        "ceilingMaterial": "Smooth",
        "annotations": [...]
      }
    ]
  }
}
```

---

## Phase 3 TODO (in prd.json)

1. **P3-001** Floor selector on room cards
2. **P3-002** Floor material tagging
3. **P3-003** Wall material tagging
4. **P3-004** Ceiling material tagging
5. **P3-005** Photo capture for rooms
6. **P3-006** Damage annotation model
7. **P3-007** Add damage annotation UI
8. **P3-008** Display annotations on room card
9. **P3-009** Voice memo for annotations
10. **P3-010** Web API sync service
11. **P3-011** Offline mode with sync queue
12. **P3-012** Duplicate room feature

---

## UX Guidelines

### Mobile-First Principles
- Large touch targets (44pt minimum)
- One-handed operation when possible
- High contrast for outdoor/bright conditions
- Auto-save constantly
- Never lose captured data

### Field Work Context
- PM has dirty/gloved hands
- May be in crawlspace or attic
- Limited time per room
- Voice input preferred over typing
- Quick photo capture essential

---

## Testing Notes

### Simulator Limitations
- RoomPlan requires actual LiDAR device
- Use iPhone 12 Pro+ or iPad Pro for testing
- Mock data can test UI without device

### Key Flows to Test
1. Create estimate -> Capture room -> See dimensions
2. Edit room name/category
3. Delete room from estimate
4. Multiple rooms per estimate
5. Persistence across app restart

---

## Common Issues

### RoomCaptureView Crashes
**Problem:** App crashes if delegate not properly retained
**Solution:** Use Coordinator pattern with UIViewControllerRepresentable

### Dimension Accuracy
**Problem:** Dimensions seem off
**Solution:** Ensure meters -> inches conversion (* 39.3701)
**Gotcha:** wall.dimensions is size, not position

### Objects Not Detected
**Problem:** Room type defaults to "Other"
**Solution:** Objects require good scanning of entire room
**Workaround:** Manual category picker

---

## Xcode Settings

### Required Capabilities
- Camera (for photo capture)
- Microphone (for voice memos)
- ARKit (implied by RoomPlan)

### Info.plist Keys
```xml
<key>NSCameraUsageDescription</key>
<string>XtMate uses the camera to capture room geometry and damage photos</string>

<key>NSMicrophoneUsageDescription</key>
<string>XtMate uses the microphone for voice notes on damage annotations</string>
```

### Build Settings
- iOS Deployment Target: 16.0
- Swift Language Version: 5.0

---

## Quick Commands

```bash
# Open project in Xcode
open ~/Documents/xtmate/mobile/XtMate/XtMate.xcodeproj

# Build from command line
xcodebuild -project XtMate.xcodeproj -scheme XtMate -sdk iphoneos

# Run tests
xcodebuild test -project XtMate.xcodeproj -scheme XtMate -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

---

*Last updated: January 13, 2026*
*XtMate iOS v0.2 - Phase 2 Complete*
