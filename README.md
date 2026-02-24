# 🚌 TransLink – Unified Transit Ecosystem (Mixed Fleet Edition)

## 1. Project Vision
TransLink is a state-of-the-art, location-aware public transport and digital payment platform designed for the Sri Lankan transportation sector. By integrating **Google Maps SDK** and **Supabase Realtime**, TransLink eliminates the need for manual dispatch dashboards, providing a seamless, automated experience for both commuters and transport operators.

---

## 2. Platform Architecture
The ecosystem is comprised of two core mobile applications and a serverless backend.

### 🏠 **Core Components**
- **Passenger App**: Feature-rich commuter platform with multi-modal trip planning, digital wallet, and AI-driven predictive timing.
- **Conductor Assistant**: Specialized tool for real-time location broadcasting, secure QR fare collection, and revenue tracking.
- **Supabase Cloud**: The "Source of Truth" for financial transactions, bus routes, and real-time positioning.

---

## 3. Latest Feature Updates (V2.0)

### 🔴🔵 **Mixed Fleet Synchronization**
The ecosystem now supports full tracking of both **Private** and **CTB (State)** buses.
- **Dynamic Mapping**: CTB buses appear in **Red** markers, while Private buses appear in **Blue**.
- **Fleet Selection**: Conductor app allows drivers to register as CTB or Private, dynamically updating their broadcast identity.

### 🎤 **Voice-Activated Search & Accessibility**
- **Natural Language Input**: Commuters can now use the voice icon to speak their destination, which is automatically parsed for trip planning.
- **Multi-lingual Support**: Full localized UI in **English, Sinhala, and Tamil** with zero hardcoded strings.

### ⚡ **Low-Latency Intelligence**
- **Butter-Smooth UI**: Optimized caching for "Nearby Stops" ensures instant display with zero API latency.
- **Bandwidth Optimization**: Marker management and data syncing are optimized for low-bandwidth 3G networks.

### 🛣️ **Intercity Express Experience**
- **Long-Range Focus**: Specialized UI for Intercity Express routes with accurate fare estimates and boarding proximity alerts.
- **Favorites Integration**: Real-time "Add to Favorites" for frequent routes.

---

## 4. Technical Stack & Configuration
| Layer                 | Technology |

| **Front-end**   |     Flutter (Dart) |

| **Backend**   |       Supabase (PostgreSQL / GraphQL / Realtime) 

| **Maps & Routing**   | Google Maps SDK & Google Directions API |

| **Payments**   |      Secure QR Code (HMAC-based) |

### 🛠️ **Supabase Integration**
To update credentials, modify these specific constants:
- **Passenger**: `translink_passenger/lib/core/constants/app_constants.dart`
- **Conductor**: `translink_Conductor/lib/core/constants/driver_constants.dart`

---

## 5. Build & Deployment
The project is stabilized for production release.

### 📦 **Final Release APKs (V2.0)**
Located in the **`build/apks/`** directory:
- `translink_passenger_v2.apk`: The premium commuter experience with mixed fleet support.
- `translink_conductor_v2.apk`: The specialized assistant with fleet registration.



---

- **Project Status**: ✅ Production Ready 
- **Architecture**: Google Maps + Supabase (Serverless)
-
