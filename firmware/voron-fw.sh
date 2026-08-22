#!/usr/bin/env bash
# Voron firmware build/flash driver.
#
# Six MCUs, three flash methods, one ordering constraint (main board last).
# Every board can be flashed over the CLI provided it is currently running
# working firmware -- see docs/voron-upgrade.md in the home-network repo.
#
#   ./voron-fw.sh list                 # boards, methods, current state
#   ./voron-fw.sh build all            # build every image
#   ./voron-fw.sh build ebb            # build one
#   ./voron-fw.sh flash mmu drybox     # flash specific boards
#   ./voron-fw.sh run all              # build all, then flash all, in order
#   ./voron-fw.sh run all --from ebb   # resume: skip boards before ebb
#   ./voron-fw.sh verify               # compare running versions against built
#
# Flags: --dry-run  --yes  --keep-klipper-running
set -euo pipefail

KLIPPER=${KLIPPER:-$HOME/klipper}
KATAPULT=${KATAPULT:-$HOME/katapult}
CFGDIR=${CFGDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
OUTDIR=${OUTDIR:-$HOME/fw-out}
STATE=${STATE:-$HOME/.voron-fw-state}
MOONRAKER=${MOONRAKER:-http://127.0.0.1:7125}

DRY=0; ASSUME_YES=0; KEEP_KLIPPER=0; FROM=""

# name|config|method|target|description
#   method: rp2040  (USB, 1200-baud DTR touch into ROM bootloader)
#           katapult (CAN, reboot-to-bootloader over CAN)
#           sdcard   (writes to onboard SD over USB serial, BTT bootloader)
# Order matters: main board LAST. Its flash offset is inferred, so everything
# else should be known-good before it is touched.
BOARDS=(
"mmu|mmb-g0b1|katapult|ff345a743db9|MMB stm32g0b1 (MMU) on CAN"
"drybox|mmb-g0b1|katapult|d9626e1b839e|MMB stm32g0b1 (drybox) on CAN"
"hbb|rp2040-hbb-eddy|rp2040|/dev/serial/by-id/usb-Klipper_rp2040_45474E621B056C7A-if00|HBB rp2040 on USB"
"eddy|rp2040-hbb-eddy|rp2040|/dev/serial/by-id/usb-Klipper_rp2040_504434031060B01C-if00|BTT Eddy rp2040 on USB"
"ebb|rp2040-ebb|rp2040|/dev/serial/by-id/usb-Klipper_rp2040_5044340310CA481C-if00|EBB toolhead rp2040 on USB"
"main|octopus-f429|sdcard|/dev/serial/by-id/usb-Klipper_stm32f429xx_0D0028001647323037343634-if00|Octopus Pro F429 via SD card"
)
SDCARD_BOARD_ID="btt-octopus-pro-f429-v1.0"

# Klipper MCU names, for verify. Keyed to board names above.
declare -A MCU_NAME=( [mmu]="mmu" [drybox]="DRYBOX" [hbb]="HBB" [eddy]="EDDY" [ebb]="EBB" [main]="mcu" )

c()  { printf '\033[%sm%s\033[0m' "$1" "$2"; }
info(){ printf '%s %s\n' "$(c '1;34' '::')" "$*"; }
ok()  { printf '%s %s\n' "$(c '1;32' 'ok')" "$*"; }
warn(){ printf '%s %s\n' "$(c '1;33' '!!')" "$*"; }
die() { printf '%s %s\n' "$(c '1;31' 'xx')" "$*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then printf '   %s %s\n' "$(c '0;36' 'would run:')" "$*"; else "$@"; fi; }

field()  { echo "$1" | cut -d'|' -f"$2"; }
lookup() { local n="$1"; for b in "${BOARDS[@]}"; do [ "$(field "$b" 1)" = "$n" ] && { echo "$b"; return 0; }; done; return 1; }
all_names(){ for b in "${BOARDS[@]}"; do field "$b" 1; done; }

mark(){ [ "$DRY" = 1 ] && return 0; printf '%s %s %s\n' "$(date -Is)" "$1" "$2" >> "$STATE"; }
done_p(){ [ -f "$STATE" ] && grep -q " $1 $2\$" "$STATE"; }

confirm() {
    [ "$ASSUME_YES" = 1 ] && return 0
    [ "$DRY" = 1 ] && return 0
    printf '%s %s [y/N] ' "$(c '1;33' '??')" "$1"
    read -r a </dev/tty
    [[ "$a" =~ ^[Yy]$ ]]
}

printer_state() {
    curl -s -m 5 "$MOONRAKER/printer/objects/query?print_stats" 2>/dev/null \
      | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["status"]["print_stats"]["state"])' 2>/dev/null \
      || echo "unreachable"
}

require_idle() {
    local st; st=$(printer_state)
    case "$st" in
        printing|paused) die "printer is $st -- refusing to touch firmware" ;;
        unreachable)     warn "moonraker unreachable; cannot confirm printer is idle" ;;
        *)               info "printer state: $st" ;;
    esac
}

klipper_stop()  { [ "$KEEP_KLIPPER" = 1 ] && return 0; info "stopping klipper"; run sudo systemctl stop klipper; }
klipper_start() { [ "$KEEP_KLIPPER" = 1 ] && return 0; info "starting klipper"; run sudo systemctl start klipper; }

# ---------------------------------------------------------------- build

build_one() {
    local b n cfg
    b=$(lookup "$1") || die "unknown board: $1"
    n=$(field "$b" 1); cfg=$(field "$b" 2)
    local cfgfile="$CFGDIR/$cfg.config"
    [ -f "$cfgfile" ] || die "missing config: $cfgfile"

    info "build $n  (config: $cfg.config)"
    mkdir -p "$OUTDIR"
    # out/ is shared across architectures and out/board is a per-arch symlink.
    # Skipping clean silently links objects from the previous target.
    run make -C "$KLIPPER" clean
    run make -C "$KLIPPER" KCONFIG_CONFIG="$cfgfile"
    run cp "$KLIPPER/out/klipper.bin" "$OUTDIR/$cfg.bin"
    [ "$DRY" = 1 ] || ok "built $OUTDIR/$cfg.bin ($(stat -c%s "$OUTDIR/$cfg.bin") bytes)"
    mark build "$n"
}

# Several boards share a config; build each distinct config once.
build_set() {
    local seen=" " n b cfg
    for n in "$@"; do
        b=$(lookup "$n") || die "unknown board: $n"
        cfg=$(field "$b" 2)
        case "$seen" in *" $cfg "*) info "build $n  (reuses $cfg.bin)"; continue;; esac
        seen+="$cfg "
        build_one "$n"
    done
}

# ---------------------------------------------------------------- flash

present_katapult() {
    "$KATAPULT/scripts/flashtool.py" -i can0 -q 2>/dev/null | grep -qi "$1"
}

flash_one() {
    local b n cfg method target desc bin
    b=$(lookup "$1") || die "unknown board: $1"
    n=$(field "$b" 1); cfg=$(field "$b" 2); method=$(field "$b" 3)
    target=$(field "$b" 4); desc=$(field "$b" 5)
    bin="$OUTDIR/$cfg.bin"
    [ -f "$bin" ] || [ "$DRY" = 1 ] || die "no image for $n -- run: $0 build $n"

    info "flash $n -- $desc"
    case "$method" in
      katapult)
        if [ "$DRY" != 1 ] && ! present_katapult "$target"; then
            die "$n: uuid $target not answering on can0. Is klipper stopped and the board powered?"
        fi
        confirm "flash $n (CAN uuid $target)?" || { warn "skipped $n"; return 0; }
        run "$KATAPULT/scripts/flashtool.py" -i can0 -u "$target" -f "$bin"
        ;;
      rp2040)
        [ "$DRY" = 1 ] || [ -e "$target" ] || die "$n: $target not present"
        confirm "flash $n (USB $(basename "$target"))?" || { warn "skipped $n"; return 0; }
        # Passing the by-id path (not 2e8a:0003) lets flash_usb.py do the
        # 1200-baud DTR touch, so no BOOTSEL button is needed.
        run make -C "$KLIPPER" KCONFIG_CONFIG="$CFGDIR/$cfg.config" flash FLASH_DEVICE="$target"
        ;;
      sdcard)
        [ "$DRY" = 1 ] || [ -e "$target" ] || die "$n: $target not present"
        warn "main board: flash offset is inferred (32KiB bootloader, 12MHz crystal)."
        warn "if wrong, USB will not enumerate and recovery needs the SD card pulled."
        confirm "flash $n via SD card ($SDCARD_BOARD_ID)?" || { warn "skipped $n"; return 0; }
        run "$KLIPPER/scripts/flash-sdcard.sh" "$target" "$SDCARD_BOARD_ID"
        ;;
      *) die "unknown method: $method" ;;
    esac
    ok "flashed $n"
    mark flash "$n"
}

# ---------------------------------------------------------------- verify

verify() {
    info "querying running MCU versions"
    curl -s -m 10 "$MOONRAKER/printer/objects/list" >/dev/null 2>&1 \
      || { warn "moonraker unreachable -- is klipper started?"; return 1; }
    python3 - "$MOONRAKER" <<'PY'
import json,sys,urllib.parse,urllib.request
base=sys.argv[1]
objs=json.load(urllib.request.urlopen(base+"/printer/objects/list",timeout=10))["result"]["objects"]
mcus=[o for o in objs if o=="mcu" or o.startswith("mcu ")]
q="&".join(urllib.parse.quote(m) for m in mcus)
st=json.load(urllib.request.urlopen(base+"/printer/objects/query?"+q,timeout=10))["result"]["status"]
vers={}
for m in mcus:
    v=st.get(m,{}).get("mcu_version","?")
    vers.setdefault(v,[]).append(m)
    print("   %-12s %s" % (m, v))
print()
if len(vers)==1: print("   all MCUs on a single version:", list(vers)[0])
else:
    print("   MIXED VERSIONS -- a board was missed:")
    for v,ms in vers.items(): print("     %s  <- %s" % (v, ", ".join(ms)))
    sys.exit(1)
PY
}

# ---------------------------------------------------------------- list

list_boards() {
    printf '%-8s %-24s %-9s %-8s %s\n' BOARD CONFIG METHOD STATE DESCRIPTION
    for b in "${BOARDS[@]}"; do
        local n c m d s=""
        n=$(field "$b" 1); c=$(field "$b" 2); m=$(field "$b" 3); d=$(field "$b" 5)
        done_p build "$n" && s="built"
        done_p flash "$n" && s="flashed"
        printf '%-8s %-24s %-9s %-8s %s\n' "$n" "$c.config" "$m" "${s:--}" "$d"
    done
    echo
    echo "state file: $STATE   images: $OUTDIR"
    echo "printer:    $(printer_state)"
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
        --from)    FROM="$2"; shift ;;
        -h|--help) usage 0 ;;
        -*)        die "unknown flag: $1" ;;
        *)         TARGETS+=("$1") ;;
    esac
    shift
done

# Resolve the target list into SEL. Runs in the CURRENT shell -- an earlier
# version used `mapfile < <(expand)`, which put die() in a subshell so a bad
# --from silently yielded an empty list and the script carried on.
SEL=()
resolve() {
    SEL=()
    local list=() n
    if [ "${#TARGETS[@]}" -eq 0 ] || [ "${TARGETS[0]}" = "all" ]; then
        while read -r n; do list+=("$n"); done < <(all_names)
    else
        list=("${TARGETS[@]}")
    fi
    # Validate every name BEFORE anything with side effects (stopping klipper).
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
    require_idle
    klipper_stop
    local n
    for n in "${SEL[@]}"; do flash_one "$n"; done
    klipper_start
    [ "$DRY" = 1 ] || sleep 5
    verify || warn "verify reported a problem -- check the versions above"
}

case "$CMD" in
  list)   list_boards ;;
  build)  resolve; info "boards: ${SEL[*]}"; build_set "${SEL[@]}" ;;
  flash)  resolve; info "boards: ${SEL[*]}"; flash_sequence ;;
  run)    resolve; info "boards: ${SEL[*]}"; build_set "${SEL[@]}"; flash_sequence ;;
  verify) verify ;;
  reset)  confirm "clear progress state?" && rm -f "$STATE" && ok "state cleared" ;;
  ""|-h|--help) usage 0 ;;
  *)      die "unknown command: $CMD (try --help)" ;;
esac
