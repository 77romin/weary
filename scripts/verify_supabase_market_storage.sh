#!/bin/zsh

set -euo pipefail

readonly project_ref="$(<supabase/.temp/project-ref)"
readonly api_base="https://${project_ref}.supabase.co"
readonly publishable_key="$(awk -F' = ' '/^SUPABASE_PUBLISHABLE_KEY = / { print $2 }' Config/Supabase.local.xcconfig)"
readonly bucket="market-media"
readonly temp_dir="$(mktemp -d /tmp/weary-market-storage.XXXXXX)"

a_token=""
listing_id=""
gallery_path=""
cutout_path=""

storage_delete() {
  local token="$1"
  local object_path="$2"
  [[ -n "$token" && -n "$object_path" ]] || return 0
  curl -sS -X DELETE "$api_base/storage/v1/object/$bucket" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg path "$object_path" '{prefixes:[$path]}')" >/dev/null || true
}

listing_delete() {
  local token="$1"
  local id="$2"
  [[ -n "$token" && -n "$id" ]] || return 0
  curl -sS -X DELETE "$api_base/rest/v1/market_listings?id=eq.$id" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" >/dev/null || true
}

cleanup() {
  storage_delete "$a_token" "$gallery_path"
  storage_delete "$a_token" "$cutout_path"
  listing_delete "$a_token" "$listing_id"
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

assert_not_equal() {
  local actual="$1"
  local unexpected="$2"
  local label="$3"
  [[ "$actual" != "$unexpected" ]] || fail "$label (unexpected=$unexpected)"
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

upload_image() {
  local token="$1"
  local object_path="$2"
  local content_type="$3"
  local output_file="$4"
  curl -sS -w '%{http_code}' -X POST "$api_base/storage/v1/object/$bucket/$object_path" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: $content_type" \
    -H 'x-upsert: false' \
    --data-binary "@$temp_dir/pixel.png" \
    -o "$output_file"
}

download_image() {
  local token="$1"
  local object_path="$2"
  local output_file="$3"
  local cache_bust
  cache_bust="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  curl -sS -w '%{http_code}' "$api_base/storage/v1/object/authenticated/$bucket/$object_path?cache_bust=$cache_bust" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" \
    -H 'Cache-Control: no-cache' \
    -o "$output_file"
}

sign_in_anonymously "$temp_dir/a-auth.json"
sign_in_anonymously "$temp_dir/b-auth.json"

a_token="$(jq -r '.access_token' "$temp_dir/a-auth.json")"
readonly a_id="$(jq -r '.user.id' "$temp_dir/a-auth.json")"
readonly b_token="$(jq -r '.access_token' "$temp_dir/b-auth.json")"
readonly b_id="$(jq -r '.user.id' "$temp_dir/b-auth.json")"

print 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' \
  | base64 -D > "$temp_dir/pixel.png"

http_status="$(curl -sS -w '%{http_code}' -X POST "$api_base/rest/v1/market_listings" \
  -H "apikey: $publishable_key" \
  -H "Authorization: Bearer $a_token" \
  -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d "$(jq -nc --arg seller "$a_id" '{seller_id:$seller,title:"Storage market jacket",description:"storage test",price:50000,condition:"excellent"}')" \
  -o "$temp_dir/listing.json")"
assert_equal "$http_status" "201" "seller creates listing for images"
listing_id="$(jq -r '.[0].id' "$temp_dir/listing.json")"
gallery_path="$a_id/$listing_id/gallery/0.png"
cutout_path="$a_id/$listing_id/verification/cutout.png"

http_status="$(upload_image "$a_token" "$gallery_path" "image/png" "$temp_dir/gallery-upload.json")"
assert_equal "$http_status" "200" "seller uploads gallery image to owned listing path"

http_status="$(download_image "$a_token" "$gallery_path" "$temp_dir/a-gallery.png")"
assert_equal "$http_status" "200" "seller reads image before metadata link"

http_status="$(download_image "$b_token" "$gallery_path" "$temp_dir/b-unlinked-gallery.json")"
assert_not_equal "$http_status" "200" "other user cannot read unlinked gallery image"

http_status="$(curl -sS -w '%{http_code}' -X POST "$api_base/rest/v1/market_listing_media" \
  -H "apikey: $publishable_key" \
  -H "Authorization: Bearer $a_token" \
  -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg listing "$listing_id" --arg path "$gallery_path" '{listing_id:$listing,storage_path:$path,sort_order:0,width:1,height:1}')" \
  -o "$temp_dir/gallery-media.json")"
assert_equal "$http_status" "201" "seller links gallery image to listing"

http_status="$(download_image "$b_token" "$gallery_path" "$temp_dir/b-gallery.png")"
assert_equal "$http_status" "200" "other user reads gallery image on visible listing"

http_status="$(upload_image "$a_token" "$cutout_path" "image/png" "$temp_dir/cutout-upload.json")"
assert_equal "$http_status" "200" "seller uploads wardrobe verification cutout"

readonly source_private_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
http_status="$(curl -sS -w '%{http_code}' -X POST "$api_base/rest/v1/market_listing_verifications" \
  -H "apikey: $publishable_key" \
  -H "Authorization: Bearer $a_token" \
  -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg listing "$listing_id" --arg source "$source_private_id" --arg path "$cutout_path" '{listing_id:$listing,source_private_id:$source,garment_name_snapshot:"옷장 재킷",cutout_storage_path:$path,is_visible:false}')" \
  -o "$temp_dir/verification.json")"
assert_equal "$http_status" "201" "seller links hidden verification cutout"

http_status="$(download_image "$b_token" "$cutout_path" "$temp_dir/b-hidden-cutout.json")"
assert_not_equal "$http_status" "200" "hidden verification cutout stays private"

http_status="$(curl -sS -w '%{http_code}' -X PATCH "$api_base/rest/v1/market_listing_verifications?listing_id=eq.$listing_id" \
  -H "apikey: $publishable_key" \
  -H "Authorization: Bearer $a_token" \
  -H 'Content-Type: application/json' \
  -d '{"is_visible":true}' \
  -o "$temp_dir/show-verification.json")"
assert_equal "$http_status" "204" "seller publishes wardrobe verification"

http_status="$(download_image "$b_token" "$cutout_path" "$temp_dir/b-public-cutout.png")"
assert_equal "$http_status" "200" "other user reads published verification cutout"

http_status="$(curl -sS -w '%{http_code}' -X PATCH "$api_base/rest/v1/market_listings?id=eq.$listing_id" \
  -H "apikey: $publishable_key" \
  -H "Authorization: Bearer $a_token" \
  -H 'Content-Type: application/json' \
  -d '{"status":"hidden"}' \
  -o "$temp_dir/hide-listing.json")"
assert_equal "$http_status" "204" "seller hides listing"

http_status="$(download_image "$b_token" "$gallery_path" "$temp_dir/b-hidden-gallery.json")"
assert_not_equal "$http_status" "200" "gallery image follows listing visibility"
http_status="$(download_image "$b_token" "$cutout_path" "$temp_dir/b-hidden-listing-cutout.json")"
assert_not_equal "$http_status" "200" "verification image follows listing visibility"

readonly forged_path="$b_id/$listing_id/gallery/forged.png"
http_status="$(upload_image "$a_token" "$forged_path" "image/png" "$temp_dir/forged-upload.json")"
assert_not_equal "$http_status" "200" "seller cannot upload into another user's folder"

readonly invalid_listing_path="$a_id/$(uuidgen | tr '[:upper:]' '[:lower:]')/gallery/invalid.png"
http_status="$(upload_image "$a_token" "$invalid_listing_path" "image/png" "$temp_dir/invalid-listing-upload.json")"
assert_not_equal "$http_status" "200" "seller cannot upload without an owned listing"

readonly invalid_mime_path="$a_id/$listing_id/gallery/invalid.txt"
http_status="$(upload_image "$a_token" "$invalid_mime_path" "text/plain" "$temp_dir/invalid-mime-upload.json")"
assert_not_equal "$http_status" "200" "bucket rejects unsupported MIME type"

storage_delete "$b_token" "$gallery_path"
http_status="$(download_image "$a_token" "$gallery_path" "$temp_dir/after-forged-delete.png")"
assert_equal "$http_status" "200" "other user cannot delete seller image"

print "Market Storage RLS verification completed."
print "Note: two anonymous Auth test users remain; all Storage and listing test data will be removed."
