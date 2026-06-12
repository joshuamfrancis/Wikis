#!/usr/bin/env bash
#
# download_verify.sh
# -----------------------------------------------------------------------------
# Reads a config file, repeatedly downloads the referenced URL (timing each
# run), verifies the file against a base64-encoded CRC-64/NVME checksum, and
# prints an ASCII summary table with per-attempt and aggregate statistics.
#
# Config format (KEY="value"):
#   URL="https://example.com/file.bin"
#   CRC64NVME="q4sUhgp5mIg="     # base64-encoded 8-byte CRC-64/NVME (AWS S3 style)
#   ATTEMPTS=3
#
# Usage:
#   ./download_verify.sh [path/to/config.conf]
#   (defaults to ./config.conf)
# -----------------------------------------------------------------------------

set -uo pipefail

CONFIG_FILE="${1:-config.conf}"

# ----------------------------------------------------------------------------- 
# Helpers
# -----------------------------------------------------------------------------
err()  { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; }
info() { printf '\033[36m[INFO]\033[0m  %s\n' "$*"; }
ok()   { printf '\033[32m[OK]\033[0m    %s\n' "$*"; }

# Read a quoted value for KEY from the config file (no `source`, so the file is
# never executed as code).
get_config() {
    local key="$1" line
    line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$CONFIG_FILE" | head -n1) || true
    line="${line#*=}"            # strip everything up to and including first '='
    line="${line%\"}"; line="${line#\"}"   # strip surrounding double quotes
    line="${line%\'}"; line="${line#\'}"   # strip surrounding single quotes
    printf '%s' "$line"
}

# Compute the CRC-64/NVME of a file and emit it base64-encoded (matching the
# representation AWS S3 uses for x-amz-checksum-crc64nvme).
compute_crc64nvme_b64() {
    python3 - "$1" <<'PYEOF'
import sys, struct, base64

# CRC-64/NVME: width=64, init=FF.., refin=refout=true, xorout=FF..,
# check("123456789")=0xae8b14860a799888.
# 0x9a6c9329ac4bc9b5 is the reflected polynomial (as used by AWS / Linux kernel).
RPOLY = 0x9a6c9329ac4bc9b5

_table = []
for i in range(256):
    crc = i
    for _ in range(8):
        crc = (crc >> 1) ^ RPOLY if (crc & 1) else (crc >> 1)
    _table.append(crc)

def crc64nvme(path):
    crc = 0xffffffffffffffff
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):   # 1 MiB chunks
            for b in chunk:
                crc = _table[(crc ^ b) & 0xff] ^ (crc >> 8)
    return crc ^ 0xffffffffffffffff

digest = struct.pack(">Q", crc64nvme(sys.argv[1]))          # 8 bytes, big-endian
print(base64.b64encode(digest).decode())
PYEOF
}

# Convert a bytes/second value into a human-readable rate.
human_rate() {
    awk -v s="$1" 'BEGIN{
        split("B/s KB/s MB/s GB/s TB/s", u, " "); i=1;
        while (s>=1024 && i<5){s/=1024; i++}
        printf "%.2f %s", s, u[i]
    }'
}

# Convert a byte count into a human-readable size.
human_size() {
    awk -v b="$1" 'BEGIN{
        split("B KB MB GB TB", u, " "); i=1;
        while (b>=1024 && i<5){b/=1024; i++}
        printf "%.2f %s", b, u[i]
    }'
}

# -----------------------------------------------------------------------------
# Load and validate configuration
# -----------------------------------------------------------------------------
[[ -f "$CONFIG_FILE" ]] || { err "Config file not found: $CONFIG_FILE"; exit 1; }

URL=$(get_config URL)
EXPECTED_CRC=$(get_config CRC64NVME)
ATTEMPTS=$(get_config ATTEMPTS)

[[ -n "$URL" ]]      || { err "URL not set in $CONFIG_FILE"; exit 1; }
[[ "$ATTEMPTS" =~ ^[0-9]+$ && "$ATTEMPTS" -gt 0 ]] || {
    err "ATTEMPTS must be a positive integer (got: '${ATTEMPTS:-}')"; exit 1; }
command -v curl   >/dev/null || { err "curl is required";    exit 1; }
command -v python3 >/dev/null || { err "python3 is required"; exit 1; }

info "Config file : $CONFIG_FILE"
info "URL         : $URL"
info "Attempts    : $ATTEMPTS"
info "Expected CRC: ${EXPECTED_CRC:-<none provided>}"
echo

# -----------------------------------------------------------------------------
# Result accumulators (parallel arrays, indexed per attempt)
# -----------------------------------------------------------------------------
declare -a R_TIME R_SPEED R_DLSTAT R_CKSTAT
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# -----------------------------------------------------------------------------
# Download loop
# -----------------------------------------------------------------------------
for (( i = 1; i <= ATTEMPTS; i++ )); do
    outfile="$WORKDIR/download_$i.bin"
    info "Attempt $i/$ATTEMPTS: downloading..."

    # --progress-bar -> live progress to the terminal (stderr)
    # -w '...'       -> machine-readable metrics captured to stdout
    if metrics=$(curl -fSL --progress-bar \
                      -o "$outfile" \
                      -w '%{time_total} %{speed_download} %{size_download} %{http_code}' \
                      "$URL" 2>/tmp/_curl_progress_$$); then
        cat /tmp/_curl_progress_$$ >&2       # show the captured progress bar
        read -r t_total speed size http <<<"$metrics"
        R_TIME[$i]="$t_total"
        R_SPEED[$i]="$speed"
        R_DLSTAT[$i]="OK"
        ok "Attempt $i: $(human_size "$size") in ${t_total}s (HTTP $http, $(human_rate "$speed"))"
    else
        cat /tmp/_curl_progress_$$ >&2 2>/dev/null || true
        R_TIME[$i]="-"
        R_SPEED[$i]="-"
        R_DLSTAT[$i]="FAIL"
        R_CKSTAT[$i]="SKIPPED"
        err "Attempt $i: download failed"
        rm -f /tmp/_curl_progress_$$
        continue
    fi
    rm -f /tmp/_curl_progress_$$

    # ---- checksum verification -------------------------------------------
    if [[ -n "$EXPECTED_CRC" ]]; then
        info "Attempt $i: computing CRC-64/NVME checksum..."
        actual_crc=$(compute_crc64nvme_b64 "$outfile")
        if [[ "$actual_crc" == "$EXPECTED_CRC" ]]; then
            R_CKSTAT[$i]="VERIFIED"
            ok "Attempt $i: checksum VERIFIED ($actual_crc)"
        else
            R_CKSTAT[$i]="MISMATCH"
            err "Attempt $i: checksum MISMATCH (expected $EXPECTED_CRC, got $actual_crc)"
        fi
    else
        R_CKSTAT[$i]="NO-REF"
        info "Attempt $i: no reference checksum in config; skipping verification"
    fi
    echo
done

# -----------------------------------------------------------------------------
# Aggregate statistics (averaged over successful downloads only)
# -----------------------------------------------------------------------------
avg_time=$(awk -v n="$ATTEMPTS" 'BEGIN{s=0;c=0}
    {if($1!="-"){s+=$1;c++}} END{if(c>0)printf "%.3f",s/c; else printf "-"}' \
    < <(for ((i=1;i<=ATTEMPTS;i++)); do echo "${R_TIME[$i]}"; done))

avg_speed_raw=$(awk 'BEGIN{s=0;c=0}
    {if($1!="-"){s+=$1;c++}} END{if(c>0)printf "%.0f",s/c; else printf ""}' \
    < <(for ((i=1;i<=ATTEMPTS;i++)); do echo "${R_SPEED[$i]}"; done))
avg_speed_h="-"
[[ -n "$avg_speed_raw" ]] && avg_speed_h=$(human_rate "$avg_speed_raw")

success_count=0
for ((i=1;i<=ATTEMPTS;i++)); do [[ "${R_DLSTAT[$i]}" == "OK" ]] && ((success_count++)); done

# -----------------------------------------------------------------------------
# ASCII summary table
# -----------------------------------------------------------------------------
sep="+---------+------------+----------------+----------+------------------+"
printf '\n%s\n' "$sep"
printf '| %-7s | %-10s | %-14s | %-8s | %-16s |\n' \
       "Attempt" "Time (s)" "Speed" "Download" "Checksum"
printf '%s\n' "$sep"
for ((i=1;i<=ATTEMPTS;i++)); do
    if [[ "${R_SPEED[$i]}" == "-" ]]; then sp="-"; else sp=$(human_rate "${R_SPEED[$i]}"); fi
    printf '| %-7s | %-10s | %-14s | %-8s | %-16s |\n' \
           "$i" "${R_TIME[$i]}" "$sp" "${R_DLSTAT[$i]}" "${R_CKSTAT[$i]}"
done
printf '%s\n' "$sep"
printf '| %-7s | %-10s | %-14s | %-8s | %-16s |\n' \
       "AVERAGE" "$avg_time" "$avg_speed_h" "$success_count/$ATTEMPTS" ""
printf '%s\n\n' "$sep"

info "Successful downloads: $success_count/$ATTEMPTS"
info "Average time        : ${avg_time}s"
info "Average speed       : ${avg_speed_h}"

# Exit non-zero if any download failed or any checksum mismatched.
rc=0
for ((i=1;i<=ATTEMPTS;i++)); do
    [[ "${R_DLSTAT[$i]}" == "OK" ]] || rc=1
    [[ "${R_CKSTAT[$i]}" == "MISMATCH" ]] && rc=1
done
exit "$rc"
