import os
import re
import time
import threading
import requests
import json
from datetime import datetime, timedelta
from functools import wraps
from urllib import parse as urllib_parse
from flask import Flask, jsonify, request, redirect, url_for, session
from flask_cors import CORS
from flask_socketio import SocketIO, emit, join_room
from werkzeug.security import generate_password_hash, check_password_hash
from pymongo import MongoClient, ASCENDING
from pymongo.errors import PyMongoError
from dotenv import load_dotenv
import jwt
from authlib.integrations.flask_client import OAuth
from concurrent.futures import ThreadPoolExecutor
from datetime import date
from dateutil.relativedelta import relativedelta
import certifi
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import uuid
try:
    from google.oauth2 import id_token as google_id_token
    from google.auth.transport import requests as google_auth_requests
    GOOGLE_AUTH_AVAILABLE = True
except ImportError:
    GOOGLE_AUTH_AVAILABLE = False
# No payment gateway SDK needed — using direct UPI

load_dotenv()

MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://localhost:27017/")
JWT_SECRET = os.getenv("SECRET_KEY", "dev_jwt_secret")
JWT_EXP_SECONDS = int(os.getenv("JWT_EXP_SECONDS", 86400))
FRONTEND_ORIGIN = os.getenv("FRONTEND_ORIGIN", "http://localhost:52358")
PORT = int(os.getenv("PORT", 5001))

# No payment gateway needed — direct UPI P2P payments
SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", 587))
SMTP_EMAIL = os.getenv("SMTP_EMAIL", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")

app = Flask(__name__)
# Allow all origins for development to avoid CORS issues
CORS(app, resources={r"/api/*": {"origins": "*"}})
app.secret_key = JWT_SECRET
socketio = SocketIO(app, cors_allowed_origins="*")

# Detect if MongoDB is local or remote (Atlas) and configure SSL accordingly
is_local_mongo = "localhost" in MONGODB_URI or "127.0.0.1" in MONGODB_URI

if is_local_mongo:
    # Local MongoDB - no SSL
    client = MongoClient(MONGODB_URI)
else:
    # Remote MongoDB (Atlas) - use SSL
    client = MongoClient(
        MONGODB_URI, 
        tls=True, 
        tlsAllowInvalidCertificates=False,
        tlsCAFile=certifi.where()
    )
db = client['userinfo']
users_col = db['users']
products_col = db['products']
inquiries_col = db['inquiries']
messages_col = db['messages']
transactions_col = db['transactions']
reports_col = db['reports']
reviews_col = db['reviews']

# ── MongoDB Indexes ─────────────────────────────────────────────────────────
users_col.create_index([("email", ASCENDING)], unique=True, sparse=True)
products_col.create_index([("id", ASCENDING)], unique=True)
products_col.create_index([("seller_email", ASCENDING)])
products_col.create_index([("status", ASCENDING)])
products_col.create_index([("created_at", ASCENDING)])
products_col.create_index([("title", "text"), ("description", "text"), ("category", "text")])
transactions_col.create_index([("txn_id", ASCENDING)], unique=True)
transactions_col.create_index([("product_id", ASCENDING)])
transactions_col.create_index([("buyer_email", ASCENDING)])
transactions_col.create_index([("seller_email", ASCENDING)])
inquiries_col.create_index([("created_at", ASCENDING)])
messages_col.create_index([("room", ASCENDING), ("created_at", ASCENDING)])
reports_col.create_index([("target_id", ASCENDING)])
reports_col.create_index([("report_id", ASCENDING)])
reviews_col.create_index([("product_id", ASCENDING)])
reviews_col.create_index([("seller_email", ASCENDING)])

# Impact Metrics Constants
IMPACT_METRICS = {
    "electronics": {"co2": 50.0, "water": 100.0, "waste": 1.5},
    "clothing": {"co2": 15.0, "water": 2000.0, "waste": 0.5},
    "books": {"co2": 2.0, "water": 20.0, "waste": 0.5},
    "home": {"co2": 25.0, "water": 50.0, "waste": 10.0},
    "accessories": {"co2": 5.0, "water": 10.0, "waste": 0.2},
    "other": {"co2": 10.0, "water": 30.0, "waste": 1.0}
}

# Material Multipliers (adjusts impact based on sustainability)
MATERIAL_MULTIPLIERS = {
    "cotton": 0.8,      # Natural, slightly better than synthetic
    "polyester": 1.2,   # Synthetic, higher impact
    "wood": 0.5,        # Renewable
    "metal": 1.5,       # High energy to produce/recycle
    "plastic": 1.3,     # High waste impact
    "glass": 0.7,       # Highly recyclable
    "other": 1.0
}

# ── Email Validation ────────────────────────────────────────────────────────
EMAIL_REGEX = re.compile(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')

def validate_email(email):
    """Validate email format. Returns True if valid."""
    if not email or not isinstance(email, str):
        return False
    return bool(EMAIL_REGEX.match(email.strip()))

# ── Lock Expiry Background Thread ───────────────────────────────────────────
LOCK_EXPIRY_MINUTES = 15

def expire_stale_locks():
    """Release product locks older than LOCK_EXPIRY_MINUTES."""
    while True:
        try:
            cutoff = datetime.utcnow() - timedelta(minutes=LOCK_EXPIRY_MINUTES)
            result = products_col.update_many(
                {"status": "locked", "locked_at": {"$lt": cutoff}},
                {"$set": {"status": "active"}, "$unset": {"locked_by": "", "locked_at": ""}}
            )
            if result.modified_count > 0:
                app.logger.info(f"Released {result.modified_count} stale locks")
        except Exception as e:
            app.logger.error(f"Lock expiry error: {e}")
        time.sleep(60)  # Check every minute

# Start lock expiry thread
lock_thread = threading.Thread(target=expire_stale_locks, daemon=True)
lock_thread.start()

def calculate_impact(category, material=None):
    """Calculate eco impact based on category and material"""
    cat_key = (category or "other").lower()
    base = IMPACT_METRICS.get(cat_key, IMPACT_METRICS["other"]).copy()

    # Apply material multiplier if available
    if material:
        multiplier = MATERIAL_MULTIPLIERS.get(material.lower(), 1.0)
        base["co2"] *= multiplier
        base["water"] *= multiplier
        base["waste"] *= multiplier

    return base

def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None
        auth_header = request.headers.get('Authorization')
        
        if auth_header:
            try:
                # Expecting "Bearer <token>"
                parts = auth_header.split(" ")
                if len(parts) == 2 and parts[0].lower() == 'bearer':
                    token = parts[1]
                else:
                    # Fallback for simple token strings or malformed Bearer
                    token = parts[-1]
            except Exception:
                return jsonify({'message': 'Authorization header format is invalid!'}), 401
        
        if not token:
            app.logger.warning(f"Auth failed: Token missing for {request.path}")
            return jsonify({'message': 'Authentication required. Please log in.'}), 401
            
        try:
            # Ensure the secret key is a string for the decode function
            secret = app.secret_key
            if isinstance(secret, bytes):
                secret = secret.decode('utf-8')

            # Add leeway to handle clock skew between client and server
            data = jwt.decode(token, secret, algorithms=["HS256"], leeway=300)
            email = data.get('email')
            if not email:
                return jsonify({'message': 'Invalid session token (no email).'}), 401

            current_user = users_col.find_one({"email": email})
            if not current_user:
                return jsonify({'message': 'User account not found.'}), 401

            return f(current_user, *args, **kwargs)
        except jwt.ExpiredSignatureError:
            return jsonify({'message': 'Token has expired!'}), 401
        except Exception as e:
            # Safely convert error to string to avoid serialization issues
            error_str = str(e)
            app.logger.warning(f"Auth failed on {request.path}: {error_str}")
            return jsonify({'message': 'Token is invalid!', 'error': error_str}), 401

    return decorated

oauth = OAuth(app)

google = oauth.register(
    name="google",
    client_id=os.getenv("GOOGLE_CLIENT_ID"),
    client_secret=os.getenv("GOOGLE_CLIENT_SECRET"),
    server_metadata_url="https://accounts.google.com/.well-known/openid-configuration",
    client_kwargs={"scope": "openid email profile"},
)

try:
    app.logger.info("Loaded Google server_metadata keys: %s", list(google.server_metadata.keys()))
    app.logger.info("Google userinfo_endpoint: %s", google.server_metadata.get("userinfo_endpoint"))
except Exception:
    app.logger.exception("Unable to read google.server_metadata (discovery may have failed)")

def create_default_user(user_id: str) -> dict:
    user_doc = {
        "user_id": user_id,
    }
    users_col.insert_one(user_doc)
    return user_doc

def get_user(user_id: str) -> dict:
    user = users_col.find_one({"user_id": user_id})
    if not user:
        user = create_default_user(user_id)
    return user

def update_user(user_id: str, update_dict: dict) -> None:
    update_dict["updated_at"] = datetime.utcnow()
    users_col.update_one({"user_id": user_id}, {"$set": update_dict})

def create_jwt_for_user(user_doc: dict) -> str:
    now = datetime.utcnow()
    payload = {
        "sub": str(user_doc.get("user_id", user_doc.get("username"))),
        "email": user_doc.get("email"),
        "name": user_doc.get("name"),
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=JWT_EXP_SECONDS)).timestamp()),
        "provider": user_doc.get("provider", "oauth")
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm="HS256")
    if isinstance(token, bytes):
        token = token.decode("utf-8")
    return token

def upsert_oauth_user(email: str, name: str = None, provider: str = "google", extra: dict = None) -> dict:
    query = {"email": email}
    now = datetime.utcnow()

    # Check if user already exists to preserve fields
    existing_user = users_col.find_one(query)

    # Determine user_id: preserve existing one if present, else fallback to name or email prefix
    if existing_user and existing_user.get("user_id"):
        user_id = existing_user["user_id"]
    elif existing_user and existing_user.get("username"):
        user_id = existing_user["username"]
    else:
        user_id = name or email.split("@")[0]

    update = {
        "$set": {
            "username": name or user_id,
            "email": email,
            "name": name or user_id,
            "user_id": user_id,
            "provider": provider,
            "updated_at": now
        },
        "$setOnInsert": {
            "created_at": now,
            "balance": 100000.0,
            "portfolio": [],
            "tradeHistory": [],
            "phone": "",
            "is_verified": email == "admin@ecowave.com",
            "is_trusted_seller": email == "admin@ecowave.com",
            "rating": 5.0,
            "sales_count": 0,
            "is_banned": False,
            "report_count": 0,
            "ban_reason": None,
            "cancellation_rate": 0.0,
        }
    }
    # Atomic operation for faster performance
    user = users_col.find_one_and_update(
        query,
        update,
        upsert=True,
        return_document=True
    )
    if user:
        user.pop("_id", None)
    return user

@app.route("/api/auth/google", methods=["GET"])
def auth_google():
    redirect_uri = url_for("auth_google_callback", _external=True)
    app.logger.info("auth_google redirect_uri: %s", redirect_uri)
    return google.authorize_redirect(redirect_uri)

@app.route("/api/reports", methods=["POST"])
@token_required
def submit_report(current_user):
    """Submit a report for a user or product"""
    try:
        data = request.get_json()
        target_id = data.get("target_id") # can be product_id or user_email
        target_type = data.get("target_type") # 'product' or 'user'
        reason = data.get("reason") # 'scam', 'fake', 'spam', etc.
        description = data.get("description", "")
        txn_id = data.get("txn_id")

        if not target_id or not target_type or not reason:
            return jsonify({"success": False, "error": "Missing required fields"}), 400

        # Prevent duplicate reports from the same user for the same target
        existing_report = reports_col.find_one({
            "reporter_email": current_user['email'],
            "target_id": target_id,
            "target_type": target_type,
            "status": "pending"
        })
        if existing_report:
            return jsonify({"success": False, "error": "You have already reported this. Our team is reviewing it."}), 400

        # Enforce: Only buyers can report sellers or products
        if target_type in ['user', 'product']:
            # Check if current_user has any transaction with this target (seller or specific product)
            query = {
                "buyer_email": current_user['email']
            }
            if txn_id:
                query["txn_id"] = txn_id

            if target_type == 'user':
                query["seller_email"] = target_id
            else:
                query["product_id"] = target_id

            has_transaction = transactions_col.find_one(query)
            if not has_transaction:
                return jsonify({"success": False, "error": "You can only report a seller or product after initiating a purchase."}), 403

        # Prevent self-reporting
        if target_type == 'user' and target_id == current_user['email']:
            return jsonify({"success": False, "error": "You cannot report yourself"}), 400

        report = {
            "report_id": str(uuid.uuid4()),
            "reporter_email": current_user['email'],
            "target_id": target_id,
            "target_type": target_type,
            "txn_id": txn_id,
            "reason": reason,
            "description": description,
            "status": "pending", # pending, validated, dismissed
            "created_at": datetime.utcnow()
        }

        reports_col.insert_one(report)
        return jsonify({"success": True, "message": "Report submitted for review"}), 201
    except Exception as e:
        app.logger.error(f"Error submitting report: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/admin/reports", methods=["GET"])
@token_required
def get_all_reports(current_user):
    """Admin: Get all pending reports"""
    if current_user['email'] != "admin@ecowave.com":
        return jsonify({"success": False, "error": "Unauthorized"}), 403
    try:
        reports = list(reports_col.find({"status": "pending"}, {"_id": 0}).sort("created_at", -1))
        return jsonify({"success": True, "reports": reports}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/admin/dismiss-report/<report_id>", methods=["POST"])
@token_required
def dismiss_report(current_user, report_id):
    """Admin: Dismiss a report"""
    if current_user['email'] != "admin@ecowave.com":
        return jsonify({"success": False, "error": "Unauthorized"}), 403
    try:
        reports_col.update_one({"report_id": report_id}, {"$set": {"status": "dismissed"}})
        return jsonify({"success": True, "message": "Report dismissed"}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/admin/validate-report/<report_id>", methods=["POST"])
@token_required
def validate_report(current_user, report_id):
    """Admin validates a report and applies punishment if necessary"""
    if current_user['email'] != "admin@ecowave.com":
        return jsonify({"success": False, "error": "Unauthorized"}), 403
    try:
        report = reports_col.find_one({"report_id": report_id})
        if not report:
            return jsonify({"success": False, "error": "Report not found"}), 404

        if report['status'] != 'pending':
            return jsonify({"success": False, "error": "Report already processed"}), 400

        reports_col.update_one({"report_id": report_id}, {"$set": {"status": "validated"}})

        target_email = None
        if report['target_type'] == 'user':
            target_email = report['target_id']
        elif report['target_type'] == 'product':
            product = products_col.find_one({"id": report['target_id']})
            if product:
                target_email = product.get('seller_email')
                # Optional: deactivate reported product
                products_col.update_one({"id": report['target_id']}, {"$set": {"status": "under_review"}})

        if target_email:
            user = users_col.find_one_and_update(
                {"email": target_email},
                {"$inc": {"report_count": 1}},
                return_document=True
            )

            if user:
                report_count = user.get('report_count', 0)
                if report_count >= 15:
                    users_col.update_one({"email": target_email}, {"$set": {"is_banned": True, "ban_reason": "Multiple community violations"}})
                elif report_count % 5 == 0 and report_count > 0:
                    users_col.update_one({"email": target_email}, {"$set": {"is_banned": True, "ban_reason": f"Temporary suspension due to {report_count} validated reports"}})

        return jsonify({"success": True, "message": "Report validated"}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/users/<email>", methods=["GET"])
def get_user_profile(email):
    """Get public profile of a user"""
    try:
        user = users_col.find_one({"email": email}, {"_id": 0, "token": 0, "balance": 0, "portfolio": 0, "tradeHistory": 0})
        if not user:
            return jsonify({"success": False, "error": "User not found"}), 404
        return jsonify({"success": True, "user": user}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


# --- Admin Extension Endpoints ---

@app.route("/api/admin/products", methods=["GET"])
@token_required
def admin_get_products(current_user):
    if current_user['email'] != "admin@ecowave.com":
        return jsonify({"success": False, "error": "Unauthorized"}), 403

    products = list(products_col.find({}, {"_id": 0}))
    # Add sales info for each product
    for p in products:
        p['is_sold'] = p.get('status') == 'sold'
        # Total revenue if we track multiple sales, but here it's 1-to-1
    return jsonify({"success": True, "products": products}), 200

@app.route("/api/admin/products/<product_id>/status", methods=["POST"])
@token_required
def admin_update_product_status(current_user, product_id):
    if current_user['email'] != "admin@ecowave.com":
        return jsonify({"success": False, "error": "Unauthorized"}), 403

    data = request.get_json()
    new_status = data.get("status") # 'active', 'banned', 'under_review'

    products_col.update_one({"id": product_id}, {"$set": {"status": new_status}})
    return jsonify({"success": True, "message": f"Product status updated to {new_status}"}), 200

@app.route("/api/admin/users", methods=["GET"])
@token_required
def admin_get_users(current_user):
    if current_user['email'] != "admin@ecowave.com":
        return jsonify({"success": False, "error": "Unauthorized"}), 403

    all_users = list(users_col.find({}, {"_id": 0}))

    # Ensure all users have required fields and are JSON serializable
    cleaned_users = []
    for u in all_users:
        user_data = {
            'email': str(u.get('email', '')),
            'name': str(u.get('name', u.get('username', 'User'))),
            'is_banned': bool(u.get('is_banned', False)),
            'report_count': int(u.get('report_count', 0)),
            'is_verified': bool(u.get('is_verified', False)),
            'phone': str(u.get('phone', '')),
            'rating': float(u.get('rating', 0.0)),
            'sales_count': int(u.get('sales_count', 0)),
            'created_at': str(u.get('created_at', ''))
        }
        cleaned_users.append(user_data)

    return jsonify({"success": True, "users": cleaned_users}), 200

@app.route("/api/admin/users/<email>/ban", methods=["POST"])
@token_required
def admin_ban_user(current_user, email):
    if current_user['email'] != "admin@ecowave.com":
        return jsonify({"success": False, "error": "Unauthorized"}), 403

    data = request.get_json()
    is_banned = data.get("is_banned", True)
    reason = data.get("reason", "Violated terms")

    users_col.update_one({"email": email}, {"$set": {
        "is_banned": is_banned,
        "ban_reason": reason if is_banned else None
    }})
    return jsonify({"success": True, "message": f"User {'banned' if is_banned else 'unbanned'}"}), 200

@app.route("/api/admin/users/<email>/verify", methods=["POST"])
@token_required
def admin_verify_user(current_user, email):
    if current_user['email'] != "admin@ecowave.com":
        return jsonify({"success": False, "error": "Unauthorized"}), 403

    data = request.get_json()
    is_verified = data.get("is_verified", True)

    users_col.update_one({"email": email}, {"$set": {"is_verified": is_verified}})
    return jsonify({"success": True, "message": f"User {'verified' if is_verified else 'unverified'}"}), 200

@app.route("/auth/google/callback", methods=["GET"])
def auth_google_callback():
    token = google.authorize_access_token()
    userinfo = google.get("https://www.googleapis.com/oauth2/v2/userinfo").json()
    email = userinfo.get("email")
    name = userinfo.get("name") or userinfo.get("given_name") or (email.split("@")[0] if email else None)
    if not email:
        return jsonify({"error": "No email returned"}), 400
    user = upsert_oauth_user(email=email, name=name, provider="google")
    jwt_token = create_jwt_for_user(user)
    redirect_url = FRONTEND_ORIGIN.rstrip("/") + "/auth-callback?token=" + urllib_parse.quote(jwt_token)
    return redirect(redirect_url)

@app.route("/api/auth/google", methods=["POST"])
def api_auth_google():
    """API login for mobile clients via Google ID token verification"""
    data = request.get_json()
    if not data:
        return jsonify({"success": False, "error": "Request body is required"}), 400

    id_token_str = data.get("id_token")
    google_client_id = os.getenv("GOOGLE_CLIENT_ID")

    email = None
    name = None

    # If ID token is provided, verify it server-side
    if id_token_str and GOOGLE_AUTH_AVAILABLE and google_client_id:
        try:
            idinfo = google_id_token.verify_oauth2_token(
                id_token_str,
                google_auth_requests.Request(),
                google_client_id
            )
            email = idinfo.get("email")
            name = idinfo.get("name") or idinfo.get("given_name") or (email.split("@")[0] if email else None)

            if not email:
                return jsonify({"success": False, "error": "No email in Google token"}), 400
            if not idinfo.get("email_verified"):
                return jsonify({"success": False, "error": "Google email not verified"}), 400
        except ValueError as e:
            app.logger.warning(f"Google ID token verification failed: {e}")
            # Try to provide a more helpful error message
            error_msg = str(e)
            if "Token used too early" in error_msg:
                return jsonify({"success": False, "error": "Google token used too early. Check server time."}), 401
            return jsonify({"success": False, "error": f"Invalid Google token: {error_msg}"}), 401
    else:
        # Fallback: accept email+name directly (for dev or when google-auth not installed)
        email = data.get("email")
        name = data.get("name", email.split("@")[0] if email else "")

        if not email:
            return jsonify({"success": False, "error": "Email or id_token is required"}), 400

        if not GOOGLE_AUTH_AVAILABLE:
            app.logger.warning("google-auth not installed; accepting unverified Google login")
        elif not google_client_id:
            app.logger.warning("GOOGLE_CLIENT_ID not set; accepting unverified Google login")

    # Securely upsert user (create if not exists)
    user = upsert_oauth_user(email=email, name=name, provider="google")

    jwt_token = create_jwt_for_user(user)

    return jsonify({
        "success": True,
        "token": jwt_token,
        "user": {
            "email": user["email"],
            "name": user.get("name", user.get("username", ""))
        }
    }), 200

@app.route("/api/auth/register", methods=["POST"])
def api_auth_register():
    """Email/Password registration"""
    try:
        data = request.get_json()
        email = (data.get("email") or "").strip().lower()
        username = data.get("username")
        password = data.get("password")
        confirm_password = data.get("confirm_password")

        if not all([email, username, password, confirm_password]):
            return jsonify({"success": False, "error": "Missing fields"}), 400

        if not validate_email(email):
            return jsonify({"success": False, "error": "Invalid email format"}), 400

        if len(password) < 6:
            return jsonify({"success": False, "error": "Password must be at least 6 characters"}), 400

        if password != confirm_password:
            return jsonify({"success": False, "error": "Passwords do not match"}), 400

        if email == "admin@ecowave.com":
            return jsonify({"success": False, "error": "This email address is reserved"}), 400

        existing_user = users_col.find_one({"email": email})
        if existing_user:
            return jsonify({"success": False, "error": "Email already registered"}), 400

        now = datetime.utcnow()
        user_id = username # Use username as user_id for new manual registrations
        user_doc = {
            "user_id": user_id,
            "email": email,
            "username": username,
            "name": username,
            "password": generate_password_hash(password),
            "provider": "email",
            "created_at": now,
            "updated_at": now,
            "balance": 100000.0,
            "phone": "",
            "is_verified": email == "admin@ecowave.com",
            "is_trusted_seller": email == "admin@ecowave.com",
            "rating": 5.0,
            "sales_count": 0,
            "is_banned": False,
            "report_count": 0,
            "ban_reason": None,
            "cancellation_rate": 0.0,
        }

        users_col.insert_one(user_doc)
        jwt_token = create_jwt_for_user(user_doc)

        return jsonify({
            "success": True,
            "token": jwt_token,
            "user": {
                "email": email,
                "name": username
            }
        }), 201
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/auth/login", methods=["POST"])
def api_auth_login():
    """Email/Password login"""
    data = request.get_json()
    email = (data.get("email") or "").strip().lower()
    password = data.get("password")

    if not email or not password:
        return jsonify({"success": False, "error": "Email and password are required"}), 400

    if not validate_email(email):
        return jsonify({"success": False, "error": "Invalid email format"}), 400
    
    user = users_col.find_one({"email": email})
    if not user:
        return jsonify({"success": False, "error": "Invalid email or password"}), 401
    
    # If user exists but has no password, they must have used OAuth.
    # We still allow them to login if they have a password.
    if user.get("provider") == "google" and not user.get("password"):
        return jsonify({"success": False, "error": "This account was created with Google. Please use 'Continue with Google' or reset your password to set one."}), 401

    if not check_password_hash(user["password"], password):
        return jsonify({"success": False, "error": "Invalid email or password"}), 401

    if not user.get("user_id"):
        user["user_id"] = user.get("username", user.get("name", email.split("@")[0]))
        users_col.update_one({"email": email}, {"$set": {"user_id": user["user_id"]}})

    jwt_token = create_jwt_for_user(user)
    
    return jsonify({
        "success": True,
        "token": jwt_token,
        "user": {
            "email": user["email"],
            "name": user.get("name", user.get("username", ""))
        }
    }), 200

# Email sending function
def send_inquiry_email(seller_email: str, product_title: str, buyer_name: str, buyer_email: str, buyer_message: str) -> bool:
    """Send email notification to seller about buyer inquiry"""
    if not SMTP_EMAIL or not SMTP_PASSWORD:
        app.logger.warning("SMTP credentials not configured, skipping email")
        return False
    
    try:
        msg = MIMEMultipart('alternative')
        msg['Subject'] = f"EcoWave: Inquiry about '{product_title}'"
        msg['From'] = SMTP_EMAIL
        msg['To'] = seller_email
        
        # Create email body
        html = f"""
        <html>
          <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
            <div style="max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f9f9f9;">
              <h2 style="color: #10b981;">New Inquiry on EcoWave! 🌊</h2>
              <p>Someone is interested in your listing: <strong>{product_title}</strong></p>
              
              <div style="background-color: white; padding: 20px; border-radius: 8px; margin: 20px 0;">
                <h3 style="margin-top: 0;">Buyer Details:</h3>
                <p><strong>Name:</strong> {buyer_name}</p>
                <p><strong>Email:</strong> <a href="mailto:{buyer_email}">{buyer_email}</a></p>
                
                <h3>Message:</h3>
                <p style="background-color: #f3f4f6; padding: 15px; border-radius: 4px;">{buyer_message}</p>
              </div>
              
              <p>You can reply directly to <a href="mailto:{buyer_email}">{buyer_email}</a> to connect with this buyer.</p>
              
              <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 30px 0;" />
              <p style="font-size: 12px; color: #6b7280;">This is an automated message from EcoWave Marketplace.</p>
            </div>
          </body>
        </html>
        """
        
        part = MIMEText(html, 'html')
        msg.attach(part)
        
        # Send email
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_EMAIL, SMTP_PASSWORD)
            server.send_message(msg)
        
        app.logger.info(f"Email sent successfully to {seller_email}")
        return True
    except Exception as e:
        app.logger.error(f"Failed to send email: {e}")
        return False

def send_chat_notification_email(recipient_email, sender_name, message_text, product_title):
    """Send an email notification about a new chat message"""
    if not SMTP_EMAIL or not SMTP_PASSWORD:
        return False

    try:
        msg = MIMEMultipart('alternative')
        msg['Subject'] = f"EcoWave: New message from {sender_name}"
        msg['From'] = SMTP_EMAIL
        msg['To'] = recipient_email

        html = f"""
        <html>
          <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333;">
            <div style="max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f9f9f9; border-radius: 10px;">
              <h2 style="color: #10b981;">New Chat Message! 💬</h2>
              <p><strong>{sender_name}</strong> sent you a message regarding <strong>{product_title}</strong>:</p>

              <div style="background-color: white; padding: 15px; border-radius: 8px; border-left: 4px solid #10b981; margin: 20px 0;">
                <p style="font-style: italic; margin: 0;">"{message_text}"</p>
              </div>

              <p>Open the EcoWave app to reply and continue the conversation.</p>

              <hr style="border: none; border-top: 1px solid #e5e7eb; margin: 30px 0;" />
              <p style="font-size: 12px; color: #6b7280;">EcoWave Marketplace - Better for the planet.</p>
            </div>
          </body>
        </html>
        """

        msg.attach(MIMEText(html, 'html'))

        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_EMAIL, SMTP_PASSWORD)
            server.send_message(msg)
        return True
    except Exception as e:
        app.logger.error(f"Failed to send chat notification email: {e}")
        return False

# Product API Endpoints
@app.route("/api/products", methods=["GET"])
def get_products():
    """Fetch all products from the database with optional filtering"""
    try:
        # Only show active products in the marketplace
        query = {"status": "active"}
        
        # Filter by Category
        category = request.args.get("category")
        if category and category != "all":
            query["category"] = category

        # Exclude seller's own products from marketplace
        exclude_seller = request.args.get("exclude_seller")
        if exclude_seller:
            query["seller_email"] = {"$ne": exclude_seller}
            
        # Filter by Search Text (title, description, AND category)
        search = request.args.get("search")
        if search:
            # Escape regex special chars to prevent ReDoS
            escaped_search = re.escape(search[:100])  # cap at 100 chars
            query["$or"] = [
                {"title": {"$regex": escaped_search, "$options": "i"}},
                {"description": {"$regex": escaped_search, "$options": "i"}},
                {"category": {"$regex": escaped_search, "$options": "i"}}
            ]

        products = list(products_col.find(query, {"_id": 0}).sort("created_at", -1))
        return jsonify({"success": True, "products": products}), 200
    except Exception as e:
        app.logger.error(f"Error fetching products: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/products/<product_id>", methods=["GET"])
def get_product(product_id):
    """Fetch a single product by ID"""
    try:
        product = products_col.find_one({"id": product_id}, {"_id": 0})
        if not product:
            return jsonify({"success": False, "error": "Product not found"}), 404
        return jsonify({"success": True, "product": product}), 200
    except Exception as e:
        app.logger.error(f"Error fetching product {product_id}: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/products", methods=["POST"])
@token_required
def create_product(current_user):
    """Create a new product listing with anti-scam checks"""
    try:
        if current_user.get('is_banned'):
            return jsonify({"success": False, "error": f"Your account is suspended: {current_user.get('ban_reason')}"}), 403

        data = request.get_json()
        
        # 1. Posting limits for new accounts
        now = datetime.utcnow()
        account_age = (now - current_user.get("created_at", now)).days
        if account_age < 1:
            # New accounts (less than 24h) can only post 2 items
            existing_count = products_col.count_documents({"seller_email": current_user['email']})
            if existing_count >= 2:
                return jsonify({"success": False, "error": "New accounts are limited to 2 listings in the first 24 hours to prevent spam."}), 400

        # 2. Duplicate listing detection (simple title/description check)
        duplicate = products_col.find_one({
            "seller_email": current_user['email'],
            "title": data['title'],
            "status": "active"
        })
        if duplicate:
            return jsonify({"success": False, "error": "You already have an active listing with this title."}), 400

        # Validate required fields
        required_fields = ["title", "description", "price", "badge", "image"]
        for field in required_fields:
            if field not in data or (isinstance(data[field], str) and not str(data[field]).strip()):
                return jsonify({"success": False, "error": f"Missing or empty field: {field}"}), 400

        try:
            price_val = float(data["price"])
        except (TypeError, ValueError):
            return jsonify({"success": False, "error": "Price must be a valid number"}), 400
        if price_val <= 0:
            return jsonify({"success": False, "error": "Price must be greater than 0"}), 400

        product_id = str(uuid.uuid4())
        
        product = {
            "id": product_id,
            "title": data["title"],
            "description": data["description"],
            "price": float(data["price"]),
            "badge": data["badge"],
            "image": data["image"],
            "category": data.get("category"),
            "material": data.get("material", ""),
            "eco_impact": calculate_impact(data.get("category", "other"), data.get("material")),
            "seller_id": current_user.get("name", "anonymous"),
            "seller_email": current_user['email'],
            "seller_location": data.get("seller_location", ""),
            "location": data.get("location"),
            "seller_phone": current_user.get("phone", ""),
            "seller_upi_id": data.get("seller_upi_id", ""),
            "created_at": datetime.utcnow(),
            "status": "active"
        }
        
        products_col.insert_one(product)
        product.pop("_id", None)
        
        return jsonify({"success": True, "product": product}), 201
    except Exception as e:
        app.logger.error(f"Error creating product: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/inquiries", methods=["POST"])
def create_inquiry():
    """Handle buyer inquiry about a product"""
    try:
        data = request.get_json()
        
        # Validate required fields
        required_fields = ["product_id", "buyer_name", "buyer_email", "buyer_message"]
        for field in required_fields:
            if field not in data:
                return jsonify({"success": False, "error": f"Missing field: {field}"}), 400
        
        # Get product details
        product = products_col.find_one({"id": data["product_id"]}, {"_id": 0})
        if not product:
            return jsonify({"success": False, "error": "Product not found"}), 404
        
        if not product.get("seller_email"):
            return jsonify({"success": False, "error": "Seller contact information not available"}), 400
        
        # Create inquiry record
        inquiry_id = str(uuid.uuid4())
        inquiry = {
            "inquiry_id": inquiry_id,
            "product_id": data["product_id"],
            "product_title": product["title"],
            "buyer_name": data["buyer_name"],
            "buyer_email": data["buyer_email"],
            "buyer_message": data["buyer_message"],
            "seller_email": product["seller_email"],
            "status": "sent",
            "created_at": datetime.utcnow()
        }
        
        # Save to database
        inquiries_col.insert_one(inquiry)
        
        # Send email to seller
        email_sent = send_inquiry_email(
            seller_email=product["seller_email"],
            product_title=product["title"],
            buyer_name=data["buyer_name"],
            buyer_email=data["buyer_email"],
            buyer_message=data["buyer_message"]
        )
        
        inquiry.pop("_id", None)  # Remove MongoDB _id from response
        
        return jsonify({
            "success": True,
            "inquiry": inquiry,
            "email_sent": email_sent
        }), 201
    except Exception as e:
        app.logger.error(f"Error creating inquiry: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/seller/inquiries", methods=["GET"])
@token_required
def get_seller_inquiries(current_user):
    """Fetch all inquiries for products owned by the logged-in seller"""
    try:
        inquiries = list(inquiries_col.find({"seller_email": current_user['email']}, {"_id": 0}).sort("created_at", -1))
        return jsonify({"success": True, "inquiries": inquiries}), 200
    except Exception as e:
        app.logger.error(f"Error fetching seller inquiries: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/products/purchased", methods=["GET"])
@token_required
def get_purchased_products(current_user):
    """Fetch all products purchased by the logged-in user"""
    try:
        # Include both 'sold' and 'reserved' (items currently in the 30/20/50 payment flow)
        products = list(products_col.find(
            {"buyer_email": current_user['email'], "status": {"$in": ["sold", "reserved"]}},
            {"_id": 0}
        ).sort("created_at", -1))

        # Ensure every product has a txn_id for the bill (fallback for older records)
        for p in products:
            if not p.get("txn_id"):
                txn = transactions_col.find_one({
                    "product_id": p.get("id"),
                    "buyer_email": current_user['email'],
                    "status": "completed"
                })
                if txn:
                    p["txn_id"] = txn["txn_id"]
                    products_col.update_one({"id": p["id"]}, {"$set": {"txn_id": txn["txn_id"]}})

        return jsonify({"success": True, "products": products}), 200
    except Exception as e:
        app.logger.error(f"Error fetching purchased products: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/reviews", methods=["POST"])
@token_required
def create_review(current_user):
    """Submit a review for a seller (restricted to buyers)"""
    try:
        data = request.get_json()
        product_id = data.get("product_id")
        rating = data.get("rating")
        comment = data.get("comment", "")

        if not product_id or rating is None:
            return jsonify({"success": False, "error": "Product ID and rating are required"}), 400

        try:
            rating_val = float(rating)
            if not (1.0 <= rating_val <= 5.0):
                raise ValueError
        except (TypeError, ValueError):
            return jsonify({"success": False, "error": "Rating must be a number between 1 and 5"}), 400

        # Verify purchase
        product = products_col.find_one({
            "id": product_id,
            "buyer_email": current_user['email'],
            "status": {"$in": ["sold", "reserved"]}
        })
        if not product:
            return jsonify({"success": False, "error": "You can only review items you have purchased."}), 403

        seller_email = product.get("seller_email")

        # Check if already reviewed
        existing = reviews_col.find_one({"product_id": product_id, "reviewer_email": current_user['email']})
        if existing:
            return jsonify({"success": False, "error": "You have already reviewed this purchase."}), 400

        review = {
            "id": str(uuid.uuid4()),
            "product_id": product_id,
            "product_title": product.get("title"),
            "seller_email": seller_email,
            "reviewer_email": current_user['email'],
            "reviewer_name": current_user.get('name', 'Eco User'),
            "rating": float(rating),
            "comment": comment,
            "created_at": datetime.utcnow()
        }

        reviews_col.insert_one(review)

        # Update seller's average rating
        all_reviews = list(reviews_col.find({"seller_email": seller_email}))
        avg_rating = sum(r['rating'] for r in all_reviews) / len(all_reviews)
        users_col.update_one({"email": seller_email}, {"$set": {"rating": avg_rating}})

        review.pop("_id", None)
        return jsonify({"success": True, "review": review}), 201
    except Exception as e:
        app.logger.error(f"Error creating review: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/reviews/seller/<email>", methods=["GET"])
def get_seller_reviews(email):
    """Get all reviews for a specific seller"""
    try:
        reviews = list(reviews_col.find({"seller_email": email}, {"_id": 0}).sort("created_at", -1))
        return jsonify({"success": True, "reviews": reviews}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/products/seller/<email>", methods=["GET"])
def get_products_by_seller(email):
    """Fetch all products by seller email with buyer info for reserved/sold items"""
    try:
        products = list(products_col.find({"seller_email": email}, {"_id": 0}).sort("created_at", -1))

        # Enrich with buyer email if transaction exists
        for p in products:
            if p.get("status") in ["reserved", "sold"]:
                txn = transactions_col.find_one({"product_id": p["id"]}, {"_id": 0, "buyer_email": 1})
                if txn:
                    p["buyer_email"] = txn.get("buyer_email")

        return jsonify({"success": True, "products": products}), 200
    except Exception as e:
        app.logger.error(f"Error fetching seller products: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/products/<product_id>", methods=["PUT"])
@token_required
def update_product(current_user, product_id):
    """Update an existing product (only by the owner or admin)"""
    try:
        data = request.get_json()
        
        # Get existing product
        existing_product = products_col.find_one({"id": product_id}, {"_id": 0})
        if not existing_product:
            return jsonify({"success": False, "error": "Product not found"}), 404

        # Verify ownership
        if existing_product.get("seller_email") != current_user["email"] and current_user.get("email") != "admin@ecowave.com":
            return jsonify({"success": False, "error": "Unauthorized to update this listing"}), 403
        
        # Prepare update data (do NOT allow changing seller_email)
        update_data = {
            "title": data.get("title", existing_product["title"]),
            "description": data.get("description", existing_product["description"]),
            "price": float(data.get("price", existing_product["price"])),
            "badge": data.get("badge", existing_product["badge"]),
            "image": data.get("image", existing_product["image"]),
            "category": data.get("category", existing_product.get("category")),
            "seller_location": data.get("seller_location", existing_product.get("seller_location", "")),
            "seller_phone": data.get("seller_phone", existing_product.get("seller_phone", "")),
            "updated_at": datetime.utcnow()
        }
        
        # Update product
        products_col.update_one({"id": product_id}, {"$set": update_data})
        
        # Get updated product
        updated_product = products_col.find_one({"id": product_id}, {"_id": 0})
        
        return jsonify({"success": True, "product": updated_product}), 200
    except Exception as e:
        app.logger.error(f"Error updating product {product_id}: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/products/<product_id>", methods=["DELETE"])
@token_required
def delete_product(current_user, product_id):
    """Delete a product listing (only by the owner or admin)"""
    try:
        # Check if product exists
        product = products_col.find_one({"id": product_id})
        if not product:
            return jsonify({"success": False, "error": "Product not found"}), 404
        
        # Verify ownership
        if product.get("seller_email") != current_user["email"] and current_user.get("email") != "admin@ecowave.com":
            return jsonify({"success": False, "error": "Unauthorized to delete this listing"}), 403

        # Block deletion if an active transaction exists
        active_txn = transactions_col.find_one({
            "product_id": product_id,
            "status": {"$in": ["initiated", "pending_shipping", "awaiting_delivery", "final_paid", "shipped"]}
        })
        if active_txn:
            return jsonify({"success": False, "error": "Cannot delete a listing with an active transaction in progress"}), 400

        # Delete product
        products_col.delete_one({"id": product_id})
        
        return jsonify({"success": True, "message": "Product deleted successfully"}), 200
    except Exception as e:
        app.logger.error(f"Error deleting product {product_id}: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/user/impact", methods=["GET"])
@token_required
def get_user_impact(current_user):
    """Get impact stats for the logged-in user"""
    try:
        impact_stats = current_user.get("impact_stats", {
            "co2_saved": 0.0,
            "water_saved": 0.0,
            "waste_saved": 0.0,
            "items_recycled": 0,
            "items_purchased": 0
        })
        return jsonify({"success": True, "impact": impact_stats}), 200
    except Exception as e:
        app.logger.error(f"Error fetching user impact: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

# UPI Payment Endpoints
@app.route("/api/payments/create-transaction", methods=["POST"])
@token_required
def create_transaction(current_user):
    """Record a new UPI transaction when buyer initiates payment.
    Uses atomic find_one_and_update to prevent race conditions."""
    try:
        data = request.get_json()
        product_id = data.get("product_id", "")

        # Atomic lock: only lock if product is currently 'active'
        # This prevents two buyers from purchasing the same item simultaneously
        now = datetime.utcnow()
        product = products_col.find_one_and_update(
            {"id": product_id, "status": "active"},
            {"$set": {
                "status": "locked",
                "locked_by": current_user['email'],
                "locked_at": now
            }},
            return_document=False  # Return the original (pre-update) document
        )

        if not product:
            # Check if it exists at all to give a better error message
            existing = products_col.find_one({"id": product_id})
            if not existing:
                return jsonify({"success": False, "error": "Product not found"}), 404
            if existing.get("status") in ("locked", "reserved", "sold"):
                return jsonify({"success": False, "error": "This item is no longer available. Another buyer may have claimed it."}), 409
            return jsonify({"success": False, "error": "This item is not available for purchase"}), 400

        # Prevent seller from buying their own product
        if product.get("seller_email") == current_user['email']:
            # Undo the lock
            products_col.update_one({"id": product_id}, {"$set": {"status": "active"}, "$unset": {"locked_by": "", "locked_at": ""}})
            return jsonify({"success": False, "error": "You cannot purchase your own listing"}), 400

        txn_id = f"txn_{str(uuid.uuid4())[:12]}"
        
        # Security: Use the price from the product record
        actual_price = float(product.get("price", 0))

        # Shipping Charge Logic: 3% of item price
        # 1% goes to seller for shipping aid, 2% to NGO for carbon offset
        shipping_charge = round(actual_price * 0.03, 2)
        seller_shipping_aid = round(actual_price * 0.01, 2)
        ngo_contribution = round(actual_price * 0.02, 2)

        total_with_shipping = actual_price + shipping_charge

        # Calculate staged amounts based on total including shipping
        advance_amount = round(total_with_shipping * 0.30, 2)

        transaction = {
            "txn_id": txn_id,
            "product_id": product_id,
            "buyer_email": current_user['email'],
            "seller_email": product.get("seller_email"),
            "seller_upi_id": product.get("seller_upi_id", ""),
            "item_price": actual_price,
            "shipping_charge": shipping_charge,
            "seller_shipping_aid": seller_shipping_aid,
            "ngo_contribution": ngo_contribution,
            "total_amount": total_with_shipping,
            "paid_amount": 0,
            "current_stage": "advance", # advance (30%), shipping (20%), final (50%)
            "stage_amount": advance_amount,
            "status": "initiated",
            "created_at": now,
            "product_snapshot": {
                "title": product.get("title"),
                "price": product.get("price"),
                "seller_email": product.get("seller_email"),
                "category": product.get("category"),
                "image": product.get("image")
            }
        }
        
        transactions_col.insert_one(transaction)
        transaction.pop("_id", None)
        
        return jsonify({"success": True, "transaction": transaction}), 201
    except Exception as e:
        # On any error, release the lock if we acquired it
        try:
            products_col.update_one(
                {"id": product_id, "locked_by": current_user['email']},
                {"$set": {"status": "active"}, "$unset": {"locked_by": "", "locked_at": ""}}
            )
        except Exception:
            pass
        app.logger.error(f"Error creating transaction: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/payments/confirm", methods=["POST"])
@token_required
def confirm_payment(current_user):
    """Buyer confirms that UPI payment was completed"""
    try:
        data = request.get_json()
        txn_id = data.get("txn_id", "")
        product_id = data.get("product_id", "")
        buyer_email = current_user['email']
        
        # SECURITY: Verify the transaction exists and belongs to this buyer/product
        # This prevents "transaction hijacking" where a user confirms a fake txn_id.
        txn = transactions_col.find_one({
            "txn_id": txn_id,
            "product_id": product_id,
            "buyer_email": buyer_email
        })
        if not txn:
            return jsonify({"success": False, "error": "Invalid transaction record"}), 400

        # Update transaction stage and paid amount
        new_paid_amount = txn.get("paid_amount", 0) + txn.get("stage_amount", 0)
        current_stage = txn.get("current_stage")

        next_stage = None
        next_amount = 0

        if current_stage == "advance":
            next_stage = "shipping"
            next_amount = round(txn["total_amount"] * 0.20, 2)
            status = "pending_shipping"
        elif current_stage == "shipping":
            next_stage = "final"
            next_amount = round(txn["total_amount"] * 0.50, 2)
            status = "awaiting_delivery"
        elif current_stage == "final":
            next_stage = "received_confirmation_pending"
            next_amount = 0
            status = "final_paid"
        else:
            next_stage = "completed"
            next_amount = 0
            status = "completed"

        transactions_col.update_one(
            {"txn_id": txn_id},
            {"$set": {
                "status": status,
                "paid_amount": new_paid_amount,
                "current_stage": next_stage,
                "stage_amount": next_amount,
                "completed_at": None # Payment is staged, not completed yet
            }}
        )
        
        # Mark product status
        # Product remains 'reserved' until buyer confirms delivery
        product_status = "reserved"
        products_col.update_one(
            {"id": product_id},
            {"$set": {
                "status": product_status,
                "buyer_email": buyer_email,
                "txn_id": txn_id
            }}
        )

        return jsonify({"success": True, "message": f"Stage {current_stage} payment recorded!"}), 200
    except Exception as e:
        app.logger.error(f"Error confirming payment: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/seller/disputes", methods=["GET"])
@token_required
def get_seller_disputes(current_user):
    """Get disputes for the seller to answer"""
    try:
        user = users_col.find_one({"email": current_user['email']}, {"seller_disputes": 1})
        disputes = user.get("seller_disputes", []) if user else []
        return jsonify({"success": True, "disputes": disputes}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/seller/disputes/respond", methods=["POST"])
@token_required
def respond_to_dispute(current_user):
    """Seller provides explanation for a dispute"""
    try:
        data = request.get_json()
        txn_id = data.get("txn_id")
        explanation = data.get("explanation")

        users_col.update_one(
            {"email": current_user['email'], "seller_disputes.txn_id": txn_id},
            {"$set": {
                "seller_disputes.$.explanation": explanation,
                "seller_disputes.$.status": "responded",
                "seller_disputes.$.responded_at": datetime.utcnow()
            }}
        )
        return jsonify({"success": True, "message": "Response submitted to admin for review."}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/payments/confirm-delivery", methods=["POST"])
@token_required
def confirm_delivery(current_user):
    """Buyer confirms they received the product. This releases funds (logic-wise) and completes sale."""
    try:
        data = request.get_json()
        txn_id = data.get("txn_id")

        txn = transactions_col.find_one({"txn_id": txn_id, "buyer_email": current_user['email']})
        if not txn:
            return jsonify({"success": False, "error": "Transaction not found"}), 404

        if txn.get("current_stage") != "received_confirmation_pending":
            return jsonify({"success": False, "error": "All payment stages must be completed before confirming delivery."}), 400

        # Update transaction to completed
        transactions_col.update_one(
            {"txn_id": txn_id},
            {"$set": {
                "status": "completed",
                "current_stage": "completed",
                "completed_at": datetime.utcnow()
            }}
        )

        # Mark product as sold
        product_id = txn.get("product_id")
        products_col.update_one(
            {"id": product_id},
            {"$set": {"status": "sold"}}
        )

        # Credit Eco Impact
        product = products_col.find_one({"id": product_id})
        impact = product.get("eco_impact", {}) if product else {}

        seller_email = product.get("seller_email") if product else None
        buyer_email_del = txn.get("buyer_email")

        # Update seller impact_stats and sales_count
        if seller_email:
            users_col.update_one(
                {"email": seller_email},
                {
                    "$inc": {
                        "sales_count": 1,
                        "impact_stats.items_recycled": 1,
                        "impact_stats.co2_saved": impact.get("co2", 0),
                        "impact_stats.water_saved": impact.get("water", 0),
                        "impact_stats.waste_saved": impact.get("waste", 0)
                    }
                }
            )

        # Update buyer impact_stats
        if buyer_email_del:
            users_col.update_one(
                {"email": buyer_email_del},
                {
                    "$inc": {
                        "impact_stats.items_purchased": 1,
                        "impact_stats.co2_saved": impact.get("co2", 0),
                        "impact_stats.water_saved": impact.get("water", 0),
                        "impact_stats.waste_saved": impact.get("waste", 0)
                    }
                }
            )

        return jsonify({"success": True, "message": "Delivery confirmed! Funds released to seller."}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/payments/dispute", methods=["POST"])
@token_required
def dispute_transaction(current_user):
    """Buyer requests a refund if product not received or issue occurred"""
    try:
        data = request.get_json()
        txn_id = data.get("txn_id")
        reason = data.get("reason")

        txn = transactions_col.find_one({"txn_id": txn_id, "buyer_email": current_user['email']})
        if not txn:
            return jsonify({"success": False, "error": "Transaction not found"}), 404

        transactions_col.update_one(
            {"txn_id": txn_id},
            {"$set": {
                "status": "disputed",
                "dispute_reason": reason,
                "disputed_at": datetime.utcnow()
            }}
        )

        # Return product to marketplace as active
        products_col.update_one(
            {"id": txn.get("product_id")},
            {"$set": {"status": "active"}, "$unset": {"buyer_email": "", "txn_id": ""}}
        )

        # Add to seller's "To Answer" list for their dashboard
        seller_email = txn.get("seller_email")
        users_col.update_one(
            {"email": seller_email},
            {"$push": {"seller_disputes": {
                "txn_id": txn_id,
                "product_id": txn.get("product_id"),
                "buyer_email": current_user['email'],
                "reason": reason,
                "status": "pending_explanation"
            }}}
        )

        return jsonify({"success": True, "message": "Dispute raised. Refund processing initiated."}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/payments/bill/<txn_id>", methods=["GET"])
@token_required
def get_bill(current_user, txn_id):
    """Fetch the generated bill for a transaction"""
    try:
        txn = transactions_col.find_one({"txn_id": txn_id}, {"_id": 0})
        if not txn:
            return jsonify({"success": False, "error": "Transaction not found"}), 404

        # Only buyer or seller or admin can see the bill
        seller_email = txn.get('product_snapshot', {}).get('seller_email') or txn.get('seller_email')
        if current_user['email'] not in [txn['buyer_email'], seller_email] and current_user['email'] != "admin@ecowave.com":
            return jsonify({"success": False, "error": "Unauthorized"}), 403

        return jsonify({"success": True, "bill": txn}), 200
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

# Chat Socket Events
def _verify_socket_token():
    """Extract and verify JWT from socket query string. Returns email or None."""
    token = request.args.get('token')
    if not token:
        return None
    try:
        secret = app.secret_key
        if isinstance(secret, bytes):
            secret = secret.decode('utf-8')
        data = jwt.decode(token, secret, algorithms=["HS256"], leeway=300)
        return data.get('email')
    except Exception:
        return None

@socketio.on('join')
def on_join(data):
    authenticated_email = _verify_socket_token()
    if not authenticated_email:
        emit('error', {'message': 'Authentication required to join chat'})
        return
    room = data['room']
    join_room(room)
    # Fetch previous messages
    messages = list(messages_col.find({"room": room}, {"_id": 0}).sort("created_at", 1))
    emit('history', messages)

@socketio.on('message')
def handle_message(data):
    authenticated_email = _verify_socket_token()
    if not authenticated_email:
        return  # Silently drop unauthenticated messages

    room = data['room']
    sender_email = data['sender']

    # Verify sender matches authenticated user
    if sender_email != authenticated_email:
        emit('error', {'message': 'Sender identity mismatch'})
        return

    text = data['text']
    msg_id = data.get('msg_id', str(uuid.uuid4()))  # Client-generated or fallback

    msg = {
        "room": room,
        "sender": sender_email,
        "text": text,
        "msg_id": msg_id,
        "created_at": datetime.utcnow().isoformat()
    }
    messages_col.insert_one(msg.copy())
    msg.pop("_id", None)
    emit('message', msg, room=room)

    # Send email notification to the other party
    try:
        # room format: productID_buyerEmail — split at first underscore only
        underscore_idx = room.find('_')
        if underscore_idx > 0:
            product_id = room[:underscore_idx]
            buyer_email = room[underscore_idx + 1:]

            product = products_col.find_one({"id": product_id})
            if product:
                seller_email = product.get('seller_email')
                product_title = product.get('title', 'Product')

                # Determine recipient (if sender is buyer, recipient is seller, and vice versa)
                recipient_email = seller_email if sender_email == buyer_email else buyer_email

                msg_count = messages_col.count_documents({"room": room})
                if msg_count <= 2:
                    # New conversation, definitely send
                    send_chat_notification_email(recipient_email, sender_email, text, product_title)
    except Exception as e:
        app.logger.error(f"Error in chat email notification: {e}")

@app.route("/api/chat/conversations", methods=["GET"])
@token_required
def get_conversations(current_user):
    """Return all chat conversations the current user participates in."""
    try:
        email = current_user['email']

        # Rooms where user sent at least one message
        sender_rooms = set(messages_col.distinct("room", {"sender": email}))

        # Rooms where user is the buyer (room format: productId_buyerEmail)
        buyer_rooms = set(messages_col.distinct(
            "room", {"room": {"$regex": f"_{re.escape(email)}$"}}
        ))

        all_rooms = sender_rooms | buyer_rooms

        conversations = []
        for room in all_rooms:
            last_msg = messages_col.find_one(
                {"room": room},
                {"_id": 0, "text": 1, "sender": 1, "created_at": 1},
                sort=[("created_at", -1)]
            )
            if not last_msg:
                continue

            underscore_idx = room.find('_')
            if underscore_idx <= 0:
                continue
            product_id = room[:underscore_idx]
            buyer_email = room[underscore_idx + 1:]

            product = products_col.find_one(
                {"id": product_id},
                {"_id": 0, "title": 1, "image": 1, "seller_email": 1}
            )
            if not product:
                continue

            seller_email = product.get("seller_email", "")
            is_seller = (seller_email == email)
            other_party = buyer_email if is_seller else seller_email

            conversations.append({
                "room": room,
                "product_id": product_id,
                "product_title": product.get("title", "Unknown"),
                "product_image": product.get("image", ""),
                "seller_email": seller_email,
                "buyer_email": buyer_email,
                "other_party": other_party,
                "is_seller": is_seller,
                "last_message": last_msg.get("text", ""),
                "last_message_sender": last_msg.get("sender", ""),
                "last_message_at": str(last_msg.get("created_at", ""))
            })

        conversations.sort(key=lambda x: x.get("last_message_at", ""), reverse=True)
        return jsonify({"success": True, "conversations": conversations}), 200
    except Exception as e:
        app.logger.error(f"Error fetching conversations: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/seller/mark-shipped", methods=["POST"])
@token_required
def mark_as_shipped(current_user):
    """Seller marks the item as shipped, which allows the buyer to pay the shipping stage (20%)."""
    try:
        data = request.get_json()
        txn_id = data.get("txn_id")

        if not txn_id:
            return jsonify({"success": False, "error": "txn_id is required"}), 400

        txn = transactions_col.find_one({"txn_id": txn_id, "seller_email": current_user['email']})
        if not txn:
            # Try finding by product if txn_id was actually a product_id (common mistake)
            txn = transactions_col.find_one({"product_id": txn_id, "seller_email": current_user['email']})
            if not txn:
                return jsonify({"success": False, "error": "Transaction not found or unauthorized"}), 404
            txn_id = txn["txn_id"]

        # Allow shipping if advance is paid
        if txn.get("current_stage") != "shipping":
            return jsonify({"success": False, "error": f"Current stage is {txn.get('current_stage')}, expected 'shipping'"}), 400

        # Update transaction status
        transactions_col.update_one(
            {"txn_id": txn_id},
            {"$set": {
                "shipped": True,
                "shipping_date": datetime.utcnow().isoformat(),
                "status": "shipped",
                "shipped_at": datetime.utcnow()
            }}
        )

        # IMPORTANT: Also update the product status to reflect it's been shipped
        products_col.update_one(
            {"id": txn["product_id"]},
            {"$set": {"status": "shipped"}}
        )

        return jsonify({"success": True, "message": "Item marked as shipped. Buyer can now pay the shipping stage (20%)."}), 200
    except Exception as e:
        app.logger.error(f"Error in mark_as_shipped: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

if __name__ == "__main__":
    # Python 3.13 + eventlet is unstable. Using standard Flask runner.
    app.run(host="0.0.0.0", port=PORT, debug=False)
