# PRD-REFACTORING: XtMate iOS Codebase Refactoring

**Document Version:** 1.0
**Created:** January 16, 2026
**Author:** Engineering Team
**Status:** Draft
**Methodology:** RALPH (Requirements Analysis for LLM-Powered Handoff)

---

## 1. Problem Statement

### Current State

The XtMate iOS codebase has accumulated significant technical debt that impedes developer productivity, increases bug risk, and complicates feature development. Key issues include:

1. **Monolithic ContentView.swift (5,065 lines)**
   - Contains models, views, view models, services, extensions, and UI components all in one file
   - Violates Single Responsibility Principle
   - Makes code navigation and debugging extremely difficult
   - Compilation times suffer due to large file size
   - High risk of merge conflicts when multiple developers work on the app

2. **Duplicate/Conflicting Model Definitions**
   - `RoomListItem` vs `ClaimRoomListItem` (similar structures, different names)
   - `ClaimStatus` vs `EstimateStatus` (same concept, different enums)
   - `JobType` defined in both Assignment.swift and CoreModels.swift with different raw values
   - `LossType` defined in both files with different implementations

3. **Misplaced Files at Root Level**
   - `CoreModels.swift` at `/XtMateiOS/` instead of `/XtMateiOS/XtMate/Models/`
   - `OnboardingView.swift` at root instead of `/Views/`
   - `PaulDavisTheme.swift` at root instead of `/Theme/`
   - `HomeDashboardView.swift` at root instead of `/Views/`
   - `ClaimDetailView.swift` at root instead of `/Views/`
   - `MaterialTaggingView.swift` at root instead of `/Views/`
   - `QuickDamageEntryView.swift` at root instead of `/Views/`
   - `PostScanQuickActionsView.swift` at root instead of `/Views/`

4. **CoreModels.swift Excluded from Build**
   - File exists but is not included in the Xcode project's build phase
   - Contains duplicate definitions that conflict with ContentView.swift
   - Creates confusion about which models are canonical

5. **Missing Clear Architecture Pattern**
   - No consistent MVVM implementation
   - Business logic mixed with UI code
   - Services not properly abstracted
   - No clear dependency injection pattern

### Impact

- **Developer Productivity:** 40%+ time spent navigating/understanding code instead of building features
- **Bug Introduction Risk:** High due to unclear boundaries and duplicate definitions
- **Onboarding Time:** New developers require 2-3x longer to become productive
- **Feature Development:** Simple changes require understanding thousands of lines of context
- **Testing:** Virtually impossible to unit test due to tight coupling

---

## 2. Goals & Non-Goals

### Goals

1. **G1:** Reduce ContentView.swift from 5,065 lines to <500 lines (app shell only)
2. **G2:** Eliminate all duplicate model definitions with single source of truth
3. **G3:** Establish clear MVVM architecture with separation of concerns
4. **G4:** Move all misplaced files to appropriate directories
5. **G5:** Ensure 100% of Swift files are properly included in Xcode build phases
6. **G6:** Create modular, testable components
7. **G7:** Maintain full feature parity throughout refactoring (no regressions)

### Non-Goals

- Adding new features during refactoring
- Changing external API contracts with the web backend
- Migrating from UserDefaults to Core Data (separate initiative)
- Redesigning the UI/UX
- Changing the RoomPlan integration approach

---

## 3. User Stories

### US-REF-001: Extract Core Models to Dedicated Files

**As a** developer
**I want to** have each model type in its own dedicated file
**So that** I can easily find, understand, and modify data structures

**Acceptance Criteria:**
- [ ] Given a model like `Estimate`, when I search for it, then I find it in `/Models/Estimate.swift`
- [ ] Given a model file, when I open it, then it contains only that model and its extensions
- [ ] Given duplicate definitions (e.g., `JobType`), when refactoring is complete, then only one canonical definition exists
- [ ] Edge case: If a model references another model, then imports are correctly specified
- [ ] Error: If a model definition is missing required Codable conformance, then compilation fails with clear error

**Files to Create:**
```
XtMate/Models/
├── Estimate.swift           # Main estimate/claim model
├── Room.swift               # Room model with extensions
├── DamageAnnotation.swift   # Damage annotation model
├── Assignment.swift         # (already exists, consolidate enums)
├── ScopeLineItem.swift      # (already exists)
├── Material.swift           # FloorMaterial, WallMaterial, CeilingMaterial enums
├── DamageTypes.swift        # DamageType, DamageSeverity, AffectedSurface
├── StatusTypes.swift        # ClaimStatus, SyncStatus, ValidationState
├── RoomTypes.swift          # RoomCategory, FloorLevel
├── GeneratedLineItem.swift  # AI-generated line item model
└── FloorPlanModels.swift    # (already exists)
```

**Technical Notes:**
- Dependencies: None
- Data: All models must maintain Codable conformance
- Complexity: M

---

### US-REF-002: Extract Views to Dedicated Files

**As a** developer
**I want to** each major view in its own file
**So that** I can work on UI components independently without scrolling through thousands of lines

**Acceptance Criteria:**
- [ ] Given a view like `EstimateDetailView`, when I search for it, then I find it in `/Views/Estimates/EstimateDetailView.swift`
- [ ] Given a view file, when I open it, then it contains that view and any small private subviews it uses
- [ ] Given ContentView.swift after extraction, when I open it, then it contains only the app shell (<500 lines)
- [ ] Edge case: Small helper views used only by one parent can stay in parent's file
- [ ] Error: If a view references an undefined model, then compilation fails immediately

**Files to Create:**
```
XtMate/Views/
├── Estimates/
│   ├── EstimateListView.swift
│   ├── EstimateDetailView.swift
│   ├── EstimateHeaderCard.swift
│   └── EstimateRow.swift
├── Rooms/
│   ├── RoomCard.swift
│   ├── RoomEditSheet.swift
│   ├── RoomReviewView.swift
│   ├── SaveRoomSheet.swift
│   ├── SavedRoomDetailView.swift
│   ├── SavedRoomFloorPlanView.swift
│   ├── SavedRoom3DView.swift
│   └── SavedRoomStatsView.swift
├── Capture/
│   ├── RoomCaptureViewRepresentable.swift
│   ├── RoomCaptureViewController.swift
│   └── FloorPlanCanvasView.swift
├── Materials/
│   ├── MaterialPickerSheet.swift
│   ├── FloorMaterialCard.swift
│   ├── WallMaterialCard.swift
│   └── CeilingMaterialCard.swift
├── Damage/
│   ├── DamageAnnotationSheet.swift
│   └── QuickDamageEntryView.swift (move from root)
├── Scope/
│   └── ScopeCard.swift
├── Onboarding/
│   ├── OnboardingView.swift (move from root)
│   └── OnboardingPage.swift
├── Dashboard/
│   └── HomeDashboardView.swift (move from root)
├── Claims/
│   └── ClaimDetailView.swift (move from root)
└── Common/
    ├── EmptyDetailView.swift
    ├── EmptyRoomsCard.swift
    ├── QuickStat.swift
    ├── CompactBadge.swift
    ├── CompactDimension.swift
    ├── FeatureCount.swift
    ├── DimensionCard.swift
    ├── FeatureCard.swift
    └── MaterialInfoCard.swift
```

**Technical Notes:**
- Dependencies: US-REF-001 (models must be extracted first)
- Data: Views reference models via import
- Complexity: L

---

### US-REF-003: Extract ViewModels to Dedicated Files

**As a** developer
**I want to** have view models separated from views
**So that** business logic can be tested independently and views remain declarative

**Acceptance Criteria:**
- [ ] Given `EstimateStore`, when I look for it, then I find it in `/ViewModels/EstimateStore.swift`
- [ ] Given a view model, when I examine it, then it contains only business logic, no UI code
- [ ] Given a view model, when I want to test it, then I can instantiate it without UI dependencies
- [ ] Edge case: View models can observe services via dependency injection
- [ ] Error: If a view model directly imports SwiftUI views, then code review rejects

**Files to Create:**
```
XtMate/ViewModels/
├── EstimateStore.swift      # Main app state management
├── ClaimDetailViewModel.swift
├── ClaimsViewModel.swift
├── MaterialPreferences.swift
└── RoomViewModel.swift      # If needed for complex room state
```

**Technical Notes:**
- Dependencies: US-REF-001
- Data: ViewModels should use `@Published` properties and conform to `ObservableObject`
- Complexity: M

---

### US-REF-004: Consolidate and Organize Services

**As a** developer
**I want to** services in a clear `/Services/` directory with single responsibilities
**So that** I can understand and modify business operations without touching UI

**Acceptance Criteria:**
- [ ] Given `SyncService`, when I look for it, then I find it in `/Services/SyncService.swift`
- [ ] Given a service, when I examine it, then it handles one domain concern
- [ ] Given overlapping service functionality, when refactoring is complete, then responsibilities are clearly separated
- [ ] Edge case: Services can depend on other services via protocols/dependency injection
- [ ] Error: If a service imports SwiftUI, then code review rejects (except for Color in theme-related code)

**Current Services (verify and organize):**
```
XtMate/Services/
├── SyncService.swift        # (exists) Web API sync
├── AuthService.swift        # (exists) Authentication
├── GeminiService.swift      # (exists) AI integration
├── ScopeGenerator.swift     # (exists) AI scope generation
├── ValidationService.swift  # (exists) Line item validation
├── VoiceRecordingService.swift # (exists) Voice memos
├── DispatchEmailParser.swift   # (exists) Email parsing
├── WorkOrderService.swift   # (exists) Work order management
└── PhotoService.swift       # (NEW) Photo capture/storage
```

**Technical Notes:**
- Dependencies: US-REF-001
- Data: Services should be singletons or injected dependencies
- Complexity: M

---

### US-REF-005: Organize Theme and Design System

**As a** developer
**I want to** all theming in a dedicated `/Theme/` directory
**So that** design changes are localized and consistent

**Acceptance Criteria:**
- [ ] Given `PaulDavisTheme`, when I look for it, then I find it in `/Theme/PaulDavisTheme.swift`
- [ ] Given `AppTheme`, when I look for it, then I find it in `/Theme/AppTheme.swift`
- [ ] Given any color/spacing/typography constant, when I search, then I find it in Theme directory
- [ ] Edge case: Theme can provide both semantic (primary, secondary) and literal colors
- [ ] Error: If hardcoded colors exist in view files, then code review flags them

**Files:**
```
XtMate/Theme/
├── AppTheme.swift           # (exists) Base theme
├── PaulDavisTheme.swift     # (move from root) Brand theme
└── ButtonStyles.swift       # Custom button styles
```

**Technical Notes:**
- Dependencies: None
- Data: Theme is read-only configuration
- Complexity: S

---

### US-REF-006: Move Root-Level Files to Proper Locations

**As a** developer
**I want to** all Swift files inside the proper XtMate/ directory structure
**So that** the project follows standard iOS project conventions

**Acceptance Criteria:**
- [ ] Given `/XtMateiOS/CoreModels.swift`, when refactored, then it is deleted (content merged into proper model files)
- [ ] Given `/XtMateiOS/OnboardingView.swift`, when refactored, then it is at `/XtMate/Views/Onboarding/OnboardingView.swift`
- [ ] Given `/XtMateiOS/PaulDavisTheme.swift`, when refactored, then it is at `/XtMate/Theme/PaulDavisTheme.swift`
- [ ] Given `/XtMateiOS/HomeDashboardView.swift`, when refactored, then it is at `/XtMate/Views/Dashboard/HomeDashboardView.swift`
- [ ] Given `/XtMateiOS/ClaimDetailView.swift`, when refactored, then it is at `/XtMate/Views/Claims/ClaimDetailView.swift`
- [ ] Given any `.swift` file at `/XtMateiOS/` root, when refactored, then it is properly organized
- [ ] Edge case: Xcode project file must be updated to reflect new file locations
- [ ] Error: If a file exists at root and in proper location, then the root copy is deleted

**Files to Move:**
| Current Location | New Location |
|-----------------|--------------|
| `/XtMateiOS/CoreModels.swift` | DELETE (merge into Models/) |
| `/XtMateiOS/OnboardingView.swift` | `/XtMate/Views/Onboarding/OnboardingView.swift` |
| `/XtMateiOS/PaulDavisTheme.swift` | `/XtMate/Theme/PaulDavisTheme.swift` |
| `/XtMateiOS/HomeDashboardView.swift` | `/XtMate/Views/Dashboard/HomeDashboardView.swift` |
| `/XtMateiOS/ClaimDetailView.swift` | `/XtMate/Views/Claims/ClaimDetailView.swift` |
| `/XtMateiOS/MaterialTaggingView.swift` | `/XtMate/Views/Materials/MaterialTaggingView.swift` |
| `/XtMateiOS/QuickDamageEntryView.swift` | `/XtMate/Views/Damage/QuickDamageEntryView.swift` |
| `/XtMateiOS/PostScanQuickActionsView.swift` | `/XtMate/Views/Capture/PostScanQuickActionsView.swift` |

**Technical Notes:**
- Dependencies: US-REF-001 through US-REF-005
- Data: Xcode project.pbxproj must be updated
- Complexity: M

---

### US-REF-007: Resolve Duplicate Model Definitions

**As a** developer
**I want to** only one canonical definition for each model and enum
**So that** there is no confusion about which type to use

**Acceptance Criteria:**
- [ ] Given `JobType`, when I search the codebase, then exactly one definition exists
- [ ] Given `LossType`, when I search the codebase, then exactly one definition exists
- [ ] Given `ClaimStatus` and `EstimateStatus`, when refactored, then one canonical `EstimateStatus` exists
- [ ] Given any model/enum, when I cmd-click it in Xcode, then I go to the single canonical definition
- [ ] Edge case: Type aliases can exist for backwards compatibility during migration
- [ ] Error: If duplicate definitions exist after refactoring, then build fails

**Duplicates to Resolve:**
| Type | Location 1 | Location 2 | Resolution |
|------|-----------|-----------|------------|
| `JobType` | `Assignment.swift` | `CoreModels.swift` | Keep Assignment.swift version, update raw values |
| `LossType` | `Assignment.swift` | `CoreModels.swift` | Keep Assignment.swift version (has XactAnalysis codes) |
| `ClaimStatus` | `CoreModels.swift` | ContentView.swift | Create canonical `EstimateStatus` in StatusTypes.swift |
| `RoomCategory` | `CoreModels.swift` (as XtMateRoomCategory) | ContentView.swift | Use `RoomCategory` with typealias |
| `DamageType` | `CoreModels.swift` | ContentView.swift | Keep CoreModels version |
| `DamageSeverity` | `CoreModels.swift` | ContentView.swift | Keep CoreModels version |

**Technical Notes:**
- Dependencies: US-REF-001
- Data: Ensure Codable raw values remain consistent for data migration
- Complexity: M

---

### US-REF-008: Create Clear Extension Organization

**As a** developer
**I want to** extensions organized predictably
**So that** I can find added functionality easily

**Acceptance Criteria:**
- [ ] Given a `Room` extension, when I look for it, then it is either in `Room.swift` or `Room+Extensions.swift`
- [ ] Given a `CGPoint` Codable extension, when I look for it, then it is in `/Extensions/CGPoint+Codable.swift`
- [ ] Given any extension, when examining it, then it has clear MARK comments explaining purpose
- [ ] Edge case: Small extensions can stay with their type if file is under 200 lines
- [ ] Error: If an extension exists in multiple places, then compilation fails

**Files to Create:**
```
XtMate/Extensions/
├── CGPoint+Codable.swift
├── CapturedRoom+Extensions.swift
├── Date+Formatting.swift
└── String+Extensions.swift
```

**Technical Notes:**
- Dependencies: US-REF-001
- Data: Extensions add protocol conformance, must not break existing Codable
- Complexity: S

---

### US-REF-009: Update Xcode Project Configuration

**As a** developer
**I want to** the Xcode project properly configured with all files
**So that** the project builds correctly and file references are accurate

**Acceptance Criteria:**
- [ ] Given any Swift file in the project, when I build, then it is included in compilation
- [ ] Given the project file, when I open it in Xcode, then folder structure matches physical disk
- [ ] Given a new developer, when they clone and open, then the project builds without manual fixes
- [ ] Edge case: Test files should be in separate test target
- [ ] Error: If a file exists on disk but not in project, then CI build fails

**Technical Notes:**
- Dependencies: All previous user stories
- Data: project.pbxproj modifications
- Complexity: M

---

### US-REF-010: Verify Feature Parity and Create Regression Tests

**As a** developer
**I want to** verify all features work after refactoring
**So that** users experience no regressions

**Acceptance Criteria:**
- [ ] Given room capture flow, when user scans a room, then dimensions are calculated correctly
- [ ] Given estimate creation, when user creates an estimate, then all fields save properly
- [ ] Given sync operation, when user syncs, then data uploads/downloads correctly
- [ ] Given material tagging, when user tags materials, then selections persist
- [ ] Given damage annotation, when user adds damage, then annotations display correctly
- [ ] Edge case: Offline mode continues to work with sync queue
- [ ] Error: If any regression is detected, then refactoring branch is blocked from merge

**Test Scenarios:**
1. Create new estimate with all fields populated
2. Capture room with LiDAR
3. Edit room name, category, floor level
4. Tag floor, wall, ceiling materials
5. Add damage annotation with all severity levels
6. Generate AI scope suggestions
7. Sync estimate to web platform
8. Force download from server
9. Delete room from estimate
10. Delete entire estimate

**Technical Notes:**
- Dependencies: All refactoring complete
- Data: Use simulator mock data for UI tests
- Complexity: L

---

## 4. Technical Architecture

### Proposed Directory Structure

```
XtMateiOS/
├── XtMate.xcodeproj/
├── XtMate/
│   ├── XtMateApp.swift              # App entry point
│   ├── ContentView.swift            # App shell only (<500 lines)
│   ├── Info.plist
│   ├── Assets.xcassets/
│   │
│   ├── Models/
│   │   ├── Estimate.swift
│   │   ├── Room.swift
│   │   ├── DamageAnnotation.swift
│   │   ├── Assignment.swift
│   │   ├── ScopeLineItem.swift
│   │   ├── Material.swift
│   │   ├── DamageTypes.swift
│   │   ├── StatusTypes.swift
│   │   ├── RoomTypes.swift
│   │   ├── GeneratedLineItem.swift
│   │   ├── FloorPlanModels.swift
│   │   ├── FloorPlanAnnotationModels.swift
│   │   └── WorkOrder.swift
│   │
│   ├── Views/
│   │   ├── Estimates/
│   │   │   ├── EstimateListView.swift
│   │   │   ├── EstimateDetailView.swift
│   │   │   ├── EstimateHeaderCard.swift
│   │   │   └── EstimateRow.swift
│   │   ├── Rooms/
│   │   │   ├── RoomCard.swift
│   │   │   ├── RoomEditSheet.swift
│   │   │   ├── RoomReviewView.swift
│   │   │   ├── SaveRoomSheet.swift
│   │   │   └── RoomDetailViews.swift
│   │   ├── Capture/
│   │   │   ├── RoomCaptureViewRepresentable.swift
│   │   │   ├── FloorPlanCanvasView.swift
│   │   │   └── PostScanQuickActionsView.swift
│   │   ├── Materials/
│   │   │   ├── MaterialPickerSheet.swift
│   │   │   ├── MaterialCards.swift
│   │   │   └── MaterialTaggingView.swift
│   │   ├── Damage/
│   │   │   ├── DamageAnnotationSheet.swift
│   │   │   ├── DamageAnnotationAssistant.swift
│   │   │   └── QuickDamageEntryView.swift
│   │   ├── Scope/
│   │   │   ├── ScopeCard.swift
│   │   │   ├── ScopeListView.swift
│   │   │   ├── ScopeLineItemRow.swift
│   │   │   └── AddLineItemSheet.swift
│   │   ├── Onboarding/
│   │   │   └── OnboardingView.swift
│   │   ├── Dashboard/
│   │   │   └── HomeDashboardView.swift
│   │   ├── Claims/
│   │   │   └── ClaimDetailView.swift
│   │   ├── FieldStaff/
│   │   │   ├── MyWorkView.swift
│   │   │   ├── WorkOrderDetailView.swift
│   │   │   └── SignatureCaptureView.swift
│   │   ├── FloorPlan/
│   │   │   └── FloorPlanView.swift
│   │   ├── NewClaimSheet.swift
│   │   ├── MainTabView.swift
│   │   └── Common/
│   │       ├── EmptyStateViews.swift
│   │       ├── StatViews.swift
│   │       ├── BadgeViews.swift
│   │       └── CardViews.swift
│   │
│   ├── ViewModels/
│   │   ├── EstimateStore.swift
│   │   ├── ClaimDetailViewModel.swift
│   │   ├── ClaimsViewModel.swift
│   │   └── MaterialPreferences.swift
│   │
│   ├── Services/
│   │   ├── SyncService.swift
│   │   ├── AuthService.swift
│   │   ├── GeminiService.swift
│   │   ├── ScopeGenerator.swift
│   │   ├── ValidationService.swift
│   │   ├── VoiceRecordingService.swift
│   │   ├── DispatchEmailParser.swift
│   │   └── WorkOrderService.swift
│   │
│   ├── Theme/
│   │   ├── AppTheme.swift
│   │   ├── PaulDavisTheme.swift
│   │   └── ButtonStyles.swift
│   │
│   ├── Components/
│   │   ├── Cards/
│   │   │   ├── AssignmentCard.swift
│   │   │   ├── ClaimInfoCard.swift
│   │   │   └── RoomsListCard.swift
│   │   └── Hero/
│   │       └── PropertyHeroView.swift
│   │
│   ├── Extensions/
│   │   ├── CGPoint+Codable.swift
│   │   └── CapturedRoom+Extensions.swift
│   │
│   ├── Config/
│   │   ├── APIKeys.swift
│   │   └── README-APIKeys.md
│   │
│   └── XtMateWidget/
│       └── XtMateWidget.swift
│
├── XtMateTests/
│   └── (test files)
│
└── docs/
    └── PRD-REFACTORING.md
```

### Architecture Pattern: MVVM

```
┌─────────────────────────────────────────────────────────────┐
│                         Views                                │
│  (SwiftUI views - declarative UI, no business logic)        │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ @ObservedObject / @StateObject
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                       ViewModels                             │
│  (ObservableObject - state management, business logic)       │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ dependency injection
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        Services                              │
│  (Singletons/Injected - API calls, persistence, AI)         │
└─────────────────────────────────────────────────────────────┘
                              │
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         Models                               │
│  (Codable structs/enums - data representation)              │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. Migration Plan

### Phase 1: Foundation (Week 1)

**Goal:** Establish model layer and resolve duplicates

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| Create `/Models/` directory structure | P0 | 2h | None |
| Extract and consolidate `Estimate` model | P0 | 4h | None |
| Extract and consolidate `Room` model | P0 | 4h | None |
| Extract `DamageAnnotation` model | P0 | 2h | None |
| Create `StatusTypes.swift` (resolve ClaimStatus/EstimateStatus) | P0 | 2h | None |
| Create `RoomTypes.swift` (resolve RoomCategory) | P0 | 2h | None |
| Create `DamageTypes.swift` | P0 | 1h | None |
| Create `Material.swift` (enums) | P0 | 2h | None |
| Resolve `JobType` duplicate | P0 | 1h | None |
| Resolve `LossType` duplicate | P0 | 1h | None |
| Delete `CoreModels.swift` after merge | P0 | 1h | All above |
| Create `CGPoint+Codable.swift` extension | P1 | 1h | None |

**Validation Checkpoint:**
- [ ] All models compile independently
- [ ] No duplicate type definitions
- [ ] Existing features still work

### Phase 2: ViewModels (Week 2)

**Goal:** Extract business logic from views

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| Extract `EstimateStore` to `/ViewModels/` | P0 | 4h | Phase 1 |
| Extract `MaterialPreferences` to `/ViewModels/` | P0 | 2h | Phase 1 |
| Verify `ClaimDetailViewModel` in proper location | P1 | 1h | Phase 1 |
| Verify `ClaimsViewModel` in proper location | P1 | 1h | Phase 1 |
| Document ViewModel patterns in CLAUDE.md | P2 | 1h | All above |

**Validation Checkpoint:**
- [ ] ViewModels are testable in isolation
- [ ] No UI code in ViewModels
- [ ] All @Published properties working

### Phase 3: Views Extraction (Week 3-4)

**Goal:** Break up ContentView.swift into organized view files

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| Create view directory structure | P0 | 1h | Phase 2 |
| Extract Estimate views (List, Detail, Row, Header) | P0 | 4h | Phase 2 |
| Extract Room views (Card, Edit, Review, Save) | P0 | 6h | Phase 2 |
| Extract Capture views (RoomCapture, FloorPlan) | P0 | 4h | Phase 2 |
| Extract Material views (Picker, Cards) | P0 | 4h | Phase 2 |
| Extract Damage views (Annotation, Quick Entry) | P0 | 3h | Phase 2 |
| Extract Scope views (Card, List, Row) | P0 | 3h | Phase 2 |
| Extract Common views (Empty states, Stats, Badges) | P1 | 3h | Phase 2 |
| Move root-level views to proper locations | P0 | 2h | Phase 2 |
| Reduce ContentView.swift to app shell | P0 | 4h | All above |

**Validation Checkpoint:**
- [ ] ContentView.swift < 500 lines
- [ ] All views render correctly
- [ ] Navigation still works

### Phase 4: Theme & Services (Week 5)

**Goal:** Organize theming and verify service layer

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| Move `PaulDavisTheme.swift` to `/Theme/` | P0 | 1h | Phase 3 |
| Verify `AppTheme.swift` organization | P0 | 1h | Phase 3 |
| Create `ButtonStyles.swift` if needed | P2 | 2h | Phase 3 |
| Verify all services in `/Services/` | P1 | 2h | Phase 3 |
| Document service patterns in CLAUDE.md | P2 | 1h | All above |

**Validation Checkpoint:**
- [ ] Theme changes are localized
- [ ] Services are properly injected
- [ ] No hardcoded colors in views

### Phase 5: Xcode Configuration & Testing (Week 6)

**Goal:** Ensure project builds correctly and features work

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| Update Xcode project with all file references | P0 | 4h | Phase 4 |
| Clean up old file references | P0 | 2h | Phase 4 |
| Manual testing of all features | P0 | 8h | All above |
| Fix any regressions found | P0 | varies | Testing |
| Update CLAUDE.md with new architecture | P1 | 2h | All above |
| Document file organization in README | P2 | 1h | All above |

**Validation Checkpoint:**
- [ ] Project builds on clean checkout
- [ ] All 10 test scenarios pass
- [ ] No regression from original functionality

---

## 6. Success Metrics

### Quantitative Metrics

| Metric | Before | Target | Measurement |
|--------|--------|--------|-------------|
| ContentView.swift lines | 5,065 | < 500 | `wc -l` |
| Duplicate model definitions | 6+ | 0 | Code search |
| Files at root level | 8 | 0 | `ls *.swift` |
| Average file size | ~1000 lines | < 300 lines | Script analysis |
| Build time (clean) | TBD | No regression | Xcode timing |
| Test coverage | ~0% | > 30% ViewModels | Xcode coverage |

### Qualitative Metrics

- **Developer onboarding:** New developer can find and modify any component within 5 minutes
- **Feature velocity:** Changes to one component don't require understanding unrelated code
- **Code review:** PRs affect focused, small files rather than monolithic ones
- **Debugging:** Stack traces point to specific, focused files

---

## 7. Risks & Mitigations

### Risk 1: Breaking Changes During Migration

**Likelihood:** High
**Impact:** High
**Mitigation:**
- Perform migration in small, incremental PRs
- Each PR must pass all manual test scenarios before merge
- Keep feature branch updated with main to catch conflicts early
- Maintain type aliases during transition for backwards compatibility

### Risk 2: Xcode Project File Conflicts

**Likelihood:** Medium
**Impact:** Medium
**Mitigation:**
- Coordinate with team to minimize parallel development during migration
- Use Xcode's "Add files to project" feature carefully
- Consider using XcodeGen or Tuist for project generation (future)
- Commit .xcodeproj changes in dedicated commits

### Risk 3: Missed Duplicate Definitions

**Likelihood:** Medium
**Impact:** Low
**Mitigation:**
- Run automated search for type names across codebase
- Use compiler errors to catch redefinitions
- Code review specifically checks for duplicates

### Risk 4: Performance Regression

**Likelihood:** Low
**Impact:** Medium
**Mitigation:**
- Architecture changes shouldn't affect runtime performance
- Monitor app startup time before/after
- Test on physical device, not just simulator

### Risk 5: Team Productivity Impact During Migration

**Likelihood:** Medium
**Impact:** Medium
**Mitigation:**
- Complete migration in dedicated sprint
- Minimize parallel feature development during migration
- Document new patterns early so team can learn
- Pair programming for complex extractions

---

## 8. Appendix

### A. Files Currently in ContentView.swift (5,065 lines)

Based on MARK comments and analysis:

**Models/Extensions (~200 lines):**
- `CGPoint: @retroactive Codable` extension
- `IdentifiableCapturedRoom` wrapper
- `FloorPlanGeometry` struct
- `DivisionLine` struct
- `SubRoom` struct

**Views (~3,500 lines):**
- `ContentView` (app shell)
- `SyncButton`
- `EmptyDetailView`
- `EstimateListView`
- `EstimateRow`
- `NewEstimateSheet`
- `EstimateDetailView`
- `EstimateHeaderCard`
- `EmptyRoomsCard`
- `RoomCard`
- `CompactBadge`, `CompactDimension`, `FeatureCount`
- `RoomEditSheet`
- `SavedRoomDetailView`
- `SavedRoomFloorPlanView`
- `SavedRoom3DView`
- `SavedRoomIsometricView`
- `SavedRoomStatsView`
- `MaterialInfoCard`
- `MaterialBadge`
- `MaterialPickerSheet`
- `MaterialSection`
- `FloorMaterialCard`, `WallMaterialCard`, `CeilingMaterialCard`
- `DamageAnnotationSheet`
- `ScopeCard`
- `TotalsCard`
- `ActionButtonsCard`
- `FloorPickerSheet`
- `RoomCaptureViewRepresentable`
- `RoomCaptureViewController`
- `RoomReviewView`
- `QuickStat`
- `DetectedObjectBadge`
- `SaveRoomSheet`
- `RoomStatsView`
- `DimensionCard`
- `FeatureCard`
- `FloorPlanCanvasView` (~700 lines)

**ViewModels (~400 lines):**
- `EstimateStore` class
- `MaterialPreferences` class

**Enums/Types (~200 lines):**
- `FloorLevel`
- `FloorMaterial`
- `WallMaterial`
- `CeilingMaterial`
- Various helper types

### B. Model Consolidation Reference

| Canonical Name | File | Notes |
|----------------|------|-------|
| `Estimate` | `Models/Estimate.swift` | Main claim/project |
| `Room` | `Models/Room.swift` | With extensions |
| `DamageAnnotation` | `Models/DamageAnnotation.swift` | |
| `Assignment` | `Models/Assignment.swift` | Includes AssignmentType, AssignmentStatus |
| `ScopeLineItem` | `Models/ScopeLineItem.swift` | |
| `JobType` | `Models/Assignment.swift` | Keep insurance/privateJob raw values |
| `LossType` | `Models/Assignment.swift` | Keep WATERDMG etc. codes |
| `EstimateStatus` | `Models/StatusTypes.swift` | Canonical status enum |
| `SyncStatus` | `Models/StatusTypes.swift` | |
| `ValidationState` | `Models/StatusTypes.swift` | |
| `RoomCategory` | `Models/RoomTypes.swift` | typealias for XtMateRoomCategory |
| `FloorLevel` | `Models/RoomTypes.swift` | |
| `DamageType` | `Models/DamageTypes.swift` | |
| `DamageSeverity` | `Models/DamageTypes.swift` | |
| `AffectedSurface` | `Models/DamageTypes.swift` | |
| `FloorMaterial` | `Models/Material.swift` | |
| `WallMaterial` | `Models/Material.swift` | |
| `CeilingMaterial` | `Models/Material.swift` | |

---

*Last updated: January 16, 2026*
*XtMate iOS Refactoring PRD v1.0*
