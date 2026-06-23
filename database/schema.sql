-- ============================================================
-- Book-Smart Platform — PostgreSQL Schema (Supabase)
-- Run this in: supabase.com → your project → SQL Editor → New query
-- ============================================================

-- 1. LEADS (sign-up / demo request form submissions)
CREATE TABLE IF NOT EXISTS leads (
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name          text NOT NULL,
  email         text NOT NULL,
  phone         text,
  school_name   text,
  province      text,
  learner_count text,
  message       text,
  status        text DEFAULT 'new',
  created_at    timestamptz DEFAULT now()
);

-- 2. SCHOOLS (multi-tenant root entity)
CREATE TABLE IF NOT EXISTS schools (
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name          text NOT NULL,
  province      text,
  emis_number   text UNIQUE,
  address       text,
  phone         text,
  email         text,
  principal     text,
  plan          text DEFAULT 'starter', -- starter | professional | district
  active        boolean DEFAULT true,
  created_at    timestamptz DEFAULT now()
);

-- 3. STAFF (principals, admins, HoDs, teachers)
CREATE TABLE IF NOT EXISTS staff (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  school_id   uuid REFERENCES schools(id) ON DELETE CASCADE,
  name        text NOT NULL,
  email       text UNIQUE NOT NULL,
  role        text CHECK (role IN ('principal','admin','hod','teacher')) DEFAULT 'teacher',
  subject     text,
  active      boolean DEFAULT true,
  created_at  timestamptz DEFAULT now()
);

-- 4. LEARNERS (with CEMIS national ID)
CREATE TABLE IF NOT EXISTS learners (
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  school_id     uuid REFERENCES schools(id) ON DELETE CASCADE,
  cemis         text NOT NULL,  -- national learner ID
  name          text NOT NULL,
  surname       text NOT NULL,
  grade         text,
  class_name    text,
  parent_name   text,
  parent_phone  text,
  parent_email  text,
  active        boolean DEFAULT true,
  created_at    timestamptz DEFAULT now(),
  UNIQUE(school_id, cemis)
);

-- 5. BOOKS CATALOG (master list — prevents typing errors)
CREATE TABLE IF NOT EXISTS books_catalog (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  isbn        text,
  title       text NOT NULL,
  subject     text,
  grade       text,
  publisher   text,
  price       numeric(10,2),
  created_at  timestamptz DEFAULT now()
);

-- 6. BOOK COPIES (individual physical items with unique barcodes)
CREATE TABLE IF NOT EXISTS book_copies (
  id            uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  school_id     uuid REFERENCES schools(id) ON DELETE CASCADE,
  catalog_id    uuid REFERENCES books_catalog(id),
  barcode       text NOT NULL UNIQUE,  -- unique serial barcode (not just ISBN)
  condition     text CHECK (condition IN ('new','good','fair','damaged','lost')) DEFAULT 'new',
  status        text CHECK (status IN ('available','assigned','lost','retired')) DEFAULT 'available',
  holder_type   text CHECK (holder_type IN ('school','staff','learner')),
  holder_id     uuid,  -- FK to staff.id or learners.id depending on holder_type
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now()
);

-- 7. TRANSACTIONS (immutable custody ledger — every handoff recorded)
CREATE TABLE IF NOT EXISTS transactions (
  id                uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  school_id         uuid REFERENCES schools(id),
  book_copy_id      uuid REFERENCES book_copies(id),
  barcode           text,
  action            text CHECK (action IN ('issue','return','transfer','audit','flag')),
  from_holder_type  text,
  from_holder_id    uuid,
  to_holder_type    text,
  to_holder_id      uuid,
  condition_before  text,
  condition_after   text,
  staff_id          uuid REFERENCES staff(id),
  notes             text,
  created_at        timestamptz DEFAULT now()
);

-- 8. BILLING CLAIMS (for lost / damaged books)
CREATE TABLE IF NOT EXISTS billing_claims (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  school_id       uuid REFERENCES schools(id),
  learner_id      uuid REFERENCES learners(id),
  book_copy_id    uuid REFERENCES book_copies(id),
  reason          text CHECK (reason IN ('lost','damaged','not_returned')),
  amount          numeric(10,2),
  status          text CHECK (status IN ('pending','paid','waived','disputed')) DEFAULT 'pending',
  notice_sent     boolean DEFAULT false,
  notice_sent_at  timestamptz,
  whatsapp_sent   boolean DEFAULT false,
  notes           text,
  created_at      timestamptz DEFAULT now()
);

-- 9. AUDITS (mid-year and year-end stock takes)
CREATE TABLE IF NOT EXISTS audits (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  school_id       uuid REFERENCES schools(id),
  started_by      uuid REFERENCES staff(id),
  type            text CHECK (type IN ('mid_year','year_end','spot_check')),
  status          text CHECK (status IN ('in_progress','complete')),
  total_expected  integer,
  total_scanned   integer,
  total_missing   integer,
  notes           text,
  started_at      timestamptz DEFAULT now(),
  completed_at    timestamptz
);

-- ── INDEXES (for fast barcode lookups and reporting) ──────────────────────
CREATE INDEX IF NOT EXISTS idx_book_copies_barcode   ON book_copies(barcode);
CREATE INDEX IF NOT EXISTS idx_book_copies_school    ON book_copies(school_id);
CREATE INDEX IF NOT EXISTS idx_book_copies_status    ON book_copies(status);
CREATE INDEX IF NOT EXISTS idx_learners_cemis        ON learners(cemis);
CREATE INDEX IF NOT EXISTS idx_learners_school       ON learners(school_id);
CREATE INDEX IF NOT EXISTS idx_transactions_book     ON transactions(book_copy_id);
CREATE INDEX IF NOT EXISTS idx_transactions_school   ON transactions(school_id);
CREATE INDEX IF NOT EXISTS idx_transactions_created  ON transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_billing_learner       ON billing_claims(learner_id);
CREATE INDEX IF NOT EXISTS idx_billing_status        ON billing_claims(status);

-- ── ROW LEVEL SECURITY ────────────────────────────────────────────────────
ALTER TABLE leads           ENABLE ROW LEVEL SECURITY;
ALTER TABLE schools         ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff           ENABLE ROW LEVEL SECURITY;
ALTER TABLE learners        ENABLE ROW LEVEL SECURITY;
ALTER TABLE book_copies     ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_claims  ENABLE ROW LEVEL SECURITY;
ALTER TABLE audits          ENABLE ROW LEVEL SECURITY;

-- Public insert for leads (unauthenticated sign-up form)
DROP POLICY IF EXISTS "leads_insert" ON leads;
CREATE POLICY "leads_insert" ON leads FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "leads_select" ON leads;
CREATE POLICY "leads_select" ON leads FOR SELECT USING (true);

SELECT 'Book-Smart schema created successfully ✓' AS result;
