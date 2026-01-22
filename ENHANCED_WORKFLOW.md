# XtMate iOS - Enhanced PM Workflow

## 🎯 Overview

The XtMate iOS app has been redesigned with a **professional, field-optimized workflow** that helps Project Managers capture claims data quickly and efficiently. Every screen is designed for **one-handed operation**, **large touch targets** (56-72pt), and **voice-first input** for use in challenging field conditions.

## 🚀 New UI Components

### 1. **OnboardingView.swift**
**First-time user experience**

- 3-slide carousel explaining key workflows
- Skip option for returning users
- Auto-shows on first launch (using `@AppStorage`)
- Beautiful gradient backgrounds with animated icons

**Flow:**
```
Slide 1: Scan Rooms with LiDAR
Slide 2: Tag Damage & Materials  
Slide 3: Sync to Web Platform
→ "Let's Go" button completes onboarding
```

---

### 2. **HomeDashboardView.swift**
**Enhanced home screen replacing simple list**

**Key Features:**
- **Status Cards** - Quick stats (Total, In Progress, Completed)
- **Urgent Banner** - Highlights pending syncs with action button
- **Filter Pills** - All, Insurance, Private, Pending Sync, Active
- **Search** - By claim #, address, or insured name
- **Enhanced Claim Cards** with:
  - Loss type icon with color coding
  - Sync status badge
  - Property address
  - Room/damage/square footage stats
  - Quick actions (Sync, Call, Navigate)
  
**Pull to Refresh:** Syncs all pending claims

**Navigation:** Taps open `ClaimDetailView`

---

### 3. **ClaimDetailView.swift**
**Comprehensive claim detail with collapsible sections**

**Sections:**
1. **Property Hero** - Visual floor plan showing all rooms (2D/3D toggle)
2. **Claim Info Card** - Collapsible card with insured/adjuster contact
3. **Rooms List** - Each room shows:
   - Category icon
   - Square footage
   - Damage count badge
   - "Has scope" indicator
   - Quick action button to add damage
4. **Assignments Row** - E → R → C workflow visualization
5. **Quick Actions Grid** - Take Photos, Add Damage, Generate Scope, View Report

**Floating Action Button:** 
- Shows "Scan Room" when no rooms exist
- 72pt touch target for easy one-handed access

**Toolbar Actions:**
- Sync to Web
- Export PDF
- Edit Claim Info
- Delete Claim

---

### 4. **PostScanQuickActionsView.swift**
**Appears immediately after room scan**

**Purpose:** Guide PMs to next steps without friction

**Quick Actions (multi-select):**
- 📸 Take Photos
- ⚠️ Add Damage
- 🎨 Tag Materials
- 🎤 Voice Note

**Features:**
- Success animation with room info (name, SF, category)
- Large action cards (130pt height)
- Visual selection state with checkmarks
- "Continue with X actions" dynamic button
- "Skip for Now" option

**Flow:**
```
Room Scan Complete
→ Quick Actions Sheet appears
→ Select desired actions
→ Execute in sequence
→ Return to Claim Detail
```

---

### 5. **QuickDamageEntryView.swift**
**Fast damage annotation - 10 seconds or less**

**Design Principles:**
- **72pt touch targets** (perfect for gloved hands)
- **Visual icons** minimize reading
- **Color-coded** damage types
- **Voice note option** for hands-free

**Sections:**
1. **Damage Type** - 6 types in 3-column grid (Water, Fire, Smoke, Mold, Impact, Wind)
2. **Severity** - 3 options (Low, Moderate, High) with colored indicators
3. **Affected Surfaces** - Multi-select (Floor, Wall, Ceiling)
4. **Documentation** - Photo and voice note buttons
5. **Optional Notes** - Text editor for additional details

**Validation:** Requires at least one affected surface

---

### 6. **MaterialTaggingView.swift**
**Smart material selection with AI suggestions**

**Features:**
- **Smart Suggestions** - AI predicts materials based on room type
  - Kitchen → Tile, LVP, Hardwood
  - Bathroom → Tile, LVP, Vinyl Sheet
  - Bedroom → Carpet, Hardwood, Laminate
- **Suggested chips** with sparkle icon
- **Material cards** in 2-column grid
- **Skip option** - Can tag materials later

**Sections:**
1. Floor Material (8 options)
2. Wall Finish (7 options)
3. Ceiling Finish (6 options)

**Smart Defaults Example:**
```swift
Kitchen Floor → [Tile, LVP, Hardwood]
Bathroom Walls → [Tile, Painted Drywall]
Basement Ceiling → [Drop Ceiling, Smooth]
```

---

## 📋 Complete User Flows

### **Flow 1: New User First Launch**
```
App Launch
→ OnboardingView (3 slides)
→ "Let's Go" button
→ HomeDashboardView
→ "+ New Claim" button
→ NewClaimSheet
→ Claim Created
→ ClaimDetailView
→ "Scan Room" FAB
→ RoomCaptureView (LiDAR)
→ PostScanQuickActionsView
→ Select actions (Photos, Damage, Materials)
→ Execute in sequence
→ Return to ClaimDetailView
```

### **Flow 2: Returning User - Quick Claim**
```
App Launch
→ HomeDashboardView (skip onboarding)
→ Pull to Refresh (sync all)
→ Search for claim
→ Tap claim card
→ ClaimDetailView
→ Tap room card
→ RoomDetailView
→ Add damage
→ QuickDamageEntryView
→ Save
→ Take photo
→ Return to room
```

### **Flow 3: Field Capture Workflow**
```
ClaimDetailView
→ "Scan Room" FAB
→ RoomCaptureView
→ Done Scanning
→ PostScanQuickActionsView appears
→ Select "Take Photos" + "Add Damage" + "Tag Materials"
→ Photo Capture
→ QuickDamageEntryView
→ Select Water + Moderate + Floor + Wall
→ Voice Note: "Standing water about 2 inches deep"
→ Save
→ MaterialTaggingView
→ Suggested: Tile (selected)
→ Wall: Painted Drywall (selected)
→ Ceiling: Popcorn (selected)
→ Save & Continue
→ Return to ClaimDetailView
→ Room now shows: 1 damage, materials tagged, X photos
```

---

## 🎨 Design System Enhancements

### **Touch Targets**
- **Minimum:** 56pt (per Apple HIG)
- **Preferred:** 72pt for primary actions
- **Spacing:** 16pt between interactive elements

### **High Contrast Mode**
- WCAG AAA compliance for outdoor readability
- Bold text weights (semibold+)
- Strong borders and shadows

### **Voice-First**
- 🎤 Voice note button on every input screen
- Speech-to-text for notes
- Hands-free operation

### **Color Coding**
- **Loss Types:** Blue (water), Red (fire), Purple (storm), etc.
- **Damage Severity:** Yellow (low), Orange (moderate), Red (high)
- **Status:** Gray (pending), Orange (active), Green (complete)

---

## 🔧 Implementation Status

### ✅ **Phase 1: Complete**
- [x] OnboardingView
- [x] HomeDashboardView with filters and search
- [x] ClaimDetailView with collapsible sections
- [x] PostScanQuickActionsView
- [x] QuickDamageEntryView
- [x] MaterialTaggingView
- [x] CoreModels.swift with all data structures

### 🚧 **Phase 2: Integration Needed**
- [ ] Connect RoomCaptureView → PostScanQuickActionsView
- [ ] Wire up photo capture flow
- [ ] Implement voice note recording
- [ ] Persistence layer (Core Data or SwiftData)
- [ ] Sync service integration

### 🎯 **Phase 3: Advanced Features**
- [ ] Offline mode with queue visualization
- [ ] Dashboard analytics widgets
- [ ] Siri Shortcuts integration
- [ ] Home screen widget
- [ ] Apple Watch companion app

---

## 📱 Testing Notes

### **Simulator Testing**
```swift
// Mock data is included in view models for testing
// Run in simulator:
1. Clean build folder (Cmd+Shift+K)
2. Build and run (Cmd+R)
3. Navigate through flows
4. Test filters, search, and actions
```

### **Device Testing (Required)**
- **LiDAR scanning** requires iPhone 12 Pro+ or iPad Pro
- **Voice notes** need microphone permissions
- **Photo capture** needs camera permissions

### **Field Testing Checklist**
- [ ] One-handed operation while standing
- [ ] Readable in bright sunlight
- [ ] Usable with gloves
- [ ] Voice input works in noisy environments
- [ ] Works offline (no crash)
- [ ] Sync resumes when connected

---

## 🔄 Migration from Old UI

### **Old Flow (Simple List)**
```swift
// OLD: ContentView with basic list
List(estimates) { estimate in
    NavigationLink(destination: EstimateDetailView(estimate: estimate)) {
        Text(estimate.name)
    }
}
```

### **New Flow (Enhanced Dashboard)**
```swift
// NEW: HomeDashboardView with rich UI
HomeDashboardView()
    // Includes stats, filters, search, enhanced cards
```

### **Update XtMateApp.swift**
```swift
@main
struct XtMateApp: App {
    var body: some Scene {
        WindowGroup {
            // OLD: ContentView()
            // NEW:
            HomeDashboardView()
        }
    }
}
```

---

## 🎓 Usage Tips for PMs

### **Speed Tips**
1. **Voice First:** Use voice notes instead of typing
2. **Bulk Actions:** Select multiple quick actions after scanning
3. **Skip Materials:** Tag materials later if in a hurry
4. **Offline Mode:** Keep working, sync automatically when connected

### **Accuracy Tips**
1. **Complete Scans:** Walk entire perimeter for accurate dimensions
2. **Mark Damage Immediately:** Capture while you're looking at it
3. **Photos Before Leaving:** Hard to come back later
4. **Voice Details:** Describe what you see (camera can't capture everything)

### **Efficiency Tips**
1. **Scan All Rooms First:** Then annotate damage
2. **Use Suggested Materials:** AI predictions are usually right
3. **Review Before Sync:** Catch errors while on-site
4. **Batch Sync:** Sync all claims at once when back in truck

---

## 📞 Support & Feedback

Report issues or suggest improvements:
- GitHub Issues: [xtmate/mobile](https://github.com/xtmate/mobile/issues)
- Slack: #mobile-app channel
- Email: support@xtmate.com

---

**Last Updated:** January 16, 2026
**Version:** 0.3.0 (Enhanced PM Workflow)
