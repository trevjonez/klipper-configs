# BIGTREETECH HBB&FE V1.0

Voron macro pad, `[mcu HBB]` -- RGB key switches driving `hbb_voron.cfg` button
macros (bed / drybox / lights ladders).

| | |
|---|---|
| MCU | **RP2040** `[live]` |
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

## Gap

No connector-level pin map recorded, and this is the **weakest-sourced board
here**. The vendor repo's `Hardware/` holds only bitmaps -- `HBB FE-PIN.jpg`,
`HBB FE接口图.jpg`, `HBB接口图.jpg` -- plus a SIZE PDF. **There is no schematic
PDF**, so there is no text source for a pin map.

Per this repo's provenance rules a `[bitmap]`-only pin map is not written down.
The trustworthy text sources are:

1. `hbb_voron.cfg` -- ground truth for every pin actually in use `[cfg]`.
2. `sample-bigtreetech-hbb.cfg` in `bigtreetech/HBB` -- names the connectors
   `[vendor-cfg]`.

Use those. If a full map is ever needed, transcribe from the sample config, not
the JPG.
