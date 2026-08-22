# Voron firmware configs

Build configs for all six MCUs, plus `voron-fw.sh`, which drives build and flash.
See `docs/voron-upgrade.md` in the `home-network` repo for the full procedure.

> **Do not put notes in the `.config` files.** They are Kconfig-generated —
> `make olddefconfig` and `menuconfig` rewrite them wholesale and strip any
> hand-added comments. Record things here instead.

## Boards

| Klipper MCU | Board | Config | Transport | Vendor docs |
|---|---|---|---|---|
| `mcu` | BTT Octopus Pro **F429** | `octopus-f429.config` | USB | [docs](https://github.com/bigtreetech/docs/blob/master/docs/Octopus%20Pro.md) · [repo](https://github.com/bigtreetech/BIGTREETECH-OCTOPUS-Pro) |
| `EBB` | BTT EBB SB2209 **USB** | `rp2040-ebb.config` | USB | [docs](https://github.com/bigtreetech/docs/blob/master/docs/EBB%20SB2209%20USB.md) · [repo](https://github.com/bigtreetech/EBB) |
| `EDDY` | BTT Eddy | `rp2040-hbb-eddy.config` | USB, via the EBB's hub | [docs](https://github.com/bigtreetech/docs/blob/master/docs/Eddy.md) · [repo](https://github.com/bigtreetech/Eddy) |
| `mmu` | BTT MMB CAN V1.0 (`MMB10`) | `mmb-g0b1-mmu.config` | CAN | [docs](https://github.com/bigtreetech/docs/blob/master/docs/MMB%20CAN%20V1.0.md) |
| `DRYBOX` | BTT MMB CAN V1.0 | `mmb-g0b1-drybox.config` | CAN | same as above |
| `HBB` | BTT HBB&FE V1.0 (macro pad, RGB key switches) | `rp2040-hbb-eddy.config` | USB | [repo](https://github.com/bigtreetech/HBB) · [sample cfg](https://github.com/bigtreetech/HBB/blob/master/sample-bigtreetech-hbb.cfg) |
| — | BTT U2C V2 (CAN adapter) | not Klipper | USB → `can0` | [docs](https://github.com/bigtreetech/docs/blob/master/docs/U2C.md) · [repo](https://github.com/bigtreetech/U2C) |

The U2C runs candlelight firmware, not Klipper, and is not managed by
`voron-fw.sh`. `~/U2C_V2_STM32G0B1.bin` on the Pi is its image.

The HBB has no page in `bigtreetech/docs`; its repo holds the manual PDFs and a
sample config. That sample maps key1–key7 to `gpio25, 26, 27, 19, 18, 13, 12`,
which matches `hbb_voron.cfg` exactly — that is how the board was identified.

## USB topology

The EBB SB2209 USB carries an onboard hub, and the Eddy is daisy-chained through
it — one cable up the umbilical instead of two. Confirmed from sysfs:

```
1-1.1.3     HBB          direct on the main 7-port hub
1-1.1.5.1   EDDY     ┐   both downstream of hub 1-1.1.5,
1-1.1.5.4   EBB      ┘   which is the EBB's onboard hub
1-1.1.6     MAIN         direct on the main 7-port hub
```

This is why the toolhead is on USB rather than CAN despite a CAN bus existing —
the hub is worth more than the wire count. A stale `#canbus_uuid: 11b4be3ecd53`
remains commented out in `voron.cfg` from the previous CAN toolhead board.

## menuconfig settings

| Board | Bootloader offset | Clock reference | Interface |
|---|---|---|---|
| Octopus Pro F429 | 32 KiB (`FLASH_START_8000`) | **8 MHz crystal** | USB on PA11/PA12 |
| MMB CAN V1.0 ×2 | 8 KiB (`FLASH_START_2000`, Katapult) | 8 MHz | CAN on PB0/PB1, 1 Mbit |
| EBB SB2209 USB | none (`FLASH_START_0100`) | — | USB |
| Eddy / HBB | none (`FLASH_START_0100`) | — | USB |

**The F429 takes an 8 MHz crystal, not 12 MHz.** The 12 MHz setting belongs to
the F446 variant, which this machine used until the board was swapped. Both the
[Voron docs](https://docs.vorondesign.com/build/software/octopus_klipper.html)
and BTT state this: "external crystal generator (F446: 12 MHz, F429: 8 MHz)".
Getting it wrong is not a subtle failure — the MCU runs at the wrong speed, USB
does not enumerate, and recovery means pulling the SD card.

`CONFIG_LOW_LEVEL_OPTIONS=y` is required before either the clock reference or
`INITIAL_PINS` can be set at all; without it Kconfig hides both and
`olddefconfig` drops them silently.

## INITIAL_PINS

Set per board, and **not** interchangeable:

| Board | `INITIAL_PINS` | Drives |
|---|---|---|
| `mcu` | `PA8,PE5` | `[heater_fan controller_fan]`, `[heater_fan exhaust_fan]` |
| `EBB` | `gpio4,gpio14` | part cooling `[fan]`, `[heater_fan hotend_fan]` |
| `DRYBOX` | `PB2` | `[heater_fan drybox_fan]` — all three box fans share this pin |
| `HBB`, `EDDY`, `mmu` | none | — |

Pins are driven **high** at MCU boot, before klippy connects. Kept deliberately
on the main board and the EBB: the hotend fan is the one that actually matters
for thermal safety, and the bay/exhaust fans running early is harmless.

This is the only difference between `rp2040-ebb.config` and
`rp2040-hbb-eddy.config`, and likewise the only difference between
`mmb-g0b1-mmu.config` and `mmb-g0b1-drybox.config`. Flashing HBB or EDDY with the
EBB config, or the MMU board with the drybox config, would assert pins that mean
nothing on those boards.

The two MMBs are identical hardware, so the MMU board's `PB2` is the same
physical header as the drybox's fan output. It is unused in the Klipper config,
but that is not the same as safe to drive high — hence two configs rather than
one shared `INITIAL_PINS`.

The drybox heater is AC and lives on `PA1` of the same MCU, so a cold boot with
no klippy leaves the element unpowered. `PB2` is set anyway so the fans spin
after an unexpected reboot rather than sitting still in a box holding residual
heat. `shutdown_speed: 1.0` already covers the klippy-disconnect case.
