# Raises Klipper's multi-MCU homing trsync timeout (klippy/mcu.py TRSYNC_TIMEOUT,
# stock 0.025s).
#
# The Cartographer is its own USB MCU, so during Z homing its trigger state is
# relayed through the host to the MCU driving the Z steppers. One late relay aborts
# the home with "Communication timeout during homing" -- it did on 2026-09-26, on a
# scan-home fast approach. 0.05 only lengthens the backstop for a relay that went
# quiet; a normal trigger is unaffected.
#
# An extra rather than an edit to mcu.py, so the Klipper checkout stays clean
# (Moonraker stops flagging it dirty) and a Klipper update cannot silently revert
# it. mcu.py reads the module global when a homing starts (MCU_trsync.start), so
# setting it here at config load takes effect for every home.
import logging
import mcu


class TrsyncTimeout:
    def __init__(self, config):
        self.timeout = config.getfloat('timeout', 0.05, minval=0.025, maxval=0.25)
        mcu.TRSYNC_TIMEOUT = self.timeout
        logging.info("trsync_timeout: TRSYNC_TIMEOUT set to %.3fs", self.timeout)

    def get_status(self, eventtime):
        return {'timeout': mcu.TRSYNC_TIMEOUT}


def load_config(config):
    return TrsyncTimeout(config)
