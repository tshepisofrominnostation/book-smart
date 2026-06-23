// Book-Smart — Lead capture + email notification
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://cbllyweteqbfrkjdkeor.supabase.co';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNibGx5d2V0ZXFiZnJramRrZW9yIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MjIzNzMxOSwiZXhwIjoyMDk3ODEzMzE5fQ.fuSBhnSIb6EA7CzCFOpGiojGgPqWmWv2ZiI9BM6kHR8';
const RESEND_API_KEY = process.env.RESEND_API_KEY || 're_CWDoVNJT_KekEy3Z2zA5Ca1NtNyfjCiZt';

exports.handler = async (event) => {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json'
  };
  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers, body: '' };
  if (event.httpMethod !== 'POST') return { statusCode: 405, headers, body: JSON.stringify({ error: 'Method not allowed' }) };

  let body;
  try { body = JSON.parse(event.body); } catch { return { statusCode: 400, headers, body: JSON.stringify({ error: 'Invalid JSON' }) }; }
  const { name, email, phone, school_name, province, learner_count, message } = body;
  if (!name || !email) return { statusCode: 400, headers, body: JSON.stringify({ error: 'Name and email required' }) };

  let dbStatus = 'not_saved';
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/leads`, {
      method: 'POST',
      headers: { 'apikey': SUPABASE_SERVICE_KEY, 'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`, 'Content-Type': 'application/json', 'Prefer': 'return=minimal' },
      body: JSON.stringify({ name, email, phone, school_name, province, learner_count, message, status: 'new' })
    });
    dbStatus = res.ok ? 'saved' : 'error_' + res.status;
  } catch (e) { dbStatus = 'error_fetch'; }

  try {
    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: 'Book-Smart <onboarding@resend.dev>',
        to: [email],
        subject: `✅ Welcome to Book-Smart, ${name}!`,
        html: `<div style="font-family:system-ui,sans-serif;max-width:560px;margin:0 auto;padding:32px;background:#f8fafc;"><div style="background:#fff;border-radius:16px;padding:32px;border:1px solid #e2e8f0;"><div style="display:flex;align-items:center;gap:12px;margin-bottom:24px;"><div style="width:44px;height:44px;background:linear-gradient(135deg,#16a34a,#15803d);border-radius:12px;display:flex;align-items:center;justify-content:center;"><span style="color:#fff;font-weight:800;font-size:18px;">B</span></div><div><div style="font-weight:800;font-size:20px;color:#0f172a;">Book-Smart</div><div style="font-size:12px;color:#64748b;">School Textbook Tracking</div></div></div><h2 style="color:#0f172a;margin:0 0 12px;">Hi ${name}, you're on the list! 🎉</h2><p style="color:#475569;line-height:1.7;margin:0 0 20px;">Thank you for requesting a trial for <strong>${school_name || 'your school'}</strong>. Our team will contact you within 24 hours to get you set up.</p><div style="background:#f0fdf4;border-radius:12px;padding:16px;border:1px solid #bbf7d0;margin-bottom:20px;"><div style="font-weight:700;font-size:14px;color:#166534;margin-bottom:8px;">Your details:</div>${phone ? '<div style=\"font-size:13px;color:#15803d;\">📞 ' + phone + '</div>' : ''}${school_name ? '<div style=\"font-size:13px;color:#15803d;\">🏫 ' + school_name + '</div>' : ''}${province ? '<div style=\"font-size:13px;color:#15803d;\">📍 ' + province + '</div>' : ''}${learner_count ? '<div style=\"font-size:13px;color:#15803d;\">👥 ' + learner_count + ' learners</div>' : ''}</div><p style="color:#64748b;font-size:13px;">Check out the live demo at <a href="https://booksmart-platform.netlify.app/#demo" style="color:#16a34a;">booksmart-platform.netlify.app</a></p><div style="margin-top:24px;padding-top:20px;border-top:1px solid #f1f5f9;font-size:12px;color:#94a3b8;">Book-Smart (Pty) Ltd · Cape Town · POPIA Compliant</div></div></div>`
      })
    });
  } catch (e) { console.error('Email error:', e.message); }

  return { statusCode: 200, headers, body: JSON.stringify({ success: true, db: dbStatus }) };
};
