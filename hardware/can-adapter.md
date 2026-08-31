# CAN adapter (USB `gs_usb`)

Not a Klipper `[mcu]`. It is the Pi's CAN interface and the **only** path to
`[mcu mmu]` and `[mcu DRYBOX]` -- both MMB boards hang off it.

| | |
|---|---|
| PCB | **unconfirmed** -- see below |
| MCU | **STM32G0B1-class** (64 MHz) `[live]` |
| Firmware | **budgetcan** (`gs_usb` class) `[live]` |
| Host driver | `gs_usb` `[live]` |
| USB id | `1d50:606f` (OpenMoko / Geschwister Schneider CAN adapter) `[live]` |
| USB strings | `iManufacturer=budgetcan`, `iProduct=budgetcan gs_usb` `[live]` |
| Serial | `004B00225542501720393839` -- an STM32 96-bit UID `[live]` |
| USB path | `1-1.1.1` `[live]` |
| Interface | `can0`, 1 Mbit `[live]` |

## The PCB cannot be identified from software

**This is the gotcha, and it is why searching for this board is frustrating.**
Every USB string comes from the *flashed firmware*, not the PCB. This unit runs
open-source **budgetcan** firmware, so the host reports:

```
Bus 001 Device 005: ID 1d50:606f OpenMoko, Inc. Geschwister Schneider CAN adapter
usb 1-1.1.1: Product: budgetcan gs_usb
usb 1-1.1.1: Manufacturer: budgetcan
```

Nothing says BigTreeTech. `1d50:606f` is the shared OpenMoko VID/PID used by the
whole `gs_usb` family, and `bcdDevice` is `0.00`, so there is no revision to
read either. Searching those strings finds a *firmware project*, not a product.

### What is actually established

`[live]` **The MCU is a 64 MHz STM32G0B1-class part.** `can0` reports
`clock 64000000`. That rules out the BTT U2C **V1.x**, whose V1.1 schematic
populates an **STM32F072C8T6** `[sch]` -- an F072 tops out at 48 MHz and
physically cannot source a 64 MHz CAN clock. Firmware declares `fclk_can`, but
it cannot invent clock the silicon does not have.

`[vendor]` BTT's own repo ships `firmware/U2C_V1_STM32F072.bin` **and**
`firmware/U2C_V2_STM32G0B1.bin`, so in BTT's naming an STM32G0B1 means a **V2**
board. `bigtreetech/U2C` publishes schematics for **V1.0 and V1.1 only** -- there
is no V2.x schematic to verify against.

### Two candidates, both consistent

1. **BTT U2C V2.x reflashed with budgetcan firmware.** Fits, but conflicts with
   "mine is pretty old" -- an old unit is more likely V1.x, and V1.x is ruled out
   by the clock.
2. **An actual BudgetCAN-design adapter** (open hardware, STM32G0B1), never a BTT
   board at all. Fits the USB strings without needing a reflash.

**To settle it: read the silkscreen.** The board is labelled. That is one glance
and it beats any amount of further inference -- which is why no version is
asserted here.

## Bus configuration

```
can0: bitrate 1000000  sample-point 0.750
      tq 62  prop-seg 5  phase-seg1 6  phase-seg2 4  sjw 1
      clock 64000000
      termination 0 [ 0, 120 ]
```

1 Mbit matches `CANBUS_FREQUENCY=1000000` on both MMB boards `[live]`, and both
were built with `CONFIG_STM32_CANBUS_PB0_PB1` `[cfg]`.

Brought up by `/etc/network/interfaces.d/can0` -- `allow-hotplug can0`,
`iface can0 can static`, `txqueuelen 1024` `[live]`.

Healthy at the time of writing: 6.2 M packets RX / 1.9 M TX, and **zero** across
`re-started`, `bus-errors`, `arbit-lost`, `error-warn`, `error-pass`, `bus-off`
`[live]`. Those counters are the first thing to check for CAN trouble.

### Termination is OFF at the adapter

`termination 0 [ 0, 120 ]` -- the adapter's own 120 R terminator is **disabled**,
and it is capable of switching it. The bus is error-free, so termination is
coming from elsewhere; the MMB CAN V1.0 carries a selectable 120 R.

**Unverified:** which physical ends terminate. Worth confirming before blaming
CAN errors on anything else.

## Nodes on this bus

| Klipper MCU | Board | uuid |
|---|---|---|
| `mmu` | [MMB CAN V1.0](mmb-can-v1.0.md) | `ff345a743db9` |
| `DRYBOX` | [MMB CAN V1.0](mmb-can-v1.0.md) | `d9626e1b839e` |

`canbus_query.py` lists only nodes **without** an assigned CAN id, so a healthy,
already-assigned board shows nothing -- expected, not a fault. See
`firmware/README.md`.
