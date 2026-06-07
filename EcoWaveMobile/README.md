# EcoWave: Sustainable Goods P2P Marketplace

EcoWave is a modern, cross-platform mobile marketplace designed to facilitate the circular economy. The application enables users to trade second-hand goods while quantifying the environmental impact (CO₂ saved, water saved, waste diverted) of each transaction. 

By prioritizing developer accessibility, this repository is configured for a **100% free, zero-cost, zero-setup developer experience** — eliminating paid third-party dependencies like Google Maps or commercial payment gateways in favor of open-source and native protocols.

---

## 🌟 Key Technical Features

### 🗺️ Cost-Free Geospatial Mapping (OpenStreetMap)
We migrated away from the paid Google Maps SDK to **OpenStreetMap** tiles rendered natively via `flutter_map` and styled beautifully to match our dark eco-friendly design system.
* **No Google Cloud Account Required** 
* **No Billing/Credit Card Activation Needed**
* **Zero API Key Configurations**
* Custom green markers show direct listing locations with instant environmental impact tooltips.

### 💳 Direct P2P UPI Payment Flow (Zero KYC / Zero Cost)
We replaced the restrictive Razorpay merchant setup (which requires commercial business registration and personal PAN/KYC submission) with a custom **Direct Peer-to-Peer UPI Gateway**:
* **Direct Bank Transfer:** Payments transfer instantly and securely from the buyer's UPI app (GPay, PhonePe, Paytm, BHIM) directly to the seller's bank account.
* **Smart Device Routing (Dual Intent & QR Mode):**
  * **On Real Devices:** Tapping "Buy Now" triggers standard UPI deep links. Android pops up a native sheet to select your preferred local UPI app with the product title and seller's price pre-filled.
  * **On Emulators:** Displays a beautiful, dynamically generated **payment QR code** on the screen. Testers can simply scan the screen with their real phone's UPI app to process transactions.
* **Safe Ledger Verification:** Buyer confirms payment completion inside the app, immediately triggering the backend to mark the product as sold and credit environmental points to both profiles.

### 🔌 Single-Point Network Configuration
All network, API, and WebSocket endpoints are centralized in a single configuration file (`lib/config/server_config.dart`). When moving from local testing to a physical APK, you only need to change a single string.

---

## 🛠️ Tech Stack

* **Frontend:** [Flutter](https://flutter.dev) (Dart) utilizing [Provider](https://pub.dev/packages/provider) for state management and [GoRouter](https://pub.dev/packages/go_router) for declarative routing.
* **Backend:** [Flask](https://flask.palletsprojects.com/) (Python-based RESTful API) + [Socket.IO](https://socket.io/) for real-time seller-buyer chat.
* **Database:** [MongoDB Atlas](https://www.mongodb.com/cloud/atlas) (NoSQL database).
* **Payment/Mapping:** Built on native UPI Deep Linking (`url_launcher`), `qr_flutter`, and OpenStreetMap (`flutter_map`).

---

## 🚀 Setup & Execution

### 1. Prerequisites
* Flutter SDK (Stable Channel)
* Python 3.10+
* MongoDB Atlas Cluster (or local MongoDB)

### 2. Backend Configuration
1. Navigate to the backend directory and set up a virtual environment:
   ```bash
   cd backend
   python -m venv venv
   # On Windows:
   venv\Scripts\activate
   # On macOS/Linux:
   source venv/bin/activate
   ```
2. Install Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```
3. Configure environment variables in `backend/.env` (simply fill in your MongoDB connection string and SMTP/Google details):
   ```env
   MONGODB_URI=mongodb+srv://<user>:<password>@cluster.mongodb.net/ecowave
   SECRET_KEY=your_jwt_secret
   SMTP_EMAIL=your_email
   SMTP_PASSWORD=your_app_password
   ```
4. Start the Flask server:
   ```bash
   python main.py
   ```

### 3. Frontend Configuration
1. Fetch and install Flutter packages:
   ```bash
   flutter pub get
   ```
2. Check your connection URL in `lib/config/server_config.dart`:
   * **For Local Emulators:** Keep `_productionUrl = ""` empty. The app will auto-detect your local machine (using `10.0.2.2:5001` on Android and `localhost:5001` on iOS).
   * **For Real Device Wi-Fi / Production Testing:** Put your computer's local network IP or your deployed cloud server URL:
     ```dart
     const String _productionUrl = 'http://192.168.1.5:5001'; // or Render/Railway URL
     ```
3. Run the application:
   ```bash
   flutter run
   ```

---

## 💡 How to Demo the Flow
1. **Log in** (or sign up) as two separate users.
2. **User A (Seller):** Taps the sell icon, fills out details, inputs a **UPI ID** (e.g. `yourname@okaxis` or `9876543210@paytm`), and lists an item.
3. **User B (Buyer):** Opens the marketplace, clicks on the item, and taps **Buy Now**.
4. **Checkout:** The UPI Checkout Sheet slides up showing the seller's UPI ID, price, and a scannable QR Code. 
5. **Process Transaction:** Tapping "Open UPI App" launches local wallets, or scanning the QR code allows sending ₹1 for physical verification.
6. **Mark Sold:** Tapping **"I have completed the payment"** will close the sheet, mark the item as Sold, and instantly award CO₂ and environmental impact points to both user profiles!
