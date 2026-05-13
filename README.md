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
        HolidayAPI["📅 Nager.Date API <br/>(LK Holidays)"]
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
    Passenger -->|8. Fetch LK Holidays| HolidayAPI

    Passenger -->|9. Present QR Ticket| Conductor
    Conductor -->|10. Scan QR & Trigger RPC <br/> via handle_payment RPC| RPC
    RPC -->|11. ACID Wallet Transaction| DB
    DB -->|12. Stream Revenue Updates| Conductor
    
    classDef client fill:#E0F2FE,stroke:#0284C7,stroke-width:2px;
    classDef backend fill:#DCFCE7,stroke:#15803D,stroke-width:2px;
    classDef external fill:#FEF3C7,stroke:#D97706,stroke-width:2px;
    class Passenger,Conductor client;
    class Auth,Realtime,DB,RPC backend;
    class Gmaps,Groq,HolidayAPI external;
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

    holidays {
        uuid id PK
        date holiday_date UK
        text name
        text country_code
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


