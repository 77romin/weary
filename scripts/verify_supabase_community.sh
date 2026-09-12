#!/bin/zsh

set -euo pipefail

readonly project_ref="$(<supabase/.temp/project-ref)"
readonly api_base="https://${project_ref}.supabase.co"
readonly publishable_key="$(awk -F' = ' '/^SUPABASE_PUBLISHABLE_KEY = / { print $2 }' Config/Supabase.local.xcconfig)"
readonly temp_dir="$(mktemp -d /tmp/weary-community-rls.XXXXXX)"

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

http_status="$(request POST "$api_base/rest/v1/posts" "$a_token" "$temp_dir/public-post.json" \
  "$(jq -nc --arg author "$a_id" '{author_id:$author,caption:"RLS public test",visibility:"public",tags:["test"]}')")"
assert_equal "$http_status" "201" "author creates a public post"
readonly public_post_id="$(jq -r '.[0].id' "$temp_dir/public-post.json")"

http_status="$(request POST "$api_base/rest/v1/posts" "$a_token" "$temp_dir/followers-post.json" \
  "$(jq -nc --arg author "$a_id" '{author_id:$author,caption:"RLS followers test",visibility:"followers"}')")"
assert_equal "$http_status" "201" "author creates a followers-only post"
readonly followers_post_id="$(jq -r '.[0].id' "$temp_dir/followers-post.json")"

http_status="$(request POST "$api_base/rest/v1/posts" "$a_token" "$temp_dir/private-post.json" \
  "$(jq -nc --arg author "$a_id" '{author_id:$author,caption:"RLS private test",visibility:"private"}')")"
assert_equal "$http_status" "201" "author creates a private post"
readonly private_post_id="$(jq -r '.[0].id' "$temp_dir/private-post.json")"

http_status="$(request GET "$api_base/rest/v1/posts?author_id=eq.$a_id&select=id" "$b_token" "$temp_dir/b-visible-before.json")"
assert_equal "$http_status" "200" "other user reads visible posts"
assert_equal "$(jq 'length' "$temp_dir/b-visible-before.json")" "1" "only public post is visible before follow"

http_status="$(request PATCH "$api_base/rest/v1/posts?id=eq.$public_post_id" "$b_token" "$temp_dir/b-update.json" '{"caption":"unauthorized edit"}')"
assert_equal "$http_status" "200" "unauthorized update is safely filtered"
assert_equal "$(jq 'length' "$temp_dir/b-update.json")" "0" "other user cannot update author's post"

http_status="$(request POST "$api_base/rest/v1/follows" "$b_token" "$temp_dir/follow.json" \
  "$(jq -nc --arg follower "$b_id" --arg following "$a_id" '{follower_id:$follower,following_id:$following}')")"
assert_equal "$http_status" "201" "user follows another profile"

http_status="$(request GET "$api_base/rest/v1/posts?author_id=eq.$a_id&select=id" "$b_token" "$temp_dir/b-visible-after.json")"
assert_equal "$http_status" "200" "follower reads visible posts"
assert_equal "$(jq 'length' "$temp_dir/b-visible-after.json")" "2" "followers-only post becomes visible"
assert_equal "$(jq --arg id "$private_post_id" '[.[] | select(.id == $id)] | length' "$temp_dir/b-visible-after.json")" "0" "private post stays hidden"

http_status="$(request POST "$api_base/rest/v1/post_likes" "$b_token" "$temp_dir/like.json" \
  "$(jq -nc --arg post "$public_post_id" --arg user "$b_id" '{post_id:$post,user_id:$user}')")"
assert_equal "$http_status" "201" "user likes a visible post"

http_status="$(request POST "$api_base/rest/v1/comments" "$b_token" "$temp_dir/comment.json" \
  "$(jq -nc --arg post "$public_post_id" --arg author "$b_id" '{post_id:$post,author_id:$author,body:"RLS comment test"}')")"
assert_equal "$http_status" "201" "user comments on a visible post"

http_status="$(request POST "$api_base/rest/v1/bookmarks" "$b_token" "$temp_dir/bookmark.json" \
  "$(jq -nc --arg post "$public_post_id" --arg user "$b_id" '{post_id:$post,user_id:$user}')")"
assert_equal "$http_status" "201" "user bookmarks a visible post"

http_status="$(request GET "$api_base/rest/v1/bookmarks?post_id=eq.$public_post_id&select=post_id" "$a_token" "$temp_dir/a-bookmarks.json")"
assert_equal "$http_status" "200" "bookmark owner isolation query"
assert_equal "$(jq 'length' "$temp_dir/a-bookmarks.json")" "0" "another user cannot read private bookmarks"

http_status="$(request GET "$api_base/rest/v1/bookmarks?post_id=eq.$public_post_id&select=post_id" "$b_token" "$temp_dir/b-bookmarks.json")"
assert_equal "$http_status" "200" "bookmark owner query"
assert_equal "$(jq 'length' "$temp_dir/b-bookmarks.json")" "1" "bookmark owner can read bookmark"

http_status="$(request DELETE "$api_base/rest/v1/follows?follower_id=eq.$b_id&following_id=eq.$a_id" "$b_token" "$temp_dir/delete-follow.json")"
assert_equal "$http_status" "200" "follower removes relationship"

for post_id in "$public_post_id" "$followers_post_id" "$private_post_id"; do
  http_status="$(request DELETE "$api_base/rest/v1/posts?id=eq.$post_id" "$a_token" "$temp_dir/delete-post.json")"
  assert_equal "$http_status" "200" "author removes test post"
done

print "Community RLS verification completed."
print "Note: two anonymous Auth test users remain; all community test content was removed."
