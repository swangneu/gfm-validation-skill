# Baseline-First Validation Checks

Before validating any disturbance scenario (phase jump, load step, voltage
dip, fault), validate that the model settles to a correct steady state with
**no events**. This separates "is the controller doing its job" from "is the
event handled correctly". Skipping the baseline lets time-step, sign, and
scaling bugs hide in the event response.

> **Sequencing vs. the pre-flight audit.** Run this *after* the static
> `pre-flight-convention-audit.md` passes. Pre-flight reads the model without
> running it (source-block params, chart text, ports); this step runs the
> model with events stripped to confirm it actually settles. The two are
> complementary, not redundant: pre-flight catches mis-wired conventions,
> this catches a correctly wired controller that still won't reach the right
> steady state. And unlike pre-flight's *regression* check (a diff against a
> previously saved snapshot), this is a first-principles check — no prior
> reference run is needed.

## Step 1 - strip events from the model

Disable every scenario element for the baseline run:

- Breakers: set `InitialState = closed`, drive the external control input
  with a constant `closed` signal, or remove the Step source.
- Programmable voltage source variation: set `VariationTiming = [start 1e6]`
  so the variation never ends, or disable the variation entity entirely.
- Load step: keep the initial-condition load only.
- Fault block: bypass or open the fault breaker permanently.

Run with only the nominal grid and constant references. A correctly
implemented dVOC / droop / VSG / PSC will converge to a stable operating
point on its own.

## Step 2 - verify the controller block is being called at its design rate

Open the controller block (MATLAB Function, S-Function, or Stateflow) and
check:

| Quantity | Expected |
|---|---|
| Block sample time | matches the algorithm's design step (the C `#define Ts`, the RK4 `dt`, etc.) |
| `Ts_power` (powergui) | <= block Ts; >= 10 samples per PWM period |
| Solver | discrete / fixed-step compatible with the block ladder |

A controller block left at "inherited" sample time when its algorithm
hardcodes a different `dt` produces wrong steady-state amplitudes and
currents - the integrator advances `dt_design / Ts_inherited` times faster
than time. See the design skill `time-step-coordination.md` for the fix.

For a MATLAB Function block:

```matlab
chart = sfroot.find('-isa','Stateflow.EMChart','Path',blockPath);
disp(chart.ChartUpdate);   % 'INHERITED' or 'DISCRETE'
disp(chart.SampleTime);    % '-1' (inherited) or the design Ts
```

## Step 3 - check steady-state metrics

In the last 100 ms before stop time, expect (for a single inverter on a
stiff grid, `P* = Q* = 0`):

| Metric | Expectation |
|---|---|
| `V_pcc` phase peak | equals the grid source peak phase voltage (no impedance drop with stiff grid + no current) |
| `V_pcc` phase balance | spread < 1% across a, b, c |
| `I_pcc` | small (a few amperes); driven only by the residual voltage mismatch through `L_f` |
| `I_pcc` phase balance | spread < 5% |
| dVOC voltage state magnitude | tracks grid amplitude, not the parameter `kv` / `Vnom` (the Andronov-Hopf limit cycle is pushed by the forcing terms) |
| Modulation max `\|m\|` | strictly below `m_max` |

For non-zero `P*`, `Q*`:

- Grid-side `I_grid` matches the dVOC reference current law applied to the
  settled state, and the active/reactive power flow direction matches the
  sign convention used by `gfm_predict_steady_state`.

## Step 4 - common baseline failures

| Symptom | Diagnosis |
|---|---|
| Current larger than predicted with `P*=Q*=0` | time-step coordination (controller block Ts != algorithm Ts) |
| Phase spread > 5% in steady state | PWM resolution too coarse, or the controller has not yet settled - extend sim time |
| Voltage state pinned at `kv`, refuses to track grid | current feedback sign wrong, or `u1`/`u2` swap inverted |
| 20-100 Hz residual oscillation that does not decay | underdamped controller mode (e.g., dVOC `eta` too low) - retune via the design skill |
| Solver freezes at the first switching event | `Ts_power` too coarse for `f_sw`; reduce to >= 10 samples per PWM period |
| dq filter using grid angle creates a transient kick on phase jump | move filter to the controller's own internal frame, or filter in stationary alpha-beta |

## Step 5 - then layer events

Only after baseline passes, enable disturbances one at a time. If a
disturbance breaks the model, you now know it is the event handling, not the
controller core.

For each event, repeat steady-state checks on the post-event window. Treat a
post-event window that has not fully settled as "extend stop time" first,
"retune controller" second. A `gfm-validation` report on a window that still
contains a slowly decaying controller mode reports the mode, not the
controller's true steady state.

## Cross-references

- Design skill `time-step-coordination.md` - how to set controller block
  sample time correctly, S-Function Builder caveats, MATLAB Function block
  port-from-C recipe.
- `scenario-contract.md` - what each scenario class can and cannot prove.
- `model-logging-contract.md` - signal naming and logging conventions.
