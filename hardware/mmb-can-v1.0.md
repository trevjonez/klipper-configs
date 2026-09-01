# BIGTREETECH MMB CAN V1.0

Used twice on the Voron: `[mcu mmu]` (Happy Hare / ERCF) and `[mcu DRYBOX]`.
**Identical hardware**, different roles -- which is why the same pin means
different things on each, and why firmware `INITIAL_PINS` is not interchangeable.

| | |
|---|---|
| MCU | **STM32G0B1CBT6** `[sch]` -- 48-pin LQFP, 128 KB flash |
| CAN transceiver | SN65HVD1050 `[sch]` |
| Clock | 64 MHz `[live]` |
| ADC / PWM | `ADC_MAX=4095`, `PWM_MAX=32768` `[live]` |
| Transport | CAN, 1 Mbit, `RECEIVE_WINDOW=192` `[live]` |
| CAN pins | PB0/PB1, reserved `[live]` |
| Crystal | PF0/PF1, reserved `[live]` |
| Bootloader | Katapult, 8 KiB offset (`FLASH_START_2000`) -- see `firmware/README.md` |
| Build config | `firmware/mmb-g0b1-mmu.config`, `firmware/mmb-g0b1-drybox.config` |
| Board revision | **V1.0**, read from the silkscreen of a spare board `[owner]` |

BTT publish hardware files for **V1.0 and V2.0 only** -- V1.1 has no separate
folder and shares the "V1.0&V1.1" user manual, so V1.0 documentation covers a
V1.1 board too. **V2.0 is a different board** with its own schematic and pinout;
none of the map below applies to it.

`CONFIG_FLASH_SIZE=0x20000` (128 KB) in the build config independently agrees
with the `B` in `STM32G0B1CBT6`.

| Instance | CAN uuid | `INITIAL_PINS` |
|---|---|---|
| `mmu` | `ff345a743db9` | none |
| `DRYBOX` | `d9626e1b839e` | `PB2` (asserts the fan relay at boot) |

## There are no power outputs on this board

**Every header is 5V / GND / 3.3V-logic-signal.** The MMB is an MMU controller:
it has stepper driver sockets and logic headers, and **no heater or fan MOSFETs
at all**.

This matters for the drybox, whose 350 W PTC heater and 3-fan relay are *both*
driven through **external relays** off logic pins (PA1 and PB2). Anything else
you want to switch needs its own external driver too.

## Connector map

| Header | Pin(s) | Notes |
|---|---|---|
| I2C (4p) | **PB4** = SDA, **PB3** = SCL | + GND, 5V |
| MOT (3p) | PA0 | 5V / GND / signal |
| Sensor (3p) | PA1 | 5V / GND / signal |
| RGB (3p) | PA2 | 5V / PA2 / GND |
| STP1..STP11 (3p each) | PA3, PA4, PB9, PB8, PC15, PC13, PC14, PB12, PB11, PB10, PB2 | 5V / GND / signal |
| SPI | PA6 = MISO, PA5 = SCK, PA7 = MOSI | |

Stepper sockets (EZ driver), **excluded** from the "spare pin" count:

| | M1 | M2 | M3 | M4 |
|---|---|---|---|---|
| EN | PA8 | PD1 | PA15 | PB5 |
| STP | PB15 | PD2 | PD0 | PB6 |
| DIR | PB14 | PB13 | PD3 | PB7 |
| CS | PA10 | PC7 | PC6 | PA9 |

### Why this map is trustworthy

It agrees across three independent sources, which is the only reason it is here
rather than marked as a gap:

1. `[sch]` schematic text via `pdftotext -layout` gives net names against pin
   numbers: `IC-SDA` on PB4, `IC-SCL` on PB3, `STOP-3` on PB9, `STOP-4` on PB8.
   (The text columns are offset by one row; read the pin name against the
   *following* line's number/net.)
2. `[cfg]` the `[board_pins mmu]` aliases in `mmu/base/mmu.cfg` map
   `MMU_PRE_GATE_0..7` to PB9, PB8, PC15, PC13, PC14, PB12, PB11, PB10 -- i.e.
   exactly STP3..STP10 in the table above, in order.
3. `[cfg]` the live drybox config: I2C on PB3/PB4 works, matching (1).

`[bitmap]` The vendor `MMB CAN V1.0-Pin.jpg` also agrees, but is treated as
corroboration only.

The V1.0 map is additionally confirmed to be the *right* map for these boards,
independent of the silkscreen: Happy Hare's `MMU_PRE_GATE_0..7` resolve to
PB9, PB8, PC15, PC13, PC14, PB12, PB11, PB10 -- exactly STP3..STP10 in order --
and `mmu/base/mmu.cfg:16` names the board type `MMB10`. A V2.0 board could not
produce that agreement.

## In use

| Pin | Header | `DRYBOX` | `mmu` |
|---|---|---|---|
| PA0 | MOT | free | selector servo |
| PA1 | Sensor | heater (via external relay) | encoder |
| PA2 | RGB | neopixel x40 | neopixel |
| PA3 | STP1 | element thermistor | gear diag |
| PA4 | STP2 | free | selector diag |
| PB2 | STP11 | fan relay (all 3 fans) | selector endstop |
| PB3/PB4 | I2C | BME280 (hardware i2c3) | free |
| PB8..PB12, PC13..PC15 | STP3..STP10 | free | pre-gate sensors 0-7 |
| PA5/PA6/PA7 | SPI | free | PA7 only by the *unloaded* ERCF cutter addon |
| M1..M4 | stepper | free | M1 = gear, M2 = selector |

**13 free non-stepper pins on DRYBOX:** PA0, PA4, PB8, PB9, PB10, PB11, PB12,
PC13, PC14, PC15, PA5, PA6, PA7.

All can do PWM. Klipper uses **software PWM** for `[fan]`, `[fan_generic]` and
`[output_pin pwm=True]` on any GPIO `[klipper]`; `hardware_pwm: True` needs a
timer channel but a fan never does.

## Hardware I2C, not bitbang

PB3/PB4 are a real hardware bus on this part: `src/stm32/Makefile:70-73` makes
`stm32f0_i2c.c` the default and only F1/F2/F4 use `i2c.c`, and its
`CONFIG_MACH_STM32G0` branch declares bus 6 as **`i2c3_PB3_PB4`** `[klipper]`.
The drybox used a software bitbang here until 2026-08-31 for no reason.

Reading `src/stm32/i2c.c` will mislead you -- its I2C3 entries are gated to
F2/F4 and it is **not** the file a G0 compiles.

Electrically the two are the same: hardware `i2c_setup` calls
`gpio_peripheral(pin, function | GPIO_OPEN_DRAIN, 1)` with pullup `1`, and the
software bus also leaned on the internal pull-ups (it releases high via
`gpio_in_reset(pin, 1)` and never drives high) `[klipper]`.

## Gotchas

* **An AHT10 cannot drive a heater on this board, or any board.** `heaters.py`
  refreshes heater PWM on its own sensor's cadence and sets the pin's
  `max_duration` to `MAX_HEAT_TIME = 3.0s`; `aht10_report_time` floors at 5s, so
  the MCU kills the output the instant the heater is commanded on `[klipper]`.
  A BME280 hardcodes `REPORT_TIME = 0.8` and works. Full write-up:
  `docs/drybox-air-control.md` in the `home-network` repo.
* **Two instances on one I2C chip is fine.** `MCU_I2C_from_config` never calls
  `lookup_pin` in the `i2c_bus` branch, and the MCU skips re-init via
  `is_enabled_pclock` `[klipper]`.
* **`START_NACK` means an absent device**, not a bus conflict. Seen once here
  when the sensor was unplugged mid-mounting.
* **Thermistors on STP headers.** The drybox element thermistor is on STP1
  (PA3), an endstop-style header. Those typically carry a board pull-up that may
  not match Klipper's default `pullup_resistor: 4700`, which would skew readings.
  **Unverified** -- the element reads 47-50 C at rest against 28 C box air, which
  is consistent either with a fans-off hot pocket or with a divider mismatch.
  Worth checking against the schematic before trusting absolute element numbers.
