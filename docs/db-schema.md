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







CREATE TABLE vehicles (
  id SERIAL PRIMARY KEY,
  reg_no TEXT,
  beacon_id INTEGER REFERENCES beacons(id),
  owner_id INTEGER REFERENCES users(id),
  route_id INTEGER,
  installed_at TIMESTAMPTZ
);






CREATE TABLE beacons (
  id SERIAL PRIMARY KEY,
  uuid TEXT,
  major INTEGER,
  minor INTEGER,
  vehicle_id INTEGER REFERENCES vehicles(id),
  hardware_serial TEXT,
  installed_at TIMESTAMPTZ,
  status TEXT
);







CREATE TABLE pings (
  id SERIAL PRIMARY KEY,
  vehicle_id INTEGER,
  user_id INTEGER,
  lat NUMERIC,
  lng NUMERIC,
  speed NUMERIC,
  rssi INTEGER,
  recorded_at TIMESTAMPTZ DEFAULT now()
);












CREATE TABLE crowd_reports (
  id SERIAL PRIMARY KEY,
  vehicle_id INTEGER,
  user_id INTEGER,
  level TEXT,
  seats_available BOOLEAN,
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);












CREATE TABLE feedback (
  id SERIAL PRIMARY KEY,
  user_id INTEGER,
  vehicle_id INTEGER,
  rating INTEGER,
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);


