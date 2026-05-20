# Scenario Contract

Use scenarios to collect evidence for one behavior at a time. Each scenario should define:

- Model name.
- Parameter source.
- Stop time.
- Disturbance timing.
- Expected comparison window.
- Signal map if the model does not use preferred log names.
- Pass/fail tolerances.

## Scenario classes

| Scenario | Purpose | Typical comparison |
|---|---|---|
| `nominal_steady_state` | Check baseline against `gfm_predict_steady_state` | Final P/Q/f/V/I |
| `load_step` | Check sharing, settling, and frequency droop after a load change | Final window after the last step |
| `p_ref_step` | Check commanded active-power tracking | Final P and f after the reference step |
| `q_ref_step` | Check voltage/reactive-power sign and settling | Final Q and V |
| `frequency_event` | Check response to external frequency perturbation | Event metrics plus recovery |
| `voltage_step` | Check voltage support and modulation headroom | V, Q, current, modulation |
| `three_phase_fault` | Check current limiting and recovery shape | Do not compare fault-on values to linear prediction |
| `unbalanced_fault` | Check per-phase/sequence limiting assumptions | Requires model-specific signals |
| `strong_grid_sweep` | Check high-SCR stability and pre-sync assumptions | Repeat across SCR/XR cases |

## Pre-event and post-event windows

For any scenario with a discrete disturbance (`p_ref_step`, `q_ref_step`, `frequency_event`, `voltage_step`, phase jump, breaker close), define **two** comparison windows:

- **Pre-event**: a settled interval ending at the disturbance time. Must be verified settled before its mean is reported — see `model-logging-contract.md` "Pre-disturbance settled-window check".
- **Post-event**: a settled interval ending at `t_stop`. Must be long enough for the controller's slowest mode to ring down.

If the pre-event window catches a transient (typically because the dVOC's persistent IC is near a saddle, or the stop time before the event was too short), the entire comparison is invalid. Report the pre-event settling status in every scenario that has an event, not just the final pass/fail row.

A "saddle in pre-event" failure looks like a controller mismatch to an unwary reader. It is not — it is a *scenario-windowing* issue and goes back to `$gfm-design` only for the IC sign, not for gain retuning.

## Fault and LVRT/FRT cases

For fault or LVRT/FRT work, validation must report assumptions rather than claim compliance:

- Voltage-time curve and measurement basis.
- Current-priority rule.
- Positive/negative sequence or per-phase behavior.
- Momentary-cessation assumption.
- Current-limit exit and recovery rule.
- Which current, voltage, DC-link, and thermal limits were logged.

Linear steady-state predictions from `gfm_predict_steady_state` are invalid during current limiting, saturation, or fault-on intervals. Compare only post-recovery steady windows unless the user provides a model-specific fault metric.
