"""
TrackBook — Bulk Student Import Service
======================================
Senior Backend Engineer | Python 3.11+ | June 2026

This service handles bulk student enrollment via uploaded Excel or CSV files.
It validates every row, provides a preview with flagged errors, and inserts
all valid records in a single atomic database transaction.

Dependencies:
    pip install pandas openpyxl psycopg2-binary python-dotenv pydantic

Usage:
    result = await process_student_import(
        file_path="uploads/students.xlsx",
        school_id="uuid-of-school",
        grade_id="uuid-of-grade",
        uploaded_by_user_id="uuid-of-admin",
        strict_mode=True,      # True = rollback if ANY row fails
        db_conn=conn
    )
"""

import re
import uuid
import logging
from datetime import datetime, date
from dataclasses import dataclass, field
from typing import Optional

import pandas as pd
import psycopg2
import psycopg2.extras
from pydantic import BaseModel, validator, ValidationError

# ─────────────────────────────────────────────
# Logging setup
# ─────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("trackbook.import")


# ─────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────

# Required columns in the uploaded file (case-insensitive, stripped)
REQUIRED_COLUMNS = {"cemis_number", "full_name", "grade", "class_name"}

# Optional columns
OPTIONAL_COLUMNS = {"date_of_birth", "parent_email", "parent_phone", "parent_name"}

# CEMIS format: 7 to 15 alphanumeric characters (adjust regex for your province)
CEMIS_PATTERN = re.compile(r'^[A-Z0-9]{7,15}$', re.IGNORECASE)

# Max rows per import (to prevent runaway imports)
MAX_ROWS = 2000


# ─────────────────────────────────────────────
# Data models
# ─────────────────────────────────────────────

class StudentRow(BaseModel):
    """Pydantic model for one validated student row."""
    cemis_number: str
    full_name: str
    grade: str
    class_name: str
    date_of_birth: Optional[date] = None
    parent_email: Optional[str] = None
    parent_phone: Optional[str] = None
    parent_name: Optional[str] = None

    @validator('cemis_number')
    def validate_cemis(cls, v: str) -> str:
        """
        Validate CEMIS number format.
        CEMIS (Community Education Management Information System) numbers
        are unique national student IDs in South Africa.
        """
        v = v.strip().upper()
        if not v:
            raise ValueError("CEMIS number cannot be empty")
        if not CEMIS_PATTERN.match(v):
            raise ValueError(
                f"CEMIS '{v}' has invalid format. "
                f"Expected 7-15 alphanumeric characters (e.g., C20240042)"
            )
        return v

    @validator('full_name')
    def validate_full_name(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 2:
            raise ValueError("Full name must be at least 2 characters")
        if len(v) > 255:
            raise ValueError("Full name too long (max 255 characters)")
        return v

    @validator('parent_email')
    def validate_email(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        v = v.strip().lower()
        if v and '@' not in v:
            raise ValueError(f"Invalid email format: {v}")
        return v or None


@dataclass
class RowResult:
    """Result for a single row during validation."""
    row_number: int                     # 1-based (matches Excel row number)
    raw_data: dict
    is_valid: bool
    errors: list[str] = field(default_factory=list)
    validated_data: Optional[StudentRow] = None


@dataclass
class ImportResult:
    """Final result of an import job."""
    job_id: str
    school_id: str
    total_rows: int
    valid_rows: int
    failed_rows: int
    inserted_rows: int
    skipped_rows: int                   # duplicates that were skipped gracefully
    errors: list[dict]                  # [{row, cemis, error_message}]
    warnings: list[dict]                # [{row, message}] — non-fatal
    committed: bool
    completed_at: datetime


# ─────────────────────────────────────────────
# Step 1: File parsing
# ─────────────────────────────────────────────

def parse_upload_file(file_path: str) -> pd.DataFrame:
    """
    Parse an uploaded Excel (.xlsx, .xls) or CSV file into a DataFrame.
    Normalizes column names to lowercase_snake_case.

    Args:
        file_path: Local path to the uploaded file.

    Returns:
        Normalized pandas DataFrame.

    Raises:
        ValueError: If file format is unsupported or required columns missing.
    """
    logger.info(f"Parsing file: {file_path}")

    # Determine file type
    if file_path.endswith(('.xlsx', '.xls')):
        # Read first sheet only
        df = pd.read_excel(file_path, sheet_name=0, dtype=str)
    elif file_path.endswith('.csv'):
        df = pd.read_csv(file_path, dtype=str, encoding='utf-8-sig')
    else:
        raise ValueError(
            "Unsupported file format. Please upload a .xlsx, .xls, or .csv file."
        )

    # Normalize column names: lowercase, strip whitespace, replace spaces with _
    df.columns = [
        col.strip().lower().replace(' ', '_').replace('-', '_')
        for col in df.columns
    ]

    # Drop completely empty rows
    df = df.dropna(how='all').reset_index(drop=True)

    logger.info(f"Parsed {len(df)} rows, columns: {list(df.columns)}")

    # Validate required columns exist
    missing_cols = REQUIRED_COLUMNS - set(df.columns)
    if missing_cols:
        raise ValueError(
            f"Missing required columns: {', '.join(sorted(missing_cols))}. "
            f"Found columns: {', '.join(df.columns)}"
        )

    # Enforce max row limit
    if len(df) > MAX_ROWS:
        raise ValueError(
            f"File contains {len(df)} rows. Maximum allowed is {MAX_ROWS}. "
            f"Please split into multiple uploads."
        )

    return df


# ─────────────────────────────────────────────
# Step 2: Row-by-row validation
# ─────────────────────────────────────────────

def validate_rows(df: pd.DataFrame) -> list[RowResult]:
    """
    Validate each row against the StudentRow Pydantic model.
    Also checks for duplicate CEMIS numbers within the file itself.

    Args:
        df: Normalized DataFrame from parse_upload_file()

    Returns:
        List of RowResult objects, one per data row.
    """
    results: list[RowResult] = []

    # Track CEMIS numbers seen so far in THIS file to catch intra-file duplicates
    seen_cemis: dict[str, int] = {}  # cemis → first row number

    for idx, row in df.iterrows():
        row_number = idx + 2  # +2 because idx is 0-based and row 1 is the header
        raw = row.to_dict()

        # Build the data dict for Pydantic, handling NaN → None
        data = {}
        for col in REQUIRED_COLUMNS | OPTIONAL_COLUMNS:
            val = raw.get(col)
            # pandas reads empty cells as float NaN
            if pd.isna(val) if not isinstance(val, str) else False:
                data[col] = None
            else:
                data[col] = str(val).strip() if val is not None else None

        errors = []

        # Check for intra-file CEMIS duplicates BEFORE Pydantic validation
        cemis_raw = (data.get('cemis_number') or '').strip().upper()
        if cemis_raw and cemis_raw in seen_cemis:
            errors.append(
                f"Duplicate CEMIS in this file — also appears at row {seen_cemis[cemis_raw]}"
            )
        elif cemis_raw:
            seen_cemis[cemis_raw] = row_number

        # Pydantic validation
        validated = None
        try:
            validated = StudentRow(**data)
        except ValidationError as exc:
            for error in exc.errors():
                # Convert Pydantic error to readable string
                field_name = ' → '.join(str(loc) for loc in error['loc'])
                errors.append(f"{field_name}: {error['msg']}")

        results.append(RowResult(
            row_number=row_number,
            raw_data=raw,
            is_valid=len(errors) == 0 and validated is not None,
            errors=errors,
            validated_data=validated if not errors else None
        ))

    return results


# ─────────────────────────────────────────────
# Step 3: Database resolution helpers
# ─────────────────────────────────────────────

def resolve_grade_and_class(
    cursor,
    school_id: str,
    grade_name: str,
    class_name: str
) -> tuple[Optional[str], Optional[str]]:
    """
    Look up grade_id and class_id for a given school by name.
    Returns (None, None) if not found — caller decides whether to error or create.

    Args:
        cursor: Active psycopg2 cursor
        school_id: UUID string of the school
        grade_name: e.g., "Grade 8" or "8"
        class_name: e.g., "8A" or "A"

    Returns:
        (grade_id, class_id) UUIDs or (None, None)
    """
    # Normalize grade name — accept "8" or "Grade 8"
    normalized_grade = grade_name.strip()
    if not normalized_grade.lower().startswith('grade'):
        normalized_grade = f"Grade {normalized_grade}"

    cursor.execute(
        """
        SELECT g.id as grade_id, c.id as class_id
        FROM grades g
        LEFT JOIN classes c ON c.grade_id = g.id 
            AND c.school_id = %s
            AND LOWER(c.name) = LOWER(%s)
        WHERE g.school_id = %s
          AND LOWER(g.name) = LOWER(%s)
        LIMIT 1
        """,
        (school_id, class_name.strip(), school_id, normalized_grade)
    )
    result = cursor.fetchone()
    if result:
        return result['grade_id'], result['class_id']
    return None, None


# ─────────────────────────────────────────────
# Step 4: Main import function
# ─────────────────────────────────────────────

def process_student_import(
    file_path: str,
    school_id: str,
    uploaded_by_user_id: str,
    db_conn,                            # psycopg2 connection
    strict_mode: bool = True,
    skip_duplicates: bool = False       # If True, skip existing CEMIS instead of error
) -> ImportResult:
    """
    Full pipeline: parse → validate → insert (atomic transaction).

    Args:
        file_path: Path to the uploaded Excel/CSV file.
        school_id: UUID of the school performing the import.
        uploaded_by_user_id: UUID of the admin who uploaded the file.
        db_conn: Active psycopg2 database connection.
        strict_mode: If True, the entire import rolls back if ANY row fails validation.
                     If False, valid rows are committed and invalid rows are reported.
        skip_duplicates: If True, rows with a CEMIS that already exists in the DB
                         are silently skipped rather than erroring.

    Returns:
        ImportResult dataclass with full statistics and error log.
    """
    job_id = str(uuid.uuid4())
    logger.info(f"[Job {job_id}] Starting import for school {school_id}")

    # ── Parse ──────────────────────────────────────────────────────────────────
    try:
        df = parse_upload_file(file_path)
    except ValueError as exc:
        logger.error(f"[Job {job_id}] File parse error: {exc}")
        raise  # Re-raise — caller handles HTTP response

    total_rows = len(df)
    logger.info(f"[Job {job_id}] {total_rows} data rows found")

    # ── Validate ───────────────────────────────────────────────────────────────
    row_results = validate_rows(df)

    valid_results = [r for r in row_results if r.is_valid]
    invalid_results = [r for r in row_results if not r.is_valid]

    logger.info(
        f"[Job {job_id}] Validation: {len(valid_results)} valid, "
        f"{len(invalid_results)} invalid"
    )

    # In strict mode, if there are ANY invalid rows, return immediately without DB writes
    if strict_mode and invalid_results:
        errors = [
            {
                "row": r.row_number,
                "cemis": r.raw_data.get('cemis_number', 'N/A'),
                "name": r.raw_data.get('full_name', 'N/A'),
                "errors": r.errors
            }
            for r in invalid_results
        ]
        logger.warning(
            f"[Job {job_id}] Strict mode: rolling back due to "
            f"{len(invalid_results)} invalid rows"
        )
        return ImportResult(
            job_id=job_id,
            school_id=school_id,
            total_rows=total_rows,
            valid_rows=len(valid_results),
            failed_rows=len(invalid_results),
            inserted_rows=0,
            skipped_rows=0,
            errors=errors,
            warnings=[],
            committed=False,
            completed_at=datetime.utcnow()
        )

    # ── Database insertion (atomic transaction) ────────────────────────────────
    inserted_rows = 0
    skipped_rows = 0
    db_errors = []
    warnings = []

    # Use a cursor with dict-like row access
    cursor = db_conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    try:
        # Start the transaction (psycopg2 is in manual commit mode)
        # If db_conn.autocommit is True, set it to False first
        db_conn.autocommit = False

        # Pre-fetch all existing CEMIS numbers for this school in one query
        # (much faster than checking individually per row)
        cursor.execute(
            "SELECT cemis_number FROM students WHERE school_id = %s AND deleted_at IS NULL",
            (school_id,)
        )
        existing_cemis = {row['cemis_number'].upper() for row in cursor.fetchall()}
        logger.info(
            f"[Job {job_id}] Found {len(existing_cemis)} existing students in DB"
        )

        # Process only valid rows (or all rows in non-strict mode)
        rows_to_insert = valid_results if not strict_mode else valid_results

        for result in rows_to_insert:
            student = result.validated_data

            # Check for DB-level CEMIS duplicate
            if student.cemis_number.upper() in existing_cemis:
                if skip_duplicates:
                    skipped_rows += 1
                    warnings.append({
                        "row": result.row_number,
                        "message": f"CEMIS {student.cemis_number} already exists — skipped"
                    })
                    continue
                else:
                    db_errors.append({
                        "row": result.row_number,
                        "cemis": student.cemis_number,
                        "name": student.full_name,
                        "errors": [
                            f"CEMIS {student.cemis_number} already exists "
                            f"in the database for this school"
                        ]
                    })
                    if strict_mode:
                        # Immediately abort and rollback
                        raise RuntimeError("CEMIS_DUPLICATE_STRICT")
                    continue

            # Resolve grade and class IDs
            grade_id, class_id = resolve_grade_and_class(
                cursor, school_id, student.grade, student.class_name
            )

            if grade_id is None:
                db_errors.append({
                    "row": result.row_number,
                    "cemis": student.cemis_number,
                    "name": student.full_name,
                    "errors": [
                        f"Grade '{student.grade}' not found for this school. "
                        f"Please configure grades in school settings first."
                    ]
                })
                if strict_mode:
                    raise RuntimeError("GRADE_NOT_FOUND_STRICT")
                continue

            # Insert the student record
            student_id = str(uuid.uuid4())
            cursor.execute(
                """
                INSERT INTO students (
                    id, school_id, cemis_number, full_name,
                    date_of_birth, grade_id, class_id,
                    enrollment_date, is_active, created_at, updated_at
                ) VALUES (
                    %s, %s, %s, %s,
                    %s, %s, %s,
                    CURRENT_DATE, TRUE, NOW(), NOW()
                )
                """,
                (
                    student_id,
                    school_id,
                    student.cemis_number,
                    student.full_name,
                    student.date_of_birth,
                    grade_id,
                    class_id,
                )
            )

            # Insert parent/guardian if provided
            if student.parent_email or student.parent_phone or student.parent_name:
                guardian_id = str(uuid.uuid4())
                cursor.execute(
                    """
                    INSERT INTO guardians (id, full_name, email, phone, created_at)
                    VALUES (%s, %s, %s, %s, NOW())
                    """,
                    (
                        guardian_id,
                        student.parent_name or 'Guardian',
                        student.parent_email,
                        student.parent_phone,
                    )
                )
                cursor.execute(
                    """
                    INSERT INTO student_guardians (student_id, guardian_id, is_primary)
                    VALUES (%s, %s, TRUE)
                    """,
                    (student_id, guardian_id)
                )

            # Track in our in-memory set to catch duplicates within same batch
            existing_cemis.add(student.cemis_number.upper())
            inserted_rows += 1

        # Log the import job to DB
        total_failed = len(invalid_results) + len(db_errors)
        cursor.execute(
            """
            INSERT INTO import_jobs (
                id, school_id, import_type, status,
                filename, total_rows, rows_succeeded, rows_failed,
                error_log, initiated_by, started_at, completed_at
            ) VALUES (%s, %s, 'students', %s, %s, %s, %s, %s, %s, %s, NOW(), NOW())
            """,
            (
                job_id,
                school_id,
                'completed' if total_failed == 0 else 'partial',
                file_path.split('/')[-1],   # filename only, not full path
                total_rows,
                inserted_rows,
                total_failed,
                psycopg2.extras.Json(db_errors),
                uploaded_by_user_id,
            )
        )

        # ── COMMIT ────────────────────────────────────────────────────────────
        db_conn.commit()
        logger.info(
            f"[Job {job_id}] COMMITTED: {inserted_rows} inserted, "
            f"{skipped_rows} skipped, {len(db_errors)} failed"
        )

    except RuntimeError as exc:
        # Strict mode triggered rollback
        db_conn.rollback()
        logger.warning(f"[Job {job_id}] ROLLED BACK due to: {exc}")
        return ImportResult(
            job_id=job_id,
            school_id=school_id,
            total_rows=total_rows,
            valid_rows=len(valid_results),
            failed_rows=len(invalid_results) + len(db_errors),
            inserted_rows=0,
            skipped_rows=0,
            errors=[*[{"row": r.row_number, "cemis": r.raw_data.get('cemis_number'),
                        "name": r.raw_data.get('full_name'), "errors": r.errors}
                      for r in invalid_results],
                    *db_errors],
            warnings=warnings,
            committed=False,
            completed_at=datetime.utcnow()
        )

    except Exception as exc:
        # Unexpected error — always rollback
        db_conn.rollback()
        logger.exception(f"[Job {job_id}] Unexpected error — ROLLED BACK: {exc}")
        raise

    finally:
        cursor.close()

    # ── Build final result ─────────────────────────────────────────────────────
    all_errors = [
        {"row": r.row_number, "cemis": r.raw_data.get('cemis_number', 'N/A'),
         "name": r.raw_data.get('full_name', 'N/A'), "errors": r.errors}
        for r in invalid_results
    ] + db_errors

    return ImportResult(
        job_id=job_id,
        school_id=school_id,
        total_rows=total_rows,
        valid_rows=len(valid_results),
        failed_rows=len(all_errors),
        inserted_rows=inserted_rows,
        skipped_rows=skipped_rows,
        errors=all_errors,
        warnings=warnings,
        committed=True,
        completed_at=datetime.utcnow()
    )


# ─────────────────────────────────────────────
# FastAPI route example (usage)
# ─────────────────────────────────────────────
"""
# In your FastAPI router:

from fastapi import APIRouter, UploadFile, File, Depends, HTTPException
import tempfile, os

router = APIRouter(prefix="/api/v1/students", tags=["Students"])

@router.post("/import")
async def import_students(
    file: UploadFile = File(...),
    strict_mode: bool = True,
    skip_duplicates: bool = False,
    current_user: User = Depends(get_current_user),
    db: Connection = Depends(get_db)
):
    # Check permissions
    if current_user.role not in ['school_admin', 'administrator']:
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    # Save upload to temp file
    suffix = '.xlsx' if 'excel' in file.content_type else '.csv'
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        content = await file.read()
        tmp.write(content)
        tmp_path = tmp.name

    try:
        result = process_student_import(
            file_path=tmp_path,
            school_id=current_user.school_id,
            uploaded_by_user_id=current_user.id,
            db_conn=db,
            strict_mode=strict_mode,
            skip_duplicates=skip_duplicates
        )
    finally:
        os.unlink(tmp_path)  # Always clean up temp file

    status_code = 200 if result.committed else 422
    return JSONResponse(status_code=status_code, content={
        "job_id": result.job_id,
        "committed": result.committed,
        "inserted": result.inserted_rows,
        "skipped": result.skipped_rows,
        "failed": result.failed_rows,
        "errors": result.errors[:50],   # Cap at 50 for response size
        "warnings": result.warnings
    })
"""
