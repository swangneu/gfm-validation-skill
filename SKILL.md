---
name: gfm-validation
description: "Use when validating a grid-forming inverter Simulink or Simscape model against a gfm-design parameter struct or analytical prediction. Triggers include running sim(), checking logged P/Q/f/V/I signals, comparing simulation results to gfm_predict_steady_state, building validation reports, defining nominal/load-step/frequency/voltage/LVRT/FRT scenarios, and reviewing whether a GFM simulation supports the design assumptions. Companion to gfm-design; use this only after a model, logs, or explicit simulation-validation request exists."
---

# GFM Validation

## Overview

Validate a grid-forming inverter Simulink/Simscape model against the analytical design produced by the companion `gfm-design` skill. This skill may call `sim()` only when the user explicitly asks for simulation validation and provides a model or captured simulation output.

Keep the boundary sharp:

- `gfm-design`: choose/tune the control law, create `gfm_params.m`, predict steady state and small-signal poles. It does not call `sim()`.
- `gfm-validation`: run or inspect simulations, compare logged behavior against the design prediction, and produce a validation report. It does not retune the controller unless the user explicitly redirects back to design.

## Workflow

1. Confirm the validation target: model name/path, parameter source, scenario, stop time, and whether the user wants a live `sim()` run or analysis of existing `Simulink.SimulationOutput`/logs.
2. Load the model contract before running: read `references/model-logging-contract.md` when signal names, logging, or `logsout` are unclear.
3. Use `Simulink.SimulationInput` for live runs. Set `p` from the provided `gfm_params` source, apply the scenario, and call `sim()` without saving or structurally editing the model unless the user asks.
4. Extract logged signals: P, Q, PCC frequency, PCC voltage, current, and modulation index when available.
5. Compare the settled simulation window against `gfm_predict_steady_state` or a supplied prediction. Treat current limiting, modulation saturation, missing logs, and fault periods as validation findings, not tuning results.
6. Write artifacts under `runs/` or another ignored output directory. Do not claim grid-code or protection compliance; report simulation evidence only.

## Resource Map

Scripts:

- `scripts/gfm_validate_sim.m`: top-level runner. Accepts a model or existing sim output, resolves parameters/prediction, extracts logs, compares metrics, and writes a report.
- `scripts/gfm_extract_sim_signals.m`: extracts canonical signals from `logsout`, `SimulationOutput`, or simple structs.
- `scripts/gfm_compare_logs_to_prediction.m`: computes settled-window metrics and pass/fail checks against a prediction.
- `scripts/gfm_write_validation_report.m`: writes a concise Markdown validation report.
- `scripts/test_gfm_validation_helpers.m`: smoke test for helper scripts using synthetic logs; does not call `sim()`.

References:

- `references/companion-boundary.md`: division of responsibility between `gfm-design` and `gfm-validation`.
- `references/model-logging-contract.md`: expected model signals, names, units, and logging conventions.
- `references/scenario-contract.md`: scenario classes and what each can and cannot prove.

## Minimal Usage

From MATLAB, with both skills on disk:

```matlab
addpath('D:\AI\gfm-validation-skill\scripts');
addpath('D:\AI\gfm-design-skill\scripts');

p = gfm_params();  % or pass 'paramsFcn','gfm_params'
result = gfm_validate_sim( ...
    'model', 'my_gfm_model', ...
    'p', p, ...
    'gfmDesignPath', 'D:\AI\gfm-design-skill\scripts', ...
    'scenarioName', 'nominal_load_step', ...
    'tStop', 1.5);
```

For already captured logs:

```matlab
pred = gfm_predict_steady_state(p, 'verbose', false);
result = gfm_validate_sim( ...
    'simOutput', simOut, ...
    'prediction', pred, ...
    'runSim', false);
```

## Output Expectations

End with:

1. The model/scenario and whether `sim()` actually ran.
2. A pass/fail table for settled P, Q, frequency, voltage, current, and modulation checks, noting missing signals.
3. The report path and any generated run artifacts.
4. A boundary note: simulation evidence is not grid-code compliance, certification, protection proof, or field qualification.

If the logs disagree with the design prediction, first check signal names/units, steady-state window, limiter activity, saturation, and scenario timing before recommending controller retuning.
