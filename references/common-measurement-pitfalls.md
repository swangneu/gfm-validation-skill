# Common Measurement and Plotting Pitfalls

Patterns observed during GFM Simulink validation that lead to wrong
conclusions if not caught. Each entry includes the symptom, the wrong
inference it invites, the actual cause, and a concrete recipe.

## 1. After a model edit, dropped signals are an edit problem, not a controller problem

**Symptom:** a previously working model produces signals near zero (or
clamped, or NaN) after a structural edit — block deletion, rename,
refactor, copy-paste, automated script-driven change.

**Wrong inference:** the controller is broken; retune gains, rebuild the
parameter struct, suspect numerical drift.

**What is actually happening:** the edit severed a load-bearing path —
a feedback line was deleted along with what looked like a sink, a
logged-signal marker moved off the visible signal, a port number
shifted on the parent system, or a mask parameter changed an algebraic
relationship the controller assumed.

The general rule:

> A block's name does not reliably indicate its function. Inspect ports
> and signal flow before any structural edit, and verify signal flow
> after.

This is most often hit when:

- A block named like a sink (`Display`, `Probe`, `Output`, `Test_*`,
  visualization roles) is actually a `SubSystem` with output ports that
  feed into the controller.
- A name-based query is run with recursive depth (the `find_system`
  default), catching nested matches the author did not intend.
- A model-reference target's interface changes silently when its
  parent moves.

**Pre-edit guard.** For any block about to be deleted, renamed, or
re-parented, confirm it is what you think it is:

```matlab
ph    = get_param(blockPath, 'PortHandles');
nOut  = numel(ph.Outport) + numel(ph.RConn) + numel(ph.LConn);
btype = get_param(blockPath, 'BlockType');
if nOut > 0
    warning('%s (BlockType=%s) has %d output/connection port(s) — not a sink.', ...
        blockPath, btype, nOut);
end
```

**Use the narrowest scope on `find_system`.** Recursive is the default;
explicit depth eliminates a class of "silent over-match" bugs:

```matlab
hits = find_system(mdl, 'SearchDepth', 1, 'Name', name);   % top level only
hits = find_system(parent, 'SearchDepth', 1, 'BlockType', 'SubSystem');
```

**Post-edit verification.** After any structural edit, run Update
Diagram and a short smoke run, then compare to a reference set of
metrics captured BEFORE the edit:

```matlab
set_param(mdl, 'SimulationCommand', 'update');   % surfaces broken paths
% then re-run a short scenario and diff settled P/Q/V/I against pre-edit baseline.
```

If the post-edit smoke shows the symptom, revert the edit and redo it
with narrower scope or different target. Do not start chasing gains
until the edit is proven harmless on a baseline scenario.

## 2. Power-angle δ: measure at inverter terminal, not at PCC

**Symptom:** P-δ trajectory has steady-state δ ≈ 0° even though
dispatched P is nonzero — contradicts the swing-equation intuition
δ_ss = arcsin(P · X / (V · V_g)) > 0.

**Wrong inference:** the controller isn't synchronizing; retune the
synchronization gain.

**Actual cause:** δ was computed from `v_pcc` instead of `v_inv`. For
a stiff grid (`Rg`, `Lg` small), `v_pcc ≈ v_grid`, so
`∠v_pcc − θ_grid ≈ 0` always, regardless of P. The swing-equation δ is
between the **inverter terminal** voltage and the grid, not between PCC
and grid. This applies to any GFM control law (droop, VSG, dVOC, PSC) —
the geometry is set by the stiff-grid impedance ratio, not by the
controller.

**Three ways to get the correct δ:**

1. **Log v_inv directly** with a 3-phase Voltage Measurement block on
   the converter-bridge side of the filter inductor. Best accuracy in
   transients.
2. **Log the controller's commanded modulation** as a v_inv reference:
   `m_abc * V_dc / 2`. Captures the controller state cleanly; ignores
   PWM ripple. Works regardless of which control law produces `m_abc`.
3. **Quasi-static back-calc** (when logging v_inv is not an option):

   ```text
   v_inv  ≈ v_pcc + (R_f + jωL_f) * i_pcc
   ```

   In a grid-aligned dq frame:

   ```text
   v_inv_d = v_pcc_d + R_f * i_d − ω * L_f * i_q
   v_inv_q = v_pcc_q + R_f * i_q + ω * L_f * i_d
   ```

   This ignores `L_f * di/dt`, so during a step transient the back-calc
   v_inv inherits any v_pcc discontinuity (e.g. from a stiff-grid phase
   step) — it shows an apparent step in δ that is not physically there.
   Acceptable for steady-state δ_ss; biased during the first ~1 cycle
   after a step event.

For an honest swing-trajectory plot, prefer methods 1 or 2.

## 3. Causal vs centered moving averages near step events

**Symptom:** in a plot of `movmean`-smoothed metrics, the pre-step
operating point appears mid-transient (e.g. pre-jump P reads 0 or
negative when it should be at P_set), or the apparent post-step
overshoot is smaller than expected.

**Wrong inference:** the controller's steady state is off; the
post-step settling is faster than it actually is.

**Actual cause:** `movmean(x, n)` uses a **centered** window by default.
At a step at index k, the smoothed value for indices `k − n/2` through
`k + n/2` mixes pre- and post-step samples.

**Fixes:**

- For any plot showing a pre-step steady state, use a **causal**
  (trailing) window:

  ```matlab
  y_smooth = movmean(y, [n-1, 0]);
  ```

- For settled-window metrics, place the window well clear of the step:

  ```matlab
  % RIGHT — window ends a margin before the step:
  preWin = [t_step - 0.10, t_step - 0.02];

  % WRONG — window straddles the step:
  preWin = [t_step - 0.05, t_step + 0.05];
  ```

A causal `movmean` with `n` = one fundamental cycle (`round(1/(f0*dt))`
samples) is the safest default for P/Q/V/I envelope plots in
grid-forming validation.

## 4. P-δ trajectory: the physical discontinuity at a grid phase step

**Symptom:** the P-δ trajectory for a stiff-grid phase-jump scenario
shows a smooth curve from the pre-jump operating point into the
post-jump swing, with no visible discontinuity.

**Wrong inference:** the post-jump trajectory matches a swing-equation
sketch; everything is smooth.

**Actual physics:** a grid phase step is a real discontinuity in
`∠v_grid`. The inverter's internal voltage state `v_inv` is continuous
(any GFM control law has its angle as an ODE state); the grid jumped,
the controller didn't. So:

```text
δ(t_step+) = δ(t_step−) − Δθ_grid                  (instantaneous step in δ)
P(t_step+) ≈ P(t_step−) * cos(Δθ_grid − δ_ss) / cos(δ_ss)   (step in P)
```

The post-step instant lands at `(δ_ss − Δθ_grid, P_pre · cos(Δθ_grid −
δ_ss)/cos(δ_ss))`. For example, with a typical small `δ_ss` and a
moderate grid step `Δθ_grid`, P steps down by roughly `cos(Δθ_grid)` of
its pre-step value before the swing begins.

If the validation plot does not show this step, the reconstruction is
either:

- Smoothing the step over the MA window (point 3 above), or
- Using a v_inv that inherits v_pcc's jump (quasi-static back-calc,
  point 2 above).

For an honest plot: log v_inv directly, disable smoothing around the
step, or annotate the smoothed plot with a dashed marker showing the
analytical jump landing point.

## 5. ModelWorkspace and chart introspection — API traps

These are not physics errors but they cost iterations until learned:

```matlab
% Setting MW data source — set the property directly, NOT via set_param:
mw = get_param(mdl, 'ModelWorkspace');
mw.DataSource = 'Model File';                        % RIGHT
% set_param(mw, 'DataSource', 'Model File');         % WRONG: errors

% Checking whether a variable exists in MW:
mw.hasVariable('Vstar')                              % RIGHT
% any(strcmp({mw.whos.Name}, 'Vstar'))               % WRONG: field is lowercase 'name'
% any(strcmp({mw.whos.name}, 'Vstar'))               % works, but hasVariable is clearer

% Reading a Stateflow chart's script:
rt = sfroot;
chart = rt.find('-isa', 'Stateflow.EMChart', 'Path', chartPath);
src = chart.Script;                                  % text of the chart

% Patching chart text — use a single anchored regex per identifier.
% Replace <param_name> with the actual identifier from the chart:
src = regexprep(src, '(\<<param_name>\s*=\s*)[\d\.\+\-eE]+(\s*;)', ['$1' newVal '$2']);
```

When the chart uses unknown identifier names, print `chart.Script` first
and inspect; don't guess from intuition about what a variable "should"
be called.
