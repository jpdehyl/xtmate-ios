# XtMate iOS - Visual Flow Diagram

## Complete User Journey

```
┌─────────────────────────────────────────────────────────────────┐
│                         APP LAUNCH                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  First Launch?   │
                    └──────────────────┘
                         │          │
                   YES   │          │   NO
                         ▼          ▼
              ┌──────────────┐  ┌──────────────────┐
              │ ONBOARDING   │  │ HOME DASHBOARD   │
              │              │  │                  │
              │ • 3 slides   │  │ • Status cards   │
              │ • Skip option│  │ • Filter pills   │
              │ • Let's Go   │  │ • Search bar     │
              └──────────────┘  │ • Claim cards    │
                      │         │ • Pull refresh   │
                      │         └──────────────────┘
                      ▼                  │
              ┌──────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       HOME DASHBOARD                            │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐     │
│  │  🔥 URGENT: 3 claims pending sync    [Sync All →]   │     │
│  └──────────────────────────────────────────────────────┘     │
│                                                                 │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                       │
│  │ 📊 12   │  │ ⏱️ 5    │  │ ✅ 4    │                       │
│  │ Total   │  │ Active  │  │ Done    │                       │
│  └─────────┘  └─────────┘  └─────────┘                       │
│                                                                 │
│  [All] [Insurance] [Private] [Pending] [Active]               │
│                                                                 │
│  Recent Claims:                                                │
│  ┌──────────────────────────────────────────────────┐         │
│  │ 💧 #202511242869                                 │         │
│  │ Jesse Daniel Mayor                               │         │
│  │ 📍 2250 W 3rd Ave                               │         │
│  │ 4 rooms | 2 damages | 1,850 SF                  │         │
│  │ [Sync] [📞 Call] [🗺️ Navigate]                  │         │
│  └──────────────────────────────────────────────────┘         │
│                                                                 │
│  [+ New Claim]  [📥 Sync All]                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Tap Claim
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      CLAIM DETAIL VIEW                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────┐      │
│  │          PROPERTY HERO (Floor Plan)                 │      │
│  │                                                     │      │
│  │    ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐        │      │
│  │    │Kitchen│  │Living│  │Bedroom│  │Bath  │        │      │
│  │    │⚠️ 2   │  │  ✓   │  │      │  │⚠️ 1  │        │      │
│  │    └──────┘  └──────┘  └──────┘  └──────┘        │      │
│  │                                                     │      │
│  │    4 rooms | 2 damages | 1,850 SF      [2D/3D]    │      │
│  └─────────────────────────────────────────────────────┘      │
│                                                                 │
│  ┌─────────────────────────────────────────────────────┐      │
│  │ 📋 Claim Info                              [▼]      │      │
│  │ 💧 Water Loss | DOL: 12/15/25                      │      │
│  │ Jesse Daniel Mayor | (604) 555-1234                │      │
│  └─────────────────────────────────────────────────────┘      │
│                                                                 │
│  🏠 Rooms:                                                     │
│  ┌─────────────────────────────────────────────────────┐      │
│  │ 🍴 Kitchen - 144 SF                                 │      │
│  │ ⚠️ 2 damages | ✓ Scoped                            │      │
│  │ [View] [+ Add Damage]                               │      │
│  └─────────────────────────────────────────────────────┘      │
│  [+ Scan New Room]                                             │
│                                                                 │
│  📊 Assignments:                                               │
│  [E] Emergency → [R] Repairs → [C] Contents                   │
│                                                                 │
│  Quick Actions:                                                │
│  [📸 Photos] [⚠️ Damage] [✨ Scope] [📄 Report]              │
│                                                                 │
│                                    ⭕ [Scan Room]              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Tap "Scan Room"
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ROOM CAPTURE (LiDAR)                       │
│                                                                 │
│  [×]                    Kitchen                                 │
│                                                                 │
│         ┌──────────────────────────────────┐                   │
│         │                                  │                   │
│         │       [LiDAR Camera View]        │                   │
│         │                                  │                   │
│         │     • • • • • • • • • • •        │                   │
│         │     Scanning surfaces...         │                   │
│         │     85% complete                 │                   │
│         │                                  │                   │
│         └──────────────────────────────────┘                   │
│                                                                 │
│  [Cancel]                         [Done Scanning]              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Done
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  POST-SCAN QUICK ACTIONS                        │
│                                                                 │
│         ┌──────────────────────────────────┐                   │
│         │        ✅ SUCCESS!               │                   │
│         │                                  │                   │
│         │        Kitchen                   │                   │
│         │    144 SF | Kitchen              │                   │
│         └──────────────────────────────────┘                   │
│                                                                 │
│  Next Steps:                                                   │
│  Select actions to complete for this room                      │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐                           │
│  │   📸         │  │   ⚠️          │                           │
│  │ Take Photos  │  │ Add Damage    │                           │
│  │ Capture room │  │ Mark visible  │                           │
│  │ conditions   │  │ damage        │                           │
│  │      ✓       │  │      ✓        │                           │
│  └──────────────┘  └──────────────┘                           │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐                           │
│  │   🎨         │  │   🎤          │                           │
│  │ Tag Materials│  │ Voice Note    │                           │
│  │ Identify     │  │ Add verbal    │                           │
│  │ surfaces     │  │ notes         │                           │
│  │      ✓       │  │               │                           │
│  └──────────────┘  └──────────────┘                           │
│                                                                 │
│  [Continue with 3 actions]  [Skip for Now]                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Continue
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   QUICK DAMAGE ENTRY                            │
│                                                                 │
│  Damage Type:                                                  │
│  ┌────────┐  ┌────────┐  ┌────────┐                           │
│  │  💧    │  │  🔥    │  │  💨    │                           │
│  │ Water  │  │  Fire  │  │ Smoke  │                           │
│  │   ●    │  │        │  │        │                           │
│  └────────┘  └────────┘  └────────┘                           │
│  ┌────────┐  ┌────────┐  ┌────────┐                           │
│  │  🦠    │  │  💥    │  │  🌪️    │                           │
│  │  Mold  │  │ Impact │  │  Wind  │                           │
│  │        │  │        │  │        │                           │
│  └────────┘  └────────┘  └────────┘                           │
│                                                                 │
│  Severity:                                                     │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐                │
│  │  ○ Low     │ │  ● Moderate│ │  ○ High    │                │
│  └────────────┘ └────────────┘ └────────────┘                │
│                                                                 │
│  Affected Surfaces:                                            │
│  ┌────────┐  ┌────────┐  ┌────────┐                           │
│  │  ▭     │  │  ▯     │  │  ▬     │                           │
│  │ Floor  │  │  Wall  │  │Ceiling │                           │
│  │   ✓    │  │   ✓    │  │        │                           │
│  └────────┘  └────────┘  └────────┘                           │
│                                                                 │
│  Documentation:                                                │
│  [📸 Add Photos]   [🎤 Voice Note]                            │
│                                                                 │
│  Additional Notes (Optional):                                  │
│  ┌──────────────────────────────────────────┐                 │
│  │ Standing water approx 2" deep near       │                 │
│  │ dishwasher. Baseboards are saturated.    │                 │
│  └──────────────────────────────────────────┘                 │
│                                                                 │
│  [Cancel]                              [Save]                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Save
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   MATERIAL TAGGING                              │
│                                                                 │
│         ┌──────────────────────────────────┐                   │
│         │            🎨                    │                   │
│         │       Tag Materials              │                   │
│         │                                  │                   │
│         │  Select materials for each       │                   │
│         │  surface                         │                   │
│         └──────────────────────────────────┘                   │
│                                                                 │
│  ▭ Floor Material                                              │
│                                                                 │
│  Suggested:  [✨ Tile] [✨ LVP] [✨ Hardwood]                  │
│                                                                 │
│  ┌────────────────┐  ┌────────────────┐                       │
│  │ Tile       ✓   │  │ LVP            │                       │
│  └────────────────┘  └────────────────┘                       │
│  ┌────────────────┐  ┌────────────────┐                       │
│  │ Hardwood       │  │ Carpet         │                       │
│  └────────────────┘  └────────────────┘                       │
│                                                                 │
│  ▯ Wall Finish                                                 │
│                                                                 │
│  Suggested:  [✨ Painted Drywall] [✨ Tile]                    │
│                                                                 │
│  ┌────────────────┐  ┌────────────────┐                       │
│  │ Painted DW  ✓  │  │ Tile           │                       │
│  └────────────────┘  └────────────────┘                       │
│                                                                 │
│  ▬ Ceiling Finish                                              │
│                                                                 │
│  ┌────────────────┐  ┌────────────────┐                       │
│  │ Smooth      ✓  │  │ Popcorn        │                       │
│  └────────────────┘  └────────────────┘                       │
│                                                                 │
│  [Skip for Now]                [Save & Continue]               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Save
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  BACK TO CLAIM DETAIL                           │
│                                                                 │
│  Kitchen - Updated! ✨                                         │
│  • 144 SF                                                      │
│  • 1 damage annotation                                         │
│  • Materials tagged (Tile, Painted DW, Smooth)                 │
│  • 3 photos                                                    │
│  • 1 voice note                                                │
│                                                                 │
│  Ready for scope generation!                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Color Legend

```
💧 Water (Blue)
🔥 Fire (Red)
💨 Smoke (Gray)
🦠 Mold (Green)
💥 Impact (Orange)
🌪️ Wind (Cyan)

⚠️ Damage Count (Orange)
✓ Scoped/Complete (Green)
⏱️ In Progress (Orange)
📊 Statistics (Blue)
```

---

## Touch Target Sizes

```
┌──────────────────────────────────────────┐
│  Primary Action Button                   │
│  72pt × 72pt                             │
│  (Perfect for gloved hands)              │
└──────────────────────────────────────────┘

┌────────────────────┐
│  Secondary Button  │
│  56pt × 56pt       │
│  (Minimum HIG)     │
└────────────────────┘

┌─────────────┐
│  Chip       │
│  44pt min   │
└─────────────┘
```

---

## Design Tokens Used

**Spacing:**
- xs: 4pt
- sm: 8pt
- md: 12pt
- lg: 16pt
- xl: 20pt
- xxl: 24pt
- xxxl: 32pt

**Corner Radius:**
- xs: 4pt (chips)
- sm: 8pt (small cards)
- md: 12pt (cards)
- lg: 16pt (modals)
- full: 9999pt (pills)

**Shadows:**
- sm: 2pt blur, 1pt offset
- md: 4pt blur, 2pt offset
- lg: 8pt blur, 4pt offset

---

## State Indicators

```
Sync Status:
  ⏳ Pending (Orange)
  🔄 Syncing (Orange, animated)
  ✅ Synced (Green)
  ❌ Failed (Red)

Claim Status:
  📝 Draft (Gray)
  ⏱️ In Progress (Orange)
  ✅ Complete (Green)

Assignment Status:
  ⏸️ Pending (Gray)
  ▶️ In Progress (Orange)
  📤 Submitted (Blue)
  ✅ Approved (Green)
  🏁 Completed (Green)
```
