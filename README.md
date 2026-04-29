# 🚌 TransLink – Unified Transit Ecosystem (V4.0)

[![Status](https://img.shields.io/badge/Status-Production%20Ready-success.svg)]()
[![Platform](https://img.shields.io/badge/Platform-Flutter%20%7C%20Dart-blue.svg)]()
[![Backend](https://img.shields.io/badge/Backend-Supabase%20%7C%20PostgreSQL-green.svg)]()


## 1. Project Vision
TransLink is a state-of-the-art, location-aware public transport and digital payment ecosystem designed for the Sri Lankan transportation sector. By deeply integrating **Google Maps SDK** and **Supabase Realtime**, TransLink eliminates the need for manual dispatch dashboards, providing a seamless, automated, and localized experience for both commuters and transport operators.

---

## 2. Platform Architecture
The ecosystem revolves around two core mobile applications communicating through a highly secure, serverless backend.

### 🏠 **Core Components**
- **Passenger App**: Feature-rich commuter platform with multi-modal trip planning, dynamic wallet integration, and AI-driven predictive timing.
- **Conductor Assistant**: Specialized field tool for real-time location broadcasting, secure QR fare collection, and live revenue tracking.
- **Supabase Cloud**: The "Source of Truth" managing ACID-compliant financial transactions via Postgres RPCs, dynamic bus routing, and low-latency realtime positioning.

---

## 3. Core Features & Capabilities (V4.0)

### 🔴🔵 **Mixed Fleet Synchronization**
- **Dynamic Mapping**: Track both Private and CTB (State) buses simultaneously. CTB buses render as **Red** markers, while Private buses appear as **Blue**.
- **Live Broadcasting**: Conductor app allows drivers to register as CTB or Private, instantly updating their global broadcast identity.

### 💳 **Secure Digital Payments & Wallets**
- **QR-based Ticketing**: Passengers generate highly secure, timestamped QR tickets representing their journey.
- **Smart Validation**: The passenger app actively checks wallet balances *before* generating QR codes, blocking transactions instantly if funds are insufficient.
- **RPC Validation**: Conductors process payments through secure PostgreSQL Remote Procedure Calls (`handle_payment`), ensuring transaction atomicity and automatically preventing over-charging.

### 🌍 **Full Multi-lingual Localization**
- **Tri-lingual UI**: The entire ecosystem (both Passenger and Conductor apps) is fully translated into **English, Sinhala, and Tamil**.
- **Dynamic Switching**: Flawless language context swapping affecting everything from voice feedback and modal dialogues to error handling and snackbars.

### ⚡ **Low-Latency Intelligence & UI/UX**
- **Butter-Smooth UI**: Optimized draggable sheets, beautiful glassmorphism effects, and distinct, color-coded action buttons.
- **Voice-Activated Search**: Commuters can use natural language voice input to search for destinations.
- **Intercity Express**: Specialized UI for Long-Range Intercity Express routes with accurate fare estimates and boarding proximity alerts.

---

## 4. Technical Stack & Configuration

| Layer                 | Technology |
|-----------------------|------------|
| **Front-end**         | Flutter (Dart) |
| **Backend**           | Supabase (PostgreSQL / Realtime / RPC) |
| **Maps & Routing**    | Google Maps SDK & Google Directions API |
| **Payments**          | Secure QR Code (HMAC-based) & DB RPCs |

### 🛠️ **Supabase Integration**
To update credentials or connect to a new database environment, modify these specific environment files:
- **Passenger Environment**: `translink_passenger/lib/core/constants/app_constants.dart`
- **Conductor Environment**: `translink_Conductor/lib/core/constants/driver_constants.dart`

---

## 5. Build & Deployment
The project is stabilized and optimized for production release.

### 📦 **Final Release APKs (V4.0)**
Pre-compiled artifacts are located in the **`/releases`** directory:
- `translink_passenger_v4.apk`: The premium commuter experience with live tracking and smart wallets.
- `translink_conductor_v4.apk`: The specialized assistant with live revenue dashboards and QR scanning.

---
*Built for the future of smart transit in Sri Lanka.*

