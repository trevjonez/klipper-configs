# BIGTREETECH U2C V2.1 (USB-to-CAN adapter)

Not a Klipper `[mcu]`. It is the Pi's CAN interface and the **only** path to
`[mcu mmu]` and `[mcu DRYBOX]` -- both MMB boards hang off it.

| | |
|---|---|
| PCB | **BIGTREETECH U2C V2.1** `[owner]` -- visually identified, corroborated below |
| MCU | **STM32G0B1** (64 MHz) `[live]` `[vendor]` |
| Firmware | **budgetcan** (`gs_usb` class) -- and this *is* BTT's stock image `[live]` |
| Host driver | `gs_usb` `[live]` |
| USB id | `1d50:606f` (OpenMoko / Geschwister Schneider CAN adapter) `[live]` |
| USB strings | `iManufacturer=budgetcan`, `iProduct=budgetcan gs_usb` `[live]` |
| Serial | `004B00225542501720393839` -- an STM32 96-bit UID `[live]` |
| USB path | `1-1.1.1` `[live]` |
| Interface | `can0`, 1 Mbit `[live]` |

## The PCB cannot be identified from software

**This is the gotcha, and it is why searching for this board is frustrating.**
Every USB string comes from the *flashed firmware*, not the PCB. The firmware
here is **budgetcan**, so the host reports:

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

### Settled

The board was **read visually as a V2.1** `[owner]`, which agrees with the clock
evidence above: a **BTT U2C V2.1 running budgetcan firmware**.

**It is running BTT's stock image, not a third-party build.** An earlier draft of
this file had that backwards -- it read the `budgetcan` strings as evidence the
board had been reflashed away from stock. It has not. BTT ship a budgetcan-branded
build, verified two ways:

* `strings ~/U2C_V2_STM32G0B1.bin` on BTT's own binary contains `budgetcan`,
  `budgetcan gs_usb` and `budgetcan firmware upgrade interface` -- exactly what
  the running board reports.
* That local binary is **md5 `d890f048...` , byte-identical to upstream HEAD**
  (`raw.githubusercontent.com/bigtreetech/U2C/master/firmware/`).

So nothing on the wire says BigTreeTech because **BTT chose not to put it there**,
not because the board was reflashed.

Upstream has not moved since **2023-01-16** (*"update U2C V2 G0B1 firmware, fix
Canboot error"*). That commit is what Katapult's README means when it says the
U2C v2.1 "requires the latest firmware" -- so this board is current, and there is
no newer image to chase.

### Katapult does not apply to this board

Katapult is a bootloader for **Klipper** MCUs. The U2C does not run Klipper, so
Katapult offers it nothing. Its only mention of the U2C is the reverse
dependency above: the adapter needs recent firmware for Katapult's *CAN flashing
of other nodes* to work.

### Making it self-identify would mean a custom build

`bcdDevice` is `0000` and the strings say budgetcan, so neither board revision
nor firmware version can be read back. Fixing that means rebuilding budgetcan
with custom USB descriptors.

**The VID/PID must stay `1d50:606f`.** The `gs_usb` driver binds on that pair; a
BigTreeTech-specific id would not bind and the adapter would simply stop working.
Only `iManufacturer`, `iProduct` and `bcdDevice` are free to change.

Judged not worth it: it puts a self-built image on the *only* path to both MMBs
and diverges from the exact binary Katapult validates against, for cosmetic gain.
The **USB serial is already a unique, firmware-independent identifier** -- it is
the STM32 96-bit UID -- and is the right thing to match on in udev.

The exact package/flash suffix remains unverified: `bigtreetech/U2C` publishes
schematics for **V1.0 and V1.1 only**, so unlike the MMB (`STM32G0B1CBT6`, from
its schematic) there is no V2.x schematic to read a full part number from.

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

### Termination is a PHYSICAL jumper, and `termination` in `ip` is a lie

The adapter terminates with a **jumper on the PCB**. It must be fitted: this is
one of the bus's two terminated ends.

`ip -d link show can0` reports `termination 0 [ 0, 120 ]`, and **that field means
nothing on this board.** It is a capability the budgetcan firmware advertises
over `gs_usb` with no hardware behind it. Proven on 2026-09-04 by toggling
`ip link set can0 type can termination 0|120` through three cycles while metering
CANH-CANL: the reading never moved. The field also read `0` for however long the
jumper was correctly fitted, so it is wrong in both directions and cannot be used
to check termination either way.

**Meter it, or look at the jumper. Do not trust `ip`.** 60 R across CANH-CANL is
a correctly terminated bus; 120 R means only one end is terminated.

This is the exception to the `[live]` provenance rule in
[README.md](README.md) -- see the caveat there.

## Topology

The adapter does **not** wire straight to the MMBs. A passive
[CEB V1.0 hub](ceb-can-hub.md) splits the bus, which is where spare CAN capacity
lives (~4 free ports):

```
Pi 4B ── USB ── U2C V2.1 (termination OFF)
                  └── CEB V1.0 (passive, 120R jumper)
                        ├── MMB  ff345a743db9  [mcu mmu]
                        └── MMB  d9626e1b839e  [mcu DRYBOX]
```

| Klipper MCU | Board | uuid |
|---|---|---|
| `mmu` | [MMB CAN V1.0](mmb-can-v1.0.md) | `ff345a743db9` |
| `DRYBOX` | [MMB CAN V1.0](mmb-can-v1.0.md) | `d9626e1b839e` |

`canbus_query.py` lists only nodes **without** an assigned CAN id, so a healthy,
already-assigned board shows nothing -- expected, not a fault. See
`firmware/README.md`.
