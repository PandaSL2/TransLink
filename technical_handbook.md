# 📘 TransLink: A-to-Z Technical Handbook

This document provides a comprehensive technical breakdown of the TransLink ecosystem. It is intended for project presentations and technical documentation.

---

## 🏗️ 1. System Architecture (The "Big Picture")
TransLink is a distributed system consisting of two cross-platform mobile apps (built with **Flutter**) and a real-time, event-driven backend (**Supabase**).

### A. The Tech Stack
*   **Frontend**: Flutter (Dart) - Single codebase for Android & iOS.
*   **Database**: PostgreSQL (Supabase) - Relational data with real-time capabilities.
*   **Real-time Communication**: PostgreSQL WAL (Write Ahead Log) + Websockets (Supabase Realtime).
*   **AI Engine**: Llama 3.1 via Groq API (Ultra-low latency inference).
*   **Maps & Geolocation**: Google Maps SDK for Flutter.

---

## 🗄️ 2. Backend Processes & Database Logic

### A. Real-time GPS Synchronization
1.  **Broadcast**: The Conductor app sends GPS coordinates (Lat/Lng) to the `live_bus_positions` table every 5 seconds.
2.  **Streaming**: The Passenger app listens to a PostgreSQL `STREAM` on that table, filtered by the selected route.
3.  **Latency**: Because it uses native websockets, the marker on the passenger's map updates in **<500ms** after the conductor's phone moves.

### B. Secure Payment Processing (The RPC Layer)
To ensure money is never lost or duplicated, I implemented **Atomic Transactions**:
*   Instead of the app calculating balances, it calls a database function: `handle_payment()`.
*   **Atomicity (ACID)**: This function performs three steps in one go:
    1.  Verifies the passenger has enough funds.
    2.  Deducts the fare from the passenger's wallet.
    3.  Creates a transaction record for the conductor.
*   If any step fails, the entire process is cancelled (rolled back), ensuring financial integrity.

### C. Row-Level Security (RLS)
Security is handled at the database level, not just the app level:
*   Passengers can only read their own wallet balance.
*   Conductors can only see transactions related to their specific bus number.
*   This prevents users from "hacking" the API to see other people's data.

---

## 🧠 3. Intelligence Layer: AI Transit Assistant (Natural Language)
*   **Context Injection**: Every AI request includes a "System Prompt" that dynamically pulls the current list of stops and routes from the database.
*   **Localization**: The AI is instructed to detect the user's language setting and respond exclusively in English, Sinhala, or Tamil.

---

## 🌍 4. Localization Engine
The trilingual support is handled via a **Key-Value Localization Engine**:
*   All strings are stored in JSON maps.
*   The `AppLocalizations` class dynamically switches the entire UI context without requiring a restart, supporting Sinhala (සිංහල), Tamil (தமிழ்), and English.

---

## 📂 5. Key File Reference
*   `supabase/migrations/000_initial_schema.sql`: Core database structure.
*   `translink_passenger/lib/services/supabase_service.dart`: Backend communication.
*   `translink_passenger/lib/services/ai_service.dart`: Groq/Llama integration.

---

*Document Version: 1.0 (May 2026)*  
*Developed by: Solo Project*
