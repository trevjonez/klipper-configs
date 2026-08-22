#!/usr/bin/env bash
# Voron firmware build/flash driver.
#
# Six MCUs, three flash methods, one ordering constraint (main board last).
# Everything here was validated against a real 0.12 -> 0.13 upgrade on
# 2026-08-22; see docs/voron-upgrade.md in the home-network repo.
#
#   ./voron-fw.sh list                 # boards, methods, current versions
#   ./voron-fw.sh build all            # build every image
#   ./voron-fw.sh flash mmu drybox     # flash specific boards
#   ./voron-fw.sh run all              # build all, then flash all, in order
#   ./voron-fw.sh run all --from ebb   # resume: skip boards before ebb
#   ./voron-fw.sh verify               # are all six on one version?
#
# Flags: --dry-run  --yes  --keep-klipper-running
set -euo pipefail

KLIPPER=${KLIPPER:-$HOME/klipper}
KATAPULT=${KATAPULT:-$HOME/katapult}
CFGDIR=${CFGDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
OUTDIR=${OUTDIR:-$HOME/fw-out}
STATE=${STATE:-$HOME/.voron-fw-state}
LASTBUILT="$OUTDIR/.last-built"
MOONRAKER=${MOONRAKER:-http://127.0.0.1:7125}

DRY=0; ASSUME_YES=0; KEEP_KLIPPER=0; FROM=""

# name|config|method|target|description
#   rp2040   USB. `make flash` with a by-id path does a 1200-baud DTR touch to
#            reach the ROM bootloader. No BOOTSEL button needed.
#   katapult CAN. flashtool asks the running Klipper firmware to reboot into
#            Katapult, so the board does NOT need to be in the bootloader first.
#   sdcard   Writes firmware.bin to the onboard SD over USB serial. The BTT
#            bootloader only reads it on a COLD BOOT -- a power cycle, not a reset.
# Main board last: it is the only one whose recovery needs physical access.
BOARDS=(
"mmu|mmb-g0b1-mmu|katapult|ff345a743db9|MMB CAN V1.0 (MMU) on CAN"
"drybox|mmb-g0b1-drybox|katapult|d9626e1b839e|MMB CAN V1.0 (drybox) on CAN"
"hbb|rp2040-hbb-eddy|rp2040|/dev/serial/by-id/usb-Klipper_rp2040_45474E621B056C7A-if00|HBB&FE macro pad on USB"
"eddy|rp2040-hbb-eddy|rp2040|/dev/serial/by-id/usb-Klipper_rp2040_504434031060B01C-if00|BTT Eddy on USB (via EBB hub)"
"ebb|rp2040-ebb|rp2040|/dev/serial/by-id/usb-Klipper_rp2040_5044340310CA481C-if00|EBB SB2209 USB toolhead"
"main|octopus-f429|sdcard|/dev/serial/by-id/usb-Klipper_stm32f429xx_0D0028001647323037343634-if00|Octopus Pro F429 via SD card"
)
SDCARD_BOARD_ID="btt-octopus-pro-f429-v1.0"
declare -A MCU_NAME=( [mmu]="mmu" [drybox]="DRYBOX" [hbb]="HBB" [eddy]="EDDY" [ebb]="EBB" [main]="mcu" )

c()   { printf '\033[%sm%s\033[0m' "$1" "$2"; }
info(){ printf '%s %s\n' "$(c '1;34' '::')" "$*"; }
ok()  { printf '%s %s\n' "$(c '1;32' 'ok')" "$*"; }
warn(){ printf '%s %s\n' "$(c '1;33' '!!')" "$*"; }
die() { printf '%s %s\n' "$(c '1;31' 'xx')" "$*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then printf '   %s %s\n' "$(c '0;36' 'would run:')" "$*"; else "$@"; fi; }

field()  { echo "$1" | cut -d'|' -f"$2"; }
lookup() { local n="$1" b; for b in "${BOARDS[@]}"; do [ "$(field "$b" 1)" = "$n" ] && { echo "$b"; return 0; }; done; return 1; }
all_names(){ local b; for b in "${BOARDS[@]}"; do field "$b" 1; done; }
mark(){ [ "$DRY" = 1 ] && return 0; printf '%s %s %s\n' "$(date -Is)" "$1" "$2" >> "$STATE"; }

confirm() {
    [ "$ASSUME_YES" = 1 ] && return 0
    [ "$DRY" = 1 ] && return 0
    printf '%s %s [y/N] ' "$(c '1;33' '??')" "$1"
    read -r a </dev/tty
    [[ "$a" =~ ^[Yy]$ ]]
}

# ---------------------------------------------------------------- preconditions

# `pi` needs passwordless sudo: rp2040_flash touches raw USB as root, and a
# missing sudoers rule fails MID-SEQUENCE with "a terminal is required".
require_sudo() {
    [ "$DRY" = 1 ] && return 0
    sudo -n true 2>/dev/null && return 0
    die "passwordless sudo is required (rp2040_flash needs root).
     Fix: echo 'pi ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/010_pi-nopasswd
          sudo chmod 0440 /etc/sudoers.d/010_pi-nopasswd && sudo visudo -c"
}

# Returns: printing | idle | klippy-error | unreachable
# klippy sitting in error is NORMAL mid-upgrade (host ahead of MCU firmware) and
# must not block flashing -- that is exactly when you need to flash.
printer_state() {
    local body st
    body=$(curl -s -m 5 "$MOONRAKER/printer/info" 2>/dev/null) || { echo unreachable; return; }
    [ -z "$body" ] && { echo unreachable; return; }
    st=$(printf '%s' "$body" | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["result"].get("state",""))
except Exception: print("")' 2>/dev/null)
    case "$st" in
        ready)   printf '%s' "$body" | python3 -c 'import json,sys,urllib.request
d=json.load(urllib.request.urlopen("'"$MOONRAKER"'/printer/objects/query?print_stats",timeout=5))
print(d["result"]["status"]["print_stats"]["state"])' 2>/dev/null || echo idle ;;
        error|shutdown|startup) echo klippy-error ;;
        "")      echo unreachable ;;
        *)       echo "$st" ;;
    esac
}

require_idle() {
    local st; st=$(printer_state)
    case "$st" in
        printing|paused) die "printer is $st -- refusing to touch firmware" ;;
        klippy-error)    info "printer state: klippy in error (expected mid-upgrade)" ;;
        unreachable)     warn "moonraker unreachable; cannot confirm printer is idle" ;;
        *)               info "printer state: $st" ;;
    esac
}

# systemctl needs a tty for sudo on some installs; moonraker never does.
svc() { run curl -s -m 90 -X POST "$MOONRAKER/machine/services/$1?service=klipper" >/dev/null; }
klipper_stop()  { [ "$KEEP_KLIPPER" = 1 ] && return 0; info "stopping klipper (via moonraker)"; svc stop;  [ "$DRY" = 1 ] || sleep 3; }
klipper_start() { [ "$KEEP_KLIPPER" = 1 ] && return 0; info "starting klipper (via moonraker)"; svc start; [ "$DRY" = 1 ] || sleep 3; }

# ---------------------------------------------------------------- build

# out/ is shared across architectures and out/board is a per-arch symlink, so a
# build for one target leaves the tree unusable for another. Every flash method
# reads from out/ (rp2040 via `make flash`, sdcard via out/klipper.dict), so the
# tree must match the board being flashed -- not just the image file.
ensure_built() {
    local cfg="$1" cfgfile="$CFGDIR/$1.config"
    [ -f "$cfgfile" ] || die "missing config: $cfgfile"
    if [ "$DRY" != 1 ] && [ -f "$LASTBUILT" ] && [ "$(cat "$LASTBUILT")" = "$cfg" ]; then
        info "  out/ already holds $cfg"
        return 0
    fi
    info "  building $cfg (make clean first -- shared out/)"
    run make -C "$KLIPPER" clean
    run make -C "$KLIPPER" KCONFIG_CONFIG="$cfgfile"
    [ "$DRY" = 1 ] && return 0
    mkdir -p "$OUTDIR"
    # rp2040 emits klipper.uf2; stm32 emits klipper.bin. Copying .bin blindly
    # aborts the whole run under `set -e`.
    local src=""
    for cand in "$KLIPPER/out/klipper.bin" "$KLIPPER/out/klipper.uf2"; do
        [ -f "$cand" ] && { src="$cand"; break; }
    done
    [ -n "$src" ] || die "$cfg: build produced no klipper.bin or klipper.uf2"
    cp "$src" "$OUTDIR/$cfg.${src##*.}"
    echo "$cfg" > "$LASTBUILT"
    ok "  built $OUTDIR/$cfg.${src##*.} ($(stat -c%s "$OUTDIR/$cfg.${src##*.}") bytes)"
}

build_one() { local b n; b=$(lookup "$1") || die "unknown board: $1"; n=$(field "$b" 1)
    info "build $n"; ensure_built "$(field "$b" 2)"; mark build "$n"; }

build_set() { local n; for n in "$@"; do build_one "$n"; done; }

# ---------------------------------------------------------------- flash

rp2040_in_bootloader() { lsusb 2>/dev/null | grep -qi "2e8a:0003"; }

# `make flash FLASH_DEVICE=<by-id>` does the 1200-baud touch, then races its own
# reset: the device re-enumerates as 2e8a:0003 and flash_usb.py dies looking for
# the old sysfs busnum. The board IS in the bootloader at that point, so retry
# against the raw id. Observed on every rp2040 board on this machine.
flash_rp2040() {
    local n="$1" cfg="$2" target="$3"
    if [ "$DRY" = 1 ]; then
        run make -C "$KLIPPER" KCONFIG_CONFIG="$CFGDIR/$cfg.config" flash FLASH_DEVICE="$target"
        return 0
    fi
    if [ -e "$target" ]; then
        if make -C "$KLIPPER" KCONFIG_CONFIG="$CFGDIR/$cfg.config" flash FLASH_DEVICE="$target"; then
            return 0
        fi
        warn "  $n: by-id flash failed; checking for a board in the ROM bootloader"
        sleep 2
    else
        warn "  $n: $target absent -- likely already in the ROM bootloader"
    fi
    rp2040_in_bootloader || die "$n: no 2e8a:0003 device present. Board may be unpowered,
     or already flashed. Check: lsusb | grep 2e8a"
    info "  $n: retrying via 2e8a:0003"
    make -C "$KLIPPER" KCONFIG_CONFIG="$CFGDIR/$cfg.config" flash FLASH_DEVICE=2e8a:0003
}

flash_one() {
    local b n cfg method target desc bin
    b=$(lookup "$1") || die "unknown board: $1"
    n=$(field "$b" 1); cfg=$(field "$b" 2); method=$(field "$b" 3)
    target=$(field "$b" 4); desc=$(field "$b" 5)

    info "flash $n -- $desc"
    ensure_built "$cfg"          # every method reads out/, not just the image
    bin="$OUTDIR/$cfg.bin"

    case "$method" in
      katapult)
        # No presence pre-check: `flashtool -q` lists only boards ALREADY in the
        # bootloader, and canbus_query lists only nodes without an assigned id.
        # A healthy board running Klipper appears in neither. flashtool -u sends
        # the reboot-to-bootloader request itself.
        [ -f "$bin" ] || [ "$DRY" = 1 ] || die "no image for $n at $bin"
        confirm "flash $n (CAN uuid $target)?" || { warn "skipped $n"; return 0; }
        run "$KATAPULT/scripts/flashtool.py" -i can0 -u "$target" -f "$bin"
        ;;
      rp2040)
        confirm "flash $n (USB $(basename "$target"))?" || { warn "skipped $n"; return 0; }
        flash_rp2040 "$n" "$cfg" "$target"
        ;;
      sdcard)
        [ "$DRY" = 1 ] || [ -e "$target" ] || die "$n: $target not present"
        confirm "flash $n via SD card ($SDCARD_BOARD_ID)?" || { warn "skipped $n"; return 0; }
        run "$KLIPPER/scripts/flash-sdcard.sh" "$target" "$SDCARD_BOARD_ID"
        warn "  $n writes firmware.bin to the SD card; the BTT bootloader reads it"
        warn "  only on a COLD BOOT. Power cycle the printer, then run: $0 verify"
        ;;
      *) die "unknown method: $method" ;;
    esac
    ok "flashed $n"
    mark flash "$n"
}

# ---------------------------------------------------------------- verify

verify() {
    info "querying running MCU versions"
    python3 - "$MOONRAKER" <<'PY'
import json,sys,urllib.parse,urllib.request
base=sys.argv[1]
try:
    objs=json.load(urllib.request.urlopen(base+"/printer/objects/list",timeout=10))["result"]["objects"]
except Exception as e:
    print("   klippy not answering (%s)." % e.__class__.__name__)
    print("   If klipper is stopped or in error, start it and re-run verify.")
    sys.exit(2)
mcus=[o for o in objs if o=="mcu" or o.startswith("mcu ")]
q="&".join(urllib.parse.quote(m) for m in mcus)
st=json.load(urllib.request.urlopen(base+"/printer/objects/query?"+q,timeout=10))["result"]["status"]
vers={}
for m in mcus:
    d=st.get(m,{}); v=d.get("mcu_version","?")
    vers.setdefault(v,[]).append(m)
    print("   %-12s %-30s INITIAL_PINS=%s" % (m, v, d.get("mcu_constants",{}).get("INITIAL_PINS","-")))
print()
if len(vers)==1:
    print("   all %d MCUs on %s" % (len(mcus), list(vers)[0])); sys.exit(0)
print("   MIXED VERSIONS -- a board was missed or needs a power cycle:")
for v,ms in vers.items(): print("     %s  <- %s" % (v, ", ".join(ms)))
sys.exit(1)
PY
}

list_boards() {
    printf '%-8s %-24s %-9s %s\n' BOARD CONFIG METHOD DESCRIPTION
    local b
    for b in "${BOARDS[@]}"; do
        printf '%-8s %-24s %-9s %s\n' "$(field "$b" 1)" "$(field "$b" 2).config" "$(field "$b" 3)" "$(field "$b" 5)"
    done
    echo
    echo "out/ currently holds: $([ -f "$LASTBUILT" ] && cat "$LASTBUILT" || echo 'unknown')"
    echo "images: $OUTDIR    state: $STATE"
    echo "printer: $(printer_state)"
}

# ---------------------------------------------------------------- main

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

CMD="${1:-}"; shift || true
TARGETS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1 ;;
        --yes|-y)  ASSUME_YES=1 ;;
        --keep-klipper-running) KEEP_KLIPPER=1 ;;
        --from)    FROM="${2:-}"; shift ;;
        -h|--help) usage 0 ;;
        -*)        die "unknown flag: $1" ;;
        *)         TARGETS+=("$1") ;;
    esac
    shift
done

SEL=()
resolve() {
    SEL=(); local list=() n
    if [ "${#TARGETS[@]}" -eq 0 ] || [ "${TARGETS[0]}" = "all" ]; then
        while read -r n; do list+=("$n"); done < <(all_names)
    else
        list=("${TARGETS[@]}")
    fi
    for n in "${list[@]}"; do
        lookup "$n" >/dev/null || die "unknown board: $n (known: $(all_names | tr '\n' ' '))"
    done
    if [ -n "$FROM" ]; then
        lookup "$FROM" >/dev/null || die "--from: unknown board '$FROM'"
        local out=() hit=0
        for n in "${list[@]}"; do
            [ "$n" = "$FROM" ] && hit=1
            [ "$hit" = 1 ] && out+=("$n")
        done
        [ "${#out[@]}" -gt 0 ] || die "--from: '$FROM' is not in the selected boards"
        list=("${out[@]}")
    fi
    SEL=("${list[@]}")
}

flash_sequence() {
    require_sudo
    require_idle
    klipper_stop
    local n
    for n in "${SEL[@]}"; do flash_one "$n"; done
    klipper_start
    [ "$DRY" = 1 ] || sleep 6
    verify || warn "verify reported a problem -- see above"
}

case "$CMD" in
  list)   list_boards ;;
  build)  resolve; info "boards: ${SEL[*]}"; build_set "${SEL[@]}" ;;
  flash)  resolve; info "boards: ${SEL[*]}"; flash_sequence ;;
  run)    resolve; info "boards: ${SEL[*]}"; build_set "${SEL[@]}"; flash_sequence ;;
  verify) verify ;;
  reset)  confirm "clear progress state?" && rm -f "$STATE" "$LASTBUILT" && ok "state cleared" ;;
  ""|-h|--help) usage 0 ;;
  *)      die "unknown command: $CMD (try --help)" ;;
esac
