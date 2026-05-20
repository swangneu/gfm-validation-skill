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

If validation fails by a large factor of `sqrt(2)`, `sqrt(3)`, `2*pi`, or a sign flip, check units and Park/Q sign before changing controller gains. Common amplitude-mode failures:

| Observed ratio | Likely cause |
|---|---|
| `V_sim / V_pred ≈ √2 ≈ 1.414` | Phi-form vs Andronov-Hopf form mismatch; Hopf limit cycle is `√2·kv`, not `kv`. Pred used `V*` where `kv` was meant (or vice versa). |
| `V_sim / V_pred ≈ √3 ≈ 1.732` | LL vs phase voltage swap. Check whether the logged signal is LL or phase. |
| `V_sim / V_pred ≈ √(3/2) ≈ 1.225` or `≈ 0.816` | Mixed LL-RMS vs phase-peak. The SPS `Three-Phase Source.Voltage` parameter is **LL RMS**, even when a comment beside the literal claims "V peak LL". Query `get_param(src,'Voltage')` and recompute. |
| `P_sim` or `Q_sim` sign flipped | Current-measurement orientation, or modulation polarity, opposite to design assumption. |

## Amplitude cross-check, P*=Q*=0 invariant (GFM-general)

> Scope: applies to any voltage-source GFM (droop, VSG, dVOC, PSC) on a stiff grid. The reasoning is independent of which control law is in the chart.

Under `P* = Q* = 0` with a stiff grid, any voltage-source GFM that synchronizes via the current it draws/injects must drive `i → 0` in steady state — because non-zero `i` against zero dispatch reference is a perpetual error the controller is built to remove. With `i ≈ 0` and a passive RL filter, the filter has near-zero drop, so the inverter voltage and grid voltage agree:

```
|v_inv,settled| ≈ |v_grid|        (peak phase, with P* = Q* = 0)
```

This is the single most useful Tier-1 amplitude sanity check (see `gfm-design/references/gfm-test-scenarios.md` for tier definitions):

1. From the SPS source block, compute `V_grid_peak = V_LL_RMS_str * sqrt(2)/sqrt(3)` (treating `Voltage`/`PositiveSequence(1)` as LL RMS).
2. Log `v_pcc_abc_V` peak in a settled window with `P*=Q*=0`.
3. The two should match within a percent.

If they don't, look up the ratio in the "Common amplitude-mode failures" table above before suspecting a tuning issue.

> dVOC-specific failure mode under this same check: if `|v_inv| ≈ √2 · V_grid_peak` or `|v_inv|` sits between `V_grid_peak` and `√2·V_grid_peak`, the chart is in Andronov-Hopf form (limit cycle at `√2·kv`) where the prediction assumed Phi-form (limit cycle at `V*`), or vice versa. See `gfm-design/references/dvoc-design.md` "Form variants".

## Residual Q with Q* = 0 (dVOC-specific specialization)

> Scope: dVOC-specific. The general "Q does not go to zero" issue across all GFM families has more possible causes; this section names one that's hard to debug from logs alone.

Some reference dVOC implementations hardcode `κ = π/2` (the implicit choice in `u₁ = i_β_ref − i_β, u₂ = i_α − i_α_ref`). If the actual filter+grid impedance angle is not exactly `90°` — usually it isn't, because filter `R` and grid `R/X` shift the angle — the dispatch loop cannot drive Q to exactly zero. The steady-state Q with `Q*=0` will sit at a small but non-zero value proportional to `(κ_chart − atan2(X_total, R_total))`.

This is **inherent to the implementation choice**, not a tuning or validation bug. Do not retune `eta`, `alpha`, or droop slopes to chase it; either accept the residual or refactor the chart to use the correct `κ = atan2(X, R)`. See `gfm-design/references/dvoc-design.md` "κ (rotation angle)".

## Pre-disturbance settled-window check (GFM-general, matters most at Tier 3)

> Scope: applies to any controller. Most relevant for Tier-3 large-signal scenarios (phase jump, SCR step, LVRT/ZVRT, large load step) where the report relies on a "before" window for comparison.

Before computing pre-event statistics for the "baseline" row of a large-signal report, confirm the window is actually settled:

- `d|v_inv|/dt ≈ 0` across the window (linear fit slope under 0.5%/cycle).
- `δ = atan2(v_β, v_α) − θ_grid` is constant within ±2°.
- `P_inst`, `Q_inst` envelopes are flat (not a damped sinusoid).

If any of these fail, the window catches a transient and the "pre-event" numbers are meaningless. Common causes:

- **(dVOC-specific)** The dVOC's persistent IC sits at a saddle (`v_α(0) = −V_peak` is 180° from a cosine grid). The state lingers near the saddle until numerical noise or the event itself perturbs it. Symptom: `δ ≈ ±180°` in the pre-event window. Fix by flipping the IC sign in the chart (see `gfm-design` `references/dvoc-design.md`, Initialization).
- **(general)** Stop time too short before the event for the controller's slowest mode to ring down. Symptom: visible damped sinusoid on `P_inst` / `Q_inst` in the pre-event window. Push `jump_time` later or extend `t_stop` and re-window.
- **(general)** The chart's IC didn't put the inverter on its intended limit cycle, so the radial dynamics are still settling at the start of the pre-event window. Less common; only happens when an inherited model is re-purposed for a new scenario without checking the IC.

The validation report should explicitly say "pre-event window settled" or call out which of the above checks failed. A pass/fail row computed over an unsettled window will look like a "design mismatch" and route the user back to `$gfm-design` for an unnecessary retune.

For Tier-1 (steady-state) and Tier-2 (small-signal) scenarios, this check still applies but is typically less of an issue because there is no large-signal disturbance whose "before" baseline matters.
