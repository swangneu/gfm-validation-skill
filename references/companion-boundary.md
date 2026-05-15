# Companion Boundary

`gfm-validation` is the simulation-facing companion to `gfm-design`.

## Use `gfm-design` for

- Choosing droop, VSG, dVOC, PSC, or virtual impedance from specs.
- Computing `gfm_params.m`, inner-loop gains, droop slopes, inertia, dVOC gains, and protection-envelope fields.
- Predicting steady-state P/Q sharing, PCC frequency, PCC voltage, current headroom, and nominal small-signal poles.
- Defining what should be simulated next.

`gfm-design` should not call `sim()`.

## Use `gfm-validation` for

- Running a provided Simulink/Simscape model with a provided parameter struct.
- Reading `logsout`, `Simulink.SimulationOutput`, or exported time-series logs.
- Comparing settled simulation values to `gfm_predict_steady_state` outputs.
- Flagging current limiting, modulation saturation, missing signals, unstable settling, and scenario mismatches.
- Producing a validation report for nominal/load-step/frequency/voltage/fault cases.

`gfm-validation` should not silently redesign the controller. If the validation fails and retuning is needed, hand the user back to `gfm-design` with the measured discrepancy and scenario details.

## Claims boundary

Simulation evidence can support engineering review, but it is not:

- Grid-code compliance.
- Relay/protection certification.
- Hardware qualification.
- Field deployment approval.

State this boundary in every validation report that touches faults, LVRT/FRT, current limiting, strong-grid stability, or interconnection requirements.
