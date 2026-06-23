# TrackBook — Teacher Scanning Dashboard
## UI/UX Design Specification
**Senior UI/UX Engineer Review | Mobile-First | June 2026**  
**Styling:** Tailwind CSS | **Framework:** React / Next.js  
**Context:** Teacher scans 40 books for one class in < 8 minutes

---

## 1. Design Principles for This Interface

1. **Zero cognitive load scanning** — The scanner input must always be focused. A teacher should be able to hold their phone in one hand, scan, and watch confirmations fly by.
2. **Loud feedback** — Every scan result (success, duplicate, error) must be visible AND audible (browser vibration + beep).
3. **No dead ends** — Every error state has a clear resolution path.
4. **Work offline** — Scans queue locally if WiFi drops. Syncs automatically when reconnected.

---

## 2. Overall Page Layout (Mobile-First)

```
┌─────────────────────────────────────┐
│  ← Back   [8A Mathematics]  👤 Ms. D │  ← Header bar (h-14, sticky)
├─────────────────────────────────────┤
│  📦 Issuing Books to:               │
│  ┌─────────────────────────────┐    │
│  │ 🔍 Search / Scan Student   │    │  ← Student selector (active step)
│  └─────────────────────────────┘    │
│                                     │
│  SIPHO MOKOENA  · CEMIS: C20240042  │  ← Selected student chip
│  Grade 8A                           │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐    │
│  │  📷  SCAN BOOK BARCODE      │    │  ← PRIMARY scan input (auto-focused)
│  │  [                        ] │    │
│  └─────────────────────────────┘    │
│                                     │
│  ✅ 12 scanned   ⚠️ 1 error         │  ← Live counters
│                                     │
├─────────────────────────────────────┤
│  SCANNED THIS SESSION               │  ← Scrollable feed
│  ─────────────────────────────      │
│  ✅ WC001-...-0042  Maths LB  09:14 │
│  ✅ WC001-...-0041  Maths LB  09:13 │
│  ⚠️ WC001-...-0039  DUPLICATE  09:12 │  ← Red row
│  ✅ WC001-...-0038  Maths LB  09:11 │
└─────────────────────────────────────┘
│  [  DONE — Assign All (12 Books)  ] │  ← Sticky bottom CTA
└─────────────────────────────────────┘
```

---

## 3. Component Breakdown & Tailwind Classes

### 3.1 Header Bar
```jsx
// Sticky header — always visible
<header className="sticky top-0 z-50 bg-white border-b border-gray-200 
                   px-4 h-14 flex items-center justify-between shadow-sm">
  <button className="text-blue-600 font-medium flex items-center gap-1">
    ← Back
  </button>
  <span className="font-semibold text-gray-800 text-sm">
    8A · Mathematics
  </span>
  <div className="flex items-center gap-2">
    {/* Offline indicator */}
    {isOffline && (
      <span className="text-xs bg-amber-100 text-amber-700 
                       px-2 py-0.5 rounded-full font-medium">
        ⚠ Offline — {pendingQueue.length} queued
      </span>
    )}
    <Avatar user={currentUser} size="sm" />
  </div>
</header>
```

### 3.2 Student Selector
```jsx
// Step 1: Teacher first selects/scans the student
<div className="mx-4 mt-4">
  <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
    Issuing to Student
  </label>
  
  {/* Search input OR scan student barcode/ID card */}
  <div className="relative mt-1">
    <input
      type="text"
      placeholder="Type name, CEMIS, or scan ID card..."
      className="w-full h-12 pl-10 pr-4 rounded-xl border-2 border-blue-400 
                 focus:border-blue-600 focus:ring-0 text-base bg-white shadow-sm"
      onChange={handleStudentSearch}
    />
    <SearchIcon className="absolute left-3 top-3.5 text-gray-400 w-5 h-5" />
  </div>

  {/* Selected student chip (after selection) */}
  {selectedStudent && (
    <div className="mt-2 flex items-center gap-3 bg-blue-50 border border-blue-200 
                    rounded-xl px-4 py-3">
      <div className="w-9 h-9 rounded-full bg-blue-600 flex items-center 
                      justify-center text-white font-bold text-sm">
        {selectedStudent.full_name[0]}
      </div>
      <div className="flex-1">
        <p className="font-semibold text-gray-900 text-sm">
          {selectedStudent.full_name}
        </p>
        <p className="text-xs text-gray-500">
          CEMIS: {selectedStudent.cemis_number} · {selectedStudent.class_name}
        </p>
      </div>
      <button onClick={clearStudent} 
              className="text-gray-400 hover:text-gray-600">✕</button>
    </div>
  )}
</div>
```

### 3.3 Scan Input (Core Interaction)
```jsx
// This input is ALWAYS auto-focused while scanning is active
// USB HID scanners act like keyboards — they type the barcode and hit Enter
// Smartphone camera scanning uses a JS barcode library (e.g., ZXing, Quagga2)

<div className="mx-4 mt-5">
  <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">
    Scan Book Barcode
  </label>
  
  <div className={`
    mt-1 relative rounded-2xl border-2 overflow-hidden transition-all duration-200
    ${scanState === 'idle'    ? 'border-gray-300 bg-gray-50' : ''}
    ${scanState === 'success' ? 'border-green-500 bg-green-50 animate-pulse' : ''}
    ${scanState === 'error'   ? 'border-red-500 bg-red-50' : ''}
    ${scanState === 'duplicate' ? 'border-amber-500 bg-amber-50' : ''}
  `}>
    {/* Camera scan button (mobile) */}
    <button onClick={openCameraScanner}
            className="absolute right-3 top-3 text-blue-600">
      <CameraIcon className="w-6 h-6" />
    </button>

    {/* The actual input — auto-focused, hidden cursor for clean UX */}
    <input
      ref={scanInputRef}
      type="text"
      value={currentScan}
      onChange={e => setCurrentScan(e.target.value)}
      onKeyDown={e => e.key === 'Enter' && handleScan(currentScan)}
      placeholder="Point scanner at barcode..."
      autoFocus
      className="w-full h-14 pl-4 pr-12 text-base font-mono bg-transparent 
                 focus:outline-none"
      disabled={!selectedStudent}
    />
  </div>

  {/* Inline feedback message — shown for 2 seconds then clears */}
  {scanFeedback && (
    <p className={`mt-2 text-sm font-medium flex items-center gap-2
      ${scanFeedback.type === 'success' ? 'text-green-700' : ''}
      ${scanFeedback.type === 'error'   ? 'text-red-700' : ''}
      ${scanFeedback.type === 'warning' ? 'text-amber-700' : ''}
    `}>
      {scanFeedback.icon} {scanFeedback.message}
    </p>
  )}
</div>
```

### 3.4 Live Counters Bar
```jsx
<div className="mx-4 mt-4 grid grid-cols-3 gap-3">
  <div className="bg-green-50 border border-green-200 rounded-xl p-3 text-center">
    <p className="text-2xl font-bold text-green-700">{successCount}</p>
    <p className="text-xs text-green-600 font-medium">Scanned</p>
  </div>
  <div className="bg-amber-50 border border-amber-200 rounded-xl p-3 text-center">
    <p className="text-2xl font-bold text-amber-700">{duplicateCount}</p>
    <p className="text-xs text-amber-600 font-medium">Duplicates</p>
  </div>
  <div className="bg-red-50 border border-red-200 rounded-xl p-3 text-center">
    <p className="text-2xl font-bold text-red-700">{errorCount}</p>
    <p className="text-xs text-red-600 font-medium">Errors</p>
  </div>
</div>
```

### 3.5 Scan Feed (Scrollable)
```jsx
// Most recent scans at the TOP for immediate visibility
<div className="mx-4 mt-5">
  <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-2">
    This Session
  </h3>
  
  <div className="space-y-2 max-h-64 overflow-y-auto">
    {scannedItems.map((item, i) => (
      <ScanFeedItem key={i} item={item} />
    ))}
  </div>
</div>

// ScanFeedItem component:
function ScanFeedItem({ item }) {
  const states = {
    success:   'bg-green-50 border-green-200 text-green-800',
    duplicate: 'bg-amber-50 border-amber-200 text-amber-800',
    error:     'bg-red-50 border-red-200 text-red-800',
    offline:   'bg-gray-50 border-gray-200 text-gray-600',
  };

  return (
    <div className={`
      flex items-center gap-3 px-4 py-3 rounded-xl border text-sm
      ${states[item.status]}
    `}>
      <span className="text-base">
        {item.status === 'success'   && '✅'}
        {item.status === 'duplicate' && '⚠️'}
        {item.status === 'error'     && '❌'}
        {item.status === 'offline'   && '📶'}
      </span>
      <div className="flex-1 min-w-0">
        <p className="font-mono text-xs truncate">{item.barcode}</p>
        <p className="text-xs truncate font-medium">{item.bookTitle}</p>
      </div>
      <div className="text-right text-xs opacity-70 shrink-0">
        <p>{item.time}</p>
        {item.status === 'offline' && (
          <p className="font-semibold">Queued</p>
        )}
      </div>
    </div>
  );
}
```

---

## 4. Visual States for All Scan Outcomes

### State 1: ✅ Successful Scan
- Border: `border-green-500`
- Background flash: `bg-green-50` (animate-pulse, 300ms)
- Browser: `navigator.vibrate(100)` (single short pulse)
- Audio: short "ding" via Web Audio API
- Feed entry: green row with book title + timestamp
- Scan input: auto-clears and re-focuses in 200ms

### State 2: ⚠️ Duplicate Scan (Same barcode scanned twice)
- Border: `border-amber-500`
- Background: `bg-amber-50`
- Browser: `navigator.vibrate([100, 50, 100])` (double pulse)
- Toast message: **"Already scanned! WC001-...-0042 is already in this session."**
- Feed entry: amber row labeled DUPLICATE
- Scan input: stays focused, user can continue

### State 3: ❌ Already Assigned to Another Student
- Border: `border-red-500`
- Background: `bg-red-50`
- Browser: `navigator.vibrate([200, 100, 200])` (longer double pulse)
- Error card appears (NOT a toast — needs action):
  ```
  ┌──────────────────────────────────────────┐
  │ ❌ Book Already Assigned                 │
  │ WC001-9780636143-0039                    │
  │ Currently with: Thandeka Nkosi (8A)      │
  │ Must be returned before re-issuing.      │
  │                                          │
  │ [Dismiss]     [Mark as Return Instead]   │
  └──────────────────────────────────────────┘
  ```

### State 4: ❌ Book is Lost / Written Off
- Red error card, no resolution from this screen
- Message: "This book (WC001-...-0041) is marked as LOST. Contact Admin."

### State 5: 📶 Offline — Scan Queued
- Amber offline banner at top (from header)
- Scan is accepted and added to local queue (IndexedDB)
- Feed entry shows "QUEUED" badge
- On reconnect: auto-sync triggers, queued scans sent to API in order

---

## 5. Workflow: Issuing 40 Books to a Full Class (Happy Path)

```
Step 1: Teacher opens session
        → Selects class (8A) + subject (Mathematics)
        → Session state initialised

Step 2: Teacher selects first student
        → Types name or scans student ID card
        → Sipho Mokoena confirmed as target

Step 3: Teacher scans books one by one
        → Each scan: green flash + vibrate + book added to list
        → Duplicates: amber warning, no re-add
        → Errors: red card with resolution options

Step 4: Teacher taps [DONE — Assign All (12 Books)]
        → Confirmation modal:
           "Assign 12 books to Sipho Mokoena?"
           [Confirm] [Cancel]
        → On confirm: POST /api/v1/transactions/issue
        → Success: receipt shown, session resets to next student

Step 5: Repeat Steps 2-4 for remaining 39 students
        → Each student gets their own session
        → Progress indicator: "12/40 students done"
```

---

## 6. Progressive Web App (PWA) Offline Strategy

```javascript
// Service Worker strategy for offline scanning
// Using Workbox (included via Next.js PWA plugin)

// Cache scan lookups for known barcodes
workbox.routing.registerRoute(
  /\/api\/v1\/inventory\/lookup\//,
  new workbox.strategies.StaleWhileRevalidate({
    cacheName: 'barcode-cache',
    plugins: [new workbox.expiration.ExpirationPlugin({ maxEntries: 5000 })]
  })
);

// Queue POST requests when offline
const bgSyncPlugin = new workbox.backgroundSync.BackgroundSyncPlugin(
  'scan-queue',
  { maxRetentionTime: 24 * 60 } // retry for 24 hours
);

workbox.routing.registerRoute(
  /\/api\/v1\/transactions\//,
  new workbox.strategies.NetworkOnly({ plugins: [bgSyncPlugin] }),
  'POST'
);
```

---

## 7. Accessibility Considerations

- Barcode input has `aria-label="Scan barcode"` and `aria-live="polite"` for screen readers
- All color feedback is also communicated via text (not color-only)
- Font sizes minimum 14px — readable in bright classroom light
- Touch targets minimum 44×44px (Apple HIG) — usable with one hand
- Dark mode supported via `dark:` Tailwind classes
