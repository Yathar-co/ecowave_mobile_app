import os
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
from pymongo import MongoClient, ASCENDING
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
import razorpay

load_dotenv()

MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://localhost:27017/")
JWT_SECRET = os.getenv("SECRET_KEY", "dev_jwt_secret")
JWT_EXP_SECONDS = int(os.getenv("JWT_EXP_SECONDS", 86400))
FRONTEND_ORIGIN = os.getenv("FRONTEND_ORIGIN", "http://localhost:52358")
PORT = int(os.getenv("PORT", 5001))

# Razorpay Configuration
RAZORPAY_KEY_ID = os.getenv("RAZORPAY_KEY_ID", "")
RAZORPAY_KEY_SECRET = os.getenv("RAZORPAY_KEY_SECRET", "")
razorpay_client = razorpay.Client(auth=(RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET))

# SMTP Configuration
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
products_col.create_index([("created_at", ASCENDING)])
inquiries_col.create_index([("created_at", ASCENDING)])
messages_col.create_index([("room", ASCENDING), ("created_at", ASCENDING)])

# Impact Metrics Constants
IMPACT_METRICS = {
    "electronics": {"co2": 50.0, "water": 100.0, "waste": 1.5},
    "clothing": {"co2": 15.0, "water": 2000.0, "waste": 0.5},
    "books": {"co2": 2.0, "water": 20.0, "waste": 0.5},
    "home": {"co2": 25.0, "water": 50.0, "waste": 10.0},
    "accessories": {"co2": 5.0, "water": 10.0, "waste": 0.2},
    "other": {"co2": 10.0, "water": 30.0, "waste": 1.0}
}

def calculate_impact(category, material=None):
    """Calculate eco impact based on category and material"""
    base = IMPACT_METRICS.get(category.lower(), IMPACT_METRICS["other"])
    return base

def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None
        auth_header = request.headers.get('Authorization')
        
        if auth_header:
            try:
                token = auth_header.split(" ")[1]
            except IndexError:
                return jsonify({'message': 'Token is missing!'}), 401
        
        if not token:
            return jsonify({'message': 'Token is missing!'}), 401
            
        try:
            data = jwt.decode(token, app.secret_key, algorithms=["HS256"])
            current_user = users_col.find_one({"email": data['email']})
            if not current_user:
                return jsonify({'message': 'User not found!'}), 401
        except Exception as e:
            return jsonify({'message': 'Token is invalid!', 'error': str(e)}), 401
            
        return f(current_user, *args, **kwargs)
    
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
    update = {
        "$set": {
            "username": name,
            "email": email,
            "name": name,
            "provider": provider,
            "updated_at": now
        },
        "$setOnInsert": {
            "created_at": now,
            "balance": 100000.0,
            "portfolio": [],
            "tradeHistory": []
        }

    }
    users_col.update_one(query, update, upsert=True)
    user = users_col.find_one(query)
    if user:
        user["user_id"] = user.get("username")
        user.pop("_id", None)
    return user

@app.route("/auth/google", methods=["GET"])
def auth_google():
    redirect_uri = url_for("auth_google_callback", _external=True)
    app.logger.info("auth_google redirect_uri: %s", redirect_uri)
    return google.authorize_redirect(redirect_uri)

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

@app.route("/api/auth/login", methods=["POST"])
def api_auth_login():
    """Simple API login for mobile clients to get a JWT token"""
    data = request.get_json()
    if not data or not data.get("email"):
        return jsonify({"success": False, "error": "Email is required"}), 400
    
    email = data["email"]
    name = data.get("name", email.split("@")[0])
    
    user = upsert_oauth_user(email=email, name=name, provider="mobile_app")
    jwt_token = create_jwt_for_user(user)
    
    return jsonify({
        "success": True,
        "token": jwt_token,
        "user": {
            "email": user["email"],
            "name": user.get("name", "")
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
        query = {}
        
        # Filter by Category
        category = request.args.get("category")
        if category and category != "all":
            query["category"] = category
            
        # Filter by Search Text
        search = request.args.get("search")
        if search:
            query["$or"] = [
                {"title": {"$regex": search, "$options": "i"}},
                {"description": {"$regex": search, "$options": "i"}}
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
def create_product():
    """Create a new product listing"""
    try:
        data = request.get_json()
        
        # Validate required fields
        required_fields = ["title", "description", "price", "badge", "image"]
        for field in required_fields:
            if field not in data:
                return jsonify({"success": False, "error": f"Missing field: {field}"}), 400
        
        # Generate unique ID
        import uuid
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
            "seller_id": data.get("seller_id", "anonymous"),
            "seller_email": data.get("seller_email", ""),
            "seller_location": data.get("seller_location", ""),
            "location": data.get("location"), # {lat: float, lng: float}
            "seller_phone": data.get("seller_phone", ""),
            "created_at": datetime.utcnow(),
            "status": "active"
        }
        
        products_col.insert_one(product)
        product.pop("_id", None)  # Remove MongoDB _id from response
        
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

@app.route("/api/products/seller/<email>", methods=["GET"])
def get_products_by_seller(email):
    """Fetch all products by seller email"""
    try:
        products = list(products_col.find({"seller_email": email}, {"_id": 0}).sort("created_at", -1))
        return jsonify({"success": True, "products": products}), 200
    except Exception as e:
        app.logger.error(f"Error fetching seller products: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/products/<product_id>", methods=["PUT"])
def update_product(product_id):
    """Update an existing product"""
    try:
        data = request.get_json()
        
        # Get existing product
        existing_product = products_col.find_one({"id": product_id}, {"_id": 0})
        if not existing_product:
            return jsonify({"success": False, "error": "Product not found"}), 404
        
        # Prepare update data
        update_data = {
            "title": data.get("title", existing_product["title"]),
            "description": data.get("description", existing_product["description"]),
            "price": float(data.get("price", existing_product["price"])),
            "badge": data.get("badge", existing_product["badge"]),
            "image": data.get("image", existing_product["image"]),
            "category": data.get("category", existing_product.get("category")),
            "seller_email": data.get("seller_email", existing_product.get("seller_email", "")),
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
def delete_product(product_id):
    """Delete a product"""
    try:
        # Check if product exists
        product = products_col.find_one({"id": product_id}, {"_id": 0})
        if not product:
            return jsonify({"success": False, "error": "Product not found"}), 404
        
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

@app.route("/api/products/<product_id>/sold", methods=["POST"])
@token_required
def mark_product_sold(current_user, product_id):
    """Mark a product as sold and credit impact to buyer/seller"""
    try:
        data = request.get_json()
        buyer_email = data.get("buyer_email")
        
        product = products_col.find_one({"id": product_id})
        if not product:
            return jsonify({"success": False, "error": "Product not found"}), 404
            
        # Verify ownership
        if product.get("seller_email") != current_user["email"]:
            return jsonify({"success": False, "error": "Unauthorized"}), 403
            
        if product.get("status") == "sold":
             return jsonify({"success": False, "error": "Product already sold"}), 400

        # Update product status
        products_col.update_one({"id": product_id}, {"$set": {"status": "sold", "buyer_email": buyer_email}})
        
        # Credit Impact
        impact = product.get("eco_impact", {})
        co2 = impact.get("co2", 0)
        water = impact.get("water", 0)
        waste = impact.get("waste", 0)
        
        # Update Seller Stats
        users_col.update_one(
            {"email": current_user["email"]},
            {"$inc": {
                "impact_stats.co2_saved": co2,
                "impact_stats.water_saved": water,
                "impact_stats.waste_saved": waste,
                "impact_stats.items_recycled": 1
            }}
        )
        
        # Update Buyer Stats if email provided
        if buyer_email:
            users_col.update_one(
                {"email": buyer_email},
                {"$inc": {
                    "impact_stats.co2_saved": co2,
                    "impact_stats.water_saved": water,
                    "impact_stats.waste_saved": waste,
                    "impact_stats.items_purchased": 1
                }}
            )
            
        return jsonify({"success": True, "message": "Product marked as sold"}), 200
        
    except Exception as e:
        app.logger.error(f"Error marking product sold: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

# Chat Socket Events
@socketio.on('join')
def on_join(data):
    room = data['room']
    join_room(room)
    # Fetch previous messages
    messages = list(messages_col.find({"room": room}, {"_id": 0}).sort("created_at", 1))
    emit('history', messages)

# Payment Endpoints
@app.route("/api/payments/create-order", methods=["POST"])
def create_order():
    """Create a Razorpay order"""
    try:
        data = request.get_json()
        amount = int(float(data['amount']) * 100)  # Amount in paise

        order_data = {
            'amount': amount,
            'currency': 'INR',
            'receipt': f"receipt_{str(uuid.uuid4())[:8]}",
            'payment_capture': 1
        }

        order = razorpay_client.order.create(data=order_data)
        return jsonify({"success": True, "order": order}), 201
    except Exception as e:
        app.logger.error(f"Error creating Razorpay order: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route("/api/payments/verify", methods=["POST"])
def verify_payment():
    """Verify Razorpay payment signature"""
    try:
        data = request.get_json()
        params_dict = {
            'razorpay_order_id': data['razorpay_order_id'],
            'razorpay_payment_id': data['razorpay_payment_id'],
            'razorpay_signature': data['razorpay_signature']
        }

        # Verify signature
        razorpay_client.utility.verify_payment_signature(params_dict)

        # If successful, mark product as sold (optional: trigger logic here)
        return jsonify({"success": True, "message": "Payment verified successfully"}), 200
    except Exception as e:
        app.logger.error(f"Payment verification failed: {e}")
        return jsonify({"success": False, "error": "Payment verification failed"}), 400

@socketio.on('message')
def handle_message(data):
    room = data['room']
    sender_email = data['sender']
    text = data['text']

    msg = {
        "room": room,
        "sender": sender_email,
        "text": text,
        "created_at": datetime.utcnow().isoformat()
    }
    messages_col.insert_one(msg.copy())
    msg.pop("_id", None)
    emit('message', msg, room=room)

    # Send email notification to the other party
    try:
        # room format: productID_buyerEmail
        parts = room.split('_')
        if len(parts) >= 2:
            product_id = parts[0]
            buyer_email = parts[1]

            product = products_col.find_one({"id": product_id})
            if product:
                seller_email = product.get('seller_email')
                product_title = product.get('title', 'Product')

                # Determine recipient (if sender is buyer, recipient is seller, and vice versa)
                recipient_email = seller_email if sender_email == buyer_email else buyer_email

                # We don't want to spam emails for every single message in a fast chat.
                # Only send if the last message in this room was more than 5 minutes ago
                # or if there are fewer than 2 messages (start of conversation).
                msg_count = messages_col.count_documents({"room": room})

                if msg_count <= 2:
                    # New conversation, definitely send
                    send_chat_notification_email(recipient_email, sender_email, text, product_title)
    except Exception as e:
        app.logger.error(f"Error in chat email notification: {e}")

if __name__ == "__main__":
    socketio.run(app, host="0.0.0.0", port=PORT, debug=True)
