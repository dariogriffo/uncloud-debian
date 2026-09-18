#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# verify_download.sh
#
# Verifies a file downloaded from an upstream release BEFORE it is unpacked
# into a package. Two independent layers, both fail-closed (exit 1):
#
#   1. Checksum  -- the upstream-published SHA-256 for this exact asset.
#                   This only proves the bytes we got are the bytes upstream
#                   published; the checksum lives on the same server as the
#                   asset, so on its own it catches corruption, truncation and
#                   mirror tampering -- NOT a compromised upstream release.
#
#   2. Attestation -- Sigstore/SLSA build provenance issued by GitHub, proving
#                   the asset was produced by a specific workflow in a specific
#                   repository. THIS is the actual signature. Pin the workflow
#                   with --signer-workflow so a fork, or some other workflow in
#                   the same repo, cannot satisfy the check.
#
# AT LEAST ONE layer must positively verify and NEITHER may fail. Upstreams
# differ: some publish only checksums, some only provenance. A mismatch in
# either layer always fails; "upstream publishes none of this kind" is only
# tolerated while the other layer succeeded.
#
# Pass --require-checksum / --require-attestation whenever upstream is known to
# publish that kind. Without them, an attacker who can replace a release could
# simply delete the checksum or the attestation and silently downgrade us to
# the weaker single layer.
#
# Usage:
#   ./verify_download.sh --tag <TAG> [options] <file>
#
# Options:
#   --repo OWNER/REPO       Upstream repo (default: 'Source:' in debian/copyright)
#   --tag TAG               Release tag that published the checksum (required)
#   --checksum-asset NAME   Exact checksum asset name, skipping the usual probes
#   --asset-name NAME       Upstream asset name, when the local file has been
#                           renamed (e.g. source.tar.gz -> foo_1.2.orig.tar.gz)
#   --require-checksum      Fail if upstream publishes no checksum for this file
#   --require-attestation   Fail if no build provenance exists for this file
#   --signer-workflow PATH  e.g. astral-sh/uv/.github/workflows/release.yml
#   --predicate-type URI    Attestation predicate to require
#                           (default https://slsa.dev/provenance/v1)
#   --base-url URL          Override where checksum assets are fetched from
#                           (defaults to the GitHub release download URL;
#                           file:// URLs are accepted, which is how the tests
#                           run offline -- it cannot make a bad file pass)
#
# Environment:
#   GITHUB_TOKEN / GH_TOKEN   Avoids API rate limiting (attestation lookup)
# ---------------------------------------------------------------------------
set -uo pipefail

fail() { echo "❌ $*" >&2; exit 1; }
info() { echo "🔎 $*"; }

FILE=""
REPO="${VERIFY_REPO:-}"
TAG=""
CHECKSUM_ASSET=""
ASSET_NAME=""
REQUIRE_ATTESTATION=0
REQUIRE_CHECKSUM=0
SIGNER_WORKFLOW=""
PREDICATE_TYPE="https://slsa.dev/provenance/v1"
BASE_URL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)                 REPO="${2:-}"; shift 2 ;;
    --tag)                  TAG="${2:-}"; shift 2 ;;
    --checksum-asset)       CHECKSUM_ASSET="${2:-}"; shift 2 ;;
    --asset-name)           ASSET_NAME="${2:-}"; shift 2 ;;
    --signer-workflow)      SIGNER_WORKFLOW="${2:-}"; shift 2 ;;
    --predicate-type)       PREDICATE_TYPE="${2:-}"; shift 2 ;;
    --base-url)             BASE_URL="${2:-}"; shift 2 ;;
    --require-attestation)  REQUIRE_ATTESTATION=1; shift ;;
    --require-checksum)     REQUIRE_CHECKSUM=1; shift ;;
    -h|--help)              sed -n '2,40p' "$0"; exit 0 ;;
    -*)                     fail "Unknown option: $1" ;;
    *)                      [ -z "$FILE" ] || fail "Only one file may be verified at a time."
                            FILE="$1"; shift ;;
  esac
done

[ -n "$FILE" ] || fail "No file given. Usage: $0 --tag <TAG> [options] <file>"
[ -f "$FILE" ] || fail "File not found: $FILE"

# --- Resolve upstream repository -------------------------------------------
if [ -z "$REPO" ] && [ -f debian/copyright ]; then
  src="$(grep -m1 -iE '^Source:' debian/copyright | sed -E 's/^[Ss]ource:[[:space:]]*//; s#[[:space:]]*$##; s#/+$##; s#\.git$##')"
  src="${src#http://}"; src="${src#https://}"
  case "$src" in
    github.com/*/*) REPO="$(printf '%s' "${src#github.com/}" | cut -d/ -f1,2)" ;;
  esac
fi
[ -n "$REPO" ] || fail "Cannot determine upstream repo (pass --repo OWNER/REPO or set 'Source:' in debian/copyright)."
case "$REPO" in
  */*) : ;;
  *)   fail "--repo must be OWNER/REPO, got '$REPO'." ;;
esac

# The local file may have been renamed after download (Debian orig tarballs
# always are), so checksum lookups use the name upstream published it under.
LOCALNAME="$(basename "$FILE")"
BASENAME="${ASSET_NAME:-$LOCALNAME}"
[ -n "$TAG" ] || [ -n "$BASE_URL" ] || fail "No --tag given; cannot locate the upstream checksum for $BASENAME."
[ -n "$BASE_URL" ] || BASE_URL="https://github.com/$REPO/releases/download/$TAG"
BASE_URL="${BASE_URL%/}"

if [ "$LOCALNAME" != "$BASENAME" ]; then
  info "Verifying $LOCALNAME (upstream: $BASENAME) against $REPO${TAG:+ @ $TAG}"
else
  info "Verifying $BASENAME against $REPO${TAG:+ @ $TAG}"
fi

# --- Layer 1: checksum ------------------------------------------------------
ACTUAL="$(sha256sum "$FILE" | awk '{print $1}')"
[ -n "$ACTUAL" ] || fail "Could not compute a SHA-256 for $FILE."

# Candidate checksum assets, most specific first. A per-asset file is preferred
# because an aggregate list may legitimately not mention this architecture.
if [ -n "$CHECKSUM_ASSET" ]; then
  CANDIDATES=("$CHECKSUM_ASSET")
else
  CANDIDATES=(
    "${BASENAME}.sha256"
    "${BASENAME}.sha256sum"
    "${BASENAME}.sha256.txt"
    "sha256.sum"
    "SHA256SUMS"
    "sha256sums.txt"
    "checksums.txt"
    "SHASUMS256.txt"
    "SHA2-256SUMS"
    "checksums-bsd"
  )
fi

# Pull the hash for BASENAME out of a checksum file. Handles the shapes seen in
# the wild: "<hash>  name", "<hash> *name" (binary mode), a bare "<hash>", and
# BSD tag format "SHA256 (name) = <hash>" (GNU `sha256sum --tag`, BSD shasum).
extract_hash() { # $1 = checksum file contents
  local content="$1" line="" hash="" esc
  esc="$(printf '%s' "$BASENAME" | sed 's/[][\.*^$/]/\\&/g')"
  line="$(printf '%s\n' "$content" \
    | sed -E 's/\r$//' \
    | grep -E "[[:space:]][*]?(\./)?$esc$" \
    | head -1)"
  if [ -n "$line" ]; then
    hash="$(printf '%s' "$line" | awk '{print $1}')"
  else
    # BSD tag format. The algorithm must be pinned exactly: these files often
    # list CRC32/MD5/SHA1/SHA512 for the same name, and matching the wrong
    # line would compare a SHA-256 against, say, an MD5 and always fail.
    line="$(printf '%s\n' "$content" \
      | sed -E 's/\r$//' \
      | grep -E "^SHA256[[:space:]]*\\($esc\\)[[:space:]]*=" \
      | head -1)"
    if [ -n "$line" ]; then
      hash="$(printf '%s' "$line" | sed -E 's/.*=[[:space:]]*//')"
    fi
  fi
  if [ -z "$hash" ]; then
    # A bare single-hash file (no filename column) belongs to this asset.
    local stripped
    stripped="$(printf '%s' "$content" | tr -d '[:space:]')"
    if printf '%s' "$stripped" | grep -qE '^[0-9a-fA-F]{64}$'; then
      hash="$stripped"
    fi
  fi
  hash="$(printf '%s' "$hash" | tr 'A-F' 'a-f')"
  printf '%s' "$hash" | grep -qE '^[0-9a-f]{64}$' || hash=""
  printf '%s' "$hash"
}

EXPECTED=""
USED_ASSET=""
for asset in "${CANDIDATES[@]}"; do
  content="$(curl -fsSL --max-time 60 "$BASE_URL/$asset" 2>/dev/null)" || continue
  [ -n "$content" ] || continue
  candidate_hash="$(extract_hash "$content")"
  if [ -n "$candidate_hash" ]; then
    EXPECTED="$candidate_hash"
    USED_ASSET="$asset"
    break
  fi
done

CHECKSUM_VERIFIED=0
if [ -z "$EXPECTED" ]; then
  [ "$REQUIRE_CHECKSUM" -eq 1 ] && \
    fail "No upstream SHA-256 published for $BASENAME in $REPO, but --require-checksum was given. Upstream normally publishes one -- treating its absence as an attack, not an accident."
  echo "ℹ️  $REPO publishes no SHA-256 for $BASENAME (tried: ${CANDIDATES[*]})."
elif [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "   expected: $EXPECTED (from $USED_ASSET)" >&2
  echo "   actual:   $ACTUAL" >&2
  fail "CHECKSUM MISMATCH for $BASENAME. The download does not match what upstream published."
else
  CHECKSUM_VERIFIED=1
  info "checksum OK ($USED_ASSET): $ACTUAL"
fi

# --- Layer 2: Sigstore build provenance ------------------------------------
ATTESTATION_VERIFIED=0
if ! command -v gh >/dev/null 2>&1; then
  [ "$REQUIRE_ATTESTATION" -eq 1 ] && \
    fail "gh is required to verify build provenance for $BASENAME but is not installed."
  echo "ℹ️  gh not installed; skipping the provenance check."
fi
if command -v gh >/dev/null 2>&1; then

# Ask first whether provenance exists at all, so that "upstream publishes none"
# and "provenance exists but does not verify" produce different messages -- and
# so that --require-attestation can catch a release that dropped its provenance.
#
# The probe MUST filter on the same predicate type that `gh attestation verify`
# will look for. Some upstreams (deno, for one) publish only a non-SLSA
# predicate such as in-toto's release/v0.2: an unfiltered probe would say
# "provenance exists", the verify would then find no SLSA provenance, and the
# download would be rejected even though nothing is wrong with it.
  HAS_ATTESTATION=0
  pt_enc="$(printf '%s' "$PREDICATE_TYPE" | sed 's/:/%3A/g; s#/#%2F#g')"
  if gh api "repos/$REPO/attestations/sha256:$ACTUAL?predicate_type=$pt_enc" >/dev/null 2>&1; then
    HAS_ATTESTATION=1
  fi

  if [ "$HAS_ATTESTATION" -eq 0 ]; then
    [ "$REQUIRE_ATTESTATION" -eq 1 ] && \
      fail "No $PREDICATE_TYPE attestation published for $BASENAME in $REPO, but --require-attestation was given. Upstream normally signs this asset -- treating its absence as an attack, not an accident."
    echo "ℹ️  $REPO publishes no $PREDICATE_TYPE attestation for $BASENAME."
  else
    verify_args=(attestation verify "$FILE" --repo "$REPO" --predicate-type "$PREDICATE_TYPE")
    [ -n "$SIGNER_WORKFLOW" ] && verify_args+=(--signer-workflow "$SIGNER_WORKFLOW")

    if ! out="$(gh "${verify_args[@]}" 2>&1)"; then
      printf '%s\n' "$out" | sed 's/^/   /' >&2
      fail "BUILD PROVENANCE VERIFICATION FAILED for $BASENAME."
    fi
    ATTESTATION_VERIFIED=1
    info "build provenance OK (${SIGNER_WORKFLOW:-$REPO})"
  fi
fi

# --- Verdict: something must actually have been verified -------------------
if [ "$CHECKSUM_VERIFIED" -eq 0 ] && [ "$ATTESTATION_VERIFIED" -eq 0 ]; then
  fail "NOTHING could be verified for $BASENAME: $REPO publishes neither a usable checksum nor build provenance for it. Refusing to package an unverified download."
fi

layers=""
[ "$CHECKSUM_VERIFIED" -eq 1 ] && layers="checksum"
[ "$ATTESTATION_VERIFIED" -eq 1 ] && layers="${layers:+$layers + }build provenance"
echo "✅ $BASENAME verified ($layers)."
