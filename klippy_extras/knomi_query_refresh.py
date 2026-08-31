# Adjust Klipper's status refresh period at runtime.
#
# klippy/webhooks.py defines SUBSCRIPTION_REFRESH_TIME = .25, the period of the
# timer that serves every objects/query and every subscription. It is the rate
# at which printer status comes into existence: nothing downstream -- not
# Moonraker's cache, not a websocket subscriber, not a faster network -- can be
# fresher than it, and a one-shot query blocks until the next tick, which is
# why an HTTP objects/query costs ~250ms.
#
# It is read inside _do_query() on every tick rather than captured at startup,
# so rebinding the module global takes effect on the next tick. That cannot be
# done from a gcode_macro -- Klipper's Jinja cannot import or rebind globals --
# hence this extra.
#
# Intended use is to raise the rate only for the span of an operation worth
# animating smoothly (homing, probing, quad gantry level) and put it back
# after, rather than running the whole machine faster.
#
#     SET_QUERY_REFRESH PERIOD=0.05
#     ... operation ...
#     SET_QUERY_REFRESH RESET=1
#
# Cost is real but small: the pass is shared, so one tick serves every client
# with a single get_status() per object. It runs inside
# reactor.assert_no_pause(), so it is non-yielding work made more frequent --
# but the multi-MCU homing keepalive that this machine depends on is NOT on
# this path. trsync_set_timeout is sent from the serialqueue's C background
# thread (chelper/trdispatch.c), off the Python reactor and out from under the
# GIL, which is presumably why it was written in C: 25ms is too tight to
# promise from Python.
#
# Lives in klipper-configs and is symlinked into klippy/extras/ so it survives
# a Klipper update instead of being clobbered by one.

import logging
import webhooks


class KnomiQueryRefresh:
    def __init__(self, config):
        self.printer = config.get_printer()
        # whatever Klipper shipped, so RESET cannot drift from upstream
        self.default = webhooks.SUBSCRIPTION_REFRESH_TIME
        self.min_period = config.getfloat('min_period', 0.02, above=0.)
        self.max_period = config.getfloat('max_period', 2., above=0.)
        gcode = self.printer.lookup_object('gcode')
        gcode.register_command('SET_QUERY_REFRESH', self.cmd_SET_QUERY_REFRESH,
                               desc=self.cmd_SET_QUERY_REFRESH_help)
        # Put it back if anything goes wrong. A macro that raises between
        # setting and resetting would otherwise leave the whole machine
        # running its status loop fast until the next restart.
        self.printer.register_event_handler("klippy:shutdown", self._restore)
        self.printer.register_event_handler("klippy:disconnect", self._restore)

    cmd_SET_QUERY_REFRESH_help = (
        "Set Klipper's status refresh period. PERIOD=<seconds> or RESET=1")

    def cmd_SET_QUERY_REFRESH(self, gcmd):
        if gcmd.get_int('RESET', 0):
            period = self.default
        else:
            period = gcmd.get_float('PERIOD', minval=self.min_period,
                                    maxval=self.max_period)
        webhooks.SUBSCRIPTION_REFRESH_TIME = period
        logging.info("knomi_query_refresh: status refresh period now %.3fs",
                     period)
        gcmd.respond_info("status refresh period = %.3fs (default %.3fs)"
                          % (period, self.default))

    def _restore(self):
        webhooks.SUBSCRIPTION_REFRESH_TIME = self.default

    def get_status(self, eventtime):
        return {'period': webhooks.SUBSCRIPTION_REFRESH_TIME,
                'default': self.default}


def load_config(config):
    return KnomiQueryRefresh(config)
