# 🐛 Astal Bar Known Issues

## Active Module States

### Color State Inconsistency

**Priority:** Medium **Status:** Open **Component:** Multiple Modules

Some modules intermittently lose their active color state indicator, affecting
the visual feedback for users.

**Affected Modules:**

- Battery Conservation Mode Toggle
- Various other module states

---

## Network Module

### WiFi State Display

**Priority:** High **Status:** Open **Component:** WiFi Module

The WiFi module continues to display outdated connection information when WiFi
is disabled, instead of showing a user-friendly status like "N/A" or
"Disconnected".

**Expected Behavior:**

- Should display "Not Connected" or "N/A" when WiFi is disabled
- Should update status immediately after state changes

---

## Audio Module

### Volume OSD Initialization

**Priority:** Medium **Status:** In Progress **Component:** Volume Module & OSD

The volume module triggers the OSD during bar initialization. While currently
patched with a variable flag, the implementation needs restructuring.

**Required Changes:**

1. Initialize OSD first
2. Have volume module check for existing OSD variable
3. Refactor current reversed implementation

---

## Power Module

### Conservation Mode Toggle State

**Priority:** Medium **Status:** Open **Component:** Battery Module

The battery conservation mode toggle switch experiences inconsistent active
state coloring, similar to the WiFi module issue.

**Steps to Reproduce:**

1. Toggle conservation mode
2. Active state color occasionally fails to update

---

## GitHub Activity Module

### Event Feed Display

**Priority:** Low **Status:** Open **Component:** GitHub Module

The GitHub activity module doesn't show instantly i open. We need to wait for a
few seconds before the feed displays.

**Steps to Reproduce:**

1. Open the GitHub module
2. Wait for a few seconds before the feed displays

---

## System Module

### Suspension Recovery Error

**Priority:** High **Status:** Open **Component:** System Suspension Handler

The system produces a variable error when resuming from suspension mode,
specifically displaying an "emit signal" error.

**Steps to Reproduce:**

1. Put laptop into suspension mode
2. Resume from suspension
3. Error appears referencing "Variable" with an "emit signal" error

**Expected Behavior:**

- System should resume from suspension without errors
- All signals should reconnect properly after suspension
