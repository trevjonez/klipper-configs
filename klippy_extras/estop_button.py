# Emergency stop button that bypasses the G-Code mutex.
#
# [gcode_button] runs its script through gcode.run_script(), which takes the
# G-Code mutex (gcode.py, run_script). A macro like PRINT_START is a single
# command line, so the whole macro executes inside one _process_commands call
# holding that mutex -- a button-bound M112 sat waiting on the mutex until the
# macro returned, which is to say it never fired when it was wanted. Presses
# landing between virtual_sdcard lines got through; presses during a macro did
# not.
#
# This calls invoke_shutdown() straight from the button callback instead, which
# is what webhooks.py's _handle_estop_request does for Mainsail's e-stop
# button. Button callbacks arrive on the reactor thread from MCU message
# handling, the same thread webhooks runs on, so it is the identical call site
# with a pin as the trigger.
#
# Still a software stop: it goes through klippy. If klippy itself is wedged,
# nothing here runs. A contactor on the PSU is the only stop that does not
# depend on software state.


class EStopButton:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.name = config.get_name().split()[-1]
        self.pin = config.get('pin')
        self.last_state = 0
        buttons = self.printer.load_object(config, "buttons")
        # register_buttons, not register_debounce_button: DebounceButton adds
        # latency to the one press that must not have any, and bounce is
        # harmless here because invoke_shutdown returns early once
        # in_shutdown_state is set.
        buttons.register_buttons([self.pin], self.button_callback)
        self.printer.lookup_object('gcode').register_mux_command(
            "QUERY_BUTTON", "BUTTON", self.name, self.cmd_QUERY_BUTTON,
            desc=self.cmd_QUERY_BUTTON_help)

    cmd_QUERY_BUTTON_help = "Report on the state of a button"
    def cmd_QUERY_BUTTON(self, gcmd):
        gcmd.respond_info("%s: %s" % (self.name, self.get_status()['state']))

    def button_callback(self, eventtime, state):
        self.last_state = state
        if state:
            self.printer.invoke_shutdown(
                "Shutdown due to %s emergency stop button" % (self.name,))

    def get_status(self, eventtime=None):
        if self.last_state:
            return {'state': "PRESSED"}
        return {'state': "RELEASED"}


def load_config_prefix(config):
    return EStopButton(config)
