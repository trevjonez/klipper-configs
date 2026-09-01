# Derived psychrometric sensors: dew point, and dew point depression against a
# reference sensor.
#
# WHY THIS EXISTS
#
# Relative humidity is not a measure of how much water is present -- it is a
# measure relative to what the air could hold at its current temperature, so
# heating a sealed box makes RH plummet while not one molecule of water has
# left. That is not a hypothetical: an 80-minute drybox run on 2026-09-01 drove
# RH from 29.7% to 12.7% while the actual water content ROSE for the first
# quarter hour. Reading RH alone gets the sign of the result wrong.
#
# The temperature-independent measures are vapour pressure (hPa) and its more
# legible cousin the dew point (C). Both are computed here.
#
# WHY DEPRESSION AGAINST AMBIENT IS THE EFFICACY NUMBER
#
# A drybox with no desiccant can only expel moisture by leaking it into the
# room, so room vapour pressure is the floor it is working against -- it cannot
# leak itself drier than the air it leaks into. Measured on this machine: the
# box plateaued at 12.1-13.0 hPa during a heat cycle while ambient sat at
# 12.19 hPa. Against RH those look like completely different numbers; against
# the ambient reference they are the same number, and the plateau is explained.
#
# So the single most useful line to plot is dew(reference) - dew(sensor): how
# many degrees drier the box is than the room it lives in. Positive is good.
# It goes NEGATIVE during a heat cycle as water is driven out of the spools
# into the box air faster than the box can shed it, which is itself the signal
# that drying is happening.
#
# WHY THE VALUE IS REPORTED AS A TEMPERATURE
#
# Moonraker only keeps history for four fields. components/data_store.py:96:
#
#     valid_fields = ("temperature", "target", "power", "speed")
#
# Humidity and pressure are live-only -- Mainsail prints them on the sensor row
# but they are never stored and never graphed. Anything that needs to be a line
# on the chart must therefore arrive as `temperature` on an object listed in
# heaters.available_sensors. Wrapping these as sensor_types inside ordinary
# [temperature_sensor] sections gets exactly that: PrinterSensorGeneric calls
# pheaters.register_sensor() for us, and the units genuinely are degrees C.
#
# The richer fields are still published on a parallel object (e.g.
# `dew_point drybox_dewpoint`) for one-shot queries, the same way bme280.py
# registers itself alongside its [temperature_sensor] to expose humidity.
#
# THIS SENSOR NEVER SHUTS THE PRINTER DOWN
#
# extras/temperature_combined.py -- the mainline precedent for a sensor built
# from other sensors -- calls printer.invoke_shutdown() on a min/max excursion.
# That is right for a sensor guarding a heater and wrong for a derived
# diagnostic: dew point depression legitimately goes negative during a normal
# dry cycle, and a habitual `min_temp: 0` would then abort a running print over
# a number that is only ever advisory. min_temp/max_temp are accepted (Klipper
# passes them in regardless) and logged when exceeded, but never enforced.
#
# LOADING
#
# Klipper only auto-loads the sensor modules listed in
# klippy/extras/temperature_sensors.cfg, which is a file in the Klipper repo.
# Rather than carry a second patch against upstream, this module is pulled in by
# a bare [psychrometrics] section in the printer config. Klipper loads sections
# in file order, so that section MUST appear before the first
# [temperature_sensor] that names one of these sensor_types -- otherwise setup
# fails with "Unknown temperature sensor 'dew_point'", which at least says so
# plainly.
#
# Lives in klipper-configs and is symlinked into klippy/extras/ so it survives
# a Klipper update instead of being clobbered by one. Adding or changing this
# file needs a `systemctl restart klipper` -- RESTART and FIRMWARE_RESTART both
# reuse the running process and will not re-import it.

import logging
import math

# Matches the source BME280s, which report every 0.8s (bme280.py:9).
REPORT_TIME = 1.0

# Magnus-Tetens with the Sonntag/WMO coefficients over water. Good to about
# 0.1C across -45..60C, which covers every zone this machine has. These are the
# same constants used for the hand calculations recorded in
# home-network/docs/drybox-air-control.md -- keep them in step or the logged
# numbers stop matching the graphed ones.
MAGNUS_A = 17.62
MAGNUS_B = 243.12
ES_ZERO = 6.112  # hPa, saturation vapour pressure at 0C

# Absolute humidity constant: g*K/(hPa*m^3), from the ideal gas law for water
# vapour (M_w / R = 18.02 / 0.08314).
ABS_HUMIDITY_K = 216.7

# RH readings can legitimately arrive as 0 from a sensor that has not completed
# a conversion yet. log(0) is -inf, so floor the input rather than letting a
# startup transient produce a nonsense dew point.
MIN_HUMIDITY = 0.05


def saturation_vapor_pressure(temp_c):
    """Saturation vapour pressure over water, hPa."""
    return ES_ZERO * math.exp(MAGNUS_A * temp_c / (MAGNUS_B + temp_c))


def vapor_pressure(temp_c, humidity_pct):
    """Actual vapour pressure, hPa. This is the water-content measure."""
    return saturation_vapor_pressure(temp_c) * humidity_pct / 100.


def dew_point(vapor_hpa):
    """Dew point in C for a given vapour pressure."""
    ratio = math.log(vapor_hpa / ES_ZERO)
    return MAGNUS_B * ratio / (MAGNUS_A - ratio)


def absolute_humidity(temp_c, vapor_hpa):
    """Water mass per unit volume, g/m^3."""
    return ABS_HUMIDITY_K * vapor_hpa / (temp_c + 273.15)


class PsychrometricSensor:
    def __init__(self, config, sensor_type, use_reference):
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.name = config.get_name().split()[-1]
        self.sensor_type = sensor_type
        self.source_name = config.get('sensor')
        self.reference_name = config.get('reference') if use_reference else None
        # Klipper hands the sensor object back to PrinterSensorGeneric and then
        # calls setup_* on it; temperature_combined sets this for the same
        # reason, so the object can stand in for its own sensor.
        self.sensor = self
        self.temperature_callback = None
        self.source = self.reference = None
        self.min_temp = self.max_temp = 0.
        self._warned = False
        self.last_temp = 0.
        # Everything the maths produced last tick, for get_status.
        self.data = {}
        self.printer.add_object("%s %s" % (sensor_type, self.name), self)
        self.update_timer = self.reactor.register_timer(self._update_event)
        self.printer.register_event_handler('klippy:connect',
                                            self._handle_connect)
        self.printer.register_event_handler('klippy:ready', self._handle_ready)

    def _lookup_humidity_sensor(self, name):
        sensor = self.printer.lookup_object(name, None)
        if sensor is None:
            raise self.printer.config_error(
                "psychrometrics '%s': no such object '%s'. Use the object name "
                "that reports humidity, e.g. 'bme280 drybox', not the "
                "[temperature_sensor] section name." % (self.name, name))
        if not hasattr(sensor, 'get_status'):
            raise self.printer.config_error(
                "psychrometrics '%s': '%s' has no status."
                % (self.name, name))
        status = sensor.get_status(self.reactor.monotonic())
        for field in ('temperature', 'humidity'):
            if status.get(field) is None:
                raise self.printer.config_error(
                    "psychrometrics '%s': '%s' does not report %s. A humidity "
                    "capable sensor (BME280/BME680/AHT10/HTU21D/SHT3X) is "
                    "required." % (self.name, name, field))
        return sensor

    def _handle_connect(self):
        self.source = self._lookup_humidity_sensor(self.source_name)
        if self.reference_name is not None:
            self.reference = self._lookup_humidity_sensor(self.reference_name)

    def _handle_ready(self):
        # Same race temperature_combined documents: a source can still be
        # mid-conversion at ready and report zeros. Start a beat later.
        self.reactor.update_timer(self.update_timer,
                                  self.reactor.monotonic() + 1.)

    # -- sensor interface expected by PrinterSensorGeneric ------------------

    def setup_minmax(self, min_temp, max_temp):
        # Recorded, deliberately not enforced. See the header.
        self.min_temp = min_temp
        self.max_temp = max_temp

    def setup_callback(self, temperature_callback):
        self.temperature_callback = temperature_callback

    def get_report_time_delta(self):
        return REPORT_TIME

    def get_temp(self, eventtime):
        return self.last_temp, 0.

    # -- computation --------------------------------------------------------

    def _read(self, sensor, eventtime):
        status = sensor.get_status(eventtime)
        temp = status.get('temperature')
        humidity = status.get('humidity')
        if temp is None or humidity is None:
            return None
        humidity = max(humidity, MIN_HUMIDITY)
        vapor = vapor_pressure(temp, humidity)
        return {
            'temperature': temp,
            'humidity': humidity,
            'vapor_pressure': vapor,
            'dew_point': dew_point(vapor),
            'absolute_humidity': absolute_humidity(temp, vapor),
        }

    def _update_event(self, eventtime):
        src = self._read(self.source, eventtime)
        ref = (self._read(self.reference, eventtime)
               if self.reference is not None else None)
        if src is not None and (self.reference is None or ref is not None):
            data = {
                'source': self.source_name,
                'source_dew_point': round(src['dew_point'], 2),
                'source_vapor_pressure': round(src['vapor_pressure'], 3),
                'source_absolute_humidity':
                    round(src['absolute_humidity'], 3),
            }
            if ref is None:
                value = src['dew_point']
            else:
                # How many degrees of dew point drier the source is than the
                # reference. Positive means the box is beating the room.
                value = ref['dew_point'] - src['dew_point']
                data.update({
                    'reference': self.reference_name,
                    'reference_dew_point': round(ref['dew_point'], 2),
                    'reference_vapor_pressure':
                        round(ref['vapor_pressure'], 3),
                    'vapor_pressure_deficit':
                        round(ref['vapor_pressure'] - src['vapor_pressure'], 3),
                })
            data['value'] = round(value, 2)
            self.last_temp = value
            self.data = data
            self._check_range(value)
        # Publish even on a skipped read so the graph holds its last value
        # rather than gapping.
        if self.temperature_callback is None:
            return self.reactor.monotonic() + REPORT_TIME
        mcu = self.printer.lookup_object('mcu')
        measured_time = self.reactor.monotonic()
        self.temperature_callback(mcu.estimated_print_time(measured_time),
                                  self.last_temp)
        return measured_time + REPORT_TIME

    def _check_range(self, value):
        out = value < self.min_temp or value > self.max_temp
        if out and not self._warned:
            self._warned = True
            logging.warning(
                "psychrometrics %s: %.2f outside %.2f..%.2f. Advisory only, "
                "not enforced.", self.name, value, self.min_temp,
                self.max_temp)
        elif not out:
            self._warned = False

    def get_status(self, eventtime):
        status = {'temperature': round(self.last_temp, 2)}
        status.update(self.data)
        return status


def load_config(config):
    pheaters = config.get_printer().load_object(config, "heaters")
    pheaters.add_sensor_factory(
        "dew_point",
        lambda cfg: PsychrometricSensor(cfg, "dew_point", False))
    pheaters.add_sensor_factory(
        "dew_point_depression",
        lambda cfg: PsychrometricSensor(cfg, "dew_point_depression", True))
    return None
