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
2. **Run the pre-flight convention audit** before `sim()`: read `references/pre-flight-convention-audit.md`, query SPS source-block parameters, scan controller chart for hardcoded literals, verify the IC is not at a saddle. This is a *static* inspection — it reads the model without running it. Most "wrong amplitude" / "doesn't settle" reports trace back to issues this audit catches in under a minute.
3. Identify which depth tier the scenario lives in (steady-state, small-signal, large-signal) — see `gfm-design/references/gfm-test-scenarios.md`. Tier-1 amplitude/sign sanity checks apply to every run; small-signal `gfm_smallsignal` comparisons apply only at Tier 2; pre-event settled-window verification matters most at Tier 3.
4. Load the model logging contract before running: read `references/model-logging-contract.md` when signal names, logging, or `logsout` are unclear.
5. **Run the no-event baseline before layering any disturbance**: read `references/baseline-first-checks.md`. Strip scenario events (lock breakers closed, disable programmable variations, bypass fault blocks), confirm the controller block's sample time matches the algorithm's hardcoded `dt`, and verify the model settles to a correct steady state. This is the *dynamic* counterpart to step 2 — it separates "is the controller doing its job" from "is the event handled correctly." A baseline that does not settle invalidates every event-response conclusion built on top of it.
6. Use `Simulink.SimulationInput` for live runs. Set `p` from the provided `gfm_params` source, apply the scenario, and call `sim()` without saving or structurally editing the model unless the user asks.
7. Extract logged signals: P, Q, PCC frequency, PCC voltage, current, and modulation index when available.
8. Compare the settled simulation window against `gfm_predict_steady_state` or a supplied prediction. Treat current limiting, modulation saturation, missing logs, and fault periods as validation findings, not tuning results.
9. Write artifacts under `runs/` or another ignored output directory. Do not claim grid-code or protection compliance; report simulation evidence only.

## Resource map

References are organized by scope. Read essential ones for every validation run; read plus ones only when the scenario calls for them.

### Essential — General (every validation run)

| Reference | Purpose |
|---|---|
| `references/pre-flight-convention-audit.md` | Pre-`sim()` audit: SPS source-block parameter strings, controller-chart literals, block-swap port topology, baseline regression. Catches `sqrt(2)`/`sqrt(3)` / sign / IC-saddle failures before they look like tuning bugs. |
| `references/baseline-first-checks.md` | Strip events (locked breakers, disabled programmable variations, bypassed fault blocks), verify the controller block's actual sample time matches the algorithm's hardcoded `dt`, then check steady-state metrics before layering disturbances. |
| `references/model-logging-contract.md` | Expected signals, units, sign conventions, amplitude cross-check (`|v_inv| ≈ |v_grid|` under `P*=Q*=0`), pre-event settled-window check. |
| `references/scenario-contract.md` | Scenario classes, pre/post-event windows, what each scenario can and cannot prove. |
| `references/companion-boundary.md` | Division of responsibility between `gfm-design` and `gfm-validation`. |
| `references/common-measurement-pitfalls.md` | Cross-cutting failure patterns that lead to wrong conclusions about the controller: dropped signals after a structural model edit (an edit problem, not a gain problem), measuring power angle at the wrong electrical boundary, moving-average causality around step events, quasi-static back-calculation limits during transients, and a small set of stable MATLAB API traps. Read FIRST when a validation result looks suspicious before retuning anything. |

### Essential — Tier definitions (cross-reference)

| Reference | Lives in | Use when |
|---|---|---|
| `gfm-test-scenarios.md` | `gfm-design` | Decide whether the scenario is Tier 1 (steady-state), Tier 2 (small-signal), or Tier 3 (large-signal). Linear predictions only apply at Tiers 1–2. |

### Scripts

| Script | Purpose |
|---|---|
| `scripts/gfm_validate_sim.m` | Top-level runner. Accepts a model or existing sim output, resolves parameters/prediction, extracts logs, compares metrics, and writes a report. |
| `scripts/gfm_extract_sim_signals.m` | Extracts canonical signals from `logsout`, `SimulationOutput`, or simple structs. |
| `scripts/gfm_compare_logs_to_prediction.m` | Computes settled-window metrics and pass/fail checks against a prediction. |
| `scripts/gfm_write_validation_report.m` | Writes a concise Markdown validation report. |
| `scripts/test_gfm_validation_helpers.m` | Smoke test for helper scripts using synthetic logs; does not call `sim()`. |

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

If the logs disagree with the design prediction, first check signal names/units, steady-state window, limiter activity, saturation, and scenario timing before recommending controller retuning. For the recurring failure patterns — near-zero output after a model edit, P-δ steady state stuck at 0°, pre-step operating point showing transient values, missing trajectory discontinuity at grid steps, or unexplained `set_param`/`whos` API errors — read `references/common-measurement-pitfalls.md` first; most of these are mechanical, not physical.
