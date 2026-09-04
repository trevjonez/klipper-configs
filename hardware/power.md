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
* **the Terminus hub chain** (FE 2.1 7-port, plus a 4-port below it), and so
  every USB MCU and the CAN adaptor hanging off it

### What survives an SSR open

Not everything USB goes down with the rail, and the split is not obvious from
looking at the machine. Enumerated with the rail off, then again with it on:

```
root_hub
 |__ Dev 2  VIA Labs hub          <- alive with 24 V OFF
     |__ Dev 7  Terminus 7-port   <- appears only with 24 V ON
     |   |__ Dev 8  Terminus 4-port -- 2x rp2040
     |   |__ Dev 11 CAN adaptor (budgetcan, gs_usb)
     |   |__ Dev 9  rp2040
     |   |__ Dev 13 stm32f429xx (Octopus)
     |__ Dev 6  C270 webcam       <- on the VIA hub, not the Terminus chain
```

The VIA hub nearest the Pi is **not** on the rail. The C270 hangs off it and
keeps streaming through a power cycle, so crowsnest holds its device and the
dashboard tiles stay live while the printer is down. Everything on the Terminus
chain -- all four USB MCUs and the CAN adaptor -- drops.

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

## Switching the 24 V rail

The Pi runs from its own 5 V supply and a **DC SSR** switches the 24 V rail, so
the machine can be powered down independently of mains while the Pi stays up.

| | |
|---|---|
| SSR | **60 A, 3-32 V DC control, -DD** `[owner]` |
| Pi GPIO | **3.3 V only**, not 5 V tolerant, ~16 mA/pin |
| Control pin | **GPIO 26** (header pin 37) |

60 A against an 8.8 A supply is enormously oversized, which is harmless.

**It must be a -DD, and it is.** A -DA is DC-control but **AC**-load: its output
is a triac, which only stops conducting at a zero crossing. On a DC rail there is
never one, so a -DA latches on the first time it is triggered and never releases
-- leaving a PSU that cannot be switched off, the exact inverse of the interlock
this section exists to provide. Recorded because "60 A, 3-32 V control" does not
distinguish the two, and the wrong one fails silently in the direction that
matters.

### Why GPIO 26

BCM 0-8 carry internal pull-**ups** at power-on, so an SSR on any of them would
conduct through boot and through every reset. BCM 9-27 default to pull-down.
Within that range GPIO 26 has no boot-time alternate function -- unlike 14/15
(UART console), 2/3 (I2C, with board pull-ups), 7-11 (SPI0), 18-21 (I2S) and
12/13 (PWM) -- and header pin 37 sits next to a ground on pin 39.

On a Pi 4 the chip is `gpiochip0`. This is not true across models: the Pi 5 moved
its GPIO behind the RP1 and renumbered. Check `gpiodetect` before reusing this on
other hardware.

### Moonraker

Control is **Moonraker `[power]` with `type: gpio`**, not Klipper. Klipper cannot
drive a Pi GPIO without the Linux host MCU, and none is configured here --
`[temperature_sensor raspberry_pi]` uses `temperature_host`, which reads `/sys`
and needs no MCU. Moonraker runs as `pi`, already in the `gpio` group.

Live in `~/printer_data/config/moonraker.conf`, which is **not** in this repo:

```ini
[power printer]
type: gpio
pin: gpiochip0/gpio26
initial_state: off
off_when_shutdown: True
off_when_shutdown_delay: 300
locked_while_printing: True
bound_services: klipper
```

**`bound_services: klipper`, not `restart_klipper_when_powered`.** The latter is
what this file called for before and is superseded in current Moonraker. It
covers the same need and additionally stops klipper on the way down rather than
leaving it running against MCUs that are not merely unresponsive but gone from
the bus entirely.

An earlier draft of this file claimed the HBB, Eddy and CAN adaptor stay alive
off Pi USB when the rail drops. **That is not the topology being built.** The USB
hub is itself on the 24 V rail, so opening the SSR takes every MCU and the hub
with it. Klipper comes back to a bus that has to re-enumerate from nothing, which
is exactly the case `bound_services` handles and a bare restart does not.

What comes back is the whole Terminus chain at once: four USB MCUs re-enumerating
and a CAN adaptor that has to find its nodes again.

**`off_when_shutdown_delay: 300` is the deliberate part.** On a Klippy shutdown
the MCU drops every output to its shutdown value: heaters off, and `heater_fan`
to `shutdown_speed`, which defaults to 1.0 rather than the 0 a plain `[fan]`
gets. `hotend_fan` does not override it. That full-speed heatbreak cooling only
happens while the EBB still has 24 V, so cutting power the instant Klipper faults
would trade a heat-creep clog for a marginally faster de-energize. Five minutes
puts the hotend well under the creep threshold; then the rail drops, which is
what covers the stuck heater MOSFET.

This does not survive a **host** shutdown or a Pi reset. GPIO 26 falls to its
pull-down, the SSR opens immediately and no delay applies. Anything that must
keep cooling across a Pi failure cannot sit behind this SSR.

### Verified on the bench, 2026-09-04

With nothing yet connected to the rail, the control path was exercised end to
end. Before moonraker claims it, GPIO 26 reads `level=0 fsel=0 func=INPUT
pull=DOWN` -- the default-low state the pin was chosen for. After loading
`[power printer]` it becomes `func=OUTPUT` at `level=0`, and it then follows the
device through repeated `on`/`off` calls to
`/machine/device_power/device?device=printer`.

Read the pin with **`raspi-gpio get 26`**, not `gpioget`: moonraker holds the
line through libgpiod, so `gpioget` fails with the line busy, while `raspi-gpio`
reads the pad registers without claiming anything.

The SSR was then fitted and probed: it switches correctly, and the same toggle
driven from Mainsail rather than curl behaves identically. So 3.3 V does drive
this unit despite sitting at the bottom of its stated 3-32 V range -- the doubt
recorded in earlier drafts is resolved for this part. The control-input voltage
and current were not written down; add them here if they get measured, since a
different SSR of the same nominal rating may not repeat this.

### Open

* Record the SSR control-input voltage and current if they get metered. The part
  works at 3.3 V, but the figures are not written down and the Pi is only good
  for ~16 mA/pin.

**Closed: the Octopus MCU power jumper.** Its manual section 4.4 allows powering
the MCU from USB-C via a jumper, which would have meant the SSR was not a genuine
reset. It does not apply here: the Octopus sits behind the Terminus hub, which is
itself on the rail, so its USB 5 V dies with the 24 V regardless of the jumper.
Confirmed by enumeration -- the board is absent with the rail off.

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
