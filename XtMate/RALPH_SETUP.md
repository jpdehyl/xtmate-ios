# Using Claude Code in Xcode with the RALPH Method

## Overview

RALPH (Recursive Agent Loop for Programmatic Hacking) is an autonomous AI coding pattern where Claude Code works through a structured PRD, implementing features one by one, tracking progress, and learning from each iteration.

---

## Files Created for Your Project

```
XtMate/
├── prd.json           # Product roadmap with 12 Phase 3 stories
├── CLAUDE.md          # Project knowledge base for Claude
├── progress.txt       # Session learnings and patterns
└── RALPH_SETUP.md     # This file - how to use the system
```

---

## Step-by-Step: Using Claude Code in Xcode

### Step 1: Open Terminal in Xcode Project

1. Open **Xcode** with your XtMate project
2. Open **Terminal** (⌘ + Space, type "Terminal")
3. Navigate to your iOS project:
   ```bash
   cd ~/Documents/xtmate/mobile/XtMate
   ```

### Step 2: Start Claude Code

```bash
claude
```

This launches Claude Code CLI in your terminal.

### Step 3: Give Claude the RALPH Prompt

Copy and paste this prompt to start an iteration:

```
Read CLAUDE.md and prd.json to understand the project.
Then read progress.txt for context from previous sessions.

Pick the next "todo" story from prd.json (lowest priority number that's not "done").
Implement that story according to its acceptance criteria.

After implementation:
1. Test that the code compiles (you can't run Xcode tests from CLI)
2. Mark the story as "done" in prd.json
3. Update progress.txt with what you learned
4. Commit the changes with a descriptive message

Then stop and report what you did.
```

### Step 4: Review and Iterate

After Claude completes a story:
1. **Build in Xcode** (⌘ + B) to verify compilation
2. **Run on device** to test the feature
3. If issues found, tell Claude to fix them
4. If working, start the next iteration

---

## RALPH Workflow Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    RALPH LOOP                           │
├─────────────────────────────────────────────────────────┤
│                                                         │
│   ┌──────────┐     ┌──────────┐     ┌──────────┐       │
│   │  Read    │ ──► │  Pick    │ ──► │ Implement│       │
│   │ Context  │     │  Story   │     │  Feature │       │
│   └──────────┘     └──────────┘     └──────────┘       │
│        │                                   │            │
│        │           CLAUDE.md               │            │
│        │           prd.json                │            │
│        │           progress.txt            │            │
│        │                                   │            │
│        ▼                                   ▼            │
│   ┌──────────┐     ┌──────────┐     ┌──────────┐       │
│   │  Next    │ ◄── │  Update  │ ◄── │  Verify  │       │
│   │ Iteration│     │  Files   │     │  & Test  │       │
│   └──────────┘     └──────────┘     └──────────┘       │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Tips for Best Results

### 1. Keep Stories Small
Each story in prd.json should be completable in one iteration (5-15 minutes of Claude work). The current stories are already scoped appropriately.

### 2. Be Specific in Acceptance Criteria
The more specific, the better. "Add a picker" is vague. "Add a Picker with options: LVP, Carpet, Tile" is specific.

### 3. Update progress.txt
After each session, have Claude update progress.txt with:
- What patterns worked
- What gotchas were discovered
- Architecture decisions made

### 4. Human-in-the-Loop (HITL) Mode
For iOS development, always use HITL mode:
- Review code after each story
- Build in Xcode to catch compile errors
- Test on device before moving on

### 5. Don't Let Progress.txt Get Stale
Delete and recreate progress.txt when starting a new sprint. It's session-specific, not permanent documentation.

---

## Current PRD Stories (Phase 3)

| ID | Story | Priority | Status |
|----|-------|----------|--------|
| P3-001 | Floor selector on room cards | 1 | todo |
| P3-002 | Floor material tagging | 2 | todo |
| P3-003 | Wall material tagging | 3 | todo |
| P3-004 | Ceiling material tagging | 4 | todo |
| P3-005 | Photo capture for rooms | 5 | todo |
| P3-006 | Damage annotation model | 6 | todo |
| P3-007 | Add damage annotation UI | 7 | todo |
| P3-008 | Display annotations on room card | 8 | todo |
| P3-009 | Voice memo for annotations | 9 | todo |
| P3-010 | Web API sync service | 10 | todo |
| P3-011 | Offline mode with sync queue | 11 | todo |
| P3-012 | Duplicate room feature | 12 | todo |

---

## Example Session

```bash
$ cd ~/Documents/xtmate/mobile/XtMate
$ claude

You: Read CLAUDE.md and prd.json, then implement the next todo story.

Claude: I'll read the project context first...
[reads CLAUDE.md]
[reads prd.json]
[reads progress.txt]

The next story is P3-001: Floor selector on room cards.

I'll implement this by:
1. Adding a `floor` property to the Room model
2. Adding a floor picker to RoomCard
3. Updating persistence

[implements code]
[updates prd.json to mark P3-001 as "done"]
[updates progress.txt with learnings]
[commits changes]

Done! Story P3-001 is complete. Please build in Xcode to verify.
```

---

## Troubleshooting

### Claude Can't Find Files
Make sure you're in the right directory:
```bash
pwd  # Should show .../xtmate/mobile/XtMate
ls   # Should show ContentView.swift, prd.json, etc.
```

### Code Doesn't Compile
Tell Claude the exact error:
```
The code doesn't compile. Error: "Cannot find 'FloorType' in scope" on line 45 of ContentView.swift. Fix this.
```

### Story Too Big
If Claude seems stuck or output is truncated, the story might be too large. Break it into smaller pieces in prd.json.

### Lost Context
If Claude seems confused, start fresh:
```
Let's start over. Read CLAUDE.md and prd.json from scratch.
```

---

## Resources

- [RALPH on GitHub](https://github.com/snarktank/ralph)
- [Claude Code Documentation](https://docs.anthropic.com/claude-code)
- [Apple RoomPlan Documentation](https://developer.apple.com/documentation/roomplan)

---

*Happy building! 🏗️*
