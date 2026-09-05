# Z offset trim buttons that bypass the G-Code mutex.
#
# [gcode_button] runs press_gcode through gcode.run_script(), which takes the
# G-Code mutex, so a press during a macro is not even parsed until the macro
# returns. Same problem, same fix as klippy_extras/estop_button.py -- see that
# file's header for the full explanation.
#
# WHAT THIS STILL CANNOT DO: a G-Code offset applies to moves parsed AFTER it
# changes. Moves already in the lookahead are committed and cannot be rewritten
# by anything. So a press reaches the nozzle only once the queued moves drain
# -- measured at 1.0-1.8s on this machine -- and a single long G1 cannot be
# adjusted at all while it runs. A 200mm prime line emitted as ONE move is
# immune to this button no matter how the button is wired; it has to be sliced
# into short segments for live trimming to mean anything.
#
# This bypasses voron_knomi.cfg's [gcode_macro SET_GCODE_OFFSET] wrapper, which
# is currently a pure passthrough to SET_GCODE_OFFSET_ORIG, so nothing is lost.
# But that wrapper declares variable_runtime_offset, and SET_Z_FROM_PROBE adds
# it back after a tap -- clearly meant to carry manual babystepping across a
# re-tap. Nothing anywhere writes runtime_offset, so it is permanently 0 and
# that carry-over silently does not happen. If it is ever wired up, this module
# has to record its steps there too or the buttons will be the one path that
# still gets wiped by a tap.
#
# Offsets are applied the way gcode_move.cmd_SET_GCODE_OFFSET does for
# Z_ADJUST. A RESTORE_GCODE_STATE in an enclosing macro would revert an
# adjustment made while that macro is running, exactly as it would revert a
# SET_GCODE_OFFSET; nothing in voron.cfg does that, but the MMU macros do.

# KlipperScreen drops any popup raised less than a second after the previous
# one (show_popup_message, from_ws branch). Sit clear of that with margin: the
# comparison happens on the KlipperScreen host at receive time, so it is
# subject to scheduling and transport jitter, not just our own spacing.
MIN_TOAST_INTERVAL = 1.25


class ZOffsetButton:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.name = config.get_name().split()[-1]
        self.step = config.getfloat('step')
        self.last_state = 0
        buttons = self.printer.load_object(config, "buttons")
        # Debounced, unlike estop_button. There a bounce is a harmless repeat
        # of an idempotent shutdown; here every extra edge is another step of
        # offset, so a bouncing contact would silently land on a wrong value.
        # Set debounce_delay in the config section -- it defaults to 0.
        buttons.register_debounce_button(config.get('pin'),
                                         self.button_callback, config)
        self.toast_timer = self.reactor.register_timer(self._flush_toast)
        self.next_toast = 0.
        self.gcode = self.printer.lookup_object('gcode')
        self.gcode.register_mux_command(
            "QUERY_BUTTON", "BUTTON", self.name, self.cmd_QUERY_BUTTON,
            desc=self.cmd_QUERY_BUTTON_help)

    cmd_QUERY_BUTTON_help = "Report on the state of a button"
    def cmd_QUERY_BUTTON(self, gcmd):
        gcmd.respond_info("%s: %s" % (self.name, self.get_status()['state']))

    def _z_offset(self):
        return self.printer.lookup_object('gcode_move').homing_position[2]

    def _emit_toast(self, z):
        # The "echo: " prefix is what makes KlipperScreen raise a popup
        # (ks_includes/notification_handler.py). respond_raw fans out to the
        # output callbacks directly and takes no mutex.
        self.gcode.respond_raw("echo: Z offset %+.4f" % (z,))

    def _flush_toast(self, eventtime):
        # Trailing edge of a burst: whatever the offset ended up at.
        self._emit_toast(self._z_offset())
        self.next_toast = eventtime + MIN_TOAST_INTERVAL
        return self.reactor.NEVER

    def button_callback(self, eventtime, state):
        self.last_state = state
        if not state:
            return
        gcode_move = self.printer.lookup_object('gcode_move')
        # The two fields cmd_SET_GCODE_OFFSET writes for a Z_ADJUST.
        gcode_move.base_position[2] += self.step
        gcode_move.homing_position[2] += self.step
        z = self._z_offset()
        # display_status is not rate limited and KlipperScreen renders it as
        # the job-status LCD line, so this stays correct through a fast burst
        # even while the popups are being throttled.
        display = self.printer.lookup_object('display_status', None)
        if display is not None:
            display.message = "Z %+.4f" % (z,)
        now = self.reactor.monotonic()
        if now >= self.next_toast:
            # Leading edge: the first press after a quiet spell shows at once.
            self._emit_toast(z)
            self.next_toast = now + MIN_TOAST_INTERVAL
            self.reactor.update_timer(self.toast_timer, self.reactor.NEVER)
        else:
            # Too soon -- KlipperScreen would drop this one. Rather than lose
            # it, collapse the rest of the burst into a single trailing popup
            # carrying the final value. Re-arming an already-armed timer to the
            # same deadline is a no-op, so a long press-and-hold still yields
            # exactly one trailing popup per interval.
            self.reactor.update_timer(self.toast_timer, self.next_toast)

    def get_status(self, eventtime=None):
        return {
            'state': "PRESSED" if self.last_state else "RELEASED",
            'z_offset': self._z_offset(),
        }


def load_config_prefix(config):
    return ZOffsetButton(config)
