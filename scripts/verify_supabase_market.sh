#!/bin/zsh

set -euo pipefail

readonly project_ref="$(<supabase/.temp/project-ref)"
readonly api_base="https://${project_ref}.supabase.co"
readonly publishable_key="$(awk -F' = ' '/^SUPABASE_PUBLISHABLE_KEY = / { print $2 }' Config/Supabase.local.xcconfig)"
readonly temp_dir="$(mktemp -d /tmp/weary-market-rls.XXXXXX)"

cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT

fail() {
  print -u2 "FAIL: $1"
  exit 1
}

assert_equal() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label (expected=$expected, actual=$actual)"
  print "PASS: $label"
}

sign_in_anonymously() {
  local output_file="$1"
  local http_status
  http_status="$(curl -sS -w '%{http_code}' -X POST "$api_base/auth/v1/signup" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $publishable_key" \
    -H 'Content-Type: application/json' \
    -d '{}' \
    -o "$output_file")"
  assert_equal "$http_status" "200" "anonymous sign-in"
  jq -e '.access_token and .user.id and .user.is_anonymous == true' "$output_file" >/dev/null \
    || fail "anonymous session payload"
}

request() {
  local method="$1"
  local url="$2"
  local token="$3"
  local output_file="$4"
  local body="${5:-}"
  local args=(-sS -w '%{http_code}' -X "$method" "$url"
    -H "apikey: $publishable_key"
    -H "Authorization: Bearer $token"
    -H 'Content-Type: application/json'
    -H 'Prefer: return=representation')
  if [[ -n "$body" ]]; then
    args+=(-d "$body")
  fi
  curl "${args[@]}" -o "$output_file"
}

sign_in_anonymously "$temp_dir/a-auth.json"
sign_in_anonymously "$temp_dir/b-auth.json"

readonly a_token="$(jq -r '.access_token' "$temp_dir/a-auth.json")"
readonly a_id="$(jq -r '.user.id' "$temp_dir/a-auth.json")"
readonly b_token="$(jq -r '.access_token' "$temp_dir/b-auth.json")"
readonly b_id="$(jq -r '.user.id' "$temp_dir/b-auth.json")"

http_status="$(request POST "$api_base/rest/v1/market_listings" "$a_token" "$temp_dir/listing.json" \
  "$(jq -nc --arg seller "$a_id" '{seller_id:$seller,title:"RLS market jacket",description:"market test",price:50000,brand_snapshot:"WEARy",category_snapshot:"outer",size_snapshot:"M",color_hex_snapshot:"222222",condition:"excellent",meeting_name:"성수역",meeting_address:"서울 성동구",meeting_latitude:37.5445,meeting_longitude:127.0559}')")"
assert_equal "$http_status" "201" "seller creates a market listing"
readonly listing_id="$(jq -r '.[0].id' "$temp_dir/listing.json")"

http_status="$(request GET "$api_base/rest/v1/market_listings?id=eq.$listing_id&select=id,price" "$b_token" "$temp_dir/b-visible.json")"
assert_equal "$http_status" "200" "other user reads active listing"
assert_equal "$(jq 'length' "$temp_dir/b-visible.json")" "1" "active listing is visible"

http_status="$(request PATCH "$api_base/rest/v1/market_listings?id=eq.$listing_id" "$b_token" "$temp_dir/b-update.json" '{"price":1000}')"
assert_equal "$http_status" "200" "unauthorized listing update is safely filtered"
assert_equal "$(jq 'length' "$temp_dir/b-update.json")" "0" "other user cannot update listing"

http_status="$(request PATCH "$api_base/rest/v1/market_listings?id=eq.$listing_id" "$a_token" "$temp_dir/a-price.json" '{"price":45000}')"
assert_equal "$http_status" "200" "seller adjusts listing price"
assert_equal "$(jq -r '.[0].previous_price' "$temp_dir/a-price.json")" "50000" "database records previous price"

http_status="$(request POST "$api_base/rest/v1/market_listing_media" "$a_token" "$temp_dir/media.json" \
  "$(jq -nc --arg listing "$listing_id" '{listing_id:$listing,storage_path:"market-test/photo-0.jpg",sort_order:0}')")"
assert_equal "$http_status" "201" "seller adds listing media metadata"

http_status="$(request POST "$api_base/rest/v1/market_listing_media" "$b_token" "$temp_dir/b-media.json" \
  "$(jq -nc --arg listing "$listing_id" '{listing_id:$listing,storage_path:"market-test/unauthorized.jpg",sort_order:1}')")"
assert_equal "$http_status" "403" "other user cannot add listing media"

http_status="$(request POST "$api_base/rest/v1/market_listing_verifications" "$a_token" "$temp_dir/verification.json" \
  "$(jq -nc --arg listing "$listing_id" --arg source "$(uuidgen | tr '[:upper:]' '[:lower:]')" '{listing_id:$listing,source_private_id:$source,garment_name_snapshot:"옷장 재킷",purchase_price:120000,wear_count:3,is_visible:false}')")"
assert_equal "$http_status" "201" "seller creates hidden wardrobe verification"

http_status="$(request GET "$api_base/rest/v1/market_listing_verifications?listing_id=eq.$listing_id&select=listing_id,purchase_price,wear_count" "$b_token" "$temp_dir/b-hidden-verification.json")"
assert_equal "$http_status" "200" "other user queries hidden verification safely"
assert_equal "$(jq 'length' "$temp_dir/b-hidden-verification.json")" "0" "hidden wardrobe data stays private"

http_status="$(request PATCH "$api_base/rest/v1/market_listing_verifications?listing_id=eq.$listing_id" "$a_token" "$temp_dir/show-verification.json" '{"is_visible":true}')"
assert_equal "$http_status" "200" "seller publishes wardrobe verification"

http_status="$(request GET "$api_base/rest/v1/market_listing_verifications?listing_id=eq.$listing_id&select=listing_id,purchase_price,wear_count" "$b_token" "$temp_dir/b-visible-verification.json")"
assert_equal "$http_status" "200" "other user reads published verification"
assert_equal "$(jq 'length' "$temp_dir/b-visible-verification.json")" "1" "published wardrobe data is visible"

http_status="$(request PATCH "$api_base/rest/v1/market_listings?id=eq.$listing_id" "$a_token" "$temp_dir/hide-listing.json" '{"status":"hidden"}')"
assert_equal "$http_status" "200" "seller hides listing"

http_status="$(request GET "$api_base/rest/v1/market_listing_verifications?listing_id=eq.$listing_id&select=listing_id,purchase_price,wear_count" "$b_token" "$temp_dir/b-hidden-listing-verification.json")"
assert_equal "$http_status" "200" "other user queries verification on hidden listing safely"
assert_equal "$(jq 'length' "$temp_dir/b-hidden-listing-verification.json")" "0" "public verification follows listing visibility"

http_status="$(request PATCH "$api_base/rest/v1/market_listings?id=eq.$listing_id" "$a_token" "$temp_dir/show-listing.json" '{"status":"active"}')"
assert_equal "$http_status" "200" "seller republishes listing"

http_status="$(request POST "$api_base/rest/v1/market_listing_favorites" "$b_token" "$temp_dir/favorite.json" \
  "$(jq -nc --arg listing "$listing_id" --arg user "$b_id" '{listing_id:$listing,user_id:$user}')")"
assert_equal "$http_status" "201" "buyer favorites visible listing"

http_status="$(request GET "$api_base/rest/v1/market_listing_favorites?listing_id=eq.$listing_id&select=listing_id" "$a_token" "$temp_dir/a-favorites.json")"
assert_equal "$http_status" "200" "seller queries another user's favorites safely"
assert_equal "$(jq 'length' "$temp_dir/a-favorites.json")" "0" "favorites remain private to their owner"

http_status="$(request PATCH "$api_base/rest/v1/market_listings?id=eq.$listing_id" "$a_token" "$temp_dir/reserved.json" '{"status":"reserved"}')"
assert_equal "$http_status" "200" "seller marks listing reserved"

http_status="$(request GET "$api_base/rest/v1/market_listings?id=eq.$listing_id&select=status" "$b_token" "$temp_dir/b-reserved.json")"
assert_equal "$http_status" "200" "buyer reads reserved listing"
assert_equal "$(jq -r '.[0].status' "$temp_dir/b-reserved.json")" "reserved" "reserved status is shared"

http_status="$(request DELETE "$api_base/rest/v1/market_listings?id=eq.$listing_id" "$a_token" "$temp_dir/delete-listing.json")"
assert_equal "$http_status" "200" "seller removes test listing"

print "Market RLS verification completed."
print "Note: two anonymous Auth test users remain; all market test content was removed."
