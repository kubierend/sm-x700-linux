# Charging

Two chips, two drivers (kernel patch 0009):

| Chip | Bus | Driver | Role |
|---|---|---|---|
| MAX77705 | i2c5 @0x69 (+ gauge @0x36) | `max77705-charger-monitor` | switching charger, USB-C/PD firmware mailbox, USB role + OTG boost, DP alt mode, thermal policy |
| SM5440 | i2c1 @0x63 | `sm5440-charger-monitor` | 2:1 charge pump for PD PPS direct charging, its ADC and protections |

Register meanings and the charging states follow Samsung's GPL drivers (SM-X706N open-source
kernel, `drivers/battery/`); the policy is our own, kept deliberately conservative.

## Switching charging (MAX77705)

- Always available on any USB source. Normal-band charge current is 1.5 A
  (`samsung,normal-band-charge-current-microamp` in the DTS; stock allows 3.15 A).
- Thermal policy from the battery, "blanket" and charger NTCs (PMK8350 ADC, raw codes run
  through Samsung's tables): reduced current in the COOL/WARM zones, float voltage down to
  4150 mV when WARM, charging off outside the safe range.
- The driver is the only sender on the USB-C firmware mailbox (one command at a time); PD
  fixed and PPS contracts, host-mode VBUS and the alternate mode all go through it.

## Direct charging (SM5440 charge pump)

Starts on its own when a PD source with a PPS APDO is attached and every entry gate passes:
no latched faults, thermal policy in the normal band, battery voltage inside the entry window,
NTC and die temperatures in range.

Session sequence: the SM5440 driver takes a **lease** on the MAX77705 (switching charging off,
input held at 500 mA), requests a bounded PPS point, verifies VBUS on its own ADC, then
programs and enables the pump. Teardown runs in reverse and always ends on fixed 5 V.

Limits:

| | |
|---|---|
| PPS request | 8.2-10 V (stock's ceiling; VBUS OVP 11 V), up to 5 A including the 500 mA buck allowance |
| Pump input current | 4500 mA (`max_pump_ma`), i.e. stock's 45 W |
| Thermal steps | pump current reduced in 250 mA steps from 43 C NTC; hard stops 50 C NTC / 90 C die |
| Watchdog | SM5440 2 s watchdog while pumping, 5 s lease on the MAX77705 side |
| Session | 900 s (`session_max_s`), then re-validated and restarted |

Measured: ~30 W into the tablet, 5.4 A into the battery at 4.08 V (39 % SOC), stable across
thermal steps; CV taper takes over above ~50 %. Not every charger/cable pair reaches the limit.

There is **no cable e-marker check** (Samsung's downstream path has none either). A
compliant PD source only advertises a 5 A APDO when the attached cable carries 5 A.

## Knobs and diagnostics

Module parameters (`/sys/module/<driver>/parameters/`):

| Parameter | Default | |
|---|---|---|
| `sm5440_charger_monitor.allow_pump` | 1 | 0 stops direct charging (also ends a running session) |
| `sm5440_charger_monitor.max_pump_ma` | 4500 | 1000-4500 |
| `sm5440_charger_monitor.session_max_s` | 900 | 10-900 |
| `max77705_charger_monitor.dp_altmode` | 1 | DisplayPort alternate mode (read-only) |

sysfs on the devices: MAX77705 `usb_port`, `temperatures`, `pd_capabilities`, `pd_state`;
SM5440 `adc`, `faults`, `registers`, `direct_charge` (state; root can start/stop a session).
Failed PD messages that end a session are logged with the mailbox and PPS state.
