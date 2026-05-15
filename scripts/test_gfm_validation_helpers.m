function test_gfm_validation_helpers()
%TEST_GFM_VALIDATION_HELPERS Smoke test without calling sim().

t = linspace(0, 2, 401)';
simStruct = struct();
simStruct.tout = t;
simStruct.P_pcc = 5000 + 40 * exp(-4*t);
simStruct.Q_pcc = 5 * exp(-5*t);
simStruct.f_pcc = 60 + 0.01 * exp(-6*t);
simStruct.V_pcc_LLrms = 480 - 2 * exp(-6*t);
simStruct.I_peak = 8.51 + 0.05 * exp(-4*t);
simStruct.modulation_index = 0.98 * ones(size(t));

pred = struct();
pred.P_total = 5000;
pred.Q_total = 0;
pred.f_pcc = 60;
pred.V_pcc_LLrms = 480;
pred.I_peak_per_inv = 8.505;
pred.m_nominal = 0.98;

p = struct('m_max', 0.98);

logs = gfm_extract_sim_signals(simStruct);
result = gfm_compare_logs_to_prediction(logs, pred, ...
    'scenarioName', 'synthetic_nominal', ...
    'settleSeconds', 0.5, ...
    'p', p);

assert(result.summary.allPassed, 'Expected synthetic validation to pass.');

result2 = gfm_validate_sim( ...
    'simOutput', simStruct, ...
    'prediction', pred, ...
    'p', p, ...
    'runSim', false, ...
    'writeReport', false, ...
    'settleSeconds', 0.5, ...
    'verbose', false);
assert(result2.summary.allPassed, 'Expected top-level helper validation to pass.');

outDir = fullfile(tempdir, ['gfm_validation_test_' datestr(now, 'yyyymmdd_HHMMSSFFF')]);
mkdir(outDir);
reportPath = fullfile(outDir, 'validation_report.md');
gfm_write_validation_report(result, reportPath);
assert(isfile(reportPath), 'Expected report file to be written.');

fprintf('[PASS] gfm-validation helper smoke test: %d checks passed\n', ...
    result.summary.nPass);
end
