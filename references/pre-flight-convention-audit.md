# Pre-flight Convention Audit

Run this audit **before** `sim()` on any inherited or programmatically patched model. It costs under a minute and catches the family of errors that masquerade as gain/tuning problems — `sqrt(2)` / `sqrt(3)` voltage offsets, sign flips, hardcoded chart literals, saddle-point ICs, and floating neutrals.

These checks are not part of the model logging contract (`model-logging-contract.md`) because they happen on the *static* model, not on logs. Do them first.

## Why this audit exists

Most "wrong amplitude" or "Q doesn't go to zero" reports turn out to be one of:

- The SPS source-block parameter was misread (LL RMS vs LL peak vs phase peak).
- The dVOC chart has constants hardcoded as literals (`P = 0;` inside the script) and the patcher missed them.
- The chart's persistent IC sits at a saddle and the pre-event window is unsettled.
- A block-type swap introduced a neutral pin that wasn't grounded.
- The controller chart implements Andronov-Hopf form (limit cycle at `√2·kv`) but the prediction assumed Phi-form (limit cycle at `V*`).

Each of these is fast to check and slow to debug after the simulation has run.

## Pre-flight checks

Run all of these via the MATLAB engine *without* calling `sim()`:

### 1. Source-block parameter audit

For the grid voltage source:

```matlab
load_system(model);
src = [model '/<grid source name>'];
op  = get_param(src, 'DialogParameters');
for f = fieldnames(op)'
    fprintf('  %s = %s\n', f{1}, num2str(get_param(src, f{1})));
end
```

Confirm:

- `Voltage` (Three-Phase Source) or `PositiveSequence(1)` (Three-Phase Programmable VS) is **LL RMS**, not LL peak. Compute the expected phase peak:
  ```
  V_phase_peak = V_LL_RMS * sqrt(2)/sqrt(3)
  ```
  If the model's README/comment claims a different unit, **trust the SPS interpretation, not the comment**. See `gfm-design` `references/simulink-modeling-conventions.md`.
- `PhaseAngle` matches the convention the controller uses for `t=0`. A controller that initializes with `v_α(0) = V_peak, v_β(0) = 0` is in cosine convention, so the source should produce `cos(ω t)` on phase A at `t=0` — that means `PhaseA = 90°` in the SPS sine convention.
- `Frequency` matches `f_n` everywhere else in the parameter set.

### 2. Chart literal audit

For each MATLAB Function block on the controller path:

```matlab
chart = sfroot.find('-isa','Stateflow.EMChart','Path','<chart block path>');
disp(chart.Script);
```

Look for:

- Hardcoded literals that should have been parameters: `P = 0;`, `Q = 0;`, `Vnom = ...`, `Ts = 1e-4;`. These are not overridden by feeding new values through `Constant` blocks. If they need to change for the scenario, patch them via Stateflow API:
  ```matlab
  chart.Script = regexprep(chart.Script, '(\<P\s*=\s*)[\+\-]?\d+\.?\d*\s*;', '$1 5000;');
  ```
- The chart's persistent-state initial condition. If you see something like:
  ```matlab
  persistent V_al V_be
  if isempty(V_al)
      V_al = -Vnom;       % <- 180° saddle vs a cosine grid
      V_be = 0;
  end
  ```
  flag it. A negative IC on `V_al` with a cosine-convention grid puts the inverter 180° from the grid, exactly at a saddle of the closed-loop synchronization dynamics. Pre-event statistics from this state are meaningless. Flip the sign (use `+Vnom`) and rebuild.
- The dVOC form. A `2*ksy*x - ksy/kv²*norm²*x` radial term is Andronov-Hopf form with limit cycle at `√2·kv`. A `(Vstar² - norm²)/Vstar² * v` factor is Phi-form with limit cycle at `Vstar`. If the prediction assumed one and the chart implements the other, the predicted amplitude is off by `√2`.

### 3. Block-swap topology audit

If the model has been programmatically patched (a block was deleted and another added in its place), verify the new block's port topology matches the surrounding wiring. The most common failure:

```matlab
phNew = get_param([model '/Programmable_Grid_Source'], 'PortHandles');
% RConn = A, B, C external connections
% LConn(1) = neutral (exposed on Three-Phase Programmable VS, even with Y/Yg)
% Three-Phase Source with InternalConnection='Yg' has NO LConn — neutral internal.
for k = 1:numel(phNew.LConn)
    ln = get_param(phNew.LConn(k), 'Line');
    if ln == -1
        error('Programmable VS LConn(%d) is floating. Add a Ground.', k);
    end
end
```

If the model was rebuilt from scratch instead of cloned, also check that the Universal Bridge's modulation sign matches the controller's output convention. The SPS Universal Bridge typically requires `modulation_sign = -1` when the controller outputs `m_abc = 2·v_ref/Vdc` in the natural sign convention — confirm by running a small `m_abc = constant` test and observing the bridge output polarity.

### 4. Baseline regression check

If the patched model started life as a copy of a verified baseline, run the baseline's known-good scenario (no scenario events, default parameters) and confirm the report still matches what the baseline produced. If you broke something during patching, this catches it before the new-scenario sim mucks up the diagnosis.

```matlab
% Save a snapshot of the pristine baseline's settled output for comparison
ref = load('runs/baseline_steady_state_reference.mat');
% Then rerun the same scenario on the patched model and compare:
%   V_pcc peak, V_pcc RMS, I_pcc RMS, P_3ph, Q_3ph
```

Tolerances: under 1% on amplitudes, under a watt or two on P/Q (subject to the model's own numerical noise).

## What this audit does not do

- It does not replace `gfm_predict_steady_state` comparison — that still applies after the audit passes.
- It does not validate that the controller's *math* is correct, only that the implementation conventions are internally consistent.
- It does not verify grid-code, protection, or LVRT/FRT requirements.

## When to skip this audit

Almost never. The one case where you can skip is when the model and parameter struct were both produced in this session by this skill's own scripts, no manual edits were made, and the model has been validated against `gfm_predict_steady_state` at least once before. In every other case — inherited models, third-party templates, programmatic patches, S-Function-derived charts — run it.

## Cross-references

- SPS source-block unit convention details: `gfm-design` `references/simulink-modeling-conventions.md` ("SPS source-block unit conventions").
- Chart literal patching and source-block audit: `gfm-design` `references/dvoc-implementation-conventions.md`.
- Phi-form vs Andronov-Hopf form amplitude trap: `gfm-design` `references/dvoc-design.md` ("Form variants: Phi-form vs Andronov-Hopf-form").
- Saddle-point IC warning: `gfm-design` `references/dvoc-design.md` (Initialization).
- Clone-and-patch workflow: `gfm-design` `references/verified-baseline-workflow.md`.
- Settled-window verification: `references/model-logging-contract.md` and `references/scenario-contract.md`.
