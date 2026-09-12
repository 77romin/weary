#!/bin/zsh

set -euo pipefail

readonly project_ref="$(<supabase/.temp/project-ref)"
readonly api_base="https://${project_ref}.supabase.co"
readonly publishable_key="$(awk -F' = ' '/^SUPABASE_PUBLISHABLE_KEY = / { print $2 }' Config/Supabase.local.xcconfig)"
readonly temp_dir="$(mktemp -d /tmp/weary-profile-rls.XXXXXX)"

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
  curl -sS -X POST "$api_base/auth/v1/signup" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $publishable_key" \
    -H 'Content-Type: application/json' \
    -d '{}' \
    -o "$output_file"
  jq -e '.access_token and .user.id' "$output_file" >/dev/null || fail "anonymous session payload"
}

request() {
  local method="$1"
  local endpoint="$2"
  local token="$3"
  local output_file="$4"
  local body="${5:-}"
  local args=(-sS -w '%{http_code}' -X "$method" "$api_base/rest/v1/$endpoint"
    -H "apikey: $publishable_key"
    -H "Authorization: Bearer $token"
    -H 'Content-Type: application/json'
    -H 'Prefer: return=representation')
  if [[ -n "$body" ]]; then
    args+=(-d "$body")
  fi
  curl "${args[@]}" -o "$output_file"
}

sign_in_anonymously "$temp_dir/a.json"
sign_in_anonymously "$temp_dir/b.json"
readonly a_token="$(jq -r '.access_token' "$temp_dir/a.json")"
readonly a_id="$(jq -r '.user.id' "$temp_dir/a.json")"
readonly b_token="$(jq -r '.access_token' "$temp_dir/b.json")"
readonly first_handle="verify_$(print "$a_id" | cut -c1-8)"

response_status="$(request PATCH "profiles?id=eq.$a_id" "$a_token" "$temp_dir/profile.json" \
  "$(jq -nc --arg handle "$first_handle" '{handle:$handle,display_name:"프로필 검증"}')")"
assert_equal "$response_status" "200" "owner sets profile ID"
assert_equal "$(jq 'length' "$temp_dir/profile.json")" "1" "profile update returns owner row"

response_status="$(request PATCH "profiles?id=eq.$a_id" "$a_token" "$temp_dir/immutable.json" \
  '{"handle":"changed_handle"}')"
assert_equal "$response_status" "400" "profile ID cannot be changed"

response_status="$(request POST "profile_measurements" "$a_token" "$temp_dir/measurement.json" \
  "$(jq -nc --arg id "$a_id" '{id:$id,height_cm:175.5,weight_kg:68.2,waist_cm:78.0}')")"
assert_equal "$response_status" "201" "owner stores private measurements"

response_status="$(request GET "profile_measurements?id=eq.$a_id&select=id,height_cm,weight_kg,waist_cm" "$a_token" "$temp_dir/owner-read.json")"
assert_equal "$response_status" "200" "owner reads private measurements"
assert_equal "$(jq 'length' "$temp_dir/owner-read.json")" "1" "owner measurement row is visible"

response_status="$(request GET "profile_measurements?id=eq.$a_id&select=id,height_cm" "$b_token" "$temp_dir/other-read.json")"
assert_equal "$response_status" "200" "other user measurement query is safely filtered"
assert_equal "$(jq 'length' "$temp_dir/other-read.json")" "0" "other user cannot read measurements"

response_status="$(request PATCH "profile_measurements?id=eq.$a_id" "$b_token" "$temp_dir/other-write.json" '{"height_cm":180}')"
assert_equal "$response_status" "200" "other user measurement update is safely filtered"
assert_equal "$(jq 'length' "$temp_dir/other-write.json")" "0" "other user cannot update measurements"

response_status="$(request DELETE "profile_measurements?id=eq.$a_id" "$a_token" "$temp_dir/delete.json")"
assert_equal "$response_status" "200" "owner removes test measurements"

print "Profile privacy verification completed."
print "Note: two anonymous Auth test users remain; private test measurements were removed."
