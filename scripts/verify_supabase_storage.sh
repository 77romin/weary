#!/bin/zsh

set -euo pipefail

readonly project_ref="$(<supabase/.temp/project-ref)"
readonly api_base="https://${project_ref}.supabase.co"
readonly publishable_key="$(awk -F' = ' '/^SUPABASE_PUBLISHABLE_KEY = / { print $2 }' Config/Supabase.local.xcconfig)"
readonly bucket="community-media"
readonly temp_dir="$(mktemp -d /tmp/weary-storage-rls.XXXXXX)"

a_token=""
public_post_id=""
private_post_id=""
public_object_path=""
private_object_path=""

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

post_delete() {
  local token="$1"
  local post_id="$2"
  [[ -n "$token" && -n "$post_id" ]] || return 0
  curl -sS -X DELETE "$api_base/rest/v1/posts?id=eq.$post_id" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" >/dev/null || true
}

cleanup() {
  storage_delete "$a_token" "$public_object_path"
  storage_delete "$a_token" "$private_object_path"
  post_delete "$a_token" "$public_post_id"
  post_delete "$a_token" "$private_post_id"
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

create_post() {
  local token="$1"
  local author_id="$2"
  local visibility="$3"
  local output_file="$4"
  curl -sS -w '%{http_code}' -X POST "$api_base/rest/v1/posts" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    -H 'Prefer: return=representation' \
    -d "$(jq -nc --arg author "$author_id" --arg visibility "$visibility" \
      '{author_id:$author,caption:"Storage RLS test",visibility:$visibility}')" \
    -o "$output_file"
}

upload_image() {
  local token="$1"
  local object_path="$2"
  local content_type="$3"
  local source_file="$4"
  local output_file="$5"
  curl -sS -w '%{http_code}' -X POST "$api_base/storage/v1/object/$bucket/$object_path" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: $content_type" \
    -H 'x-upsert: false' \
    --data-binary "@$source_file" \
    -o "$output_file"
}

download_image() {
  local token="$1"
  local object_path="$2"
  local output_file="$3"
  curl -sS -w '%{http_code}' "$api_base/storage/v1/object/authenticated/$bucket/$object_path" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $token" \
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

http_status="$(create_post "$a_token" "$a_id" "public" "$temp_dir/public-post.json")"
assert_equal "$http_status" "201" "author creates public image post"
public_post_id="$(jq -r '.[0].id' "$temp_dir/public-post.json")"
public_object_path="$a_id/$public_post_id/look.png"

http_status="$(create_post "$a_token" "$a_id" "private" "$temp_dir/private-post.json")"
assert_equal "$http_status" "201" "author creates private image post"
private_post_id="$(jq -r '.[0].id' "$temp_dir/private-post.json")"
private_object_path="$a_id/$private_post_id/look.png"

http_status="$(upload_image "$a_token" "$public_object_path" "image/png" "$temp_dir/pixel.png" "$temp_dir/public-upload.json")"
assert_equal "$http_status" "200" "owner uploads to owned post path"

http_status="$(download_image "$a_token" "$public_object_path" "$temp_dir/a-before-link.png")"
assert_equal "$http_status" "200" "owner reads image before media record exists"

http_status="$(download_image "$b_token" "$public_object_path" "$temp_dir/b-before-link.json")"
assert_not_equal "$http_status" "200" "other user cannot read unlinked image"

http_status="$(curl -sS -w '%{http_code}' -X POST "$api_base/rest/v1/post_media" \
  -H "apikey: $publishable_key" \
  -H "Authorization: Bearer $a_token" \
  -H 'Content-Type: application/json' \
  -H 'Prefer: return=representation' \
  -d "$(jq -nc --arg post "$public_post_id" --arg path "$public_object_path" \
    '{post_id:$post,storage_path:$path,media_type:"image",sort_order:0,width:1,height:1}')" \
  -o "$temp_dir/public-media.json")"
assert_equal "$http_status" "201" "owner links image to public post"

http_status="$(download_image "$b_token" "$public_object_path" "$temp_dir/b-public.png")"
assert_equal "$http_status" "200" "other user reads image on visible public post"

http_status="$(upload_image "$a_token" "$private_object_path" "image/png" "$temp_dir/pixel.png" "$temp_dir/private-upload.json")"
assert_equal "$http_status" "200" "owner uploads private post image"

http_status="$(curl -sS -w '%{http_code}' -X POST "$api_base/rest/v1/post_media" \
  -H "apikey: $publishable_key" \
  -H "Authorization: Bearer $a_token" \
  -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg post "$private_post_id" --arg path "$private_object_path" \
    '{post_id:$post,storage_path:$path,media_type:"image",sort_order:0,width:1,height:1}')" \
  -o "$temp_dir/private-media.json")"
assert_equal "$http_status" "201" "owner links image to private post"

http_status="$(download_image "$b_token" "$private_object_path" "$temp_dir/b-private.json")"
assert_not_equal "$http_status" "200" "private post image stays hidden"

readonly forged_path="$b_id/$public_post_id/forged.png"
http_status="$(upload_image "$a_token" "$forged_path" "image/png" "$temp_dir/pixel.png" "$temp_dir/forged-upload.json")"
assert_not_equal "$http_status" "200" "user cannot upload into another user's folder"

readonly invalid_mime_path="$a_id/$public_post_id/invalid.png"
http_status="$(upload_image "$a_token" "$invalid_mime_path" "text/plain" "$temp_dir/pixel.png" "$temp_dir/invalid-upload.json")"
assert_not_equal "$http_status" "200" "bucket rejects unsupported MIME type"

storage_delete "$b_token" "$public_object_path"
http_status="$(download_image "$a_token" "$public_object_path" "$temp_dir/after-forged-delete.png")"
assert_equal "$http_status" "200" "other user cannot delete owner's image"

print "Storage RLS verification completed."
print "Note: two anonymous Auth test users remain; all Storage and post test data will be removed."
