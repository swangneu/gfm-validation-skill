function gfm_write_validation_report(result, reportPath)
%GFM_WRITE_VALIDATION_REPORT Write a Markdown report for validation results.

folder = fileparts(reportPath);
if ~isempty(folder) && ~exist(folder, 'dir')
    mkdir(folder);
end

fid = fopen(reportPath, 'w');
assert(fid > 0, 'Could not open report path: %s', reportPath);
cleanup = onCleanup(@() fclose(fid));

fprintf(fid, '# GFM validation report\n\n');
fprintf(fid, '- Generated: %s\n', result.generatedAt);
fprintf(fid, '- Scenario: %s\n', result.scenarioName);
if isfield(result, 'model') && ~isempty(result.model)
    fprintf(fid, '- Model: %s\n', result.model);
end
if isfield(result, 'didRunSim')
    fprintf(fid, '- sim() run: %s\n', logicalText(result.didRunSim));
end
fprintf(fid, '- Status: %s (%d passed, %d failed, %d checks)\n\n', ...
    statusText(result.summary.allPassed), result.summary.nPass, ...
    result.summary.nFail, result.summary.nChecks);

fprintf(fid, '## Checks\n\n');
if isempty(result.checks)
    fprintf(fid, 'No checks were produced. Verify the signal map and prediction fields.\n\n');
else
    fprintf(fid, '| Check | Actual | Expected/limit | Error | Tolerance | Units | Result |\n');
    fprintf(fid, '|---|---:|---:|---:|---:|---|---|\n');
    for k = 1:numel(result.checks)
        c = result.checks(k);
        fprintf(fid, '| %s | %.9g | %.9g | %.9g | %.9g | %s | %s |\n', ...
            c.name, c.actual, c.expected, c.error, c.tolerance, c.units, ...
            statusText(c.pass));
    end
    fprintf(fid, '\n');
end

if isfield(result, 'missingSignals') && ~isempty(result.missingSignals)
    fprintf(fid, '## Missing Signals\n\n');
    for k = 1:numel(result.missingSignals)
        fprintf(fid, '- %s\n', result.missingSignals{k});
    end
    fprintf(fid, '\n');
end

notes = {};
for k = 1:numel(result.checks)
    if isfield(result.checks(k), 'note') && ~isempty(result.checks(k).note)
        notes{end+1} = sprintf('%s: %s', result.checks(k).name, result.checks(k).note); %#ok<AGROW>
    end
end
if ~isempty(notes)
    fprintf(fid, '## Notes\n\n');
    for k = 1:numel(notes)
        fprintf(fid, '- %s\n', notes{k});
    end
    fprintf(fid, '\n');
end

fprintf(fid, '## Boundary\n\n');
fprintf(fid, 'This report is simulation evidence only. It is not grid-code compliance, certification, protection proof, hardware qualification, or field deployment approval.\n');
end

function out = statusText(tf)
if tf
    out = 'PASS';
else
    out = 'FAIL';
end
end

function out = logicalText(tf)
if tf
    out = 'yes';
else
    out = 'no';
end
end
