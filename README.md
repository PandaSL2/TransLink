# 🚌 TransLink – Unified Transit Ecosystem (V4.0)

[![Production Ready](https://img.shields.io/badge/Status-Production%20Ready-success.svg?style=for-the-badge&logo=github)](https://github.com/PandaSL2/TransLink)
[![Platform - Flutter](https://img.shields.io/badge/Platform-Flutter%20%7C%20Dart-02569B.svg?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![Backend - Supabase](https://img.shields.io/badge/Backend-Supabase%20%7C%20Postgres-3ECF8E.svg?style=for-the-badge&logo=supabase)](https://supabase.com)
[![AI Engine - Groq](https://img.shields.io/badge/AI%20Engine-Groq%20%7C%20Llama%203.1-F55036.svg?style=for-the-badge&logo=groq)](https://groq.com)
[![Localization - Sinhala/Tamil/English](https://img.shields.io/badge/Localization-Tri--lingual%20%28EN%2FSI%2FTA%29-FF9900.svg?style=for-the-badge)]()

TransLink is a state-of-the-art, location-aware public transport and digital wallet ecosystem designed for the Sri Lankan transportation sector. By deeply integrating **Google Maps SDK**, **Supabase Realtime Websockets**, and **Llama 3.1 LLM (via Groq)**, TransLink bridges the gap between commuters and transit operators—eliminating the need for expensive manual dispatch dashboards and providing a seamless, automated, and localized digital ticketing experience.

---

## 🗺️ System Architecture

The TransLink ecosystem consists of two distinct cross-platform mobile clients communicating via an ACID-compliant, real-time backend-as-a-service (BaaS) and external microservices.

```mermaid
graph TD
    %% Clients
    subgraph Mobile_Clients [Mobile Applications]
        Passenger["📱 Passenger App <br/>(Commuters)"]
        Conductor["📟 Conductor Assistant <br/>(Bus Operators)"]
    end

    %% Backend BaaS
    subgraph Backend_Cloud [Supabase BaaS Cloud]
        Auth["🔐 GoTrue Auth <br/>(JWT Roles)"]
        Realtime["📡 PostgreSQL Realtime <br/>(Websockets Broadcast)"]
        DB[("🗄️ PostgreSQL Database <br/>(RLS & Functions)")]
        RPC["⚡ Plpgsql RPCs <br/>(Payment Atomicity)"]
    end

    %% External Microservices
    subgraph External_APIs [External Cloud Services]
        Gmaps["🗺️ Google Maps SDK <br/>& Directions API"]
        Groq["🧠 Groq AI API <br/>(Llama 3.1-8B-Instant)"]
    end

    %% Interactions
    Passenger -->|1. Authenticate / JWT| Auth
    Conductor -->|1. Authenticate / JWT| Auth
    
    Conductor -->|2. Upsert GPS Status <br/> 5s Interval Background| DB
    DB -->|3. Trigger Event / WAL| Realtime
    Realtime -.->|4. Stream Live Location <br/> WS Low-Latency| Passenger
    
    Passenger -->|5. Read Routes / Stops| DB
    Passenger -->|6. Geolocation & Routing| Gmaps
    Passenger -->|7. NLP Search / Voice Chat| Groq

    Passenger -->|9. Present QR Ticket| Conductor
    Conductor -->|10. Scan QR & Trigger RPC <br/> via handle_payment RPC| RPC
    RPC -->|11. ACID Wallet Transaction| DB
    DB -->|12. Stream Revenue Updates| Conductor
    
    classDef client fill:#E0F2FE,stroke:#0284C7,stroke-width:2px;
    classDef backend fill:#DCFCE7,stroke:#15803D,stroke-width:2px;
    classDef external fill:#FEF3C7,stroke:#D97706,stroke-width:2px;
    class Passenger,Conductor client;
    class Auth,Realtime,DB,RPC backend;
    class Gmaps,Groq external;
```

---

## 🗄️ Database Entity Relationship Diagram (ERD)

The PostgreSQL database is highly structured with primary-foreign key integrity constraints, PostgreSQL functions, and row-level security (RLS) policies guarding sensitive data.

```mermaid
erDiagram
    routes ||--o{ route_variants : "has"
    routes ||--o{ service_profiles : "schedules"
    routes ||--o{ favourites : "starred by"
    
    route_variants ||--o{ route_stop_sequences : "contains"
    route_variants ||--o{ fixed_departures : "has departures"
    stops ||--o{ route_stop_sequences : "referenced in"
    
    auth_users ||--|| profiles : "one-to-one profile"
    auth_users ||--|| passenger_wallets : "has balance"
    auth_users ||--o{ fare_transactions : "performs"
    auth_users ||--o{ favourites : "saves"
    auth_users ||--o{ live_bus_positions : "broadcasts (as driver)"

    routes {
        uuid id PK
        text route_number UK
        text name
        text type
        text color_hex
        boolean is_active
        timestamp created_at
    }

    route_variants {
        uuid id PK
        uuid route_id FK
        text direction
        text origin_name
        text destination_name
        integer base_duration_minutes
        numeric distance_km
        jsonb polyline_coords
        timestamp created_at
    }

    stops {
        uuid id PK
        text name
        text address
        numeric lat
        numeric lng
        boolean is_active
        timestamp created_at
    }

    route_stop_sequences {
        uuid id PK
        uuid route_variant_id FK
        uuid stop_id FK
        integer sequence_order
        integer walking_meters
    }

    service_profiles {
        uuid id PK
        uuid route_id FK
        text profile_name
        text service_type
        text day_type
        time window_start
        time window_end
        integer interval_minutes
        integer delay_factor_minutes
        boolean is_active
        timestamp created_at
    }

    fixed_departures {
        uuid id PK
        uuid route_variant_id FK
        text day_type
        time departure_time
        boolean is_active
        timestamp created_at
    }

    live_bus_positions {
        text bus_number PK
        text route_number
        text route_name
        numeric latitude
        numeric longitude
        numeric speed
        numeric heading
        text status
        text fleet_type
        timestamp last_updated_at
        uuid driver_id FK
    }

    profiles {
        uuid id PK
        text email
        text role
        text full_name
        timestamp created_at
    }

    passenger_wallets {
        uuid user_id PK
        numeric balance
        timestamp updated_at
        timestamp created_at
    }

    fare_transactions {
        uuid id PK
        uuid passenger_id FK
        numeric amount
        text bus_number
        text route_number
        text type
        text status
        text description
        timestamp created_at
    }

    favourites {
        uuid id PK
        uuid user_id FK
        uuid route_id FK
        text label
        timestamp created_at
    }
```

---

## ✨ Core Features & Technical Implementation

### 🔴🔵 1. Real-time Mixed Fleet Synchronization
- **Dynamic Live Tracking**: Tracks both Private and CTB (State) buses simultaneously. CTB buses render dynamically as **Red** markers, while Private buses appear as **Blue** markers.
- **WebSocket Broadcast**: Uses Supabase Realtime to push live bus locations at a **5-second interval** directly to the Google Maps UI in the passenger app with zero-flicker updating.
- **Operating Hours Intelligence**: The Conductor app actively checks schedule profiles (`RouteScheduleService`) and automatically terminates tracking when operating hours end.

### 💳 2. Smart Wallets & Secure QR Payments
- **Secure Ticketing**: Passengers generate a secure QR code encoding their `uid`, requested journey `fare`, and destination (`dest`).
- **Atomic Transactions (Postgres RPC)**: Payments are processed on the server via the custom PostgreSQL function `handle_payment`. This ensures database **atomicity**: the passenger's wallet is decremented and a transaction record is created within a single transaction block. If any step fails (e.g., insufficient funds), the entire block rolls back to prevent inconsistencies.
- **Live Revenue Streaming**: The Conductor's homepage listens to a live stream of `fare_transactions` filtered by their specific `bus_number`, instantly updating their **Session Revenue** and **Passenger Count** widgets upon a successful scan.

### 🗣️ 3. Intelligent AI Transit Chatbot
- **Llama-3.1 Processing (Groq)**: Integrated directly in the passenger app is an interactive AI chatbot using the ultra-fast `llama-3.1-8b-instant` model.
- **Context-Aware Assistance**: The chatbot receives live database structures (available routes and stops) dynamically in its system prompt to answer specific routing, timetable, and fare queries accurately.
- **Smart suggestions**: Auto-suggests stops (`getSuggestions`) and interprets speech/natural language queries (`interpretQuery`) dynamically.
- **Tri-lingual Responses**: Dynamically updates prompt instructions so the AI responds exclusively in the user's selected language (Sinhala, Tamil, or English).

### 🌍 4. Complete Tri-lingual Localization
- **Native Inline Localization**: Fully translated interface supporting **English**, **Sinhala (සිංහල)**, and **Tamil (தமிழ்)** across all text elements, dialogs, error handlers, and notifications.
- **Localized Voice Feedback**: App actions speak/respond utilizing appropriate regional language contexts for voice search capabilities.

---

## 📂 Project Directory Structure

```text
TransLink/
├── supabase/                            # Supabase Backend Configuration
│   ├── functions/                       # Edge Functions
│   └── migrations/                      # Database Schema & Data Migrations
│       ├── supabase_schema.sql          # Primary Tables, Triggers, & Indexes
│       ├── 010_seed_real_routes.sql     # Seed script for Sri Lankan Bus Routes
│       ├── 012_payment_rpc.sql          # Secure transactional payments RPC
│       └── 013_drop_unused_tables.sql   # Unused table cleanup
├── translink_passenger/                 # Commuter Mobile Application (Flutter)
│   ├── assets/                          # App Icons, Images & Fonts
│   └── lib/
│       ├── core/
│       │   ├── constants/               # Credentials & Config (app_constants.dart)
│       │   └── utils/                   # Translation Engines (app_localizations.dart)
│       ├── features/                    # UI Modules (Map, Wallet, AI Support, etc.)
│       └── services/                    # APIs & Services (supabase_service.dart, ai_service.dart)
├── translink_Conductor/                 # Driver/Conductor Mobile Application (Flutter)
│   └── lib/
│       ├── core/
│       │   └── constants/               # Credentials & Config (driver_constants.dart)
│       ├── features/                    # Core Modules (Home setup, QR Scanner dashboard)
│       └── services/                    # GPS Background tracking, RPC Scan payments
└── releases/                            # Pre-compiled Android Artifacts
    ├── translink_passenger_v4.apk       # Finished Commuter APK
    └── translink_conductor_v4.apk       # Finished Driver APK
```

---

## ⚙️ Environment Configuration & Setup

### 🔑 1. Setting up Credentials
To connect the ecosystem to your custom database and services, modify the environment files in the respective directories:

#### Commuter App (Passenger)
Open [app_constants.dart](file:///d:/Projects/Translink/TransLink/translink_passenger/lib/core/constants/app_constants.dart) and configure the following:
```dart
class AppConstants {
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';
}
```

#### Driver App (Conductor)
Open [driver_constants.dart](file:///d:/Projects/Translink/TransLink/translink_Conductor/lib/core/constants/driver_constants.dart) and configure the following:
```dart
class DriverConstants {
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
  static const String groqApiKey = 'YOUR_GROQ_API_KEY';
}
```

### 💻 2. Building and Running Locally

Ensure you have Flutter SDK (>=3.0.0) installed and configured.

#### Step 1: Clone and navigate to workspace
```bash
git clone https://github.com/PandaSL2/TransLink.git
cd TransLink
```

#### Step 2: Set up Passenger App
```bash
cd translink_passenger
flutter pub get
flutter run
```

#### Step 3: Set up Conductor App
```bash
cd ../translink_Conductor
flutter pub get
flutter run
```

---

## 🎓 Viva Presentation Handbook

This section is dedicated to helping you defend your project with confidence, showcasing the engineering depth and architectural decisions that make TransLink stand out.

### 🏛️ Key Architectural Highlights
*   **Why Supabase instead of Firebase Realtime?**
    *   *Relational Integrity*: Firebase uses flat JSON structures which lead to data duplication and lack ACID compliance for monetary transactions. Supabase utilizes a full **PostgreSQL** relational engine. This allows complex joins (e.g., matching passenger ID, bus number, and calculating routes), database triggers (for user profile generation), and exact monetary precision (`NUMERIC(10,2)`).
    *   *Postgres Realtime*: Rather than writing expensive query listeners, we leverage Postgres Write-Ahead Logs (WAL) via websockets to stream coordinates only when rows mutate.
*   **Preventing Race Conditions**: Payment processing is kept out of client devices. All financial transactions are wrapped in a single database Remote Procedure Call (`handle_payment`), ensuring that wallet balance checks and transaction records occur atomically under high isolation levels.

---

### 🧐 Expected Examiner Questions & Defense

#### Q1: "How do you guarantee that a passenger isn't charged twice, or that a network failure doesn't cause money to be deducted without creating a transaction?"
> 💡 **Defense Strategy:** Point to the database architecture and explain **ACID transaction atomicity**.
> 
> "In TransLink, we do not handle financial logic in the Flutter client. We implemented a secure, serverless **PostgreSQL Remote Procedure Call (RPC)** named `handle_payment`. This function executes inside a database transaction block. 
> It first checks the passenger’s wallet balance. If verified, it subtracts the fare and writes a row to the `fare_transactions` table. If either action fails, or if a database constraint is violated, PostgreSQL rolls back the entire operation, restoring the wallet balance to its previous state. This ensures absolute transactional atomicity and prevents discrepancies due to app crashes or network timeouts."

#### Q2: "Continuous GPS broadcasting drains mobile batteries. How does the Conductor app optimize background tracking?"
> 💡 **Defense Strategy:** Explain background isolates, state filtering, and operating hour constraints.
> 
> "We optimized battery and network bandwidth in three ways:
> 1. **Background Isolate**: We use `flutter_background_service` running in a dedicated Android background execution environment. It captures GPS data in a lightweight isolate separate from the UI thread.
> 2. **Temporal Throttling**: GPS updates are throttled to a **5-second window**. Sub-second polling is unnecessary for bus transit.
> 3. **Operating Hours Bounds**: The background service automatically monitors operating hours (`RouteScheduleService`). If the driver forgets to stop tracking at the end of their shift, the background isolate terminates automatically, shutting down GPS hardware polling and saving power."

#### Q3: "What happens if there is no internet connection on a remote route in Sri Lanka?"
> 💡 **Defense Strategy:** Emphasize local database sync and offline caching.
> 
> "The Passenger app features an `offline_service.dart`. When a network failure is detected, the app switches to offline mode. It caches the latest downloaded bus timetable and routing coordinates locally in **SharedPreferences** and uses a localized Levenshtein Distance algorithm to continue providing search suggestions. 
> On the driver side, the GPS tracking system gracefully fails with standard error feedback, and the scanner can buffer local validation indicators until standard data coverage resumes."

---

### 🚀 Interactive Live Demo Script (For Examiners)

To show off your application's capabilities, follow this quick 3-step sequence during your viva:

| Step | Action | Feature to Highlight | Expected Outcome |
|---|---|---|---|
| **1** | Open the **Conductor App** and log in. Select a route (e.g., `138 Maharagama - Colombo Fort`), choose "Private" or "CTB" fleet identity, and tap **"Start Route"**. | *Mixed Fleet Synchronization & Background Tracking* | The app goes into "Online" status, displaying a green badge, and begins streaming location updates to the DB. |
| **2** | Open the **Passenger App** and go to the Map tab. Select English, Sinhala, or Tamil. You will see a live bus icon floating on Route 138. | *Low-latency Maps & Multi-language Localization* | The bus icon appears immediately as **Blue** (Private) or **Red** (CTB). Swapping languages immediately alters the UI headers, snackbars, and voice dialogs without lag. |
| **3** | In the **Passenger App**, generate a Ticket QR for Route 138. Use the **Conductor App**'s scan tab to scan the QR code. | *Serverless Secure Ticketing & Real-time Revenue Dashboard* | The payment RPC executes. The Passenger app shows a "Success" e-ticket. Instantly, the Conductor's revenue card triggers a ripple animation, showing updated **Session Revenue** and **Passenger Count** on the live stream. |

---
*Developed with a commitment to the future of smart transit in Sri Lanka.*
