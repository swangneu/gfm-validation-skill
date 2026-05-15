function logs = gfm_extract_sim_signals(simOut, varargin)
%GFM_EXTRACT_SIM_SIGNALS Extract canonical GFM validation signals.
%
% logs = gfm_extract_sim_signals(simOut) accepts a Simulink.SimulationOutput,
% a logsout Dataset, or a simple struct. The returned struct uses canonical
% fields: P, Q, f, V_LLrms, I_peak, and m_index when those signals exist.

ip = inputParser;
ip.addParameter('signalMap', struct(), @(x)isstruct(x));
ip.parse(varargin{:});
opt = ip.Results;

aliases = defaultAliases();
keys = fieldnames(aliases);
fallbackTime = getFallbackTime(simOut);

logs = struct();
logs.sourceClass = class(simOut);
logs.availableSignals = struct();
logs.missingSignals = {};

for k = 1:numel(keys)
    key = keys{k};
    candidates = aliases.(key);
    if isfield(opt.signalMap, key)
        candidates = normalizeCandidates(opt.signalMap.(key), candidates);
    end

    [found, rawName, rawValue] = findSignal(simOut, candidates);
    if found
        sig = normalizeSignal(rawValue, fallbackTime);
        sig.name = rawName;
        sig.canonicalName = key;
        logs.(key) = sig;
        logs.availableSignals.(key) = rawName;
    else
        logs.missingSignals{end+1} = key; %#ok<AGROW>
    end
end

end

function aliases = defaultAliases()
aliases = struct();
aliases.P = {'P_pcc','P_total','P_load','P'};
aliases.Q = {'Q_pcc','Q_total','Q_load','Q'};
aliases.f = {'f_pcc','freq_pcc','frequency','f'};
aliases.V_LLrms = {'V_pcc_LLrms','V_LL_rms','V_ll_rms','V_pcc','V'};
aliases.I_peak = {'I_peak','I_pcc_peak','I_inv_peak','I'};
aliases.m_index = {'modulation_index','m_index','m_abc_max','m'};
end

function candidates = normalizeCandidates(value, fallback)
if isempty(value)
    candidates = fallback;
elseif ischar(value)
    candidates = [{value}, fallback];
elseif isstring(value)
    candidates = [cellstr(value(:))', fallback];
elseif iscell(value)
    candidates = [value(:)', fallback];
else
    error('gfm_extract_sim_signals:badSignalMap', ...
        'Signal map values must be char, string, or cell array.');
end
candidates = unique(candidates, 'stable');
end

function t = getFallbackTime(obj)
t = [];
if isstruct(obj)
    fields = fieldnames(obj);
    idx = find(strcmpi(fields, 'tout') | strcmpi(fields, 'time') | strcmpi(fields, 't'), 1);
    if ~isempty(idx) && isnumeric(obj.(fields{idx}))
        t = obj.(fields{idx})(:);
    end
elseif isa(obj, 'Simulink.SimulationOutput')
    try
        if any(strcmp(obj.who, 'tout'))
            t = obj.get('tout');
            t = t(:);
        end
    catch
        t = [];
    end
end
end

function [found, rawName, rawValue] = findSignal(obj, candidates)
found = false;
rawName = '';
rawValue = [];

if isstruct(obj)
    [found, rawName, rawValue] = findInStruct(obj, candidates);
    if ~found && isfield(obj, 'logsout')
        [found, rawName, rawValue] = findSignal(obj.logsout, candidates);
    end
    return;
end

if isa(obj, 'Simulink.SimulationOutput')
    [found, rawName, rawValue] = findInSimulationOutput(obj, candidates);
    return;
end

if isa(obj, 'Simulink.SimulationData.Dataset')
    [found, rawName, rawValue] = findInDataset(obj, candidates);
    return;
end
end

function [found, rawName, rawValue] = findInStruct(s, candidates)
found = false;
rawName = '';
rawValue = [];
fields = fieldnames(s);
for c = 1:numel(candidates)
    idx = find(strcmpi(fields, candidates{c}), 1);
    if ~isempty(idx)
        rawName = fields{idx};
        rawValue = s.(rawName);
        found = true;
        return;
    end
end
end

function [found, rawName, rawValue] = findInSimulationOutput(simOut, candidates)
found = false;
rawName = '';
rawValue = [];

try
    names = simOut.who;
    for c = 1:numel(candidates)
        idx = find(strcmpi(names, candidates{c}), 1);
        if ~isempty(idx)
            rawName = names{idx};
            rawValue = simOut.get(rawName);
            found = true;
            return;
        end
    end
catch
end

try
    if any(strcmp(simOut.who, 'logsout'))
        logsout = simOut.get('logsout');
        [found, rawName, rawValue] = findInDataset(logsout, candidates);
    end
catch
end
end

function [found, rawName, rawValue] = findInDataset(ds, candidates)
found = false;
rawName = '';
rawValue = [];
try
    for n = 1:ds.numElements
        element = ds.getElement(n);
        for c = 1:numel(candidates)
            if strcmpi(element.Name, candidates{c})
                rawName = element.Name;
                rawValue = element.Values;
                found = true;
                return;
            end
        end
    end
catch
end
end

function sig = normalizeSignal(raw, fallbackTime)
if isa(raw, 'Simulink.SimulationData.Signal')
    raw = raw.Values;
end

if isa(raw, 'timeseries')
    t = raw.Time(:);
    data = raw.Data;
elseif istimetable(raw)
    rowTimes = raw.Properties.RowTimes;
    if isduration(rowTimes)
        t = seconds(rowTimes - rowTimes(1));
    elseif isdatetime(rowTimes)
        t = seconds(rowTimes - rowTimes(1));
    else
        t = (0:height(raw)-1)';
    end
    data = raw{:, :};
elseif isstruct(raw)
    [t, data] = fromSignalStruct(raw, fallbackTime);
elseif isnumeric(raw) || islogical(raw)
    data = raw;
    t = fallbackTime;
else
    error('gfm_extract_sim_signals:unsupportedSignal', ...
        'Unsupported signal value class: %s', class(raw));
end

data = squeeze(double(data));
if isempty(data)
    data = NaN;
end
if isrow(data)
    data = data(:);
end
if isempty(t)
    t = (0:size(data, 1)-1)';
else
    t = t(:);
end

if numel(t) ~= size(data, 1)
    if ~isscalar(data) && numel(t) == size(data, 2)
        data = data.';
    else
        t = (0:size(data, 1)-1)';
    end
end

sig = struct();
sig.time = t;
sig.data = data;
end

function [t, data] = fromSignalStruct(raw, fallbackTime)
fields = fieldnames(raw);
t = fallbackTime;
data = [];

timeIdx = find(strcmpi(fields, 'Time') | strcmpi(fields, 'time') | strcmpi(fields, 't'), 1);
dataIdx = find(strcmpi(fields, 'Data') | strcmpi(fields, 'data') | strcmpi(fields, 'values'), 1);

if ~isempty(timeIdx)
    t = raw.(fields{timeIdx});
end
if ~isempty(dataIdx)
    data = raw.(fields{dataIdx});
else
    error('gfm_extract_sim_signals:badStructSignal', ...
        'Struct signal must contain Data/data/values.');
end
end
