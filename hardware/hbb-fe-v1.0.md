# BIGTREETECH HBB&FE V1.0

Voron macro pad, `[mcu HBB]` -- RGB key switches driving `hbb_voron.cfg` button
macros (bed / drybox / lights ladders).

| | |
|---|---|
| MCU | **RP2040** `[live]` `[vendor]` |
| Flash | **W25Q080** `[vendor]` |
| Key LEDs | **WS2812B** `[vendor]` |
| Klipper `CLOCK_FREQ` | 12 MHz `[live]` -- **timer base, not core clock** |
| ADC / PWM | `ADC_MAX=4095`, `PWM_MAX=32768` `[live]` |
| Transport | USB, direct on the main 7-port hub (`1-1.1.3`) |
| Serial | `usb-Klipper_rp2040_45474E621B056C7A-if00` `[cfg]` |
| `INITIAL_PINS` | none `[live]` |
| Bootloader | none (`FLASH_START_0100`) |
| Build config | `firmware/rp2040-hbb-eddy.config` (shared with Eddy) |

## How this board was identified

It has **no page in `bigtreetech/docs`**. The identification came from matching
`hbb_voron.cfg` against the vendor sample config
`sample-bigtreetech-hbb.cfg` in `bigtreetech/HBB`, which matches exactly
`[vendor-cfg]`. Recorded in `firmware/README.md`.

## Button wiring gotcha

The button pins are **inverted** so the edges mean what they say -- see commit
`86d40c2` "Invert the HBB button pins so the edges mean what they say", and the
earlier "Put the heater button actions back on the edge that is a physical push"
and "Fix unreliable long press: drop the shared flag". If you touch the button
config, re-read those first; the edge semantics have been wrong twice.

## Sources -- no schematic exists

`bigtreetech/HBB` has **no schematic PDF**. Confirmed by enumerating all 39
files in the repo, not by a filtered guess: `Hardware/` holds only
`BIGTREETECH HBB V1.0-SIZE.pdf` and three bitmaps (`HBB FE-PIN.jpg`,
`HBB FE接口图.jpg`, `HBB接口图.jpg`).

Per this repo's provenance rules a `[bitmap]`-only pin map is not written down.
Two text sources cover it instead:

1. **`BIGTREETECH HBB&FE V1.0 User Manual.pdf`** has a **text layer**. Extract
   with `pdftotext -layout`; it is where the RP2040 / W25Q080 / WS2812B parts
   above come from `[vendor]`.
2. **`sample-bigtreetech-hbb.cfg`** in the same repo -- plain text, names every
   key pin (`HBB:gpio25` for `key1`, and so on) `[vendor-cfg]`.

For pins actually **in use**, `hbb_voron.cfg` is already ground truth `[cfg]` and
needs no vendor source at all.

Worth knowing: that upstream sample config's comments describe the active-low
button wiring in the same terms as this repo's own commit history, so the
findings here appear to have been upstreamed.

A fork exists at `trevjonez/HBB`.
