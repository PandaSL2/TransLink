# TransLink — Database Schema (simple version)

This document lists the main database tables for the TransLink demo.  
Use PostgreSQL for the implementation. Below are the table definitions (conceptual) and SQL examples.

---

## 1. users
Stores passenger and owner accounts.

Columns:
- id (serial PRIMARY KEY)
- name (text)
- email (text UNIQUE)
- phone (text)
- password_hash (text)
- role (text) — 'passenger' or 'owner'
- created_at (timestamp with time zone DEFAULT now())

SQL (example):
```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name TEXT,
  email TEXT UNIQUE,
  phone TEXT,
  password_hash TEXT,
  role TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
