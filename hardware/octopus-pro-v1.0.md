# BIGTREETECH Octopus Pro V1.0 (F429)

The main board on **all four printers**: `[mcu]` on the Voron and on Bears 1-3.

| | |
|---|---|
| MCU | **STM32F429ZGT6** `[sch]` -- 144-pin LQFP, 1 MB flash |
| Also populated | MAX31865 (RTD/PT100 amp) `[sch]` |
| Clock | 168 MHz `[live]` |
| ADC | `ADC_MAX=4095` `[live]` |
| USB | PA11/PA12, reserved `[live]` |
| Crystal | PH0/PH1, reserved `[live]` |
| Bootloader | 32 KiB (`FLASH_START_8000`), reads `firmware.bin` from onboard SD at power-on |
| Build config | `firmware/octopus-f429.config` |

## Variants -- get this right before flashing

The Octopus Pro schematic populates **either STM32F429ZGT6 or STM32F446ZET6**
`[sch]`. Ours are the F429: every board reports `MCU=stm32f429xx` `[live]`.

The **V1.1** schematic adds an **STM32H723ZET6** variant `[sch]`. Not used here.

`firmware/README.md` mentions F446 because the Voron ran that variant until its
board was swapped. Historical only.

## Package matters: port H barely exists

`ZxT6` is the 144-pin LQFP, on which **only PH0/PH1 exist** (the crystal,
reserved `[live]`).

Klipper still *advertises* buses on PH4/PH5 and PH7/PH8 -- `i2c2a` and `i2c3a`
-- because its bus table is declared per **family**, not per package
`[klipper]`. Those pins are not bonded out. Do not try to use them.

## Per-printer identity

| Printer | Serial | Klipper | `PWM_MAX` | `INITIAL_PINS` |
|---|---|---|---|---|
| Voron | `0D0028001647323037343634` | `v0.13.0-743` | 32768 | `PA8,PE5` |
| Bear 1 | `2B0016001451323039323733` | `v0.12.0-286-g81de9a861` | 255 | `PA8,PE5,PD12,PD13,PD14` |
| Bear 2 | `3C0035001651323039323733` | `v0.12.0-286-g81de9a861` | 255 | `PA8,PE5,PD12,PD13,PD14` |
| Bear 3 | `3C002A001651323039323733` | `v0.12.0-286-g81de9a861` | 255 | `PA8,PE5,PD12,PD13,PD14` |

All `[live]` except serials `[cfg]`.

The three Bears are **identical to each other** in every field their MCUs report.
`PWM_MAX` differs from the Voron only because of the Klipper version, not the
silicon. `INITIAL_PINS` is a firmware build choice and is **not** interchangeable
between boards -- see `firmware/README.md`.

Bear 3 is pending a hardware rebuild to match 1 and 2.

## Hardware I2C buses

Declared for this family, with usage on the **Voron** `[klipper]` + `[cfg]`:

| Bus | Pins | Voron status |
|---|---|---|
| `i2c1` | PB6, PB7 | in use -- Blobifier (`mmu/addons/blobifier_hw.cfg`) |
| `i2c1a` | PB8, PB9 | **free** |
| `i2c2` | PB10, PB11 | **free** |
| `i2c3` | PA8, PC9 | PA8 is a fan (`fans_common.cfg`, also `INITIAL_PINS`) |
| `i2c2_PF1_PF0` | PF1, PF0 | in use -- stepper dir/enable (`voron.cfg:158-159`) |
| `i2c2a` / `i2c3a` | PH4/PH5, PH7/PH8 | **do not exist on this package** |

Free-in-config is not the same as broken out on an accessible header. Confirm
against the vendor pinout before wiring. Note the *conventional* I2C header pins
(PB6/PB7) are already taken here.

## Gap

No connector-level pin map is recorded yet. The vendor has
`Hardware/BIGTREETECH Octopus Pro - PIN.pdf` and
`Hardware/BIGTREETECH-Octopus-Pro-V1.0-Color-PIN-V3.0.pdf`; if either has a text
layer, extract it with `pdftotext -layout` rather than reading the JPG.

For pins actually **in use**, this repo's `.cfg` files are already ground truth
and need no vendor source.
