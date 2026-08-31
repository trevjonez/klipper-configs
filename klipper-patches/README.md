# Klipper patch: make SAVE_CONFIG follow a symlinked printer.cfg

## The problem

`printer_data/config/printer.cfg` on this machine is a symlink to
`klipper-configs/voron.cfg`, so the real config lives in git. Klipper's
`SAVE_CONFIG` destroys that link every time it runs.

`klippy/configfile.py`, in `_cmd_SAVE_CONFIG`:

```python
os.rename(cfgname, backup_name)   # moves the SYMLINK to printer-<date>.cfg
os.rename(temp_name, cfgname)     # writes a fresh REGULAR file in its place
```

`os.rename` moves the symlink itself. Afterwards:

- `printer.cfg` is a regular file, detached from the repo
- the old symlink survives as `printer-<date>.cfg`, which looks like an
  ordinary backup and is easy to delete without noticing what it was
- `voron.cfg` stops receiving updates and silently goes stale
- every later `SAVE_CONFIG` rewrites the detached file, so it only breaks
  **once** — after which nothing looks wrong

The tell is a `printer-<date>.cfg` in the config directory that is itself a
symlink.

## The fix

Resolve the path before the backup/temp names are computed:

```python
cfgname = os.path.realpath(cfgname)
```

The rename then replaces the *target* file, the link survives, and the repo
copy stays current. Still a rename onto the final path, so it is still atomic.

### Placement matters

It must go **after** `build_fileconfig_with_includes(new_regular_data, cfgname)`
(configfile.py:374). That call resolves relative `[include]` directives against
the directory of the config path it is handed. This config uses
`[include ../../klipper-configs/...]`, which is relative to
`printer_data/config/`. Resolving the symlink earlier would make those
includes resolve from `klipper-configs/` instead and fail to load.

The `# Determine filenames` comment (configfile.py:381) is the correct seam.

## Applying

```bash
cd ~/klipper
git apply ~/klipper-configs/klipper-patches/0001-save_config-follow-symlinks.patch
sudo systemctl restart klipper
# or: curl -X POST "http://voron.lan:7125/machine/services/restart?service=klipper"
```

It must be a **process** restart. `RESTART` and `FIRMWARE_RESTART` are not
enough, and this was originally documented here as "or FIRMWARE_RESTART", which
is wrong -- verified 2026-08-31 by watching a patched `aht10.py` stay invisible
across a `FIRMWARE_RESTART`.

`klippy.py` (lines 93-107) runs `while 1: ... printer = Printer(...); res =
printer.run(); ... start_args['start_reason'] = res` -- both restart commands
return a reason into that loop and rebuild the printer objects **inside the same
Python process**. Extras are loaded with `importlib.import_module('extras.' +
module_name)`, which hits the `sys.modules` cache on the second pass, so the
edited file on disk is never re-read. The only difference between `RESTART` and
`FIRMWARE_RESTART` is that the latter also resets the MCUs.

Corollary: for **config-only** edits prefer `RESTART` -- `FIRMWARE_RESTART`
needlessly resets all six MCUs.

This leaves the Klipper repo dirty, which **blocks Moonraker's update
manager** (`git_deploy.py:90` refuses to update a modified repo). Before any
Klipper update:

```bash
git -C ~/klipper stash push klippy/configfile.py
# ...update...
git -C ~/klipper stash pop        # expect conflicts if the region moved
```

## Side effect: backups land in the repo

With the patch, backups are written next to the *target*, so they appear in
`klipper-configs/` as `voron-<date>.cfg` rather than in `printer_data/config/`.
Covered by `.gitignore` in this repo.

## Upstreaming

Worth proposing to Klipper. The change is three lines plus a comment, fixes a
silent data-detachment bug, and has no effect on configs that are not
symlinked (`realpath` on a regular file returns it unchanged). The main
argument to anticipate is whether backups belong beside the link or beside the
target; beside the target is more consistent, since that is the file actually
being replaced.

## Related: SAVE_CONFIG only ever writes the main config file

Worth knowing when deciding what goes in an `[include]`.

`SAVE_CONFIG` writes exactly one file — `cfgname`, the config klippy was
started with. Autosaved values go into the `#*#` block appended to the end of
it and act as overrides layered on top of whatever the includes defined.
Included files are never modified.

It will also refuse to save rather than create a competing definition.
`configfile.py:338`:

```python
def _disallow_include_conflicts(self, regular_fileconfig):
    for section in self.fileconfig.sections():
        for option in self.fileconfig.options(section):
            if regular_fileconfig.has_option(section, option):
                msg = ("SAVE_CONFIG section '%s' option '%s' conflicts "
                       "with included value" % (section, option))
                raise self.printer.command_error(msg)
```

`self.fileconfig` is the pending autosave data; `regular_fileconfig` is the
config as parsed *with* includes. If Klipper wants to autosave an option that is also literally written in
an **included** file, the entire `SAVE_CONFIG` aborts with that error.

Corrected 2026-08-31: an earlier version of this note said "main file or
included". That is wrong for the main file. `cmd_SAVE_CONFIG` first runs
`regular_data = self._strip_duplicates(regular_data, self.fileconfig)`,
and `_strip_duplicates` **comments out** (prefixes `#`) every option line in
the main file that the autosave block is about to define. So duplicates in
the main config are handled automatically and never reach the check -- which
is why an ordinary `PID_CALIBRATE` + `SAVE_CONFIG` works with `pid_Kp`
sitting in the body. Only included files are immune to that stripping, hence
the function's name.

### What this means for splitting config across files

**Any value a calibration writes must live in the main config, not an include.**
Macros, pin definitions and hardware sections can be split freely; autosaved
options cannot.

On this printer that covers, at minimum:

| Section | Autosaved options |
|---|---|
| `[probe_eddy_current btt_eddy]` | `calibrate`, `tap_threshold`, `reg_drive_current`, `z_offset` |
| `[temperature_probe btt_eddy]` | `calibration_temp`, `drift_calibration`, `drift_calibration_min_temp` |
| `[input_shaper]` | `shaper_type_x/y`, `shaper_freq_x/y` |
| `[bed_mesh default]` | the whole mesh |
| `[extruder]`, `[heater_bed]` | PID terms, after `PID_CALIBRATE` |

It also explains why a literal definition disappears once a calibration owns
the value — `reg_drive_current: 15` was commented out in the body when
`LDC_CALIBRATE_DRIVE_CURRENT` first wrote it to the autosave block. Leaving
both in place is exactly the conflict this check rejects.

So the planned split of probe logic out of `voron_knomi.cfg` is safe for the
macros (`SET_Z_FROM_PROBE`, `PROBE_EDDY_CURRENT_CALIBRATE_AUTO`), but
`[probe_eddy_current]` and `[temperature_probe]` themselves must stay in the
main config.
