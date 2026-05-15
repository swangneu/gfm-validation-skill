function result = gfm_validate_sim(varargin)
%GFM_VALIDATE_SIM Run or inspect a GFM Simulink validation case.
%
% result = gfm_validate_sim('model','my_model','p',p,'gfmDesignPath',path)
% runs sim(), extracts logs, compares against gfm_predict_steady_state, and
% writes a Markdown report. Pass 'simOutput',simOut,'runSim',false to compare
% already captured logs without calling sim().

ip = inputParser;
ip.addParameter('model', '', @(x)ischar(x) || isstring(x));
ip.addParameter('p', [], @(x)isstruct(x) || isempty(x));
ip.addParameter('paramsFcn', '', @(x)ischar(x) || isstring(x));
ip.addParameter('paramsFile', '', @(x)ischar(x) || isstring(x));
ip.addParameter('prediction', [], @(x)isstruct(x) || isempty(x));
ip.addParameter('gfmDesignPath', '', @(x)ischar(x) || isstring(x));
ip.addParameter('load_P', [], @(x)isempty(x) || isnumeric(x));
ip.addParameter('load_Q', 0, @isnumeric);
ip.addParameter('simOutput', [], @(x)true);
ip.addParameter('runSim', true, @islogical);
ip.addParameter('tStop', [], @(x)isempty(x) || isnumeric(x) || ischar(x) || isstring(x));
ip.addParameter('scenarioName', 'validation_case', @(x)ischar(x) || isstring(x));
ip.addParameter('simInputFcn', [], @(x)isempty(x) || isa(x, 'function_handle'));
ip.addParameter('signalMap', struct(), @(x)isstruct(x));
ip.addParameter('tolerance', struct(), @(x)isstruct(x));
ip.addParameter('settleWindow', [], @(x)isempty(x) || (isnumeric(x) && numel(x) == 2));
ip.addParameter('settleSeconds', [], @(x)isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('runsDir', 'runs', @(x)ischar(x) || isstring(x));
ip.addParameter('writeReport', true, @islogical);
ip.addParameter('reportPath', '', @(x)ischar(x) || isstring(x));
ip.addParameter('verbose', true, @islogical);
ip.parse(varargin{:});
opt = ip.Results;

p = resolveParams(opt);
pred = resolvePrediction(opt, p);

didRunSim = false;
simOut = opt.simOutput;
if isempty(simOut)
    if ~opt.runSim
        error('gfm_validate_sim:noSimOutput', ...
            'runSim is false, but no simOutput was supplied.');
    end
    if strlength(string(opt.model)) == 0
        error('gfm_validate_sim:noModel', ...
            'A model is required when simOutput is not supplied.');
    end
    simOut = runSimCase(opt, p);
    didRunSim = true;
end

logs = gfm_extract_sim_signals(simOut, 'signalMap', opt.signalMap);
result = gfm_compare_logs_to_prediction(logs, pred, ...
    'scenarioName', opt.scenarioName, ...
    'settleWindow', opt.settleWindow, ...
    'settleSeconds', opt.settleSeconds, ...
    'tolerance', opt.tolerance, ...
    'p', p);

result.model = char(opt.model);
result.didRunSim = didRunSim;
result.reportPath = '';

if opt.writeReport
    reportPath = char(opt.reportPath);
    if isempty(reportPath)
        runDir = makeRunDir(opt.runsDir, opt.scenarioName);
        reportPath = fullfile(runDir, 'validation_report.md');
    end
    gfm_write_validation_report(result, reportPath);
    result.reportPath = reportPath;
end

if opt.verbose
    fprintf('[gfm_validate_sim] %s: %d passed, %d failed, %d checks\n', ...
        result.scenarioName, result.summary.nPass, result.summary.nFail, ...
        result.summary.nChecks);
    if ~isempty(result.reportPath)
        fprintf('  report: %s\n', result.reportPath);
    end
end
end

function p = resolveParams(opt)
if ~isempty(opt.p)
    p = opt.p;
    return;
end

if strlength(string(opt.paramsFcn)) > 0
    p = callParamsFunction(char(opt.paramsFcn));
    return;
end

if strlength(string(opt.paramsFile)) > 0
    p = loadParamsFile(char(opt.paramsFile));
    return;
end

p = struct();
end

function p = callParamsFunction(nameOrPath)
[folder, name, ext] = fileparts(nameOrPath);
if ~isempty(folder)
    addpath(folder);
end
if strcmpi(ext, '.m') || isempty(ext)
    p = feval(name);
else
    error('gfm_validate_sim:badParamsFcn', ...
        'paramsFcn must be a function name or .m file path.');
end
end

function p = loadParamsFile(path)
[folder, name, ext] = fileparts(path);
if strcmpi(ext, '.mat')
    data = load(path);
    if isfield(data, 'p')
        p = data.p;
    else
        error('gfm_validate_sim:noPInMat', ...
            'MAT file must contain a variable named p.');
    end
elseif strcmpi(ext, '.m')
    oldPath = path;
    if ~isempty(folder)
        addpath(folder);
    end
    try
        p = feval(name);
    catch
        p = [];
        run(oldPath);
        if ~exist('p', 'var') || isempty(p)
            error('gfm_validate_sim:noPInScript', ...
                'Parameter script must return or assign a struct named p.');
        end
    end
else
    error('gfm_validate_sim:badParamsFile', ...
        'paramsFile must be a .m or .mat file.');
end
end

function pred = resolvePrediction(opt, p)
if ~isempty(opt.prediction)
    pred = opt.prediction;
    return;
end

if isempty(fieldnames(p))
    error('gfm_validate_sim:noPrediction', ...
        'Supply prediction or a parameter struct plus gfmDesignPath/gfm_predict_steady_state.');
end

if strlength(string(opt.gfmDesignPath)) > 0
    addpath(char(opt.gfmDesignPath));
end

if exist('gfm_predict_steady_state', 'file') ~= 2
    error('gfm_validate_sim:noDesignPredictor', ...
        'gfm_predict_steady_state was not found. Add the gfm-design scripts path or pass prediction.');
end

args = {'verbose', false};
if ~isempty(opt.load_P)
    args = [args, {'load_P', opt.load_P}]; %#ok<AGROW>
end
if ~isempty(opt.load_Q)
    args = [args, {'load_Q', opt.load_Q}]; %#ok<AGROW>
end
pred = gfm_predict_steady_state(p, args{:});
end

function simOut = runSimCase(opt, p)
model = char(opt.model);
load_system(model);
simIn = Simulink.SimulationInput(model);
if ~isempty(fieldnames(p))
    simIn = simIn.setVariable('p', p);
end
if ~isempty(opt.tStop)
    simIn = simIn.setModelParameter('StopTime', char(string(opt.tStop)));
end
if ~isempty(opt.simInputFcn)
    simIn = opt.simInputFcn(simIn, p);
end
simOut = sim(simIn);
end

function runDir = makeRunDir(runsDir, scenarioName)
stamp = datestr(now, 'yyyymmdd_HHMMSS');
safeScenario = regexprep(char(scenarioName), '[^A-Za-z0-9_-]', '_');
runDir = fullfile(char(runsDir), [safeScenario '_' stamp]);
if ~exist(runDir, 'dir')
    mkdir(runDir);
end
end
