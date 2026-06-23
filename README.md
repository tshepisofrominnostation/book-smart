# 📚 Book-Smart

> **B2B SaaS platform for textbook and school asset tracking — built for South African township and local schools.**

[![Live Demo](https://img.shields.io/badge/Live%20Demo-booksmart--platform.netlify.app-16a34a?style=for-the-badge&logo=netlify)](https://booksmart-platform.netlify.app)
[![Netlify Status](https://api.netlify.com/api/v1/badges/b57bc7c3-a62b-4af5-b2ab-954d2866881f/deploy-status)](https://app.netlify.com/projects/booksmart-platform/deploys)
![License](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)
![Stack](https://img.shields.io/badge/stack-HTML%20%7C%20Supabase%20%7C%20Netlify-0f172a?style=for-the-badge)

---

## 🎯 Problem

South African public schools lose millions of rands in textbooks every year. With no digital tracking system:
- 1 in 3 books issued at the start of the year are never returned
- Schools have no paper trail to legally bill students for lost or damaged books
- Administrators spend hours manually reconciling inventory at year-end

**Book-Smart solves this with a barcode-per-book, CEMIS-per-learner digital custody chain.**

---

## ✨ Features

| Feature | Description |
|---|---|
| 📱 **Mobile scanning** | Scan barcodes with any smartphone camera |
| 🖨️ **USB scanner support** | Plug-and-play HID barcode scanners (no drivers) |
| 🔗 **Custody chain** | Deputy Principal → Admin → HoD → Teacher → Learner |
| 🆔 **CEMIS integration** | Every book tied to a learner's national ID |
| 📊 **Audit tools** | Mid-year and year-end automated stock takes |
| 💰 **Billing module** | Auto-generate claims for lost/damaged books |
| 📱 **WhatsApp notices** | Send billing notices directly to parents |
| 📥 **Bulk Excel import** | Import hundreds of learners from a spreadsheet |
| 🏫 **Multi-tenant** | Each school is isolated — data never crosses |
| 🔒 **POPIA compliant** | Row-level security on all tables |

---

## 🛠️ Tech Stack

```
Frontend:   Vanilla HTML + CSS + JavaScript (no framework — runs on any device)
Backend:    Netlify Serverless Functions (Node.js)
Database:   Supabase (PostgreSQL) — hosted in af-south-1
Email:      Resend API
WhatsApp:   Meta WhatsApp Business API (configurable)
Hosting:    Netlify (CDN + edge functions)
```

---

## 📁 Project Structure

```
book-smart/
├── frontend/
│   └── index.html              # Full single-page application
├── backend/
│   ├── functions/
│   │   ├── submit-lead.js      # Lead capture + email notification
│   │   ├── scan-book.js        # Barcode scan + transaction recording
│   │   └── send-whatsapp.js    # WhatsApp / SMS billing notices
│   └── bulk_import_service.py  # Excel/CSV bulk learner import
├── database/
│   └── schema.sql              # Full PostgreSQL schema (9 tables)
├── docs/
│   ├── PRD.md                  # Product Requirements Document
│   ├── API_Design.md           # REST API endpoint specifications
│   ├── Architecture.md         # Multi-tenant cloud architecture
│   ├── UI_UX_Design.md         # UI/UX component specifications
│   └── Original_Schema_Reference.sql
├── netlify.toml                # Netlify build + function config
└── README.md
```

---

## 🚀 Getting Started

### 1. Clone the repo

```bash
git clone https://github.com/tshepisofrominnostation/book-smart.git
cd book-smart
```

### 2. Set up Supabase

1. Create a free project at [supabase.com](https://supabase.com)
2. Go to **SQL Editor → New query**
3. Paste and run the contents of `database/schema.sql`
4. Copy your **Project URL** and **anon/service keys** from Settings → API

### 3. Set up Resend (email)

1. Sign up free at [resend.com](https://resend.com)
2. Create an API key

### 4. Configure environment variables

Create a `.env` file (or set in Netlify dashboard):

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-role-key
SUPABASE_ANON_KEY=your-anon-key
RESEND_API_KEY=re_your_key_here
WHATSAPP_TOKEN=your-meta-token (optional)
WA_PHONE_NUMBER_ID=your-phone-number-id (optional)
```

### 5. Deploy to Netlify

```bash
# Install Netlify CLI
npm install -g netlify-cli

# Login
netlify login

# Deploy
netlify deploy --dir frontend --prod
```

Or click below to deploy with one click:

[![Deploy to Netlify](https://www.netlify.com/img/deploy/button.svg)](https://app.netlify.com/start/deploy?repository=https://github.com/tshepisofrominnostation/book-smart)

---

## 🗄️ Database Schema

The platform uses **9 relational tables** in PostgreSQL:

```
leads           → Sign-up form submissions
schools         → Multi-tenant school accounts
staff           → Principal / Admin / HoD / Teacher accounts
learners        → Learner profiles with CEMIS national ID
books_catalog   → Master book list (locked-down, no typos)
book_copies     → Individual physical copies with unique barcodes
transactions    → Immutable custody ledger (every handoff)
billing_claims  → Lost/damaged book claims
audits          → Mid-year and year-end stock takes
```

See `database/schema.sql` for full DDL with indexes and RLS policies.

---

## 📡 API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/.netlify/functions/submit-lead` | Capture sign-up form lead |
| `POST` | `/.netlify/functions/scan-book` | Record a barcode scan / transaction |
| `POST` | `/.netlify/functions/send-whatsapp` | Send billing notice to parent |

See `docs/API_Design.md` for full request/response specifications.

---

## 🏗️ Roadmap

- [ ] Full authentication (Supabase Auth + role-based access)
- [ ] Barcode PDF generation & printing
- [ ] Mobile PWA (installable on Android/iOS)
- [ ] Offline sync with service worker
- [ ] Government DBE / WCED API integration
- [ ] District-wide dashboard
- [ ] React Native mobile app

---

## 👤 About

Built by **Tshepiso Thosago** as a portfolio project and real-world solution for South African township schools.

- 🌐 Live site: [booksmart-platform.netlify.app](https://booksmart-platform.netlify.app)
- 💼 GitHub: [@tshepisofrominnostation](https://github.com/tshepisofrominnostation)

---

## 📄 License

MIT License — free to use, modify, and distribute.

---

*Built with ❤️ for SA educators · POPIA Compliant · Hosted on Netlify (Cape Town CDN)*
