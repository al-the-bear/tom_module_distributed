# Supervisor Orchestration - Documentation Index

## Overview Documents

### 1. **QUICK_REFERENCE.md** ⭐ START HERE
Quick reference guide covering:
- The four cleanup rules
- Stack-aware frame removal
- How to safely call another participant
- Supervisor API basics
- Orchestrator file structure
- Implementation order

**Best for:** Quick lookup, implementation guidance

### 2. **DESIGN_UPDATE_SUMMARY.md**
Complete summary of all changes made:
- What changed and why
- Document structure reorganization
- Major design principles
- Code examples provided
- Implementation readiness assessment
- Questions answered

**Best for:** Understanding scope of changes, why decisions were made

### 3. **CLEANUP_SIMPLIFICATION.md**
Detailed explanation of cleanup mechanism simplification:
- What changed from old to new design
- Four cleanup rules with examples
- Removal algorithm with stack examples
- Operation completion sequence
- Benefits table
- Implementation checklist

**Best for:** Deep dive into cleanup mechanism

---

## Main Design Document

### 4. **supervisor_orchestration.md** (1931 lines)
Comprehensive design specification with 8 parts:

#### Part 1: Cleanup Mechanism (Detailed)
- States and state transitions
- Four cleanup rules in detail
- Cleanup responsibility matrix
- Ledger-assisted cleanup code
- Example: Bridge crashes during call chain

#### Part 2: Stack Frame with Supervisor Association
- Enhanced stack frame structure
- JSON serialization format
- Supervisor association via optional fields

#### Part 3a: Failure Notification in Dart Code (NEW)
- Problem statement
- Stream-based notification solution
- Caller patterns with examples
- Safe call patterns with code
- Concurrent call with safety nets
- Manual polling approaches
- Best practice checklist

#### Part 3b: Supervisor API
- Overview of supervisor-created Ledger
- One Ledger per isolate principle
- Static `initSupervisorLedger()` method
- Callback types and specifications
- Supervised call registration
- In-memory supervised call registry

#### Part 4: Supervisor Heartbeats in Operation File
- Simplified heartbeat structure
- JSON structure
- Supervisor death detection
- Supervisor status tracking

#### Part 5: Heartbeat Continuation
- Heartbeat lifecycle
- Automatic continuation until terminal
- Behavior during cleanup
- Important properties

#### Part 6: Supervisor Orchestrator
- Overview and file structure
- Orchestration group and supervisors registry
- RegisteredSupervisor with restart policy
- Orchestrator API
- Startup flow
- Heartbeat loop with failure handling
- Supervisor dependency flow

#### Part 7: Integrated Flow Example
- Detailed timeline of Bridge crash scenario
- Shows all four rules in action
- What made this simpler

#### Part 8: API Summary
- Types in operation file
- Types in Supervisor API
- Types in orchestration files
- Key methods
- Implementation phases

**Best for:** Complete design specification, implementation guidance

---

## Code Examples

### 5. **doc/examples/failure_notification_patterns.dart**
Complete working Dart code with 6 failure notification patterns:

1. **Stream-Based (Recommended)** - Listen to state changes
2. **Wait For Cleanup** - Race call against cleanup
3. **Wait For Terminal With Timeout** - Wait for completion
4. **Concurrent Call With Multiple Safety Nets** - Complex pattern
5. **Callback-Based With Early Exit** - Immediate notification
6. **Stream-Based With First** - Simple first-to-complete

Each pattern includes:
- Full working code
- Usage explanation
- Exception handling
- When to use it

Includes mock implementation and main() for testing.

**Best for:** Copy-paste examples, understanding Dart patterns

---

## Reading Path by Role

### Architect/Designer
1. Read **QUICK_REFERENCE.md** (5 min)
2. Read **CLEANUP_SIMPLIFICATION.md** (10 min)
3. Review **supervisor_orchestration.md** Parts 1, 6 (15 min)
4. Total: ~30 minutes

### Implementation Engineer
1. Read **QUICK_REFERENCE.md** (5 min)
2. Review **supervisor_orchestration.md** all parts (45 min)
3. Study **failure_notification_patterns.dart** (15 min)
4. Read implementation checklist in **CLEANUP_SIMPLIFICATION.md** (5 min)
5. Total: ~70 minutes

### Code Reviewer
1. Skim **DESIGN_UPDATE_SUMMARY.md** (10 min)
2. Focus on **supervisor_orchestration.md** Parts 1, 3a, 7 (20 min)
3. Review **failure_notification_patterns.dart** (10 min)
4. Total: ~40 minutes

### System Integration
1. Read **QUICK_REFERENCE.md** (5 min)
2. Review Orchestrator section (Part 6) (20 min)
3. Check failure notification patterns (15 min)
4. Total: ~40 minutes

---

## Key Concepts at a Glance

| Concept | Location | Key Points |
|---------|----------|-----------|
| **Four Cleanup Rules** | QUICK_REFERENCE.md, supervisor_orchestration.md Part 1 | Rule 1: Each frame cleans itself, Rule 2: Ledger cleans unsupervised, Rule 3: Supervisor cleans via callback, Rule 4: Dead supervisor frames |
| **Stack-Aware Removal** | QUICK_REFERENCE.md, CLEANUP_SIMPLIFICATION.md | Ledger removes stacked crashed frames when caller removes |
| **Failure Notification** | supervisor_orchestration.md Part 3a, failure_notification_patterns.dart | Stream-based, 6 patterns, no polling |
| **Supervisor API** | supervisor_orchestration.md Part 3b | One Ledger per isolate, supervisor-created, callbacks |
| **Stack Frame** | supervisor_orchestration.md Part 2 | supervisorId, supervisorHandle, state fields |
| **Orchestrator** | supervisor_orchestration.md Part 6 | Two files per group, preserves healthy supervisors |
| **Heartbeat Lifecycle** | supervisor_orchestration.md Part 5 | Continues until terminal, automatic cleanup, no manual stop |

---

## Quick Links

### State Transitions
- **Running → Cleanup:** When stale heartbeat detected
- **Cleanup → Failed:** When stack becomes empty
- **Failed → End:** After 2 more heartbeats, file deleted

### Supervisor Callbacks
- `onCallCrashed(handle, info)` - Called once per crashed call during supervisor heartbeat
- `onCallStarted(handle, info)` - Optional, called when call starts (if supervisor exists)
- `onCallEnded(handle, info)` - Optional, called on normal completion

### Key Methods
- `operation.stateChanges` - Stream of state changes
- `operation.waitForCleanup()` - Wait for cleanup to start
- `operation.waitForTerminal()` - Wait for operation completion
- `Ledger.initSupervisorLedger(...)` - Initialize supervisor mode

### File Locations
- Operation file: `{ledger_path}/operations/{operationId}.json`
- Orchestrator file: `{ledger_path}/{groupId}.orchestrator.json`
- Supervisors file: `{ledger_path}/{groupId}.supervisors.json`

---

## Frequently Asked Questions

**Q: What if a supervisor dies during cleanup?**
A: Rule 4 handles it - any alive participant removes the orphaned crashed frames.

**Q: Do we need ordered cleanup from last frame to first?**
A: No - stack-aware removal handles it automatically when frames are removed.

**Q: How do I detect if my callee crashed?**
A: Use `operation.stateChanges` stream or `operation.waitForCleanup()` - see Part 3a.

**Q: Can I manually stop heartbeats?**
A: No - heartbeats continue until operation is terminal (by design).

**Q: What if all supervisors in a group are dead?**
A: Fresh start - orchestrator clears registrations and starts fresh.

**Q: Can VSCode Extension start Bridge via orchestrator?**
A: Yes - use `orchestrator.requestSupervisorStart()` with start info and dependencies.

**Q: How does Ledger know the supervisor?**
A: It reads `Ledger.instance.supervisorId` when creating frames.

**Q: Where is the supervised call registry stored?**
A: In memory in the supervisor process, not in the operation file.

---

## Document Statistics

| Document | Lines | Purpose | Audience |
|----------|-------|---------|----------|
| QUICK_REFERENCE.md | 350 | Quick lookup | Everyone |
| CLEANUP_SIMPLIFICATION.md | 200 | Summary | Decision makers |
| DESIGN_UPDATE_SUMMARY.md | 300 | Change log | Reviewers |
| supervisor_orchestration.md | 1931 | Complete spec | Implementers |
| failure_notification_patterns.dart | 550 | Code examples | Developers |

**Total documentation:** ~3,300 lines of specification and examples

---

## Next Steps

1. **Review QUICK_REFERENCE.md** to understand the four rules
2. **Read supervisor_orchestration.md Part 1** for detailed cleanup mechanism
3. **Study failure_notification_patterns.dart** for Dart patterns
4. **Start implementation** with Phase 1 from checklist in CLEANUP_SIMPLIFICATION.md
5. **Update existing tests** to match new behavior
6. **Add integration tests** for cleanup scenarios

---

## Change History

- **2026-01-21:** Initial documentation with simplified cleanup mechanism
  - Created QUICK_REFERENCE.md
  - Created CLEANUP_SIMPLIFICATION.md  
  - Created DESIGN_UPDATE_SUMMARY.md
  - Rewrote supervisor_orchestration.md Parts 1, 3a, 4, 5, 7
  - Created failure_notification_patterns.dart
