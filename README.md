# 📚 Book-Smart — School Inventory Management Platform

> *Know exactly where every book is. Every single one.*

**Built by Tshepiso Freddy Thosago | Rem0Beg Solutions**

[![JavaScript](https://img.shields.io/badge/JavaScript-ES6+-F7DF1E?style=for-the-badge&logo=javascript)](https://javascript.com)
[![Netlify](https://img.shields.io/badge/Live-Netlify-00C7B7?style=for-the-badge&logo=netlify)](https://booksmart-platform.netlify.app)
[![Supabase](https://img.shields.io/badge/Database-Supabase-3ECF8E?style=for-the-badge&logo=supabase)](https://supabase.com)

---

## 🌐 Live Demo

**👉 [https://booksmart-platform.netlify.app](https://booksmart-platform.netlify.app)**

---

## 💡 What Book-Smart Solves

Primary schools in South Africa run textbook allocation from paper registers. The result:
- Books go missing with no record of who had them
- Year-end returns are chaotic
- No data for ordering next year's books

Book-Smart is a lightweight web platform purpose-built for township and government primary schools — simple enough for a school secretary to use on day one.

---

## 🏗️ Architecture

```
Static Frontend (HTML + CSS + JS)
  - Hosted on Netlify CDN (loads in <1s anywhere in SA)
  - No framework overhead — pure vanilla JS
         │
         ▼
Netlify Serverless Functions (Node.js)
  - submit-lead.js    → captures school sign-ups
  - scan-book.js      → barcode lookup + issue/return
  - send-whatsapp.js  → parent/teacher notifications
         │
         ▼
Supabase (PostgreSQL)
  - Managed cloud database
  - Real-time subscriptions available
  - Row-level security for data isolation
         │
         ▼
Resend (Transactional Email)
  - Email confirmations and reports
```

**Why this stack?**
- **No server to maintain** — Netlify Functions scale to zero when not in use
- **No cold starts in SA** — Netlify CDN has edge nodes in Cape Town
- **Supabase** gives us a real PostgreSQL database without managing a server
- Total hosting cost: **R0/month** on free tiers for a school with <500 students

---

## ⚡ Netlify Serverless Functions

Each function is a Node.js file that runs on-demand — no always-on server.

```javascript
// scan-book.js — simplified
exports.handler = async (event) => {
  const { barcode } = JSON.parse(event.body);

  // 1. Look up barcode in Supabase
  const { data: book } = await supabase
    .from('book_copies')
    .select('*, books(*), students(*)')
    .eq('barcode', barcode)
    .single();

  if (!book) return { statusCode: 404, body: 'Not found' };

  // 2. Toggle status
  const newStatus = book.status === 'available' ? 'issued' : 'available';
  await supabase.from('book_copies').update({ status: newStatus }).eq('id', book.id);

  // 3. Log the transaction
  await supabase.from('transactions').insert({ book_copy_id: book.id, action: newStatus });

  return { statusCode: 200, body: JSON.stringify({ book, newStatus }) };
};
```

---

## 🗄️ Database (Supabase / PostgreSQL)

```sql
schools       (id, name, emis_number, province, contact_email)
books         (id, school_id, title, isbn, subject, grade, replacement_cost)
book_copies   (id, book_id, barcode, status, condition)
students      (id, school_id, name, grade, parent_phone)
transactions  (id, book_copy_id, student_id, action, created_at)
leads         (id, school_name, contact_name, email, created_at)
```

---

## 💡 Interview Q&A

**"Why Netlify Functions instead of a full Express server?"**
> For a school platform that might process 200 scans on a Monday morning and nothing for the rest of the week, a traditional server wastes money sitting idle. Serverless functions only run when called — you pay per invocation, not per hour. For low-traffic use cases like this, serverless is 10x cheaper and zero maintenance.

**"What is Supabase and how does it differ from Firebase?"**
> Supabase is an open-source Firebase alternative built on PostgreSQL. Firebase uses a NoSQL document database (Firestore). Supabase uses a real relational database — you write SQL, have foreign keys, joins, and ACID transactions. For structured data like books and students with clear relationships, relational is the right choice. Supabase also provides a REST API and real-time subscriptions out of the box.

**"Why vanilla JavaScript instead of React?"**
> This platform targets school secretaries on low-spec computers, potentially with slow connections. React adds ~150KB of JavaScript before your code even runs. Vanilla JS adds zero overhead. The DOM manipulation for this use case is simple enough that a framework would be over-engineering. I chose the right tool for the context, not the most impressive-sounding one.

**"How does the barcode scanner work?"**
> USB barcode scanners behave like keyboards — they type the barcode string and press Enter. The browser's `keydown` event listener captures this. When Enter is detected, the value is sent to the `scan-book` Netlify Function. The function looks up the barcode, returns the book details, and toggles the status. The whole round-trip takes under 200ms. No special scanner SDK or driver needed.

**"How do you handle school data isolation?"**
> Supabase has Row Level Security (RLS). Each school has a unique `school_id`. RLS policies on every table enforce `WHERE school_id = auth.school_id()` — the database itself rejects queries that try to access another school's data, even if the application code has a bug. Security at the database layer, not just the application layer.

**"What happens if a scan fails halfway (book updated but transaction not logged)?"**
> Both the status update and the transaction insert happen in the same Supabase request using a database transaction. If the transaction insert fails, the status update rolls back. The system is always consistent — you can't have a book show as "issued" without a corresponding transaction record.

---

## ⚙️ Local Setup

```bash
git clone https://github.com/tshepisofrominnostation/book-smart.git
cd book-smart

# Install Netlify CLI
npm install -g netlify-cli

# Set environment variables
cp .env.example .env
# Fill in: SUPABASE_URL, SUPABASE_SERVICE_KEY, RESEND_API_KEY

# Run locally (includes serverless functions)
netlify dev
# Open http://localhost:8888
```

---

## 🗺️ Roadmap

- [x] Barcode scan → issue/return
- [x] Netlify serverless functions
- [x] Supabase PostgreSQL backend
- [x] Lead capture for schools
- [ ] WhatsApp Business API (parent notifications)
- [ ] Bulk import from Excel/CSV
- [ ] Mobile PWA (offline scanning)
- [ ] Department of Basic Education integration

---

## 👤 About

**Developer:** Tshepiso Freddy Thosago | Rem0Beg Solutions
**GitHub:** [github.com/tshepisofrominnostation](https://github.com/tshepisofrominnostation)
