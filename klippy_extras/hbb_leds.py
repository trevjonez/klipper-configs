# HBB button LEDs driven from a reactor timer instead of a delayed_gcode.
#
# [delayed_gcode _hbb_status_leds] used to repaint these every 5s. A delayed_gcode
# runs through gcode.run_script(), which takes the G-Code mutex, and START_PRINT
# (like any macro) holds that mutex from its first line to its last. So through
# a 300s soak, QGL, the mesh and M109 the loop simply did not run: the heater
# LEDs stayed dark after M140/M104 and the homed LED stayed white after G28,
# until the whole macro returned. Same root cause as estop_button.py and
# zoffset_button.py -- see those headers.
#
# This reads the state straight off the objects (heater targets, homed axes, the
# _HBB_VARS.night flag) and writes the neopixel the way SET_LED SYNC=0 does. No
# template, no mutex, no toolhead. A pass that changes nothing sends nothing:
# LEDHelper dedupes per LED and _check_transmit returns early.
#
# LED 4: idle until homed, yellow while QGL or the Z touch after it is still
# pending, green once a Z home has completed after QGL was applied.
#
# It also stops a side effect of the old loop. SET_LED defaults to SYNC=1, which
# goes through toolhead.register_lookahead_callback -> get_last_move_time ->
# _calc_print_time, and on an idle toolhead that fires toolhead:sync_print_time.
# idle_timeout treats that as activity, so four SET_LEDs every 5s kept pushing
# its 1800s timeout back. With this in place idle_timeout can fire again --
# see the deploy notes before relying on an overnight drybox run.
#
# Only LED state lives here. The nevermore and chamber-ceiling logic that rode
# along in the old loop issue real fan commands and stay in G-Code.

import logging

HOMED = (0., .5, 0., 0.)
# Homed, but not ready to print: QGL not applied yet, or applied with no Z
# home (the hot-bed touch) since. START_PRINT sits here through the soak.
LEVELLING = (.5, .4, 0., 0.)
HEATING = (1., 0., 0., 0.)
HOMED_INDEX = 4
# heater name (as heaters.lookup_heater wants it) -> HBB LED index
HEATER_INDEX = (('extruder', 6), ('heater_bed', 7), ('drybox', 3))

# Drybox strip effects, defined in voron.cfg beside [neopixel drybox]. The
# effects animate on led_effect's own reactor timer and were never blocked;
# only the switch between them was, because that was a SET_LED_EFFECT inside
# the mutex-bound loop.
DRYBOX_HEATER = 'drybox'
FX_HEATING = ['drybox_heating_%d' % i for i in range(1, 9)]
FX_IDLE_DIM = 'drybox_idle_dim'
FX_IDLE = 'drybox_idle'
FX_PARAMS = {'REPLACE': '1', 'FADETIME': '0.5'}


class HBBLeds:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.led_name = config.get('led')
        self.interval = config.getfloat('interval', 0.5, above=0.05)
        # Idle colour is the neopixel's own initial colour, read once here. This
        # is what _HBB_VARS.init_r/g/b cached for the templates.
        np = config.getsection('neopixel ' + self.led_name)
        self.idle = (np.getfloat('initial_RED', 0.),
                     np.getfloat('initial_GREEN', 0.),
                     np.getfloat('initial_BLUE', 0.), 0.)
        self.printer.register_event_handler('klippy:ready', self._handle_ready)

    def _handle_ready(self):
        lookup = self.printer.lookup_object
        helper = lookup('neopixel ' + self.led_name).led_helper
        # Private LEDHelper API, the same calls led_effect.py makes. Bound here
        # so a Klipper update that renames them fails loudly at startup rather
        # than inside the timer.
        self.set_color = helper._set_color
        self.transmit = helper._check_transmit
        self.kin = lookup('toolhead').get_kinematics()
        self.qgl = lookup('quad_gantry_level')
        self.qgl_at = self.z_home_at = None
        self.printer.register_event_handler('homing:home_rails_end',
                                            self._handle_home_rails_end)
        pheaters = lookup('heaters')
        self.heaters = [(pheaters.lookup_heater(n), i) for n, i in HEATER_INDEX]
        self.drybox = pheaters.lookup_heater(DRYBOX_HEATER)
        self.vars = lookup('gcode_macro _HBB_VARS')
        self.fx_heating = [lookup('led_effect ' + n) for n in FX_HEATING]
        self.fx_idle_dim = lookup('led_effect ' + FX_IDLE_DIM)
        self.fx_idle = lookup('led_effect ' + FX_IDLE)
        self.gcode = lookup('gcode')
        self.reactor.register_timer(self._tick, self.reactor.NOW)

    def _tick(self, eventtime):
        if self.printer.is_shutdown():
            return self.reactor.NEVER
        # An exception escaping a reactor timer is not caught by the reactor
        # and takes klippy down -- mid-print. A cosmetic LED is never worth that.
        try:
            self._update(eventtime)
        except Exception:
            logging.exception("hbb_leds: update failed")
        return eventtime + self.interval

    def _handle_home_rails_end(self, homing_state, rails):
        if 2 in homing_state.get_axes():
            self.z_home_at = self.reactor.monotonic()

    def _update(self, eventtime):
        homed = 'xyz' in self.kin.get_status(eventtime)['homed_axes']
        # Klipper clears 'applied' itself on motor_off (z_tilt.py ZAdjustStatus), so this
        # only has to remember when it last went true.
        if not self.qgl.get_status(eventtime)['applied']:
            self.qgl_at = None
        elif self.qgl_at is None:
            self.qgl_at = eventtime
        ready = (self.qgl_at is not None and self.z_home_at is not None
                 and self.z_home_at > self.qgl_at)
        self.set_color(HOMED_INDEX, self.idle if not homed
                       else HOMED if ready else LEVELLING)
        for heater, index in self.heaters:
            target = heater.get_temp(eventtime)[1]
            self.set_color(index, HEATING if target > 0. else self.idle)
        self.transmit()
        self._update_drybox(eventtime)

    def _update_drybox(self, eventtime):
        # Compare against what is actually running, not a remembered flag, so a
        # stray STOP_LED_EFFECTS self-heals on the next pass (as the macro did).
        # 2 = heating, 1 = idle dim (night), 0 = idle bright, -1 = none running.
        if self.drybox.get_temp(eventtime)[1] > 0.:
            want = 2
        else:
            want = 1 if int(self.vars.variables.get('night', 0)) else 0
        if self.fx_heating[0].enabled:
            have = 2
        elif self.fx_idle_dim.enabled:
            have = 1
        elif self.fx_idle.enabled:
            have = 0
        else:
            have = -1
        if want == have:
            return
        fx = {2: self.fx_heating, 1: [self.fx_idle_dim], 0: [self.fx_idle]}
        for effect in fx[want]:
            # The effect's own handler, so REPLACE/FADETIME behave exactly as
            # SET_LED_EFFECT from G-Code. Calling it directly takes no mutex.
            gcmd = self.gcode.create_gcode_command(
                'SET_LED_EFFECT', 'SET_LED_EFFECT', dict(FX_PARAMS))
            effect.cmd_SET_LED_EFFECT(gcmd)


def load_config(config):
    return HBBLeds(config)
