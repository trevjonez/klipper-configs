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
EDDY   port 1  ┐  both downstream of the EBB's own hub,
EBB    port 4  ┘  which itself hangs off the 7-port hub
```

So unplugging or re-enumerating the EBB takes the Eddy with it. Port numbering
under the main hub is not stable across reboots or re-cabling -- match by the
`by-id` serial, never by USB path.

## The link is NOT a plain USB cable

This matters more than anything else on this page, and it is invisible from the
config, which just says `serial:`.

```
7-port hub
  |
  |  USB-A to USB-C cable  <-- ordinary, in the electronics bay, REPLACEABLE
  v
EBB USB Adaptor PCB  (+ 24 V input)
  |
  |  composite umbilical: ~20 AWG data pair + 14-16 AWG power
  |  AMASS 2+2 pin connector, and it FLEXES on every toolhead move
  v
EBB SB2209
```

Two segments, one PCB, three connector interfaces. "Replace the EBB's USB cable"
only ever means the **bay-side** segment; the umbilical is not a standard cable
and is not casually swappable.

### The adaptor PCB does real signal conditioning

From `EBB_SB2209_USB/Hardware/BIGTREETECH EBB EBB USB Adaptor V1.0-SCH.pdf`
`[sch]`:

| ref | part | function |
|---|---|---|
| **L1** | `SDCW2012-2-900TF` | **common-mode choke (~90 ohm) on the data pair** |
| D5 | `SR05-N` | USB ESD suppressor array on the data lines |
| -- | `CV0402VT6030T` (2 kV) | chip varistor, further ESD |
| D44 | `SMAJ28A` | 28 V TVS on the DC input |
| F1 | 10 A | fuse on the 24 V input |
| R1 | 5.1 K | USB-C CC1 pulldown (sink identification) |
| C11, R2/R3/R4/R9 | 10 nF, 1 M | filtering / bias |
| P1 | `AMASS 2+2PIN_5R0` | umbilical connector |

The topology is read straight off the netlist and is not in doubt: the data nets
are **separate on each side** -- `USBC_P`/`USBC_N` toward the host,
`USB_P`/`USB_N` toward the toolhead -- bridged by **L1**. That is a deliberate
common-mode choke on a high-speed pair.

`AMASS 2+2PIN` means the umbilical carries **two large pins (24 V + ground) and
two small (D+/D-)**. So the USB data pair is referenced to the *power* ground,
with no dedicated USB ground or shield. That is bold for high-speed USB, and it
is why the choke and ESD parts exist rather than being optional. BTT clearly
engineered around a hostile cable.

Consequence: the adaptor PCB is a **component in the signal path with its own
failure modes** (choke, ESD array, fuse), not a connector shell.

### Speed: the hub is 480M, the MCUs are 12M

```
root -> VIA hub -> 7-port hub -> EBB hub      all 480M
                                    |-> Eddy   12M
                                    |-> EBB    12M
```

Every RP2040 negotiates **12 Mbit full-speed**, which is very forgiving. But the
EBB's onboard hub uplink is **480 Mbit**, and that is what the two cable segments
plus the adaptor have to carry.

**So cable quality is set by the hub, not the MCUs.** A cable marginal at 480M
still passes 12M traffic happily -- which is exactly why this link threw
`error -71` at descriptor-read on 2026-09-01 while 12M devices on the same
physical hub were fine. Combined with being the only run that flexes, this is
the most demanding *and* most mechanically stressed USB path in the machine.

### Cable failure history

2026-09-01: the BTT-supplied cables were replaced fleet-wide after the Octopus's
failed outright and this link threw `error -71`. Replacing the bay-side segment
cleared it. See `hosts/voron.md` in the home-network repo for the full symptom
table and the diagnosis trap (a bad cable follows the device to every port, so
varying the port while reusing the cable proves nothing).

## In use

Known from `[cfg]`: hotend heater on `gpio7`, part cooling and hotend fans on
`gpio4`/`gpio14`. Extruder driven by the onboard TMC2209. Phaetus Dragon High
Flow heat break, T-D500 thermistor (`thermistor_T-D500.cfg`).

## Gap

No connector-level pin map recorded. Sources, with what is known about each:

* `EBB_SB2209_USB/Hardware/BIGTREETECH EBB SB2209 USB V1.0-SCH.pdf` -- **has a
  text layer**, and is where the RP2040 / W25Q16 / TMC2209 / MAX31865 parts came
  from. Net names extract (`HE0`, `HE0_TH`, `FAN1_PWM`, `GPIO0`..`GPIO29`) but
  the layout is **column-scrambled**, so pairing a GPIO to a net by line
  proximity produces garbage. Do not do it. Pin values in this repo come from
  our own `.cfg` files, which are ground truth for anything in use.
* `BIGTREETECH EBB SB2209 USB-Pin.pdf` -- **rasterised, zero extractable text**
  (verified). Bitmap only, so corroboration at best per the provenance rules.

Beware the `bigtreetech/EBB` repo: it holds **many** unrelated boards (EBB36/42
CAN in STM32F072 and STM32G0B1, SB2209 **CAN** RP2040, SB2240, GEN2). Ours is
specifically the `EBB_SB2209_USB` directory.
