# BIGTREETECH EBB SB2209 USB

Voron toolhead board, `[mcu EBB]`. Stealthburner form factor.

| | |
|---|---|
| MCU | **RP2040** `[sch]` `[live]` |
| Flash | W25Q16 `[sch]` |
| Stepper driver | TMC2209 (onboard, extruder) `[sch]` |
| Also populated | MAX31865 (RTD/PT100 amp) `[sch]` |
| Klipper `CLOCK_FREQ` | 12 MHz `[live]` -- **timer base, not core clock** |
| ADC / PWM | `ADC_MAX=4095`, `PWM_MAX=32768` `[live]` |
| Transport | **USB** |
| Serial | `usb-Klipper_rp2040_5044340310CA481C-if00` `[cfg]` |
| `INITIAL_PINS` | `gpio4,gpio14` -- part cooling `[fan]`, `[heater_fan hotend_fan]` `[live]` |
| Bootloader | none (`FLASH_START_0100`) |
| Build config | `firmware/rp2040-ebb.config` |

`CLOCK_FREQ=12000000` is Klipper's timer base off the 12 MHz crystal. The
Cortex-M0+ cores run at their normal speed; this is not a 12 MHz CPU.

## USB, not CAN -- and it carries a hub

This is the **USB** variant. `voron.cfg:29` still has
`#canbus_uuid: 11b4be3ecd53` commented out from the previous CAN toolhead board.

The board has an **onboard USB hub**, and the Eddy is daisy-chained through it:

```
1-1.1.5.1   EDDY   ┐  both downstream of hub 1-1.1.5,
1-1.1.5.4   EBB    ┘  which is the EBB's own hub
```

So unplugging or re-enumerating the EBB takes the Eddy with it.

## In use

Known from `[cfg]`: hotend heater on `gpio7`, part cooling and hotend fans on
`gpio4`/`gpio14`. Extruder driven by the onboard TMC2209. Phaetus Dragon High
Flow heat break, T-D500 thermistor (`thermistor_T-D500.cfg`).

## Gap

No connector-level pin map recorded. Vendor schematic is
`EBB_SB2209_USB/Hardware/BIGTREETECH EBB SB2209 USB V1.0-SCH.pdf` and a pinout
PDF sits beside it as `BIGTREETECH EBB SB2209 USB-Pin.pdf` -- prefer
`pdftotext -layout` on those over any JPG.

Beware the `bigtreetech/EBB` repo: it holds **many** unrelated boards (EBB36/42
CAN in STM32F072 and STM32G0B1, SB2209 **CAN** RP2040, SB2240, GEN2). Ours is
specifically the `EBB_SB2209_USB` directory.
