// Book-Smart — Barcode scan + transaction recording
// Handles both USB scanner and camera scan events

exports.handler = async (event) => {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json'
  };

  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers, body: '' };

  let body;
  try { body = JSON.parse(event.body); } catch { return { statusCode: 400, headers, body: JSON.stringify({ error: 'Invalid JSON' }) }; }

  const { barcode, school_id, learner_id, staff_id, action = 'issue' } = body;
  if (!barcode) return { statusCode: 400, headers, body: JSON.stringify({ error: 'Barcode required' }) };

  const SUPABASE_URL = process.env.SUPABASE_URL || 'https://cbllyweteqbfrkjdkeor.supabase.co';
  const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

  // 1. Look up the book copy
  const bookRes = await fetch(
    `${SUPABASE_URL}/rest/v1/book_copies?barcode=eq.${encodeURIComponent(barcode)}&select=*`,
    { headers: { 'apikey': SUPABASE_SERVICE_KEY, 'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}` } }
  );
  const books = await bookRes.json();

  if (!books.length) {
    return { statusCode: 404, headers, body: JSON.stringify({ status: 'not_found', message: `Barcode ${barcode} not registered in the system` }) };
  }

  const book = books[0];

  // 2. Check if already assigned
  if (book.status === 'assigned' && action === 'issue') {
    return {
      statusCode: 409, headers,
      body: JSON.stringify({ status: 'conflict', message: `Book ${barcode} is already assigned to another learner`, book })
    };
  }

  // 3. Record transaction
  const txRes = await fetch(`${SUPABASE_URL}/rest/v1/transactions`, {
    method: 'POST',
    headers: {
      'apikey': SUPABASE_SERVICE_KEY,
      'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=minimal'
    },
    body: JSON.stringify({
      school_id,
      book_copy_id: book.id,
      barcode,
      action,
      from_holder_type: book.holder_type,
      from_holder_id: book.holder_id,
      to_holder_type: action === 'issue' ? 'learner' : 'school',
      to_holder_id: action === 'issue' ? learner_id : null,
      condition_before: book.condition,
      condition_after: book.condition,
      staff_id
    })
  });

  // 4. Update book copy status
  await fetch(`${SUPABASE_URL}/rest/v1/book_copies?id=eq.${book.id}`, {
    method: 'PATCH',
    headers: {
      'apikey': SUPABASE_SERVICE_KEY,
      'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      status: action === 'issue' ? 'assigned' : 'available',
      holder_type: action === 'issue' ? 'learner' : 'school',
      holder_id: action === 'issue' ? learner_id : null,
      updated_at: new Date().toISOString()
    })
  });

  return {
    statusCode: 200, headers,
    body: JSON.stringify({ status: 'success', action, barcode, book, message: `Book ${action === 'issue' ? 'issued' : 'returned'} successfully` })
  };
};
