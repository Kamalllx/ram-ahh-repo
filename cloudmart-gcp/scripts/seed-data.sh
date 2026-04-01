#!/usr/bin/env bash
# Seed CloudMart with demo products and a test user
set -euo pipefail

PROJECT_ID=${1:-$(gcloud config get-value project)}
REGION=${2:-us-central1}

API_URL=$(gcloud run services describe cloudmart-api-gateway \
  --region="$REGION" --project="$PROJECT_ID" \
  --format="value(status.url)")

echo "Seeding data via $API_URL"

# ── Register test user ────────────────────────────────────────
echo "→ Creating test user..."
REGISTER=$(curl -sf -X POST "$API_URL/api/v1/users/register" \
  -H "Content-Type: application/json" \
  -d '{
    "email":     "demo@cloudmart.demo",
    "password":  "Demo123456!",
    "full_name": "Demo User",
    "phone":     "+1-555-0100"
  }')

TOKEN=$(echo "$REGISTER" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
echo "✓ Test user created (email: demo@cloudmart.demo / password: Demo123456!)"

# ── Seed products ─────────────────────────────────────────────
echo "→ Seeding products..."
PRODUCTS=(
  '{"name":"Wireless Noise-Cancelling Headphones","description":"Premium over-ear headphones with 30hr battery and active noise cancellation. Perfect for travel and focus work.","price":299.99,"category":"Electronics","tags":["audio","wireless","noise-cancelling"],"stock_quantity":150}'
  '{"name":"Mechanical Keyboard — TKL","description":"Tenkeyless mechanical keyboard with Cherry MX Blue switches. N-key rollover, RGB backlight, aluminum frame.","price":149.99,"category":"Electronics","tags":["keyboard","mechanical","gaming"],"stock_quantity":75}'
  '{"name":"4K Webcam","description":"4K UHD webcam with autofocus, dual microphones, and privacy shutter. Plug-and-play USB-C.","price":99.99,"category":"Electronics","tags":["webcam","4k","streaming"],"stock_quantity":200}'
  '{"name":"Ergonomic Office Chair","description":"Lumbar support, adjustable armrests, breathable mesh back. Rated for 8+ hours of daily use.","price":449.99,"category":"Furniture","tags":["ergonomic","office","chair"],"stock_quantity":30}'
  '{"name":"Standing Desk — Motorized","description":"Electric height-adjustable desk, 48x24 inch surface, memory presets, cable management included.","price":599.99,"category":"Furniture","tags":["desk","standing","motorized"],"stock_quantity":20}'
  '{"name":"Running Shoes — Trail Pro","description":"Lightweight trail running shoes with Vibram sole, waterproof membrane, and cushioned midsole.","price":129.99,"category":"Sports","tags":["running","trail","waterproof"],"stock_quantity":100}'
  '{"name":"Smart Water Bottle","description":"Insulated stainless steel bottle with hydration tracking app integration and LED reminder ring.","price":49.99,"category":"Sports","tags":["hydration","smart","insulated"],"stock_quantity":300}'
  '{"name":"Portable Espresso Maker","description":"Handheld espresso maker compatible with Nespresso pods. No electricity needed — perfect for travel.","price":79.99,"category":"Kitchen","tags":["coffee","espresso","travel"],"stock_quantity":80}'
  '{"name":"Bamboo Cutting Board Set","description":"Set of 3 bamboo cutting boards with juice groove, grip feet, and built-in handles.","price":39.99,"category":"Kitchen","tags":["kitchen","bamboo","eco-friendly"],"stock_quantity":120}'
  '{"name":"Cloud-Native Architecture (Book)","description":"Deep dive into microservices, containers, service meshes, and cloud-native patterns. 650 pages.","price":54.99,"category":"Books","tags":["technology","cloud","architecture"],"stock_quantity":500}'
)

for product in "${PRODUCTS[@]}"; do
  RESP=$(curl -sf -X POST "$API_URL/api/v1/products" \
    -H "Content-Type: application/json" \
    -d "$product")
  NAME=$(echo "$product" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
  echo "  ✓ $NAME"
done

# ── Place sample order ────────────────────────────────────────
echo "→ Placing sample order..."
curl -sf -X POST "$API_URL/api/v1/orders" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "items": [
      {"product_id":"demo-1","product_name":"Wireless Headphones","quantity":1,"unit_price":299.99},
      {"product_id":"demo-2","product_name":"Mechanical Keyboard","quantity":1,"unit_price":149.99}
    ],
    "shipping_address": {
      "street":  "1 Cloud Way",
      "city":    "San Francisco",
      "state":   "CA",
      "zip":     "94105",
      "country": "US"
    },
    "payment_method": "card_demo"
  }' >/dev/null

echo "✓ Sample order placed"

echo ""
echo "Seed complete!"
echo ""
echo "Test credentials:"
echo "  Email:    demo@cloudmart.demo"
echo "  Password: Demo123456!"
echo "  Token:    ${TOKEN:0:30}..."
