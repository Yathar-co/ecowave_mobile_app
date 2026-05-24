# EcoWave: Sustainable Goods Marketplace

EcoWave is a cross-platform mobile marketplace focused on facilitating the circular economy. The application enables users to trade second-hand goods while quantifying the environmental impact of each transaction. Built using a modern stack consisting of Flutter, Flask, and MongoDB, it provides a robust platform for sustainable commerce.

---

## Core Objectives
The primary goal of EcoWave is to reduce environmental degradation by encouraging product reuse. The platform implements an impact-tracking engine that calculates key environmental metrics, including CO₂ emissions avoided, water conservation, and waste diversion, based on product category and material composition.

---

## Technical Features

### Marketplace Architecture
- **Categorized Inventory:** Efficient browsing of sustainable goods across multiple sectors.
- **Impact Quantification:** Data-driven badges displaying environmental savings per listing.
- **Geolocation Services:** Integrated GPS positioning for localized seller-buyer discovery.

### Communication System
- **Real-time Messaging:** Low-latency communication layer implemented via Socket.IO.
- **Asynchronous Notifications:** Fallback SMTP service to alert users of pending inquiries when they are offline.

### Payment Integration
- **Razorpay Payment Gateway:** Support for diverse payment methods including UPI, Credit/Debit cards, and Netbanking.
- **Security Protocols:** Server-side signature verification to ensure transaction integrity and idempotent order processing.

### Geospatial Mapping
- **Google Maps Integration:** Map-based visualization of product distribution for enhanced local search capabilities.

---

## Tech Stack

- **Frontend:** [Flutter](https://flutter.dev) utilizing [Provider](https://pub.dev/packages/provider) for state management and [GoRouter](https://pub.dev/packages/go_router) for declarative routing.
- **Backend:** [Flask](https://flask.palletsprojects.com/) (Python-based RESTful API).
- **Database:** [MongoDB Atlas](https://www.mongodb.com/cloud/atlas) (NoSQL).
- **Socket Layer:** [Socket.IO](https://socket.io/) for full-duplex communication.
- **Payment Processor:** [Razorpay](https://razorpay.com/).
- **Mapping SDK:** [Google Maps SDK for Android](https://developers.google.com/maps).

---

## Deployment and Setup

### 1. Prerequisites
- Flutter SDK (Stable Channel)
- Python 3.10 or higher
- MongoDB Atlas cluster access

### 2. Backend Configuration
```bash
cd backend
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
```
Configure environment variables in `/backend/.env`:
```env
MONGODB_URI=your_mongodb_uri
SECRET_KEY=your_jwt_secret
SMTP_EMAIL=your_email
SMTP_PASSWORD=your_app_password
RAZORPAY_KEY_ID=your_razorpay_id
RAZORPAY_KEY_SECRET=your_razorpay_secret
```
Start the Flask server:
```bash
python main.py
```

### 3. Frontend Configuration
```bash
# Fetch dependencies
flutter pub get

# API Configuration Requirements:
# 1. Inject Google Maps API Key into: android/app/src/main/AndroidManifest.xml
# 2. Inject Razorpay Public Key into: lib/screens/marketplace_screen.dart

# Build and execute
flutter run
```

---

## Contribution Guidelines
We welcome contributions that improve the accuracy of impact calculations or enhance platform scalability. Please submit pull requests following standard Git flow and ensure all new features are documented.
