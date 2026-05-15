# Model Logging Contract

Use this contract before calling `sim()` or comparing captured logs.

## Required steady-state signals

The validation scripts extract canonical signal fields from `logsout`, `SimulationOutput`, or structs. Prefer these names:

| Canonical | Preferred log name | Units | Meaning |
|---|---|---|---|
| `P` | `P_pcc` | W | Three-phase real power at PCC or load boundary |
| `Q` | `Q_pcc` | VAR | Three-phase reactive power at PCC or load boundary |
| `f` | `f_pcc` | Hz | PCC frequency |
| `V_LLrms` | `V_pcc_LLrms` | V | PCC line-line RMS voltage |
| `I_peak` | `I_peak` | A | Peak phase current, per inverter or limiting path |
| `m_index` | `modulation_index` | pu | Modulation index or max phase command magnitude |

Accepted aliases are implemented in `gfm_extract_sim_signals.m`, but use the preferred names in new models.

## Logging format

Best option:

- Enable signal logging to `logsout`.
- Log each signal as a `timeseries`.
- Keep units in the signal name or block annotation if Simulink unit metadata is not used.

Acceptable alternatives:

- A `Simulink.SimulationOutput` with top-level variables named like the preferred log names.
- A struct with fields such as `tout`, `P_pcc`, `Q_pcc`, `f_pcc`, and `V_pcc_LLrms`.

## Windowing

Compare only a settled window, not the entire transient. Default behavior uses the last 20 percent of the run. For events, pass `settleSeconds` or `settleWindow` so the comparison excludes switching transients, fault-on intervals, and reference steps.

## Sign conventions

Use the same convention as `gfm-design`:

- Positive `P_pcc`: inverter supplies real power to the PCC/load.
- Positive `Q_pcc`: lagging/injected reactive power according to the model convention used by `gfm_design_from_specs`.
- `f_pcc` in Hz, not rad/s.
- `V_pcc_LLrms` in line-line RMS volts, not phase RMS or phase peak.

If validation fails by a large factor of `sqrt(2)`, `sqrt(3)`, `2*pi`, or a sign flip, check units and Park/Q sign before changing controller gains.
