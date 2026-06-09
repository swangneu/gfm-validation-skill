# gfm-validation

A portable [Codex](https://openai.com/codex) / [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) skill for validating grid-forming (GFM) inverter Simulink/Simscape runs against the analytical designs produced by the companion [`gfm-design`](https://github.com/swangneu/gfm-design-skill) skill.

## What it does

When invoked, the skill helps you:

- **Audit** the model *before* `sim()`: query the SPS source-block parameter strings (LL RMS vs LL peak), scan controller charts for hardcoded literals, check that block-swap patches are wired correctly (neutral grounds), and verify the IC isn't sitting at a saddle. Catches the $\sqrt{2}$/$\sqrt{3}$/sign-flip family of errors in under a minute, before they masquerade as tuning bugs.
- **Run** explicit Simulink validation cases with `sim()` only after a model and parameter source exist.
- **Inspect** existing `Simulink.SimulationOutput`, `logsout`, or exported MATLAB structs without rerunning a model.
- **Extract** canonical logged signals for real power, reactive power, PCC frequency, PCC voltage, current, and modulation index.
- **Compare** settled simulation windows against `gfm_predict_steady_state` predictions from `gfm-design`.
- **Report** pass/fail checks for P/Q/f/V/I/modulation with missing-signal notes and tolerance details.
- **Frame** Tier-1 steady-state, Tier-2 small-signal, and Tier-3 large-signal (phase jump, SCR step, LVRT/ZVRT) scenarios — including the pre-event settled-window verification that Tier-3 reports need to be meaningful.
- **Cross-check** the amplitude invariant `|v_inv| ≈ |v_grid|` under `P*=Q*=0`, with a failure-ratio lookup table that maps observed mismatches ($\sqrt{2}$, $\sqrt{3}$, $\sqrt{3/2}$) to root causes (Phi/Hopf form mismatch, LL/phase swap, LL-RMS/phase-peak swap).

Deliverable is a Markdown validation report plus a MATLAB `result` struct. This skill is the simulation-facing companion to `gfm-design`: use `gfm-design` for first-pass controller design and analytical predictions; use `gfm-validation` once a Simulink model or captured logs exist.

## Companion Boundary

| Skill | Owns | Does not own |
|---|---|---|
| `gfm-design` | Control-law choice, parameter tuning, `gfm_params.m`, steady-state prediction, small-signal quick-look | Running `sim()` or judging model logs |
| `gfm-validation` | Running/inspecting simulations, extracting logged signals, comparing logs to predictions, writing validation reports | Silent controller retuning or certification claims |

If validation fails, first check signal names, units, comparison windows, limiter activity, saturation, and scenario timing. Hand the measured discrepancy back to `gfm-design` only when retuning is explicitly needed.

## Coverage

References are scoped so you only read what your task needs.

**Essential — General (every validation run):**

| Topic | Reference doc |
|---|---|
| Pre-`sim()` static audit: SPS source-block parameter strings, controller-chart literals, block-swap port topology, regression vs. a saved snapshot | [pre-flight-convention-audit.md](references/pre-flight-convention-audit.md) |
| No-event baseline run: strip events, confirm the controller sample time matches the algorithm `dt`, verify steady state before layering disturbances | [baseline-first-checks.md](references/baseline-first-checks.md) |
| Expected signals, units, sign conventions, amplitude cross-check (`\|v_inv\| ≈ \|v_grid\|` under `P*=Q*=0`), pre-event settled-window check | [model-logging-contract.md](references/model-logging-contract.md) |
| Scenario classes, pre/post-event windows, what each scenario can and cannot prove | [scenario-contract.md](references/scenario-contract.md) |
| Division of responsibility between `gfm-design` and `gfm-validation` | [companion-boundary.md](references/companion-boundary.md) |
| Cross-cutting measurement/plotting traps that mimic tuning bugs (dropped signals after a model edit, power-angle measured at the wrong boundary, causal vs. centered `movmean`, quasi-static back-calc limits, MATLAB API traps) — read before retuning | [common-measurement-pitfalls.md](references/common-measurement-pitfalls.md) |

**Essential — Tier definitions (cross-reference into `gfm-design`):**

| Topic | Lives in | Use when |
|---|---|---|
| Depth-tier scenario matrix: steady-state $\to$ small-signal $\to$ large-signal | [`gfm-design/gfm-test-scenarios.md`](https://github.com/swangneu/gfm-design-skill/blob/main/references/gfm-test-scenarios.md) | Decide whether the scenario is Tier 1, 2, or 3. Linear predictions only apply at Tiers 1–2. |

**Scripts:**

| Area | Purpose | Resource |
|---|---|---|
| Top-level runner | Run or inspect validation cases | [gfm_validate_sim.m](scripts/gfm_validate_sim.m) |
| Log extraction | Convert logsout/SimulationOutput/structs into canonical signals | [gfm_extract_sim_signals.m](scripts/gfm_extract_sim_signals.m) |
| Prediction comparison | Settled-window metrics and tolerance checks | [gfm_compare_logs_to_prediction.m](scripts/gfm_compare_logs_to_prediction.m) |
| Report writing | Markdown validation report generation | [gfm_write_validation_report.m](scripts/gfm_write_validation_report.m) |

## Install

The skill is a folder containing `SKILL.md`, `references/`, and `scripts/`. Install the same folder in the skill directory for the agent you use.

### [Codex](https://openai.com/codex)

User-level install on Windows PowerShell:

```powershell
$root = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { "$env:USERPROFILE\.codex" }
New-Item -ItemType Directory -Force (Join-Path $root "skills") | Out-Null
git clone https://github.com/swangneu/gfm-validation-skill (Join-Path $root "skills\gfm-validation")
```

macOS / Linux:

```bash
root="${CODEX_HOME:-$HOME/.codex}"
mkdir -p "$root/skills"
git clone https://github.com/swangneu/gfm-validation-skill "$root/skills/gfm-validation"
```

Restart Codex, then ask for a GFM simulation-validation task or invoke the skill explicitly with `$gfm-validation`.

### [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)

Project-level install (this repo only, commits to git):

```text
your-project/
|-- .claude/
|   `-- skills/
|       `-- gfm-validation/      contents of this repo
`-- ...
```

User-level install on Windows PowerShell:

```powershell
git clone https://github.com/swangneu/gfm-validation-skill "$env:USERPROFILE\.claude\skills\gfm-validation"
```

macOS / Linux:

```bash
git clone https://github.com/swangneu/gfm-validation-skill ~/.claude/skills/gfm-validation
```

Restart Claude Code, then type `/gfm-validation`; the skill name should appear in the slash-command list. Claude Code can also invoke it automatically when you describe a GFM simulation-validation task.

### Compatibility notes

- `SKILL.md` is the shared skill manifest used by both Codex and Claude Code.
- `agents/openai.yaml` is Codex UI metadata. Claude Code can ignore it safely.
- The MATLAB scripts and reference docs are standalone and do not depend on either agent.
- `gfm-design` is recommended because it supplies `gfm_predict_steady_state`, but you can also pass a precomputed `prediction` struct.

## Use without a skill runner

All MATLAB scripts under [scripts/](scripts/) are standalone and run from MATLAB R2024b or newer. Live model runs require Simulink and the toolboxes needed by your model; existing log analysis can run without opening Simulink models.

- `gfm_validate_sim.m` - top-level validation runner.
- `gfm_extract_sim_signals.m` - logsout/SimulationOutput/struct signal extraction.
- `gfm_compare_logs_to_prediction.m` - settled-window comparison to a prediction.
- `gfm_write_validation_report.m` - Markdown report writer.
- `test_gfm_validation_helpers.m` - smoke harness using synthetic logs; it does not call `sim()`.

The reference markdown files under [references/](references/) define the logging contract, scenario contract, and companion boundary.

## Quick start (MATLAB only)

```matlab
% 1. Add both companion skills to your path
addpath('<path-to-gfm-validation>/scripts');
addpath('<path-to-gfm-design>/scripts');

% 2. Load or create the design parameter struct
p = gfm_params();  % or p = gfm_design_from_specs(...)

% 3. Run a Simulink validation case and compare against gfm-design prediction
result = gfm_validate_sim( ...
        'model',         'my_gfm_model', ...
        'p',             p, ...
        'gfmDesignPath', '<path-to-gfm-design>/scripts', ...
        'scenarioName',  'nominal_load_step', ...
        'tStop',         1.5);

% 4. Inspect result.reportPath for the Markdown report.
```

For already captured logs:

```matlab
addpath('<path-to-gfm-validation>/scripts');
addpath('<path-to-gfm-design>/scripts');

pred = gfm_predict_steady_state(p, 'verbose', false);
result = gfm_validate_sim( ...
        'simOutput',  simOut, ...
        'prediction', pred, ...
        'runSim',     false);
```

## Repo layout

```text
gfm-validation/
|-- SKILL.md                            Shared Codex/Claude skill manifest
|-- agents/
|   `-- openai.yaml                     Codex UI metadata
|-- README.md                           This file
|-- LICENSE                             MIT
|-- references/                         Validation workflow notes
|   |-- pre-flight-convention-audit.md  Static pre-sim() audit: source-block params, chart literals, IC saddles, neutral grounding
|   |-- baseline-first-checks.md        No-event baseline run: strip events, controller sample-time check, steady-state verify
|   |-- model-logging-contract.md       Signal names, units, amplitude cross-check, pre-event settled-window check
|   |-- scenario-contract.md            Scenario classes, pre/post-event windows, claims boundary
|   |-- common-measurement-pitfalls.md  Measurement/plotting traps that mimic tuning bugs (read before retuning)
|   `-- companion-boundary.md           Boundary between design and validation
`-- scripts/                            MATLAB validation tooling
    |-- gfm_validate_sim.m              Run/inspect a validation case
    |-- gfm_extract_sim_signals.m       Extract canonical P/Q/f/V/I/m signals
    |-- gfm_compare_logs_to_prediction.m
    |-- gfm_write_validation_report.m
    `-- test_gfm_validation_helpers.m
```

## Requirements

- MATLAB R2024b or newer.
- Simulink and the model-specific toolboxes required by your GFM model if `sim()` will be called.
- The companion `gfm-design` scripts on the MATLAB path when you want automatic prediction via `gfm_predict_steady_state`.

No Simulink run is required when validating an already captured `SimulationOutput`, `logsout`, or exported struct.

## Scope and verification

- Output of this skill is **simulation evidence**, not certification or compliance proof.
- Linear `gfm-design` steady-state predictions are invalid during current limiting, modulation saturation, or fault-on intervals; compare post-event settled windows unless you define a model-specific fault metric.
- Missing or mismatched signals are validation findings. Do not tune around a failed check until units, signs, and logging locations are confirmed.
- LVRT/FRT, strong-grid, and fault reports must state the voltage-time curve, measurement basis, current-priority rule, sequence/per-phase behavior, momentary-cessation assumption, and recovery rule when those details matter.
- This project is **not** certified, safety-qualified, or grid-code-qualified validation software. Do not use its outputs for safety-critical, protection, grid-interconnection, production hardware, or field deployment decisions without independent engineering review, EMT/HIL testing, and applicable certification.
- Run [`test_gfm_validation_helpers.m`](scripts/test_gfm_validation_helpers.m) after edits; it exercises the helper chain with synthetic logs and does not call `sim()`.

## Contributing

Issues and pull requests welcome. Priority targets:

1. Scenario templates for nominal, load-step, frequency-event, voltage-step, and strong-grid sweeps.
2. Model-specific signal-map examples for common Simulink logging layouts.
3. Fault and LVRT/FRT validation metrics that distinguish fault-on behavior from recovery behavior.
4. Batch-run support for SCR/XR sweeps and multi-unit sharing cases.
5. Better report artifacts, including CSV summaries and plots.

## License

[MIT](LICENSE).
