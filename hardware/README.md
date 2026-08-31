# Hardware inventory

Board and MCU identity for every controller this repo drives. Written for agents
and humans arriving cold: start here, then open the per-board file.

**Scope: identity and part numbers.** Connector-level pin maps are only present
where they have been verified from text; see "Provenance" below.

## Provenance rules

Every fact here is tagged with where it came from, because a wrong pin or part
number in a hardware doc is worse than no doc.

| Tag | Source | Trust |
|---|---|---|
| `[live]` | The MCU's own startup report in `klippy.log` (`MCU '<name>' config:`) | Highest -- the silicon describing itself |
| `[cfg]` | This repo's own `.cfg` files | Highest for *what is in use* |
| `[klipper]` | Klipper source (`src/`, `klippy/extras/`) | Authoritative for family capability |
| `[sch]` | Vendor schematic PDF, text layer extracted with `pdftotext -layout` | High -- verifiable text |
| `[vendor-cfg]` | Vendor `sample-bigtreetech-*.cfg` | High -- plain text |
| `[vendor]` | Vendor user-manual PDF, text layer extracted | High -- verifiable text |
| `[owner]` | Purchase record / recollection | Medium -- state it as such, never as verified |
| `[bitmap]` | Vendor pinout JPG/PNG read visually | **Low. Cross-check only, never a sole source.** |

Anything that would rest on `[bitmap]` alone is left out and marked as a gap.

## Printers

Four machines. Only `voron` is on Klipper 0.13; the three Bears are still on 0.12.

| Printer | Host | `printer.cfg` -> | Klipper | MCUs |
|---|---|---|---|---|
| Voron | `voron.lan` (192.168.1.87) | `voron.cfg` | `v0.13.0-743-gac2a7f8b0` | 6 |
| Bear 1 | `mk3-1.lan` (192.168.1.90) | `octopus_pro_bear_1.cfg` | `v0.12.0-286-g81de9a861` | 1 |
| Bear 2 | `mk3-2.lan` (192.168.1.166) | `octopus_pro_bear_2.cfg` | `v0.12.0-286-g81de9a861` | 1 |
| Bear 3 | `mk3-3.lan` (192.168.1.27) | `octopus_pro_bear_3.cfg` | `v0.12.0-286-g81de9a861` | 1 |

The Voron's Klipper reports itself as `...-gac2a7f8b0-**dirty**`. That is
expected, not a problem: `klipper-patches/0001` is applied to `~/klipper`. Note
it also blocks Moonraker's update manager (`git_deploy.py:90` refuses to update a
modified repo) -- stash before updating.

All four run `master`. The `MK3-Bear-1/2/3` branches are **dead** -- last touched
2020, and `MK3-Bear-3`'s final commit is literally "rename config to prep for
unified branch". `octopus_pro_bear_*.cfg` on master superseded them. Do not
resurrect those branches.

The Bears sit at older commits than the Voron, so what they *run* can lag this
repo's tip. Check `git -C ~/klipper-configs log --oneline -1` on the host before
assuming.

## MCU inventory

9 live, 2 dormant.

| Klipper MCU | Printer | Board | MCU part | Transport | Identity |
|---|---|---|---|---|---|
| `mcu` | Voron | [Octopus Pro V1.0](octopus-pro-v1.0.md) | STM32F429ZGT6 | USB | `0D0028001647323037343634` |
| `EBB` | Voron | [EBB SB2209 USB](ebb-sb2209-usb.md) | RP2040 | USB (own hub) | `5044340310CA481C` |
| `EDDY` | Voron | [BTT Eddy](btt-eddy.md) | RP2040 | USB via EBB hub | `504434031060B01C` |
| `HBB` | Voron | [HBB&FE V1.0](hbb-fe-v1.0.md) | RP2040 | USB | `45474E621B056C7A` |
| `mmu` | Voron | [MMB CAN V1.0](mmb-can-v1.0.md) | STM32G0B1CBT6 | CAN 1 Mbit | uuid `ff345a743db9` |
| `DRYBOX` | Voron | [MMB CAN V1.0](mmb-can-v1.0.md) | STM32G0B1CBT6 | CAN 1 Mbit | uuid `d9626e1b839e` |
| `mcu` | Bear 1 | [Octopus Pro V1.0](octopus-pro-v1.0.md) | STM32F429ZGT6 | USB | `2B0016001451323039323733` |
| `mcu` | Bear 2 | [Octopus Pro V1.0](octopus-pro-v1.0.md) | STM32F429ZGT6 | USB | `3C0035001651323039323733` |
| `mcu` | Bear 3 | [Octopus Pro V1.0](octopus-pro-v1.0.md) | STM32F429ZGT6 | USB | `3C002A001651323039323733` |
| `ercf` | -- | FYSETC ERB | RP2040 | USB | `E66160F423192638` |
| `menu` | -- | *unidentified* | STM32F042x6 | USB | `210006800C43303848373220` |

Not a Klipper MCU, but on the critical path for two of them:

| Device | Role | MCU | Identity |
|---|---|---|---|
| [CAN adapter](can-adapter.md) | USB->CAN for `mmu` + `DRYBOX` | STM32G0B1-class | `1d50:606f`, budgetcan `gs_usb` |

Its **PCB is unconfirmed** -- USB strings come from firmware, not the board. See
that file; settling it needs one look at the silkscreen.

Identities are `[cfg]`. MCU parts are `[sch]` except RP2040/F042 which are `[live]`.

### Dormant

Both have config files but neither is included by any active printer, so neither
is on a live machine's bus:

* **`ercf`** -- FYSETC ERB, the pre-Happy-Hare ERCF v1.1 controller.
  `ercf_hardware.cfg` names the board in its own header `[cfg]`. Superseded by
  Happy Hare under `mmu/`; not included anywhere.
* **`menu`** -- STM32F042x6 `[live-historic]` driving a `MiniDisplay` /
  `display_7920`. **Board not identified** -- deliberately not guessed. Its
  include is commented out at `voron.cfg:5`.

## Fleet notes

**All four main boards are the same board and the same chip.** Every one reports
`MCU=stm32f429xx` `[live]`, and the Octopus Pro V1.0 schematic populates either
STM32F429ZGT6 or STM32F446ZET6 `[sch]` -- ours are the F429. The F446 mentioned
in `firmware/README.md` is historical: the Voron's board was swapped. Octopus Pro
**V1.1** adds an STM32H723ZET6 variant `[sch]` which is *not* used here.

**The three Bears are identical to each other** in every field their MCUs report
`[live]` -- same chip, clock, `INITIAL_PINS`, and reserved pins. Bear 3 is
pending a hardware rebuild to match 1 and 2.

**Where the fleet actually diverges is software, not hardware:**

| | Voron | Bears |
|---|---|---|
| Klipper | `v0.13.0-743` | `v0.12.0-286` |
| `PWM_MAX` | 32768 | 255 |
| `INITIAL_PINS` | `PA8,PE5` | `PA8,PE5,PD12,PD13,PD14` |

`PWM_MAX` differs only because of the Klipper version, not the silicon.
`INITIAL_PINS` is a firmware build choice -- see `firmware/README.md`, and note
it is **not** interchangeable between boards.

**RP2040 `CLOCK_FREQ=12000000` is not the core clock.** All three RP2040 boards
report 12 MHz `[live]`; that is Klipper's timer base, derived from the 12 MHz
crystal. The Cortex-M0+ cores still run at their normal speed. Do not read it as
a 12 MHz CPU.

## Related

* `firmware/README.md` -- what to flash each board with, bootloader offsets,
  `INITIAL_PINS`, and field notes from the 0.12 -> 0.13 upgrade.
* `klipper-patches/` -- local Klipper patches and why they exist.
* `docs/drybox-air-control.md` in the `home-network` repo -- the drybox air
  control work, which is where most of the MMB detail here was established.
