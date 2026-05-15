function result = gfm_compare_logs_to_prediction(logs, pred, varargin)
%GFM_COMPARE_LOGS_TO_PREDICTION Compare settled logged signals to prediction.

ip = inputParser;
ip.addParameter('scenarioName', 'validation_case', @(x)ischar(x) || isstring(x));
ip.addParameter('settleWindow', [], @(x)isempty(x) || (isnumeric(x) && numel(x) == 2));
ip.addParameter('settleSeconds', [], @(x)isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('tolerance', struct(), @(x)isstruct(x));
ip.addParameter('p', struct(), @(x)isstruct(x));
ip.parse(varargin{:});
opt = ip.Results;

tol = mergeTolerance(opt.tolerance);
checks = emptyChecks();

if hasSignal(logs, 'P') && (isfield(pred, 'P_total') || isfield(pred, 'P_per_inv'))
    expected = expectedTotal(pred, 'P');
    actual = windowMean(logs.P, opt);
    checks(end+1) = makeCheck('P_total', actual, expected, ... %#ok<AGROW>
        max(tol.P_abs, tol.P_rel * max(1, abs(expected))), 'W', '');
end

if hasSignal(logs, 'Q') && (isfield(pred, 'Q_total') || isfield(pred, 'Q_per_inv'))
    expected = expectedTotal(pred, 'Q');
    actual = windowMean(logs.Q, opt);
    checks(end+1) = makeCheck('Q_total', actual, expected, ... %#ok<AGROW>
        max(tol.Q_abs, tol.Q_rel * max(1, abs(expected))), 'VAR', '');
end

if hasSignal(logs, 'f') && isfield(pred, 'f_pcc')
    expected = pred.f_pcc;
    actual = windowMean(logs.f, opt);
    checks(end+1) = makeCheck('f_pcc', actual, expected, tol.f_Hz, 'Hz', ''); %#ok<AGROW>
end

if hasSignal(logs, 'V_LLrms') && isfield(pred, 'V_pcc_LLrms')
    expected = pred.V_pcc_LLrms;
    actual = windowMean(logs.V_LLrms, opt);
    checks(end+1) = makeCheck('V_pcc_LLrms', actual, expected, ... %#ok<AGROW>
        max(tol.V_abs, tol.V_rel * max(1, abs(expected))), 'V', '');
end

if hasSignal(logs, 'I_peak') && isfield(pred, 'I_peak_per_inv')
    expected = max(pred.I_peak_per_inv(:));
    actual = windowMax(logs.I_peak, opt);
    checks(end+1) = makeCheck('I_peak', actual, expected, ... %#ok<AGROW>
        max(tol.I_abs, tol.I_rel * max(1, abs(expected))), 'A', ...
        'Compare current carefully when the model logs per-phase or per-unit currents.');
end

if hasSignal(logs, 'm_index')
    actual = windowMaxAbs(logs.m_index, opt);
    if isfield(opt.p, 'm_max')
        expected = opt.p.m_max;
        pass = actual <= expected + tol.m_abs;
        checks(end+1) = makeLimitCheck('m_index_limit', actual, expected, tol.m_abs, 'pu', pass, ... %#ok<AGROW>
            'Limit check: actual <= m_max + tolerance.');
    elseif isfield(pred, 'm_nominal')
        expected = pred.m_nominal;
        checks(end+1) = makeCheck('m_index', actual, expected, tol.m_abs, 'pu', ''); %#ok<AGROW>
    end
end

nPass = sum([checks.pass]);
nFail = numel(checks) - nPass;

result = struct();
result.scenarioName = char(opt.scenarioName);
result.generatedAt = datestr(now, 'yyyy-mm-dd HH:MM:SS');
result.checks = checks;
result.summary = struct( ...
    'nChecks', numel(checks), ...
    'nPass', nPass, ...
    'nFail', nFail, ...
    'allPassed', nFail == 0 && numel(checks) > 0);
result.missingSignals = {};
if isfield(logs, 'missingSignals')
    result.missingSignals = logs.missingSignals;
end
result.availableSignals = struct();
if isfield(logs, 'availableSignals')
    result.availableSignals = logs.availableSignals;
end
result.prediction = pred;
end

function tf = hasSignal(logs, name)
tf = isfield(logs, name) && isstruct(logs.(name)) && isfield(logs.(name), 'data');
end

function total = expectedTotal(pred, prefix)
totalField = [prefix '_total'];
perInvField = [prefix '_per_inv'];
if isfield(pred, totalField)
    total = pred.(totalField);
else
    total = sum(pred.(perInvField)(:));
end
end

function checks = emptyChecks()
checks = struct('name', {}, 'actual', {}, 'expected', {}, 'error', {}, ...
    'tolerance', {}, 'units', {}, 'pass', {}, 'note', {});
end

function check = makeCheck(name, actual, expected, tolerance, units, note)
err = actual - expected;
check = struct();
check.name = name;
check.actual = actual;
check.expected = expected;
check.error = err;
check.tolerance = tolerance;
check.units = units;
check.pass = abs(err) <= tolerance;
check.note = note;
end

function check = makeLimitCheck(name, actual, limit, tolerance, units, pass, note)
check = struct();
check.name = name;
check.actual = actual;
check.expected = limit;
check.error = actual - limit;
check.tolerance = tolerance;
check.units = units;
check.pass = pass;
check.note = note;
end

function value = windowMean(sig, opt)
data = windowData(sig, opt);
value = mean(data(:), 'omitnan');
end

function value = windowMax(sig, opt)
data = windowData(sig, opt);
value = max(data(:), [], 'omitnan');
end

function value = windowMaxAbs(sig, opt)
data = windowData(sig, opt);
value = max(abs(data(:)), [], 'omitnan');
end

function data = windowData(sig, opt)
t = sig.time(:);
x = sig.data;
if isempty(t) || numel(t) ~= size(x, 1)
    data = x;
    return;
end

if ~isempty(opt.settleWindow)
    idx = t >= opt.settleWindow(1) & t <= opt.settleWindow(2);
elseif ~isempty(opt.settleSeconds)
    idx = t >= (max(t) - opt.settleSeconds);
else
    idx = t >= (min(t) + 0.8 * (max(t) - min(t)));
end

if ~any(idx)
    idx = true(size(t));
end
data = x(idx, :);
end

function tol = mergeTolerance(userTol)
tol = struct();
tol.P_rel = 0.05;
tol.P_abs = 50;
tol.Q_rel = 0.05;
tol.Q_abs = 50;
tol.f_Hz = 0.05;
tol.V_rel = 0.05;
tol.V_abs = 5;
tol.I_rel = 0.10;
tol.I_abs = 0.5;
tol.m_abs = 0.02;

fields = fieldnames(userTol);
for k = 1:numel(fields)
    tol.(fields{k}) = userTol.(fields{k});
end
end
