# 🚌 TransLink – Unified Transit Ecosystem (NTC 2026 Compatible)

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

## 3. Latest Feature Updates (V2.5)

### 🗺️ **Dynamic Map Intelligence (Passenger)**
The Passenger App now features **Context-Aware Marker Filtering**. 
- **Exploration Mode**: Shows all active buses in the city on startup to highlight system activity.
- **Search Focus**: When a user searches for a destination (e.g., *"Kottawa"*), the map automatically hides irrelevant bus markers, showing only those routes that serve the user's intended journey.
- **Auto-Reset**: Markers instantly restore when a search is cleared.

### 📶 **Resilient Error Handling (Conductor)**
To handle network variability in transit, the Conductor Assistant now features **Expert Error Translation**.
- **Localized Alerts**: Cryptic technical exceptions (like `SocketException`) are automatically translated into user-friendly alerts in **English, Sinhalese, and Tamil**.
- **User-Centric**: Drivers see "No internet connection" instead of code errors, ensuring they know exactly how to resolve connectivity issues.

---

## 4. Technical Stack & Configuration
| Layer               | Technology |

| **Front-end** |     Flutter (Dart) |
| **Backend** |       Supabase (PostgreSQL / GraphQL / Realtime) 
| **Maps & Routing** | Google Maps SDK & Google Directions API |
| **Payments** |      Secure QR Code (HMAC-based) |

### 🛠️ **Supabase Integration**
To update credentials, modify these specific constants:
- **Passenger**: `translink_passenger/lib/core/constants/app_constants.dart`
- **Conductor**: `translink_Conductor/lib/core/constants/driver_constants.dart`

---

## 5. Build & Deployment
The project is stabilized for production release.

### 📦 **Final Release APKs**
Located in the **`build/apks/`** directory:
- `translink_passenger.apk`: The premium commuter experience.
- `translink_conductor.apk`: The specialized assistant for drivers/conductors.



---

- **Project Status**: ✅ Production Ready 
- **Architecture**: Google Maps + Supabase (Serverless)
-
