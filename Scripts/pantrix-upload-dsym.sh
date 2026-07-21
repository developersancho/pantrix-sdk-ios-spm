#!/usr/bin/env bash
#
# Upload dSYMs to Pantrix so iOS crash reports can be symbolicated.
#
# An iOS crash frame is an ASLR-slided address and carries no symbols. The ONLY thing that turns it
# back into a function name is the dSYM, matched by its image's LC_UUID — by nothing else. If the
# dSYM is never uploaded, that build's crashes are a column of hex forever. And dSYMs are deleted
# when a build machine is recycled: this step has a clock on it that nothing else in the pipeline has.
#
# First-time setup (one command) — create a gitignored .pantrixrc with your credentials, add it to
# .gitignore, and print the Xcode snippet to paste. Nothing is created otherwise; this is the only
# route that WRITES a file (the wizard) — every route below only READS the credentials:
#
#   Scripts/pantrix-upload-dsym.sh --init         # prompts for API URL + CI key (or writes placeholders)
#   Scripts/pantrix-upload-dsym.sh --init --force # overwrite an existing .pantrixrc
#
# Three ways to run it — all reuse the same 3-step upload (manifest -> presigned PUT -> commit):
#
#   1) CI / release pipeline (source of truth) — archive, then point at the .xcarchive, whose dSYMs/
#      holds EVERY embedded framework's dSYM (app + PREBUILT binary frameworks like PantrixCore):
#
#        PANTRIX_API_URL=https://api.example.com PANTRIX_CI_KEY=pxu_… \
#          Scripts/pantrix-upload-dsym.sh --archive build/MyApp.xcarchive
#
#   2) Xcode Archive POST-ACTION (recommended for local ⌘⇧A -> TestFlight/App Store) — Scheme -> Archive
#      -> Post-actions -> New Run Script Action (provide build settings from the app target). When Pantrix
#      is added via SPM the script sits in the package checkout, so reference it at that stable path:
#
#        "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/pantrix-sdk-ios-spm/Scripts/pantrix-upload-dsym.sh" \
#          --archive "$ARCHIVE_PATH"
#
#      (If you vendored the script into your own repo instead, use "$SRCROOT/Scripts/pantrix-upload-dsym.sh".)
#      Runs AFTER the archive is assembled, so it sees the COMPLETE dSYMs/ (incl. prebuilt framework
#      dSYMs) and is NOT subject to Xcode 15/16 User Script Sandboxing (unlike a build phase).
#      See Docs/PANTRIX_DSYM_UPLOAD.md for the full step-by-step consumer setup.
#
#   3) Compile-time build phase (opt-in) — a late "Run Script" phase (place it last, like Crashlytics'
#      `run`). Globs EVERY *.dSYM in ${DWARF_DSYM_FOLDER_PATH} — and on current Xcode that folder holds
#      the app's dSYM AND PantrixCore.framework.dSYM, because Xcode's builtin-process-xcframework copies
#      the xcframework's bundled dSYM there at build time. So this route covers the closed-source core
#      too (verified empirically: it declares 2 slices). Trade-off vs routes 1/2: it runs on EVERY build
#      (hence opt-in) and is sandboxed — so the archive routes stay the default for releases.
#      Opt-in via PANTRIX_UPLOAD_DSYM=1; NEVER fails the build. Under ENABLE_USER_SCRIPT_SANDBOXING
#      (Xcode 15/16 default) declare the dSYM folder as an Input File so the script may READ every dSYM
#      inside it (the sandbox denies that file read otherwise — it is not curl's network that's blocked):
#        Input Files: ${DWARF_DSYM_FOLDER_PATH}
#        Script:      "${SRCROOT}/Scripts/pantrix-upload-dsym.sh"
#
# Credentials: PANTRIX_API_URL + PANTRIX_CI_KEY come from the environment (a CI secret) OR a gitignored
# .pantrixrc auto-discovered by walking up from SRCROOT/$PWD (so nothing is passed by hand). The CI key
# is key_type=CI — NOT the SDK ingest key (the backend 401s that) — and must never ship inside the app.
#
# CI mode fails loudly (a green CI that skipped the upload = an unreadable crash months later); the
# post-action / build-phase routes never break the build.
#
# Requirements: macOS with Xcode (dwarfdump, lipo), curl, shasum, plutil. No jq.
#
set -euo pipefail

# ------------------------------ config -------------------------------------

# Required. There is no default on purpose — the SDK itself has no hard-coded endpoint (the host app
# supplies it), and guessing one here would silently upload a customer's symbols to the wrong host.
API_URL="${PANTRIX_API_URL:-}"

# Required. A CI key, NOT the SDK key. The SDK key ships inside the app and anyone can extract it;
# the backend refuses it here (401) precisely so that nobody can poison a project's symbols.
CI_KEY="${PANTRIX_CI_KEY:-}"

# Build-phase mode only. Without it, every developer's local archive would push ~100MB of dSYMs on
# every build. CI mode does not need it: running this script by hand IS the intent.
OPT_IN="${PANTRIX_UPLOAD_DSYM:-0}"

MODE=""            # "ci" | "buildphase"
ARCHIVE=""
BUILD_PHASE=0      # 1 → never exit non-zero
INIT=0             # 1 → run the --init wizard and exit
FORCE=0            # 1 → --init may overwrite an existing .pantrixrc

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# ------------------------------ output -------------------------------------

log()  { printf '[pantrix] %s\n' "$*" >&2; }
warn() { printf '[pantrix] WARNING: %s\n' "$*" >&2; }

# In a build phase this must never break the build; in CI it must break it.
die() {
    printf '[pantrix] ERROR: %s\n' "$*" >&2
    if [ "$BUILD_PHASE" -eq 1 ]; then
        warn "skipping dSYM upload — the build is NOT affected"
        exit 0
    fi
    exit 1
}

usage() {
    # Print the whole leading comment block (line 2 up to the first non-# line) — robust to the block
    # growing, unlike a hard-coded line range.
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit "${1:-0}"
}

# ------------------------------ setup (--init) ------------------------------
# Double-quote a value for a sourced .pantrixrc (escape \ " ` $ so the value survives `. .pantrixrc`).
dq() { printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"`$]/\\&/g')"; }

# `--init`: the wizard. Create a gitignored .pantrixrc at the repo root, ensure .gitignore covers it,
# and print the Xcode snippet to paste. NEVER echoes the CI key back. Env > interactive prompt >
# placeholder. Refuses to clobber an existing file without --force.
do_init() {
    local force="$1"
    local root rc gi api key placeholder=0
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$root" ] || root="$PWD"
    rc="$root/.pantrixrc"
    gi="$root/.gitignore"

    if [ -f "$rc" ] && [ "$force" -ne 1 ]; then
        die "$rc already exists — refusing to overwrite (re-run with: --init --force)"
    fi

    # Environment wins (a CI secret); else prompt when interactive; else leave an editable placeholder.
    api="${PANTRIX_API_URL:-}"
    key="${PANTRIX_CI_KEY:-}"
    if [ -t 0 ]; then
        [ -n "$api" ] || { printf '[pantrix] API base URL (e.g. https://your-host.com/api): ' >&2; IFS= read -r api || true; }
        if [ -z "$key" ]; then
            printf '[pantrix] CI key (key_type=CI, starts pxu_ — input hidden): ' >&2
            IFS= read -r -s key || true
            printf '\n' >&2
        fi
    fi
    [ -n "$api" ] || { api='https://your-host.com/api'; placeholder=1; }
    [ -n "$key" ] || { key='pxu_REPLACE_WITH_YOUR_CI_KEY'; placeholder=1; }

    # Guard the classic mix-up: the px_ SDK ingest key is not the pxu_ CI key (backend 401s it here).
    case "$key" in
        pxu_*|pxu_REPLACE_WITH_YOUR_CI_KEY) ;;
        px_*) warn "that key starts 'px_' — that looks like the SDK INGEST key. dSYM upload needs a CI key (key_type=CI, usually 'pxu_'); the backend rejects the SDK key here (401)." ;;
    esac

    umask 077
    {
        printf '# Pantrix dSYM-upload credentials. Gitignored — NEVER commit this file.\n'
        printf '# PANTRIX_CI_KEY is a CI key (key_type=CI), NOT the px_ SDK ingest key that ships in the app.\n'
        printf 'PANTRIX_API_URL=%s\n' "$(dq "$api")"
        printf 'PANTRIX_CI_KEY=%s\n'  "$(dq "$key")"
    } > "$rc"
    chmod 600 "$rc" 2>/dev/null || true
    log "wrote $rc (chmod 600)"

    if [ -f "$gi" ] && grep -qxF '.pantrixrc' "$gi"; then
        log ".gitignore already ignores .pantrixrc"
    else
        printf '.pantrixrc\n' >> "$gi"
        log "added .pantrixrc to $gi"
    fi

    log ""
    log "Next: add ONE dSYM-upload hook to your app target (see Docs/PANTRIX_DSYM_UPLOAD.md)."
    log "Build phase — Build Phases > + > New Run Script Phase (drag last), Input Files: \${DWARF_DSYM_FOLDER_PATH}:"
    cat >&2 <<'STEP'

  PANTRIX_UPLOAD_DSYM=1 \
    "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/pantrix-sdk-ios-spm/Scripts/pantrix-upload-dsym.sh"

STEP
    log "Or an Archive post-action — Scheme > Edit Scheme > Archive > Post-actions (settings from your app target):"
    cat >&2 <<'STEP'

  "${BUILD_DIR%/Build/*}/SourcePackages/checkouts/pantrix-sdk-ios-spm/Scripts/pantrix-upload-dsym.sh" --archive "$ARCHIVE_PATH"

STEP

    [ "$placeholder" -eq 1 ] && warn "wrote placeholder value(s) — edit $rc and set your real PANTRIX_API_URL / PANTRIX_CI_KEY"
    exit 0
}

# ------------------------------ args ---------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --init)    INIT=1; shift ;;
        --force)   FORCE=1; shift ;;
        --archive) ARCHIVE="${2:-}"; MODE="ci"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) printf 'Unknown argument: %s\n\n' "$1" >&2; usage 2 ;;
    esac
done

# The wizard runs before any upload machinery (no credentials or dSYMs needed — it CREATES the config).
if [ "$INIT" -eq 1 ]; then
    do_init "$FORCE"
fi

if [ -z "$MODE" ]; then
    MODE="buildphase"
    BUILD_PHASE=1
fi

# ------------------------------ config-file discovery -----------------------
# Load PANTRIX_API_URL / PANTRIX_CI_KEY from a gitignored .pantrixrc when the environment didn't
# already provide them (env / CI secret always wins). Search: an explicit PANTRIX_CONFIG, else walk
# up from SRCROOT (build phase / archive post-action) or $PWD (CI) — NOT from the .xcarchive path,
# which lives in ~/Library/Developer/Xcode/Archives, OUTSIDE the repo, so it never contains .pantrixrc.
load_config() {
    local f="${PANTRIX_CONFIG:-}"
    if [ -z "$f" ]; then
        local dir="${SRCROOT:-$PWD}"
        while [ -n "$dir" ] && [ "$dir" != "/" ]; do
            [ -f "$dir/.pantrixrc" ] && { f="$dir/.pantrixrc"; break; }
            dir="$(dirname "$dir")"
        done
    fi
    [ -n "$f" ] && [ -f "$f" ] || return 0
    # shellcheck disable=SC1090
    . "$f"
    API_URL="${API_URL:-${PANTRIX_API_URL:-}}"
    CI_KEY="${CI_KEY:-${PANTRIX_CI_KEY:-}}"
    log "loaded config from $f"
}
load_config

# ------------------------------ collect dSYMs -------------------------------

# Every DWARF binary we intend to upload, one path per line.
DSYM_BINARIES="$TMPDIR_ROOT/binaries.txt"
: > "$DSYM_BINARIES"

collect_from_dsym_bundle() {
    local bundle="$1"
    local dwarf_dir="$bundle/Contents/Resources/DWARF"
    [ -d "$dwarf_dir" ] || { warn "no DWARF directory in $(basename "$bundle") — skipping"; return; }
    # Usually exactly one binary, named after the product rather than after the bundle — do not
    # assume the name, just take what is there.
    local found=0
    for binary in "$dwarf_dir"/*; do
        [ -f "$binary" ] || continue
        printf '%s\n' "$binary" >> "$DSYM_BINARIES"
        found=1
    done
    [ "$found" -eq 1 ] || warn "no DWARF binary in $(basename "$bundle") — skipping"
}

# Guard the incremental-build dSYM race (buildphase mode only). This postBuild script declares the dSYM
# FOLDER as its input, not dsymutil's output, so Xcode's parallel build graph can run it BEFORE dsymutil
# rewrites the app's dSYM for an incremental relink. We would then read the STALE dSYM (the prior build's
# LC_UUID), the backend confirms that old id is "already present", we upload nothing — and THIS build's
# crashes reference a uuid whose dSYM never arrives, so they symbolicate to status="missing" and quietly
# never reach the crash rollup. Detect it by checking the just-linked app binary's uuid against what the
# collected dSYMs cover; if it is missing, the folder's dSYM is stale, so regenerate the matching dSYM
# straight from the binary and upload THAT. dsymutil reads the binary's debug map (the .o files still in
# DerivedData), so the regenerated dSYM is complete. Only touches the app's own dSYM — a prebuilt
# framework's dSYM (a binary-xcframework consumer) is never relinked here and never goes stale.
guard_stale_app_dsym() {
    local app_binary="${TARGET_BUILD_DIR:-}/${EXECUTABLE_PATH:-}"
    [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${EXECUTABLE_PATH:-}" ] && [ -f "$app_binary" ] || return 0

    local covered
    covered="$(while IFS= read -r b; do [ -n "$b" ] && dwarfdump --uuid "$b" 2>/dev/null; done < "$DSYM_BINARIES" \
        | awk '/^UUID:/{print $2}')"

    local missing=0 line uuid
    while IFS= read -r line; do
        case "$line" in UUID:*) ;; *) continue ;; esac
        uuid="$(printf '%s' "$line" | awk '{print $2}')"
        printf '%s\n' "$covered" | grep -qiF "$uuid" && continue
        missing=1
    done < <(dwarfdump --uuid "$app_binary" 2>/dev/null || true)
    [ "$missing" -eq 1 ] || return 0

    warn "app dSYM is STALE — $(basename "$app_binary") was relinked but ${dsym_dir:-the dSYM folder} still holds the prior build's dSYM (an incremental-build race). Regenerating from the binary so this build's crashes symbolicate."
    local regen="$TMPDIR_ROOT/regen-$(basename "$app_binary").dSYM"
    if dsymutil "$app_binary" -o "$regen" 2>/dev/null; then
        collect_from_dsym_bundle "$regen"
    else
        warn "dsymutil could not regenerate the dSYM — this build's crashes will NOT symbolicate; do a clean build (Cmd-Shift-K) and rebuild."
    fi
}

case "$MODE" in
ci)
    [ -n "$ARCHIVE" ] || die "--archive needs a path"
    [ -d "$ARCHIVE" ] || die "no such archive: $ARCHIVE"
    dsym_dir="$ARCHIVE/dSYMs"
    [ -d "$dsym_dir" ] || die "no dSYMs directory in $ARCHIVE (was it archived with dwarf-with-dsym?)"

    shopt -s nullglob
    bundles=("$dsym_dir"/*.dSYM)
    shopt -u nullglob
    [ "${#bundles[@]}" -gt 0 ] || die "no .dSYM bundles in $dsym_dir"
    for bundle in "${bundles[@]}"; do collect_from_dsym_bundle "$bundle"; done

    # Version metadata for the builds UI — never a lookup key, so a miss is not fatal.
    if [ -f "$ARCHIVE/Info.plist" ]; then
        VERSION_NAME="$(plutil -extract ApplicationProperties.CFBundleShortVersionString raw -o - -- "$ARCHIVE/Info.plist" 2>/dev/null || true)"
        VERSION_CODE="$(plutil -extract ApplicationProperties.CFBundleVersion raw -o - -- "$ARCHIVE/Info.plist" 2>/dev/null || true)"
    fi
    ;;
buildphase)
    if [ "$OPT_IN" != "1" ]; then
        log "PANTRIX_UPLOAD_DSYM is not 1 — skipping (set it to 1 to enable dSYM upload)"
        exit 0
    fi
    # Debug builds are DEBUG_INFORMATION_FORMAT=dwarf: the symbols live in the .o files and no dSYM
    # bundle is ever produced. There is nothing to upload and nothing is wrong.
    if [ "${DEBUG_INFORMATION_FORMAT:-}" != "dwarf-with-dsym" ]; then
        log "DEBUG_INFORMATION_FORMAT=${DEBUG_INFORMATION_FORMAT:-<unset>} — no dSYM is produced, nothing to upload"
        exit 0
    fi
    # Upload EVERY dSYM this build produced. On current Xcode that INCLUDES the prebuilt PantrixCore's
    # dSYM: builtin-process-xcframework copies the xcframework's bundled dSYM into this folder at build
    # time (verified — this route declares 2 slices). The archive routes (1/2) stay the release default
    # for robustness (aggregation, no sandbox, version metadata), not because this route misses the core.
    dsym_dir="${DWARF_DSYM_FOLDER_PATH:-}"
    [ -d "$dsym_dir" ] || die "no dSYM folder at ${dsym_dir:-<unset>}"
    shopt -s nullglob
    bundles=("$dsym_dir"/*.dSYM)
    shopt -u nullglob
    [ "${#bundles[@]}" -gt 0 ] || die "no .dSYM bundles in $dsym_dir"
    for bundle in "${bundles[@]}"; do collect_from_dsym_bundle "$bundle"; done
    guard_stale_app_dsym
    VERSION_NAME="${MARKETING_VERSION:-}"
    VERSION_CODE="${CURRENT_PROJECT_VERSION:-}"
    ;;
esac

VERSION_NAME="${VERSION_NAME:-}"
VERSION_CODE="${VERSION_CODE:-}"

[ -s "$DSYM_BINARIES" ] || die "no DWARF binaries found"
[ -n "$API_URL" ] || die "PANTRIX_API_URL is not set"
[ -n "$CI_KEY" ] || die "PANTRIX_CI_KEY is not set"
API_URL="${API_URL%/}"

# ------------------------------ slice out each arch -------------------------

# One row per uploadable slice: <uuid>\t<arch>\t<name>\t<file>\t<sha256>\t<size>
SLICES="$TMPDIR_ROOT/slices.tsv"
: > "$SLICES"
slice_n=0

# Read line-by-line (NOT `for … in $(cat)`): dSYM paths contain SPACES — an Xcode archive lives at
# ".../MyApp DD.MM.YYYY, HH.MM.xcarchive", so word-splitting shattered the path and dwarfdump found
# nothing. Real archives always have spaces; a /tmp test path doesn't — which is exactly how this hid.
while IFS= read -r binary; do
    [ -n "$binary" ] || continue
    name="$(basename "$binary")"

    # `lipo -thin` FAILS on a thin file ("must be a fat file when the -thin option is specified"),
    # and a single-arch dSYM — the common case, including every device-only release build — IS thin.
    # So check first and upload it as-is; do not thin what is already thin.
    is_fat=0
    lipo -info "$binary" 2>/dev/null | grep -q '^Architectures in the fat file' && is_fat=1

    # One line per arch: "UUID: <uuid> (<arch>) <path>". A fat binary has a DIFFERENT UUID per slice,
    # which is exactly why arch is not a lookup dimension: each slice is already its own key.
    while IFS= read -r line; do
        case "$line" in UUID:*) ;; *) continue ;; esac
        uuid="$(printf '%s' "$line" | awk '{print $2}')"
        arch="$(printf '%s' "$line" | awk '{print $3}' | tr -d '()')"
        [ -n "$uuid" ] && [ -n "$arch" ] || { warn "unparsable dwarfdump line: $line"; continue; }

        slice_n=$((slice_n + 1))
        upload_file="$TMPDIR_ROOT/slice-$slice_n"
        if [ "$is_fat" -eq 1 ]; then
            # Upload the THIN inner DWARF, not a tar of the bundle: those bytes are exactly what
            # symbolicator expects at the key it looks under — no untar, no slice selection later.
            lipo -thin "$arch" "$binary" -output "$upload_file" 2>/dev/null \
                || { warn "cannot thin $name to $arch — skipping that slice"; continue; }
        else
            cp "$binary" "$upload_file"
        fi

        sha="$(shasum -a 256 "$upload_file" | awk '{print $1}')"
        size="$(stat -f%z "$upload_file")"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$uuid" "$arch" "$name" "$upload_file" "$sha" "$size" >> "$SLICES"
    done < <(dwarfdump --uuid "$binary" 2>/dev/null || true)
done < "$DSYM_BINARIES"

[ -s "$SLICES" ] || die "no UUIDs found in any dSYM — nothing to upload"
log "found $(wc -l < "$SLICES" | tr -d ' ') slice(s) to declare"

# ------------------------------ 1. manifest ---------------------------------

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

MANIFEST="$TMPDIR_ROOT/manifest.json"
{
    printf '{'
    [ -n "$VERSION_NAME" ] && printf '"versionName":"%s",' "$(json_escape "$VERSION_NAME")"
    # versionCode is a number on the wire; CFBundleVersion is a string and may be "1.2.3" rather than
    # an integer. Only send it when it really is an integer instead of emitting invalid JSON.
    case "$VERSION_CODE" in
        ''|*[!0-9]*) ;;
        *) printf '"versionCode":%s,' "$VERSION_CODE" ;;
    esac
    printf '"files":['
    first=1
    while IFS=$'\t' read -r uuid arch name file sha size; do
        [ $first -eq 1 ] || printf ','
        first=0
        printf '{"type":"MACHO_DSYM","debugId":"%s","sha256":"%s","size":%s,"name":"%s","arch":"%s"}' \
            "$(json_escape "$uuid")" "$sha" "$size" "$(json_escape "$name")" "$(json_escape "$arch")"
    done < "$SLICES"
    printf ']}'
} > "$MANIFEST"

RESPONSE="$TMPDIR_ROOT/manifest-response.json"
# `|| true`, `|| echo 000` DEĞİL: curl başarısız olduğunda -w zaten "000" basar; ikincisi
# onun üstüne bir 000 daha eklerdi ("000000") ve hata mesajı anlamsızlaşırdı.
code="$(curl -sS -o "$RESPONSE" -w '%{http_code}' \
    -X POST "$API_URL/v1/ci/debug-files" \
    -H "Authorization: Bearer $CI_KEY" \
    -H 'Content-Type: application/json' \
    --data-binary "@$MANIFEST" || true)"
code="${code:-000}"

case "$code" in
    200) ;;
    401) die "the API rejected the key (401) — PANTRIX_CI_KEY must be a CI key, not the SDK key" ;;
    000) die "could not reach $API_URL" ;;
    *)   die "manifest failed (HTTP $code): $(cat "$RESPONSE" 2>/dev/null | head -c 400)" ;;
esac

count="$(plutil -extract files raw -o - -- "$RESPONSE" 2>/dev/null || echo 0)"
[ "$count" -gt 0 ] || die "the API returned no files"

# ------------------------------ 2. direct PUT -------------------------------

IDS="$TMPDIR_ROOT/ids.txt"
: > "$IDS"
uploaded=0
skipped=0

i=0
while [ "$i" -lt "$count" ]; do
    id="$(plutil -extract "files.$i.id" raw -o - -- "$RESPONSE")"
    debug_id="$(plutil -extract "files.$i.debugId" raw -o - -- "$RESPONSE")"
    already="$(plutil -extract "files.$i.alreadyPresent" raw -o - -- "$RESPONSE" 2>/dev/null || echo false)"
    printf '%s\n' "$id" >> "$IDS"

    if [ "$already" = "true" ]; then
        # An unchanged build re-run by CI uploads nothing. This is why re-running CI is free.
        skipped=$((skipped + 1))
        i=$((i + 1))
        continue
    fi

    url="$(plutil -extract "files.$i.uploadUrl" raw -o - -- "$RESPONSE")"
    # Match the slice by debugId rather than by position: never key a lookup on an ordinal you did
    # not send. (Measure's `rewriteAppleCrashReport` keys on a response ordinal and drifts.)
    file="$(awk -v u="$debug_id" 'BEGIN{IGNORECASE=1} tolower($1)==tolower(u){print $4; exit}' "$SLICES")"
    [ -n "$file" ] || die "the API returned an unknown debugId: $debug_id"

    # Forward every signed header verbatim, EXCEPT content-length: curl derives it from the file and
    # refuses to have it set by hand. That is fine — the signature binds the exact byte count, so a
    # body of any other size is rejected by storage with a 403 rather than silently accepted.
    header_args=()
    while IFS= read -r key; do
        [ -n "$key" ] || continue
        case "$(printf '%s' "$key" | tr 'A-Z' 'a-z')" in content-length) continue ;; esac
        value="$(plutil -extract "files.$i.headers.$key" raw -o - -- "$RESPONSE")"
        header_args+=(-H "$key: $value")
    done < <(plutil -extract "files.$i.headers" raw -o - -- "$RESPONSE" 2>/dev/null || true)

    # ${arr[@]+"${arr[@]}"} — macOS bash 3.2'de `set -u` + BOŞ dizi = "unbound variable".
    # Ve bu dizi normalde boş: imzalanan tek header content-length ve onu curl kendisi koyuyor.
    put_code="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT ${header_args[@]+"${header_args[@]}"} \
        --upload-file "$file" "$url" || true)"
    put_code="${put_code:-000}"
    case "$put_code" in
        200|204) uploaded=$((uploaded + 1)) ;;
        403) die "storage rejected the upload for $debug_id (403) — the presigned URL expired, or the bytes changed after the manifest was declared" ;;
        000) die "could not reach the storage host in the presigned URL — is MINIO_PUBLIC_ENDPOINT set to an address CI can resolve? (url: ${url%%\?*})" ;;
        *)   die "upload failed for $debug_id (HTTP $put_code)" ;;
    esac
    i=$((i + 1))
done

log "uploaded $uploaded, already present $skipped"

# ------------------------------ 3. commit -----------------------------------

# Nothing is symbolicatable until this succeeds: the bytes sit at a staging key and the backend
# re-derives each LC_UUID from them before promoting. A declared debugId is a content CLAIM; the
# server verifies it once, here.
COMMIT="$TMPDIR_ROOT/commit.json"
{
    printf '{"ids":['
    first=1
    while IFS= read -r id; do
        [ $first -eq 1 ] || printf ','
        first=0
        printf '"%s"' "$id"
    done < "$IDS"
    printf ']}'
} > "$COMMIT"

COMMIT_RESPONSE="$TMPDIR_ROOT/commit-response.json"
commit_code="$(curl -sS -o "$COMMIT_RESPONSE" -w '%{http_code}' \
    -X POST "$API_URL/v1/ci/debug-files/commit" \
    -H "Authorization: Bearer $CI_KEY" \
    -H 'Content-Type: application/json' \
    --data-binary "@$COMMIT" || true)"
commit_code="${commit_code:-000}"

if [ "$commit_code" != "200" ]; then
    # 422 means the bytes did not match the claim. Print WHICH file and WHY — a bare status code
    # would send someone hunting through a 30-dSYM archive by hand.
    n="$(plutil -extract files raw -o - -- "$COMMIT_RESPONSE" 2>/dev/null || echo 0)"
    j=0
    while [ "$j" -lt "$n" ]; do
        if [ "$(plutil -extract "files.$j.committed" raw -o - -- "$COMMIT_RESPONSE" 2>/dev/null || echo true)" = "false" ]; then
            warn "  $(plutil -extract "files.$j.errorCode" raw -o - -- "$COMMIT_RESPONSE" 2>/dev/null): $(plutil -extract "files.$j.error" raw -o - -- "$COMMIT_RESPONSE" 2>/dev/null)"
        fi
        j=$((j + 1))
    done
    die "commit failed (HTTP $commit_code) — no dSYM was accepted for the failed entries"
fi

log "done — $(wc -l < "$IDS" | tr -d ' ') debug file(s) ready for symbolication"
