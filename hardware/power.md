# Power

How the Voron is powered, and what actually limits it. Board identity is in the
per-board files; this is the rails and the switching.

## Two rails since 2026-09-24

The machine ran on a single 24 V rail until 2026-09-24, when a **48 V supply was
added for stepper motor power only**. Logic is untouched: the Octopus, both
MMBs, the EBB and every sensor still run from 24 V. What moved is the driver
VM on the six Octopus TMC5160s and the two MMB EZ5160s.

Nothing in Klipper expresses a supply voltage for a TMC, so the only place the
machine records this is `voltage:` in `voron_autotune.cfg` -- it feeds PWM_OFS,
PWM_GRAD and the chopper hysteresis. `[autotune_tmc extruder]` is the one
section still on 24, because the EBB's 2209 is genuinely still on 24 V.

**TODO -- the 48 V supply's make, model and rating are not recorded here.**
Fill them in; the 24 V budget below only became a non-question because the
steppers left it, and that argument is unverifiable without the 48 V figures.

## The 24 V supply

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

* Octopus Pro logic -- but **not** the six TMC5160s' motor supply, which is on
  48 V as of 2026-09-24. Their VCC_IO side is still 24 V-derived.
* hotend heater, via the EBB (~50-60 W)
* fans: part cooling, hotend, Nevermore, exhaust, electronics bay
* three drybox fans (core + two blowers)
* five neopixel chains
* both MMB boards, over their XT30s. The MMU gear and selector steppers are
  **no longer on this rail** -- their EZ5160s take motor power from 48 V, while
  the MMB's own XT30 stays at 24 V. The MMB is a 24 V board and putting 48 V on
  that connector would take the onboard regulator with it.
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
| ~~6x TMC5160 (DC input, not coil current)~~ | ~~2-3 A~~ moved to 48 V |
| fans (five, main machine) | 1-1.5 A |
| neopixels (rarely full white) | 0.5-2 A |
| MMBs + MMU steppers | 0.5-1 A |
| drybox fans (three) | 1-1.5 A |

Plausible peak lands somewhere around **7-11 A against a 8.8 A supply**, so a
worst case -- printing while the drybox runs, the MMU moves and the LEDs are
bright -- may sit at or over the limit.

Moving the steppers to 48 V takes an estimated 2-3 A off that peak, which is
the single biggest line item after the hotend. It does not make the budget
*measured* -- every figure above still has wide error bars -- but it does mean
the worst case is no longer sitting on the supply's nameplate.

**If unexplained MCU resets or brownouts ever appear, PSU capacity is a prime
suspect.** To move this from estimate to fact, measure PSU output current under a
representative load. A 350 Voron with an MMU and a drybox is a lot for a 200 W
supply; an LRS-350-24 (14.6 A) is the usual step up.

*(The USB dropouts on 2026-09-01 were traced to cables, not power -- new cables
fixed them. Recorded here only so the two are not conflated later.)*

## Switching the rails

The Pi runs from its own 5 V supply and a **DC SSR** switches each rail, so the
machine can be powered down independently of mains while the Pi stays up.

| | |
|---|---|
| SSRs | **two**, both 60 A, 3-32 V DC control, -DD `[owner]` |
| Pi GPIO | **3.3 V only**, not 5 V tolerant, ~16 mA/pin |
| Control pin | **GPIO 26** (header pin 37) -- **one pin drives both** |

The 48 V SSR added on 2026-09-24 is the identical part on the identical control
pin, wired in parallel with the 24 V one. That is deliberate and is the right
shape: there is one switch, both rails rise and fall together, and no software
knows there are two. **Moonraker's `[power printer]` needed no change at all.**

Keeping them ganged also sidesteps the failure mode a split would invite. A
TMC5160 with motor power present and its logic supply absent is an abuse
condition, so 48 V must never be up while 24 V is down. Sharing one control leg
makes that true by construction rather than by sequencing logic.

60 A against either supply is enormously oversized, which is harmless.

**One thing the parallel wiring does change: GPIO 26 now drives two SSR inputs,
so it sources roughly twice the current it did.** An SSR input is an LED and a
series resistor, and this pin was never metered -- the "Open" item below has
been outstanding since the first SSR went in. It is now twice as worth closing,
because the Pi is only good for ~16 mA/pin and the margin, whatever it is, just
halved. If the rails ever fail to come up together, or come up unreliably,
measure here first.

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

**`initial_state: off` is load-bearing, and the live file said `on` until
2026-09-24** -- this doc had been describing an intent the machine never had.
The symptom was the rail coming up by itself on every boot, which reads as
Mainsail or Klipper doing it and is neither: Moonraker's GPIO device bakes the
initial state into the pin claim itself (`power.py:644`,
`initial_val = int(self.initial_state or 0)`), so the line is driven high the
moment Moonraker starts.

Note `off` is not the same as omitting the line, because of `bound_services`:

| | rail at boot | klipper service |
|---|---|---|
| `initial_state: on` | on | started |
| `initial_state: off` | off | **actively stopped** (`power.py:332`) |
| line omitted | off | left running (`power.py:650-651` skips the branch) |

`off` is the coherent one. Klipper with the rail down is erroring against MCUs
that are gone from the bus, so stopping it is correct, and Mainsail then renders
a powered-off printer with a toggle rather than a fault. Verified 2026-09-24:
after `systemctl restart moonraker`, klipper goes `inactive`, the device reads
`off`, and `raspi-gpio get 26` reports `level=0 func=OUTPUT`.

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

### The rewire cost a night of CAN debugging

Not a fault of the rail work itself, but caused by it: relocating the PSU and
rewiring knocked the **120 R terminator jumper off the CAN adapter**, and the CAN
bus did not work again until it was found on the floor and refitted. Nothing
about the symptom pointed at power -- see
[ceb-can-hub.md](ceb-can-hub.md) for the full trail.

**After any mechanical work in the electronics bay, meter 60 R across CANH-CANL
before assuming the change you made is at fault.** Jumpers are the smallest thing
in there and the easiest to dislodge.

### Open

* Record the SSR control-input voltage and current if they get metered. The
  parts work at 3.3 V, but the figures are not written down and the Pi is only
  good for ~16 mA/pin -- now across **two** SSR inputs in parallel.
* Record the 48 V supply's make, model and current rating.

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
