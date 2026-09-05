# Klipper patch: raise the neopixel chain-length cap

## The problem

The halo strip was replaced with a finer-pitch WS2812B run of **334 LEDs**.
Klipper refuses it at config parse:

```
configparser.Error: neopixel chain too long
```

`klippy/extras/neopixel.py`:

```python
MAX_MCU_SIZE = 500  # Sanity check on LED chain length
...
color_indexes.extend([(lidx, "RGBW".index(c)) for c in co])
self.color_map = list(enumerate(color_indexes))
if len(self.color_map) > MAX_MCU_SIZE:
    raise config.error("neopixel chain too long")
```

The cap is on **bytes, not pixels** -- `chain_count * len(color_order)`. GRB is
three bytes per pixel, so the stock limit is `500 // 3 = 166` LEDs (RGBW would
allow only 125). 334 needs 1002.

Splitting the strip does not rescue it. Two chains carry at most 332, two short
of 334; and an even split is 167 each, which is 501 bytes -- over by one. It
would take **four** chains, which means four GPIO pins, four data taps at the
corners, and rewriting every macro to address four objects.

## Why raising it is safe *here*

`MAX_MCU_SIZE` is not a hardware limit and its own comment says so. Neither of
the obvious guesses is what it guards:

* **Not MCU memory.** The buffer is `oid_alloc(sizeof(*n) + data_size)`, sized at
  config time, and `data_size` is a `uint16_t` rejecting only `& 0x8000` -- the
  firmware would accept 32767 bytes. The F429 has 256 KB and the halo is the only
  chain on it. 1002 bytes is nothing.
* **Not CPU time or step timing.** `src/neopixel.c` bit-bangs the line and
  disables interrupts only around each individual edge, not for the frame:

  ```c
  neopixel_delay(last_start, BIT_MIN_TICKS);
  irq_disable();
  neopixel_time_t start = neopixel_get_time();
  gpio_out_toggle_noirq(pin);
  irq_enable();
  ```

  A long chain never blocks the stepper interrupt.

What it actually guards is **reliability**. Every edge is checked, and one late
edge abandons the whole frame:

```c
if (neopixel_check_elapsed(last_start, start, bit_max_ticks))
    goto fail;
```
```c
fail:
    // A hardware irq messed up the transmission - report a failure
```

The host retries a bounded number of times, then gives up quietly --
`logging.info("Neopixel update did not succeed")`. So more LEDs means more edges
means a higher chance an update is silently dropped, worst while printing when
interrupt density peaks.

**That cost is near zero for this chain.** `[neopixel halo]` is set from
`initial_*` at boot and essentially never updated; a frame that is never sent
cannot be dropped. The same argument would *not* justify this for
`sb_leds`, which the `status_*` macros drive constantly.

1024 is the next round number above the 1002 required.

## Applying

```bash
cd ~/klipper
git apply ~/klipper-configs/klipper-patches/0003-neopixel-raise-max-chain-length.patch
sudo systemctl restart klipper
```

It must be a **process** restart. `RESTART` and `FIRMWARE_RESTART` rebuild the
printer objects inside the same Python process and hit the `sys.modules` cache,
so an edited extras file is never re-read -- see README.md for the full
reasoning.

Adds `klippy/extras/neopixel.py` to the dirty set, which **blocks Moonraker's
update manager** alongside `0001`. Stash both before any Klipper update.

## If the LEDs misbehave

The failure mode this trades against is *stale colour*, not a crash. If the halo
ever stops tracking a colour change, check for `Neopixel update did not succeed`
in `klippy.log` before suspecting wiring. Frequent hits would be the signal that
334 on one chain is too many in practice, and that the four-chain split is
needed after all.

## Upstreaming

Not worth proposing as-is. 500 is a defensible default and the real fix upstream
would be to make the cap configurable, or to derive it from the MCU's actual
free memory, rather than to raise a constant for everyone.
