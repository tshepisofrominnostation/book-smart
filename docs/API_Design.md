# TrackBook — REST API Design
**Senior Backend Engineer Review | Version 1.0 | June 2026**  
**Stack:** Node.js / Express (TypeScript) or Python / FastAPI  
**Auth:** JWT Bearer tokens with school_id claim

---

## Base URL
```
https://api.trackbook.co.za/api/v1
```

All endpoints require `Authorization: Bearer <jwt_token>` header.  
JWT payload includes: `{ user_id, school_id, role, email }`

---

## Endpoint 1: POST /api/v1/transactions/issue

**Purpose:** Bulk-issue specific serialized books (by barcode) to one or more students. Generates a digital receipt (batch record).

### Request
```json
POST /api/v1/transactions/issue
Content-Type: application/json
Authorization: Bearer <token>

{
  "batch_note": "Grade 8A Mathematics books - Term 1",
  "hierarchy_bypassed": false,
  "bypass_reason": null,
  "assignments": [
    {
      "barcode": "WC001-9780636143-0042",
      "to_custodian_type": "student",
      "to_custodian_id": "stu_uuid_001",
      "condition_at_handoff": "good"
    },
    {
      "barcode": "WC001-9780636143-0043",
      "to_custodian_type": "student",
      "to_custodian_id": "stu_uuid_002",
      "condition_at_handoff": "good"
    }
  ]
}
```

### Internal Logic (step-by-step)
```
1. Authenticate & authorize:
   - Extract school_id, user_id, role from JWT
   - Confirm role is allowed to issue (teacher, hod, administrator, school_admin)

2. Validate request body:
   - assignments array must be non-empty
   - Each barcode must be non-empty string
   - Each to_custodian_id must exist in users or students table

3. BEGIN TRANSACTION (PostgreSQL)

4. For each assignment in the array:
   a. SELECT inventory_item WHERE barcode = ? AND school_id = ? FOR UPDATE
      → If NOT FOUND: collect error {barcode, error: "BARCODE_NOT_FOUND"}
      → If item.current_custodian_type != issuer's type: 
         collect error {barcode, error: "CUSTODY_CHAIN_VIOLATION"}
      → If item.condition IN ('lost', 'written_off'):
         collect error {barcode, error: "ITEM_NOT_ISSUABLE", detail: item.condition}
      → If item already assigned to a DIFFERENT student (not a return path):
         collect error {barcode, error: "ALREADY_ASSIGNED", 
                        detail: item.current_custodian_name}

   b. If no error for this item:
      INSERT INTO custody_transactions (
        school_id, inventory_item_id, transaction_type='issue',
        from_custodian_type, from_custodian_id, from_custodian_name,
        to_custodian_type, to_custodian_id, to_custodian_name,
        condition_at_handoff, batch_id, issued_by_id
      )
      -- The sync_inventory_custodian trigger handles updating inventory_items

5. If ANY error exists AND strict_mode=true:
   ROLLBACK → return 422 with full error list

6. If errors exist AND strict_mode=false (partial success mode):
   COMMIT successful rows, return 207 Multi-Status

7. COMMIT

8. Generate receipt record in audit log
```

### Success Response (200)
```json
{
  "status": "success",
  "batch_id": "batch_uuid_here",
  "issued_count": 2,
  "failed_count": 0,
  "receipt": {
    "batch_id": "batch_uuid_here",
    "issued_by": "Ms. Nomsa Dlamini",
    "timestamp": "2026-06-21T08:30:00Z",
    "items": [
      {
        "barcode": "WC001-9780636143-0042",
        "title": "Platinum Mathematics Grade 8 Learner Book",
        "assigned_to": "Sipho Mokoena",
        "cemis": "C20240042",
        "condition": "good"
      }
    ]
  }
}
```

### Error Response (422 — barcode already assigned)
```json
{
  "status": "partial_error",
  "issued_count": 1,
  "failed_count": 1,
  "errors": [
    {
      "barcode": "WC001-9780636143-0043",
      "error_code": "ALREADY_ASSIGNED",
      "message": "This book is currently assigned to Thandeka Nkosi (CEMIS: C20240031). It must be returned before re-issuing.",
      "current_custodian": "Thandeka Nkosi"
    }
  ]
}
```

---

## Endpoint 2: POST /api/v1/transactions/receive

**Purpose:** Record the return of a book. Checks condition vs. initial issue state. Updates ledger.

### Request
```json
POST /api/v1/transactions/receive
Content-Type: application/json

{
  "barcode": "WC001-9780636143-0042",
  "condition_at_return": "damaged",
  "notes": "Cover torn, pages 12-15 missing",
  "return_to_custodian_type": "teacher",
  "return_to_custodian_id": "teacher_uuid_001"
}
```

### Internal Logic
```
1. Authenticate & validate
2. Fetch inventory_item by barcode (school-scoped) FOR UPDATE
3. Fetch the most recent custody_transaction for this item (the active issue)
4. Validate:
   - Item must not already be in school stock (condition: no active issue)
   - The person receiving must be in the correct chain above current custodian
5. Compare condition_at_return vs. condition_at_handoff:
   - If degraded (e.g., 'good' → 'damaged'): flag = CONDITION_DEGRADED
6. BEGIN TRANSACTION
7. INSERT INTO custody_transactions (type='return', condition_at_return, ...)
8. If CONDITION_DEGRADED:
   - INSERT INTO billing_claims (student_id, amount_due from catalog, ...)
9. COMMIT
10. Return response with condition comparison and any billing_claim_id created
```

### Success Response (200)
```json
{
  "status": "success",
  "barcode": "WC001-9780636143-0042",
  "book_title": "Platinum Mathematics Grade 8 Learner Book",
  "returned_by": "Sipho Mokoena",
  "condition_at_issue": "good",
  "condition_at_return": "damaged",
  "condition_flag": "CONDITION_DEGRADED",
  "billing_claim_created": true,
  "billing_claim_id": "claim_uuid_here",
  "billing_amount": 245.00
}
```

---

## Endpoint 3: POST /api/v1/audit/schedule

**Purpose:** Creates an audit session snapshot — records expected inventory state vs. physical count.

### Request
```json
POST /api/v1/audit/schedule
Content-Type: application/json

{
  "name": "Mid-Year Audit June 2026",
  "scope": "full_school",
  "grade_ids": null,
  "notes": "Scheduled before July school holidays"
}
```

### Internal Logic
```
1. Authenticate — role must be school_admin or administrator
2. Check no other audit session is 'in_progress' for this school
3. BEGIN TRANSACTION
4. INSERT INTO audit_sessions (school_id, name, initiated_by, status='in_progress')
5. Snapshot current expected state:
   SELECT barcode, current_custodian_type, current_custodian_id, 
          current_custodian_name, condition
   FROM inventory_items 
   WHERE school_id = ? AND is_active = true
   → Store this as JSONB in audit_sessions.expected_snapshot
6. COMMIT
7. Return audit_session_id — teachers/admins then scan against this session
```

### Scanning into an Audit (POST /api/v1/audit/{session_id}/scan)
```json
{
  "barcode": "WC001-9780636143-0042",
  "condition_observed": "good"
}
```
→ Marks that barcode as scanned in the session. System compares to expected snapshot and flags discrepancies.

### Audit Completion Response
```json
{
  "audit_session_id": "audit_uuid_here",
  "name": "Mid-Year Audit June 2026",
  "total_expected": 1240,
  "total_scanned": 1187,
  "discrepancies": {
    "missing": 53,
    "orphaned": 0,
    "condition_changed": 12
  },
  "report_url": "https://api.trackbook.co.za/reports/audit_uuid_here.pdf"
}
```

---

## Endpoint 4: GET /api/v1/inventory/lookup/{barcode}

**Purpose:** Fast barcode lookup — used by the scanning UI to display book + custodian info instantly.

### Response (< 500ms target via indexed barcode lookup)
```json
{
  "barcode": "WC001-9780636143-0042",
  "book": {
    "title": "Platinum Mathematics Grade 8 Learner Book",
    "publisher": "Maskew Miller Longman",
    "grade": "Grade 8",
    "subject": "Mathematics",
    "isbn": "9780636143005"
  },
  "current_custodian": {
    "type": "student",
    "id": "stu_uuid_001",
    "name": "Sipho Mokoena",
    "cemis": "C20240042",
    "class": "8A"
  },
  "condition": "good",
  "status": "assigned"
}
```

---

## Endpoint 5: POST /api/v1/students/import

**Purpose:** Bulk student upload via CSV/Excel (see Phase 4 code).

```json
POST /api/v1/students/import
Content-Type: multipart/form-data

file: students.xlsx
grade_id: "grade_uuid"
strict_mode: true
```

### Response
```json
{
  "job_id": "import_job_uuid",
  "status": "processing",
  "poll_url": "/api/v1/jobs/import_job_uuid/status"
}
```

---

## Common Error Codes

| Code | HTTP Status | Description |
|---|---|---|
| `BARCODE_NOT_FOUND` | 404 | Barcode doesn't exist in this school's inventory |
| `ALREADY_ASSIGNED` | 409 | Book currently assigned to another student |
| `CUSTODY_CHAIN_VIOLATION` | 403 | Issuer doesn't currently hold this book in the chain |
| `ITEM_NOT_ISSUABLE` | 422 | Book is lost or written off |
| `AUDIT_IN_PROGRESS` | 409 | Another audit is already running |
| `CEMIS_DUPLICATE` | 409 | CEMIS number already exists for this school |
| `CEMIS_INVALID_FORMAT` | 422 | CEMIS doesn't match expected format |
| `UNAUTHORIZED_ROLE` | 403 | User's role cannot perform this action |
| `SCHOOL_SCOPE_VIOLATION` | 403 | Resource belongs to a different school |
