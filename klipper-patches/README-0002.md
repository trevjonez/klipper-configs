# Klipper patch 0002: allow an AHT10 report time below 5s

> **STATUS: NOT APPLIED. Superseded 2026-08-31.**
>
> The drybox air sensor is now a BME280, and `bme280.py` hardcodes
> `REPORT_TIME = 0.8` (bme280.py:9) -- already inside `MAX_HEAT_TIME` of 3.0s --
> so it drives the heater with no patch at all. This patch was reverted from
> `~/klipper` to keep the repo clean for Moonraker's update manager.
>
> It was tested and it worked: 12 minutes at `aht10_report_time: 1` with zero
> I2C errors, then sustained heater control off the AHT10. It is kept here only
> because the underlying finding is worth reporting upstream (see Upstreaming
> below). Re-apply only if an AHT-family sensor ever needs to drive a heater.

## The problem

Pointing `[heater_generic drybox]` at the AHT10 in the box air (see
`docs/drybox-air-control.md` in the home-network repo) shuts the MCU down the
instant the heater is commanded on:

```
MCU DRYBOX shutdown: Scheduled digital out event will exceed max_duration
```

This is not a tuning problem. In `klippy/extras/heaters.py`:

* `MAX_HEAT_TIME = 3.0` (line 14), applied to the heater pin as
  `setup_max_duration(MAX_HEAT_TIME)` (line 62). The MCU shuts the output down
  unless the host refreshes the heater PWM within **3 seconds**.
* `self.pwm_delay = self.sensor.get_report_time_delta()` (line 32). The heater
  refreshes PWM on *its sensor's* reporting cadence.
* For the AHT10 that delta is `aht10_report_time`, whose floor was **5s**
  (`aht10.py:40`, `minval=5`).
* Line 80 then computes
  `next_pwm_time = pwm_time + MAX_HEAT_TIME - (3. * pwm_delay + 0.001)`
  = `read_time + 5 + 3 - 15.001`, roughly **7 seconds in the past**.

5s > 3s, so the refresh can never land inside the window. Unpatched, an AHT10
cannot drive a Klipper heater at all -- only report temperature.

It looks healthy while the heater is off, because a heater at zero power
schedules no nonzero digital-out event to exceed its duration.

## The fix

Drop the floor so the sensor can be polled fast enough to satisfy the heater:

```python
self.report_time = config.getint('aht10_report_time', 30, minval=1)
```

### Why 1 and not 2

The real callback interval is longer than `report_time`. `_sample_aht` returns
`measured_time + self.report_time`, and `_make_measurement` first spends
`reactor.pause(monotonic() + .110)` waiting on the conversion. The busy-retry
loop (`MAX_BUSY_CYCLES = 5`) can add up to ~0.55s more.

| `report_time` | typical spacing | worst case with retries | vs 3.0s limit |
|---|---|---|---|
| 5 | ~5.11s | ~5.66s | fails immediately |
| 2 | ~2.11s | ~2.66s | only 0.34s of margin |
| 1 | ~1.11s | ~1.55s | ~1.45s of margin |

So **1**. The AHT10's conversion is ~75-110ms, so the hardware sustains it.

## Applying

```bash
cd ~/klipper
git apply ~/klipper-configs/klipper-patches/0002-aht10-allow-fast-report-time.patch
```

Then restart the **process**, not the firmware:

```bash
curl -X POST "http://voron.lan:7125/machine/services/restart?service=klipper"
# or: sudo systemctl restart klipper
```

`FIRMWARE_RESTART` is **not enough** and will look like the patch failed with
`Option 'aht10_report_time' ... must have minimum of 5`. Klippy's restart loop
rebuilds its objects inside the same Python process, so `sys.modules` still
holds the old module. Any `.py` change needs a real process restart. (Patch
0001's README says "or FIRMWARE_RESTART" -- that is wrong for the same reason.)

Like patch 0001 this leaves the Klipper repo dirty, which blocks Moonraker's
update manager (`git_deploy.py:90`). Before a Klipper update:

```bash
git -C ~/klipper stash push klippy/extras/aht10.py klippy/configfile.py
# ...update...
git -C ~/klipper stash pop
```

## Costs and caveats

* **Self-heating.** Measurement duty rises from ~2% (80ms per 5.11s) to ~7%
  (80ms per 1.11s). AHT sensors are known to self-heat when polled hard. Expect
  a small positive offset on the air reading; characterise it by comparing
  against the pre-patch baseline at the same ambient.
* **More chances to collide with the neopixels.** DRYBOX bitbangs 40 neopixels
  for `led_effect` and bitbangs software I2C on PB3/PB4; both are
  timing-sensitive. 1Hz polling is 5x the exposure of 5s polling.
* **A failed measurement is silent and permanent.** `_sample_aht` does
  `if not self._make_measurement(): self.temp = self.humidity = .0; return
  self.reactor.NEVER` -- it returns *before* the `min_temp` check, so a dead
  AHT10 stops sampling and never shuts the printer down on its own. When the
  AHT10 is the heater sensor the backstop is the MCU's `max_duration`, which
  turns the output off and shuts the MCU down. That is fail-safe but noisy, and
  it means `min_temp` buys nothing against this failure mode.

## Upstreaming

Worth proposing. `minval=5` appears arbitrary -- the AHT10 converts in ~75ms,
and the value silently makes the sensor unusable for the heater role that
`aht10.py` itself registers via `add_sensor_factory`. A sensor advertised as a
heater sensor should be pollable fast enough to drive a heater.
