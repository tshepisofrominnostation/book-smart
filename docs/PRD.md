# TrackBook — Product Requirements Document (PRD)
**Version:** 1.0 | **Date:** June 2026 | **Status:** Draft  
**Product Manager:** Senior PM Review  
**Platform Type:** B2B SaaS — School Inventory & Asset Tracking

---

## 1. Executive Summary

TrackBook is a B2B SaaS platform purpose-built for South African (and emerging-market) public and private schools to track physical inventory — primarily textbooks and school assets — at the individual serialized item level. The system enforces a multi-tiered chain of custody that mirrors the school's administrative hierarchy, ensuring accountability at every handoff and enabling rapid, evidence-based billing recovery for lost or damaged books.

**Core Problem:** Schools lose millions in book budgets annually due to untracked handoffs, no serialized records, and no digital audit trail. When a book goes missing, there is no data to determine who last held it.

**Core Solution:** Every physical book gets a unique serialized barcode (not just an ISBN). Every handoff is a logged transaction. Every student is tied to a national ID (CEMIS). Financial loss is converted into an auditable, recoverable claim.

---

## 2. Goals & Success Metrics

| Goal | KPI | Target (Year 1) |
|---|---|---|
| Prevent book loss | % of books returned end-of-year | ≥ 90% return rate |
| Adoption | Schools onboarded | 50 schools |
| Speed | Time to issue 40 books (1 class) | < 8 minutes |
| Data integrity | Upload error rate on bulk imports | < 0.5% |
| Recovery | Billing claims raised vs. collected | ≥ 70% collection |

---

## 3. Core User Personas

### 3.1 System Administrator (SysAdmin / Deputy Principal)
- **Who:** Deputy Principal or senior admin staff. One per school. Has full system access.
- **Goals:** Onboard staff and students, configure school hierarchy, run full audits, generate financial loss reports, authorize billing.
- **Pain Points:** Currently uses Excel spreadsheets with no audit trail; no way to trace a missing book back to a student.
- **Key Actions:** Bulk import students/staff, configure grade structures, generate end-of-year reports, approve billing claims.

### 3.2 Administrator (Inventory Clerk / Storeroom Manager)
- **Who:** School administrator or storeroom manager. Handles physical receipt of new stock from government/procurement.
- **Goals:** Receive bulk deliveries, print and apply barcodes, issue books up the chain to HoDs.
- **Pain Points:** Manual counting, no barcode system, hand-written ledgers easily lost.
- **Key Actions:** Receive stock, generate unique barcodes, bulk-issue to HoDs, run stock-on-hand reports.

### 3.3 Head of Department (HoD)
- **Who:** Subject/grade HoD. Receives books from Administrator and distributes to teachers.
- **Goals:** Track which teacher holds which set of books per subject. Confirm handoffs digitally.
- **Pain Points:** Teachers claim they never received books; no proof of issue.
- **Key Actions:** Accept custody from Admin, assign books to teachers, view teacher-level accountability report.

### 3.4 Teacher
- **Who:** Classroom teacher. The most frequent daily user. Mobile-first interactions.
- **Goals:** Issue individual books to students quickly (scan-based), record returns, flag damaged books.
- **Pain Points:** Scanning 40 books per class is tedious; needs to work offline if WiFi is unreliable.
- **Key Actions:** Scan-to-issue books to individual students, scan-to-return, flag condition changes, view class roster accountability.

### 3.5 Parent / Guardian (Read-Only Portal)
- **Who:** Parent or legal guardian of a student.
- **Goals:** Know which books their child holds, understand any pending financial obligations.
- **Pain Points:** Surprised by end-of-year invoices; no visibility during the year.
- **Key Actions:** View child's current book assignments, view condition at issue, acknowledge billing notices.

---

## 4. Functional Requirements

### 4.1 Authentication & Role Management
- **FR-001:** Multi-role RBAC system: SysAdmin, Administrator, HoD, Teacher, Parent (read-only).
- **FR-002:** School-scoped accounts — a teacher at School A cannot see data for School B.
- **FR-003:** Invite-based onboarding (admin invites staff via email).
- **FR-004:** SSO support via Google Workspace (optional, Phase 2).
- **FR-005:** Session timeout after 30 minutes of inactivity.

### 4.2 School & Hierarchy Configuration
- **FR-006:** SysAdmin can configure grades (e.g., Grade 8–12), classes (8A, 8B), and subjects.
- **FR-007:** HoD assignments are subject-specific (e.g., one HoD for Mathematics, another for English).
- **FR-008:** System supports flexible chain of custody — books can bypass HoD layer (Admin → Teacher directly) or bypass Teacher layer (Admin → Student for direct allocation).

### 4.3 Master Textbook Database (Locked Catalog)
- **FR-009:** Pre-populated, admin-locked catalog of textbooks with: Title, Publisher, Grade, Subject, Component (e.g., Learner Book, Teacher Guide), ISBN, Cover Image URL.
- **FR-010:** School-level admins CANNOT add free-text book titles — they must select from the approved catalog. This prevents data inconsistency.
- **FR-011:** SysAdmin (platform-level) can add/edit catalog entries.
- **FR-012:** Catalog supports filtering by Grade + Subject to surface the correct set of books.

### 4.4 Inventory & Barcode Management
- **FR-013:** Each physical copy receives a unique serialized barcode (format: `[SchoolCode]-[ISBN]-[SequenceNumber]`, e.g., `WC001-9780636143-0042`).
- **FR-014:** System generates and exports print-ready barcode label sheets (PDF, Avery-compatible).
- **FR-015:** Condition states: `New`, `Good`, `Fair`, `Damaged`, `Lost`, `Written-Off`.
- **FR-016:** Each physical copy record stores: Barcode ID, Book Title (FK to catalog), School, Condition, Current Custodian, Acquisition Date, Acquisition Cost.
- **FR-017:** Barcode scanning supported via: (a) smartphone camera (QR/barcode via browser API), (b) USB HID plug-and-play scanner (auto-input to active field).

### 4.5 Student Profiles & CEMIS Integration
- **FR-018:** Student records must include: Full Name, CEMIS Number (unique national ID), Grade, Class, Parent/Guardian contact (email + phone).
- **FR-019:** CEMIS number is the primary unique identifier — the system enforces uniqueness at the database level.
- **FR-020:** Students can be bulk-imported via Excel/CSV (see FR-028).
- **FR-021:** Student profiles display current book assignments, historical assignments, and any outstanding billing claims.

### 4.6 Transactions & Chain of Custody
- **FR-022:** Every book movement is recorded as an immutable transaction: Issuer (user), Receiver (user or student), Barcode, Condition at handoff, Timestamp, Digital acknowledgment (checkbox or signature).
- **FR-023:** Bulk issue: A teacher can scan multiple barcodes in sequence and assign all to one student, OR assign a pre-configured "book set" to a student via one action.
- **FR-024:** Flexible custody bypass: Admin can issue directly to a student (skipping HoD and Teacher layers), but this must be flagged and reasons recorded.
- **FR-025:** "Accept Custody" action: When a HoD or Teacher receives books, they must explicitly confirm receipt (digital acknowledgment). Unacknowledged transfers are flagged in a dashboard.
- **FR-026:** Returns: When a book is returned, the system records condition at return and flags any condition degradation (e.g., `Good` → `Damaged`) for review.

### 4.7 Mid-Year Auditing
- **FR-027:** Scheduled Audit: SysAdmin or Administrator can trigger an audit snapshot — a frozen record of expected inventory (from transactions) vs. physical scanned count.
- **FR-027a:** Audit generates a discrepancy report: books expected but not scanned (potentially lost), books scanned but not in expected list (orphans).
- **FR-027b:** Audit results can be exported to PDF and Excel.

### 4.8 Bulk Excel Import/Export
- **FR-028:** Bulk Student Import: Upload CSV/Excel with required columns (CEMIS, Full Name, Grade, Class, Parent Email). System validates, shows preview with error rows highlighted, user confirms, system inserts in a transaction (all-or-nothing rollback on error).
- **FR-029:** Bulk Inventory Import: Upload CSV of new deliveries (Barcode, ISBN, Condition, Acquisition Cost). System generates serial barcodes if not provided.
- **FR-030:** Export: Any table view (students, inventory, transactions, audit) can be exported to Excel and PDF.

### 4.9 Billing & Loss Recovery
- **FR-031:** When a book is marked `Lost` or `Damaged Beyond Repair`, the system auto-generates a billing claim against the last custodian (student).
- **FR-032:** Billing claim includes: Student name, CEMIS, Book title, Barcode, Condition at issue, Condition at return/audit, Replacement cost (from catalog), Parent contact.
- **FR-033:** SysAdmin can mark a claim as: `Pending`, `Paid`, `Waived`, `Escalated`.
- **FR-034:** System generates a printable billing notice letter (PDF) per student.
- **FR-035:** Parent portal displays pending claims with payment instructions.

### 4.10 Reporting & Dashboards
- **FR-036:** School-level dashboard: total books, total assigned, total returned, total lost, total billing outstanding.
- **FR-037:** Teacher dashboard: class roster with book assignment status per student.
- **FR-038:** HoD dashboard: teacher accountability view — which teachers have outstanding books.
- **FR-039:** Historical audit trail: full transaction log, filterable by date range, user, barcode, student.

---

## 5. Non-Functional Requirements

| Requirement | Detail |
|---|---|
| **Performance** | Barcode scan-to-confirm < 500ms. Bulk import of 1,000 students < 30 seconds. |
| **Availability** | 99.5% uptime during school hours (07:00–17:00 SAST). |
| **Offline Support** | Teacher scanning view must support offline queuing (PWA with local cache). Syncs when reconnected. |
| **Security** | All data encrypted at rest (AES-256) and in transit (TLS 1.3). Role-based data access enforced at API layer. |
| **Compliance** | POPIA compliant (South African data privacy). Student CEMIS numbers treated as sensitive PII. |
| **Accessibility** | WCAG 2.1 AA for all primary interfaces. |
| **Multi-Tenancy** | Full school data isolation. One school cannot access another school's data. |

---

## 6. Out-of-Scope (v1.0)

| Item | Reason |
|---|---|
| Full library cataloging / lending system | Different use case (timed loans, reservations, late fees). Out of scope. |
| e-Book / digital resource tracking | Physical assets only in v1. |
| Student academic performance tracking | Out of scope — covered by school MIS systems (e.g., SASAMS). |
| Financial payment processing (accepting online payments) | Billing notice generation only; actual payment via school finance system. |
| Government CEMIS API direct integration (real-time) | API access requires WCED/DBE partnership. Planned for Phase 3. |
| Procurement / PO generation to suppliers | Phase 2 feature. |
| Parent mobile app (native iOS/Android) | Web-responsive portal only in v1. |

---

## 7. Dependencies & Assumptions

- Schools have at least one device with a camera or USB barcode scanner per teacher.
- CEMIS numbers are available from school administrative records for import.
- Internet connectivity available at school level (even if intermittent — hence offline mode).
- Provincial/national textbook catalog data can be seeded from DBE curriculum documents.

---
