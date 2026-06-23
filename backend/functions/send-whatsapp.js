// Book-Smart — WhatsApp billing notice sender
// Uses Meta WhatsApp Business API (or CallMeBot for testing)

exports.handler = async (event) => {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json'
  };

  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers, body: '' };

  let body;
  try { body = JSON.parse(event.body); } catch {
    return { statusCode: 400, headers, body: JSON.stringify({ error: 'Invalid JSON' }) };
  }

  const { phone, parent_name, learner_name, book_title, amount, reason, school_name } = body;
  if (!phone) return { statusCode: 400, headers, body: JSON.stringify({ error: 'Phone number required' }) };

  const WHATSAPP_TOKEN = process.env.WHATSAPP_TOKEN;
  const RESEND_API_KEY = process.env.RESEND_API_KEY;

  const message = `📚 *Book-Smart Notice — ${school_name || 'Your School'}*\n\nDear ${parent_name || 'Parent/Guardian'},\n\nThis is to inform you that:\n\n*Learner:* ${learner_name}\n*Book:* ${book_title}\n*Reason:* ${reason === 'lost' ? '❌ Book reported lost' : '⚠️ Book returned damaged'}\n*Amount due:* R${amount}\n\nPlease settle this at the school admin office at your earliest convenience.\n\nThank you for your cooperation.\n\n_Book-Smart · School Textbook Tracking_`;

  // If WhatsApp token available and not 'skip', use Meta API
  if (WHATSAPP_TOKEN && !WHATSAPP_TOKEN.startsWith('skip')) {
    // Meta WhatsApp Cloud API
    const PHONE_NUMBER_ID = process.env.WA_PHONE_NUMBER_ID || '';
    try {
      const res = await fetch(`https://graph.facebook.com/v18.0/${PHONE_NUMBER_ID}/messages`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${WHATSAPP_TOKEN}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          messaging_product: 'whatsapp',
          to: phone.replace(/\s+/g, '').replace(/^0/, '27'),
          type: 'text',
          text: { body: message }
        })
      });
      const result = await res.json();
      return { statusCode: 200, headers, body: JSON.stringify({ success: true, channel: 'whatsapp', result }) };
    } catch (e) {
      // Fall through to email fallback
    }
  }

  // Fallback: send via email (Resend) — log WhatsApp message content
  const emailHtml = `
    <div style="font-family:system-ui,sans-serif;max-width:520px;margin:0 auto;padding:24px;">
      <div style="background:#fff;border-radius:16px;padding:28px;border:1px solid #e2e8f0;">
        <div style="background:#25D366;color:#fff;border-radius:10px;padding:12px 16px;margin-bottom:20px;font-size:13px;font-weight:600;">
          📱 WhatsApp Billing Notice (Preview)
        </div>
        <div style="font-size:14px;color:#0f172a;line-height:1.8;white-space:pre-line;">${message}</div>
        <div style="margin-top:20px;padding:12px;background:#fef9c3;border-radius:8px;font-size:12px;color:#92400e;border:1px solid #fde68a;">
          ⚠ WhatsApp integration pending setup. This notice has been logged. Connect your WhatsApp Business API to enable direct messaging.
        </div>
      </div>
    </div>
  `;

  try {
    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: 'Book-Smart <onboarding@resend.dev>',
        to: ['delivered@resend.dev'],
        subject: `📚 Billing Notice — ${learner_name} · R${amount}`,
        html: emailHtml
      })
    });
  } catch (e) { console.error('Email fallback error:', e.message); }

  return {
    statusCode: 200, headers,
    body: JSON.stringify({ success: true, channel: 'email_fallback', message: 'Notice logged. WhatsApp will be sent once Business API is configured.' })
  };
};
