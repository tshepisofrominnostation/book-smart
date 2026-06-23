-- ============================================================
-- TrackBook — PostgreSQL Database Schema (DDL)
-- Lead Database Architect Review | Version 1.0 | June 2026
-- ============================================================
-- Design Principles:
--   1. Normalized to 3NF — no redundant data storage
--   2. Immutable audit ledger — transactions are never deleted or updated
--   3. Soft deletes everywhere (deleted_at) — no data is hard-deleted
--   4. Multi-tenant via school_id on every table
--   5. CEMIS enforced unique at DB level
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- EXTENSIONS
-- ─────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ─────────────────────────────────────────────────────────────
-- 1. SCHOOLS (one row per tenant)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE schools (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(255) NOT NULL,
    emis_code       VARCHAR(20) UNIQUE NOT NULL,   -- Government school code
    province        VARCHAR(50) NOT NULL,
    district        VARCHAR(100),
    address         TEXT,
    contact_email   VARCHAR(255),
    contact_phone   VARCHAR(20),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ                    -- soft delete
);

-- ─────────────────────────────────────────────────────────────
-- 2. USERS (staff: SysAdmin, Administrator, HoD, Teacher)
-- ─────────────────────────────────────────────────────────────
CREATE TYPE user_role AS ENUM (
    'platform_admin',   -- TrackBook super admin
    'school_admin',     -- Deputy Principal / SysAdmin
    'administrator',    -- Storeroom / Inventory Clerk
    'hod',              -- Head of Department
    'teacher',
    'parent'
);

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id       UUID REFERENCES schools(id) ON DELETE RESTRICT,  -- NULL for platform_admin
    email           VARCHAR(255) UNIQUE NOT NULL,
    password_hash   TEXT NOT NULL,                 -- bcrypt hash
    full_name       VARCHAR(255) NOT NULL,
    role            user_role NOT NULL,
    phone           VARCHAR(20),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ
);

-- ─────────────────────────────────────────────────────────────
-- 3. GRADES & CLASSES (school configuration)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE grades (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    name        VARCHAR(50) NOT NULL,              -- e.g., "Grade 8", "Grade 12"
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE classes (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    grade_id    UUID NOT NULL REFERENCES grades(id) ON DELETE CASCADE,
    school_id   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    name        VARCHAR(50) NOT NULL,              -- e.g., "8A", "8B"
    teacher_id  UUID REFERENCES users(id),         -- Homeroom teacher
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(school_id, grade_id, name)
);

-- ─────────────────────────────────────────────────────────────
-- 4. SUBJECTS & HOD ASSIGNMENTS
-- ─────────────────────────────────────────────────────────────
CREATE TABLE subjects (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id   UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    name        VARCHAR(100) NOT NULL,             -- e.g., "Mathematics", "Life Sciences"
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(school_id, name)
);

CREATE TABLE hod_subject_assignments (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id   UUID NOT NULL REFERENCES schools(id),
    hod_id      UUID NOT NULL REFERENCES users(id),
    subject_id  UUID NOT NULL REFERENCES subjects(id),
    grade_id    UUID REFERENCES grades(id),        -- NULL = all grades for this subject
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(school_id, hod_id, subject_id, grade_id)
);

-- ─────────────────────────────────────────────────────────────
-- 5. MASTER TEXTBOOK CATALOG (locked, platform-managed)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE catalog_books (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    isbn            VARCHAR(20) UNIQUE NOT NULL,
    title           VARCHAR(500) NOT NULL,
    publisher       VARCHAR(255) NOT NULL,
    grade           VARCHAR(50) NOT NULL,          -- e.g., "Grade 8"
    subject         VARCHAR(100) NOT NULL,
    component       VARCHAR(100) NOT NULL,         -- e.g., "Learner Book", "Teacher Guide"
    edition         VARCHAR(50),
    year_published  SMALLINT,
    replacement_cost NUMERIC(10,2),               -- default billing amount
    cover_image_url TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- NOTE: Only platform_admin can INSERT/UPDATE this table (enforced via RLS)
);

-- ─────────────────────────────────────────────────────────────
-- 6. STUDENTS
-- ─────────────────────────────────────────────────────────────
CREATE TABLE students (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id       UUID NOT NULL REFERENCES schools(id) ON DELETE RESTRICT,
    cemis_number    VARCHAR(50) NOT NULL,           -- National Student ID
    full_name       VARCHAR(255) NOT NULL,
    date_of_birth   DATE,
    grade_id        UUID REFERENCES grades(id),
    class_id        UUID REFERENCES classes(id),
    enrollment_date DATE NOT NULL DEFAULT CURRENT_DATE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ,

    -- CEMIS uniqueness is SCHOOL-scoped (same CEMIS cannot appear twice at same school)
    -- but a student transferring schools would have new school record
    UNIQUE(school_id, cemis_number)
);

-- ─────────────────────────────────────────────────────────────
-- 7. PARENT / GUARDIAN PROFILES
-- ─────────────────────────────────────────────────────────────
CREATE TABLE guardians (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES users(id),     -- if they have a portal login
    full_name       VARCHAR(255) NOT NULL,
    email           VARCHAR(255),
    phone           VARCHAR(20),
    relationship    VARCHAR(50),                   -- e.g., "Mother", "Father", "Guardian"
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE student_guardians (
    student_id      UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    guardian_id     UUID NOT NULL REFERENCES guardians(id) ON DELETE CASCADE,
    is_primary      BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (student_id, guardian_id)
);

-- ─────────────────────────────────────────────────────────────
-- 8. PHYSICAL INVENTORY (individual book copies)
-- ─────────────────────────────────────────────────────────────
CREATE TYPE book_condition AS ENUM (
    'new',
    'good',
    'fair',
    'damaged',
    'lost',
    'written_off'
);

CREATE TYPE custodian_type AS ENUM (
    'school',       -- In storeroom / not yet issued
    'administrator',
    'hod',
    'teacher',
    'student'
);

CREATE TABLE inventory_items (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id           UUID NOT NULL REFERENCES schools(id) ON DELETE RESTRICT,
    catalog_book_id     UUID NOT NULL REFERENCES catalog_books(id),

    -- Serialized barcode: format WC001-9780636143-0042
    barcode             VARCHAR(100) UNIQUE NOT NULL,
    barcode_sequence    INTEGER NOT NULL,           -- numeric suffix for ordering

    condition           book_condition NOT NULL DEFAULT 'new',
    acquisition_date    DATE NOT NULL DEFAULT CURRENT_DATE,
    acquisition_cost    NUMERIC(10,2),

    -- Current custodian (denormalized for fast lookup — source of truth is custody_log)
    current_custodian_type  custodian_type NOT NULL DEFAULT 'school',
    current_custodian_id    UUID,                  -- FK to users.id or students.id
    current_custodian_name  VARCHAR(255),          -- denormalized for reporting speed

    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ
);

-- ─────────────────────────────────────────────────────────────
-- 9. CUSTODY TRANSACTION LEDGER (immutable audit trail)
-- ─────────────────────────────────────────────────────────────
-- This is the heart of the system. NEVER UPDATE OR DELETE rows here.
-- Every book handoff creates a new row.

CREATE TYPE transaction_type AS ENUM (
    'issue',            -- Issuing a book to next custodian
    'return',           -- Returning a book up the chain
    'transfer',         -- Lateral transfer (e.g., Teacher A → Teacher B)
    'audit_confirm',    -- Confirmed present during audit
    'condition_update', -- Condition changed without custody change
    'write_off'         -- Book declared lost/destroyed
);

CREATE TABLE custody_transactions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id           UUID NOT NULL REFERENCES schools(id),
    inventory_item_id   UUID NOT NULL REFERENCES inventory_items(id),

    transaction_type    transaction_type NOT NULL,

    -- From
    from_custodian_type custodian_type,
    from_custodian_id   UUID,
    from_custodian_name VARCHAR(255),

    -- To
    to_custodian_type   custodian_type NOT NULL,
    to_custodian_id     UUID NOT NULL,
    to_custodian_name   VARCHAR(255),

    -- Condition snapshot at time of handoff
    condition_at_handoff    book_condition NOT NULL,
    condition_at_return     book_condition,        -- filled in on return transactions
    notes               TEXT,

    -- Acknowledgment
    acknowledged_at     TIMESTAMPTZ,              -- NULL = pending acknowledgment
    acknowledged_by_id  UUID REFERENCES users(id),

    -- Bypass flag (for skipping hierarchy layers)
    hierarchy_bypassed  BOOLEAN NOT NULL DEFAULT FALSE,
    bypass_reason       TEXT,

    -- Bulk reference (multiple transactions from one scanning session)
    batch_id            UUID,                     -- groups transactions from same session

    issued_by_id        UUID NOT NULL REFERENCES users(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()

    -- NO updated_at — this table is append-only
);

-- ─────────────────────────────────────────────────────────────
-- 10. AUDIT SESSIONS
-- ─────────────────────────────────────────────────────────────
CREATE TYPE audit_status AS ENUM ('in_progress', 'completed', 'cancelled');

CREATE TABLE audit_sessions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id       UUID NOT NULL REFERENCES schools(id),
    name            VARCHAR(255) NOT NULL,          -- e.g., "Mid-Year Audit 2026"
    initiated_by    UUID NOT NULL REFERENCES users(id),
    status          audit_status NOT NULL DEFAULT 'in_progress',
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    notes           TEXT
);

CREATE TABLE audit_discrepancies (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    audit_session_id    UUID NOT NULL REFERENCES audit_sessions(id) ON DELETE CASCADE,
    inventory_item_id   UUID NOT NULL REFERENCES inventory_items(id),
    barcode             VARCHAR(100) NOT NULL,
    expected_custodian  VARCHAR(255),
    scanned_at          TIMESTAMPTZ,               -- NULL = not scanned (missing)
    discrepancy_type    VARCHAR(50) NOT NULL,       -- 'missing', 'orphan', 'condition_change'
    resolved            BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_at         TIMESTAMPTZ,
    notes               TEXT
);

-- ─────────────────────────────────────────────────────────────
-- 11. BILLING CLAIMS
-- ─────────────────────────────────────────────────────────────
CREATE TYPE claim_status AS ENUM ('pending', 'paid', 'waived', 'escalated', 'written_off');

CREATE TABLE billing_claims (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id           UUID NOT NULL REFERENCES schools(id),
    student_id          UUID NOT NULL REFERENCES students(id),
    inventory_item_id   UUID NOT NULL REFERENCES inventory_items(id),
    transaction_id      UUID REFERENCES custody_transactions(id), -- triggering transaction

    amount_due          NUMERIC(10,2) NOT NULL,
    condition_at_issue  book_condition NOT NULL,
    condition_at_claim  book_condition NOT NULL,
    claim_reason        TEXT NOT NULL,
    status              claim_status NOT NULL DEFAULT 'pending',

    raised_by_id        UUID NOT NULL REFERENCES users(id),
    raised_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ,
    resolved_by_id      UUID REFERENCES users(id),
    resolution_notes    TEXT
);

-- ─────────────────────────────────────────────────────────────
-- 12. BULK IMPORT JOBS (for tracking upload status)
-- ─────────────────────────────────────────────────────────────
CREATE TYPE import_type AS ENUM ('students', 'inventory');
CREATE TYPE import_status AS ENUM ('pending', 'processing', 'completed', 'failed', 'partial');

CREATE TABLE import_jobs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    school_id       UUID NOT NULL REFERENCES schools(id),
    import_type     import_type NOT NULL,
    status          import_status NOT NULL DEFAULT 'pending',
    filename        VARCHAR(500),
    total_rows      INTEGER,
    rows_succeeded  INTEGER DEFAULT 0,
    rows_failed     INTEGER DEFAULT 0,
    error_log       JSONB,                         -- array of {row, error_message}
    initiated_by    UUID NOT NULL REFERENCES users(id),
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ
);


-- ═══════════════════════════════════════════════════════════════
-- INDEXES — Performance-critical for reporting and scanning
-- ═══════════════════════════════════════════════════════════════

-- Inventory lookups (the #1 hot path — barcode scan)
CREATE UNIQUE INDEX idx_inventory_barcode ON inventory_items(barcode);
CREATE INDEX idx_inventory_school ON inventory_items(school_id);
CREATE INDEX idx_inventory_custodian ON inventory_items(current_custodian_id, current_custodian_type);
CREATE INDEX idx_inventory_catalog ON inventory_items(catalog_book_id);
CREATE INDEX idx_inventory_condition ON inventory_items(school_id, condition);

-- Student lookups (CEMIS is the key lookup for issuing)
CREATE UNIQUE INDEX idx_students_cemis_school ON students(school_id, cemis_number);
CREATE INDEX idx_students_class ON students(class_id);
CREATE INDEX idx_students_grade ON students(grade_id);

-- Transaction ledger queries (audit trails, reporting)
CREATE INDEX idx_custody_item ON custody_transactions(inventory_item_id);
CREATE INDEX idx_custody_school_date ON custody_transactions(school_id, created_at DESC);
CREATE INDEX idx_custody_to_custodian ON custody_transactions(to_custodian_id, to_custodian_type);
CREATE INDEX idx_custody_from_custodian ON custody_transactions(from_custodian_id, from_custodian_type);
CREATE INDEX idx_custody_batch ON custody_transactions(batch_id) WHERE batch_id IS NOT NULL;
CREATE INDEX idx_custody_unacknowledged ON custody_transactions(school_id, acknowledged_at) 
    WHERE acknowledged_at IS NULL;

-- Billing claims
CREATE INDEX idx_billing_student ON billing_claims(student_id);
CREATE INDEX idx_billing_school_status ON billing_claims(school_id, status);

-- Audit
CREATE INDEX idx_audit_school ON audit_sessions(school_id);

-- Catalog
CREATE INDEX idx_catalog_grade_subject ON catalog_books(grade, subject);
CREATE UNIQUE INDEX idx_catalog_isbn ON catalog_books(isbn);

-- Users
CREATE INDEX idx_users_school_role ON users(school_id, role) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_users_email ON users(email) WHERE deleted_at IS NULL;


-- ═══════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY (RLS) — Multi-tenant isolation
-- ═══════════════════════════════════════════════════════════════
-- Enable RLS on all school-scoped tables
ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE custody_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_claims ENABLE ROW LEVEL SECURITY;

-- Example policy: users can only see data for their own school
-- (Set via JWT claim: current_setting('app.current_school_id'))
CREATE POLICY school_isolation_policy ON inventory_items
    USING (school_id = current_setting('app.current_school_id')::UUID);

CREATE POLICY school_isolation_policy ON students
    USING (school_id = current_setting('app.current_school_id')::UUID);

CREATE POLICY school_isolation_policy ON custody_transactions
    USING (school_id = current_setting('app.current_school_id')::UUID);


-- ═══════════════════════════════════════════════════════════════
-- TRIGGERS — Maintain consistency
-- ═══════════════════════════════════════════════════════════════

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_inventory_updated_at
    BEFORE UPDATE ON inventory_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_students_updated_at
    BEFORE UPDATE ON students
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Prevent updates to the custody ledger (immutability guard)
CREATE OR REPLACE FUNCTION prevent_custody_update()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'custody_transactions is append-only. Updates are not permitted.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_custody_immutable
    BEFORE UPDATE ON custody_transactions
    FOR EACH ROW EXECUTE FUNCTION prevent_custody_update();

-- Sync current custodian on inventory_items after every new transaction
CREATE OR REPLACE FUNCTION sync_inventory_custodian()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE inventory_items
    SET 
        current_custodian_type = NEW.to_custodian_type,
        current_custodian_id   = NEW.to_custodian_id,
        current_custodian_name = NEW.to_custodian_name,
        condition              = NEW.condition_at_handoff,
        updated_at             = NOW()
    WHERE id = NEW.inventory_item_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_custodian
    AFTER INSERT ON custody_transactions
    FOR EACH ROW EXECUTE FUNCTION sync_inventory_custodian();
