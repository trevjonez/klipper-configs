# BIGTREETECH Eddy

Voron Z probe, `[mcu EDDY]`. Eddy-current inductive sensor, no physical switch.

| | |
|---|---|
| MCU | **RP2040** `[live]` |
| Sensor | **LDC1612** inductance-to-digital converter `[klipper]` |
| Klipper `CLOCK_FREQ` | 12 MHz `[live]` -- **timer base, not core clock** |
| ADC / PWM | `ADC_MAX=4095`, `PWM_MAX=32768` `[live]` |
| Transport | USB, **via the EBB's onboard hub** |
| Serial | `usb-Klipper_rp2040_504434031060B01C-if00` `[cfg]` |
| `INITIAL_PINS` | none `[live]` |
| Bootloader | none (`FLASH_START_0100`) |
| Build config | `firmware/rp2040-hbb-eddy.config` (shared with HBB) |

The LDC1612 is established from our own stack, not vendor marketing:
`probe_eddy_current.py:1029` declares `sensors = {"ldc1612": ldc1612.LDC1612}`
`[klipper]`, and `voron.cfg:333` uses `[probe_eddy_current btt_eddy]` `[cfg]`.
The build config also sets `CONFIG_WANT_LDC1612=y`.

## I2C

The Eddy's LDC1612 is on **hardware** I2C: `i2c_mcu: EDDY`, `i2c_bus: i2c0f`
(RP2040 gpio20/gpio21) `[cfg]`. Worth noting because it is the *other* hardware
I2C bus in this repo besides the drybox BME280.

## Shares a firmware config with the HBB

`firmware/rp2040-hbb-eddy.config` builds for both Eddy and HBB. The only
difference from `rp2040-ebb.config` is `INITIAL_PINS`, which is exactly why they
are not interchangeable -- flashing the Eddy with the EBB config would assert
`gpio4,gpio14`, which mean nothing here. See `firmware/README.md`.

## Calibration lives in the autosave block

`[probe_eddy_current btt_eddy]` autosaves `calibrate`, `tap_threshold`,
`reg_drive_current` and `z_offset`, and `[temperature_probe btt_eddy]` autosaves
drift calibration. Those **must** stay in the main config, never an `[include]`
-- `SAVE_CONFIG` refuses to write an option that is also literally defined in an
included file. See `klipper-patches/README.md`.

## Gap

No connector-level pin map recorded. The `bigtreetech/Eddy` repo has **no
hardware directory at all** -- only user-manual PDFs and sample configs. The
authoritative text sources are therefore `sample-bigtreetech-eddy.cfg` (and the
`-homing` / `-zoffbeta` variants) in that repo, plus our own `voron.cfg`.
