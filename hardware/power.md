# Power

How the Voron is powered, and what actually limits it. Board identity is in the
per-board files; this is the rails and the switching.

## The 24 V supply is the ceiling

| | |
|---|---|
| PSU | **Meanwell LRS-200-24** `[owner]` |
| Output | **24 V, 8.8 A, ~211 W** |
| Input | 85-264 VAC, **no PFC** |
| Output trim | adjustable (LRS series, roughly +/-10%) |

**8.8 A is the real limit on everything below** -- not the Octopus's
`MB_POWER_IN` fuse (15 A stock, 20 A per BTT's 24 V guidance), and not any SSR.
The fuse sits above what the supply can even deliver, so it will never open from
overcurrent: the PSU current-limits or shuts down first.

Note the LRS series derates at high ambient. Inside a warm enclosure in summer,
8.8 A is optimistic.

## What is on the 24 V rail -- and what is not

The two biggest heat loads in the machine are **mains**, not 24 V:

| load | supply | switched by |
|---|---|---|
| bed heater | **mains** | AC SSR, 24 V control from `BED_OUT` (PA1) |
| drybox PTC (350 W) | **mains** | AC SSR, 3.3 V control direct from `MMB_SENSOR` (PA1) |

So neither appears in the 24 V budget. See
[octopus-pro-v1.0.md](octopus-pro-v1.0.md) and
[mmb-can-v1.0.md](mmb-can-v1.0.md) for those control chains and the SSR
drive-voltage difference.

What the 24 V rail does carry:

* Octopus Pro logic and six TMC5160 steppers
* hotend heater, via the EBB (~50-60 W)
* fans: part cooling, hotend, Nevermore, exhaust, electronics bay
* three drybox fans (core + two blowers)
* five neopixel chains
* both MMB boards, over their XT30s, plus the MMU gear and selector steppers
* the EBB USB adaptor's 24 V input (10 A fuse on that board)

### Budget -- estimated, not measured

Rough figures with wide error bars. **Nothing here has been measured**; treat it
as a sanity check, not a spec.

| load | est. |
|---|---|
| hotend heater | 2.1-2.5 A |
| 6x TMC5160 (DC input, not coil current) | 2-3 A |
| fans (five, main machine) | 1-1.5 A |
| neopixels (rarely full white) | 0.5-2 A |
| MMBs + MMU steppers | 0.5-1 A |
| drybox fans (three) | 1-1.5 A |

Plausible peak lands somewhere around **7-11 A against a 8.8 A supply**, so a
worst case -- printing while the drybox runs, the MMU moves and the LEDs are
bright -- may sit at or over the limit.

**If unexplained MCU resets or brownouts ever appear, PSU capacity is a prime
suspect.** To move this from estimate to fact, measure PSU output current under a
representative load. A 350 Voron with an MMU and a drybox is a lot for a 200 W
supply; an LRS-350-24 (14.6 A) is the usual step up.

*(The USB dropouts on 2026-09-01 were traced to cables, not power -- new cables
fixed them. Recorded here only so the two are not conflated later.)*

## Planned: switching the 24 V rail

Intent is to run the Pi from its own 5 V supply and put a **DC SSR on the 24 V
rail**, so the machine can be powered down independently of mains while the Pi
stays up.

| | |
|---|---|
| SSR on hand | **60 A, 3-32 V control** `[owner]` |
| Pi GPIO | **3.3 V only**, not 5 V tolerant, ~16 mA/pin |

3.3 V drives that SSR directly -- no level shift needed. 60 A against an 8.8 A
supply is enormously oversized, which is harmless.

Control should be **Moonraker's `[power]` with `type: gpio`**, not Klipper.
Klipper cannot drive a Pi GPIO without the Linux host MCU, and none is
configured here -- `[temperature_sensor raspberry_pi]` uses `temperature_host`,
which reads `/sys` and needs no MCU.

Settings that matter for this topology:

* **`restart_klipper_when_powered: True`** -- cutting 24 V drops the Octopus, the
  EBB and both MMBs, while the USB-powered HBB, Eddy and CAN adaptor stay alive
  off the Pi. Klipper will shut down on the way out and the CAN nodes need
  re-enumerating on the way back.
* `initial_state: off`, and consider `off_when_shutdown`.

**Check the Octopus's MCU power jumper first.** Per its manual section 4.4, the
board *can* be powered from USB-C via a jumper. If that jumper is fitted, cutting
24 V will not fully reset the board -- the MCU stays alive on USB and a latched
peripheral stays latched. For the SSR to be a genuine reset, the board must
depend on 24 V alone.

### It doubles as a mains-heater interlock

Both mains heaters take their SSR control from 24 V-powered boards, so losing the
rail disables **every mains heating element at once**. That is a real safety
property.

But it protects the **control path only**. An SSR that has failed **shorted** --
the characteristic SSR failure mode -- ignores its control input entirely. So this
is an excellent operational interlock and **not** a service isolation. Pull mains
before working on bed or PTC wiring.

The bed's last-resort layer is a **130 C / 15 A thermal fuse** `[owner]`, which is
one-shot; see [octopus-pro-v1.0.md](octopus-pro-v1.0.md).
