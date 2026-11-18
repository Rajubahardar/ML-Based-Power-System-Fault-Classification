
%% ============================================================
%  AUTOMATED ENGINEERING DOCUMENTATION SYSTEM
%  Project: AI-Based Transmission Line Fault Detection
%  MATLAB: R2024b
%
%  HOW TO USE:
%  1. Change the PHASE CONFIGURATION section for each new phase.
%  2. Run this script.
%  3. Reports and project index update automatically.
%
%  This script does not modify source models or raw datasets.
%% ============================================================

clc;

%% 1. PROJECT CONFIGURATION

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

% Change these three values for future phases.
cfg.id = 'Phase1_Normal_Operation';

cfg.title = ...
    'Normal Operation Modelling of a 132 kV Three-Phase Transmission Line';

cfg.objective = ...
    ['Develop a three-phase 132 kV transmission line model under ' ...
     'normal operating conditions and record sending-end and ' ...
     'receiving-end voltage and current signals.'];

cfg.status = 'PRELIMINARY - ELECTRICAL VALIDATION PENDING';

% Phase 1 source files
cfg.model = fullfile(projectRoot, ...
    '03_Simulink_Models','Phase_1_Normal_Model', ...
    'Transmission_Line_132kV_Phase1.slx');

cfg.dataset = fullfile(projectRoot, ...
    '04_Data_Generation','Normal_Data', ...
    'Phase1_Normal_Operation_Data.mat');

cfg.buildScript = fullfile(projectRoot, ...
    '03_Simulink_Models','Phase_1_Normal_Model', ...
    'build_Transmission_Line_Phase1.m');

cfg.figureFolder = fullfile(projectRoot, ...
    '10_Documentation','Figures','Phase1_Normal_Operation');

%% 2. DOCUMENTATION FOLDERS

reportFolder = fullfile(projectRoot, ...
    '10_Documentation','Reports');

registerFolder = fullfile(projectRoot, ...
    '10_Documentation','Registers');

validationFolder = fullfile(projectRoot,'08_Validation');

if ~isfolder(reportFolder), mkdir(reportFolder); end
if ~isfolder(registerFolder), mkdir(registerFolder); end
if ~isfolder(validationFolder), mkdir(validationFolder); end

%% 3. VERIFY SOURCE FILES

assert(isfile(cfg.model), ...
    'Simulink model not found.');

assert(isfile(cfg.dataset), ...
    'Simulation dataset not found.');

assert(isfile(cfg.buildScript), ...
    'Build script not found.');

%% 4. LOAD ACTUAL SIMULATION DATA

D = load(cfg.dataset);

required = {'Vabc_S','Iabc_S','Vabc_R','Iabc_R'};

for k = 1:numel(required)
    assert(isfield(D,required{k}), ...
        'Missing dataset variable: %s',required{k});
end

t = D.Vabc_S.Time(:);

VS = D.Vabc_S.Data;
IS = D.Iabc_S.Data;
VR = D.Vabc_R.Data;
IR = D.Iabc_R.Data;

assert(size(VS,2)==3 && size(IS,2)==3 && ...
       size(VR,2)==3 && size(IR,2)==3, ...
       'Unexpected signal dimensions.');

%% 5. CALCULATE STEADY-STATE RMS

steady = t >= 0.2 & t <= 0.4;

assert(any(steady), ...
    'Steady-state interval is empty.');

rmsVS = sqrt(mean(VS(steady,:).^2,1));
rmsIS = sqrt(mean(IS(steady,:).^2,1));
rmsVR = sqrt(mean(VR(steady,:).^2,1));
rmsIR = sqrt(mean(IR(steady,:).^2,1));

%% 6. DATA INTEGRITY CHECK

signals = {VS,IS,VR,IR};

signalNames = {
    'Sending Voltage'
    'Sending Current'
    'Receiving Voltage'
    'Receiving Current'
};

nanCounts = zeros(4,1);
infCounts = zeros(4,1);
maxValues = zeros(4,1);

for k = 1:4
    nanCounts(k) = sum(isnan(signals{k}(:)));
    infCounts(k) = sum(isinf(signals{k}(:)));
    maxValues(k) = max(abs(signals{k}(:)));
end

totalNaN = sum(nanCounts);
totalInf = sum(infCounts);

%% 7. ENGINEERING PARAMETERS

parameter = {
    'Nominal voltage',             '132',       'kV L-L RMS', 'Selected design value'
    'Frequency',                   '50',        'Hz',         'Provisional'
    'Line length',                 '100',       'km',         'Provisional'
    'Positive sequence resistance','0.03',      'ohm/km',     'Illustrative'
    'Zero sequence resistance',    '0.30',      'ohm/km',     'Illustrative'
    'Positive sequence inductance','0.001',     'H/km',       'Illustrative'
    'Zero sequence inductance',    '0.003',     'H/km',       'Illustrative'
    'Positive sequence capacitance','1.0e-8',   'F/km',       'Illustrative'
    'Zero sequence capacitance',   '6.0e-9',    'F/km',       'Illustrative'
    'Load active power',           '50',        'MW',         'Provisional'
    'Load reactive power',         '16.434',    'MVAr',       'Provisional'
    'Source short-circuit level',  '1000',      'MVA',        'Provisional'
    'Source X/R ratio',            '10',        'Dimensionless','Provisional'
    'Simulation duration',         num2str(t(end)-t(1)), 's', 'Measured'
    'Sampling interval',           num2str(mean(diff(t)),'%.9g'), 's', 'Measured'
    };

parameterTable = cell2table(parameter, ...
    'VariableNames',{'Parameter','Value','Unit','Status'});

%% 8. VERIFY EXISTING FIGURES

figureNames = {
    'Sending_End_Voltage.fig'
    'Sending_End_Voltage.png'
    'Sending_End_Current.fig'
    'Sending_End_Current.png'
    'Receiving_End_Voltage.fig'
    'Receiving_End_Voltage.png'
    'Receiving_End_Current.fig'
    'Receiving_End_Current.png'
    };

figureExists = false(numel(figureNames),1);

for k = 1:numel(figureNames)
    figureExists(k) = isfile( ...
        fullfile(cfg.figureFolder,figureNames{k}));
end

%% 9. CREATE PHASE REPORT

reportFile = fullfile(reportFolder, ...
    [cfg.id,'_Technical_Report.md']);

fid = fopen(reportFile,'w');
assert(fid~=-1,'Cannot create technical report.');

fprintf(fid,'# %s\n\n',cfg.title);

fprintf(fid,'**Project:** AI-Based Fault Detection and Classification in a 132 kV Three-Phase Transmission Line\n\n');

fprintf(fid,'## Document Information\n\n');
fprintf(fid,'- Phase ID: %s\n',cfg.id);
fprintf(fid,'- Status: %s\n',cfg.status);
fprintf(fid,'- Generated: %s\n',datestr(now,31));
fprintf(fid,'- MATLAB release: %s\n\n',version('-release'));

fprintf(fid,'## 1. Objective\n\n%s\n\n',cfg.objective);

fprintf(fid,'## 2. System Configuration\n\n');
fprintf(fid,'| Parameter | Value |\n|---|---:|\n');

for k = 1:size(parameter,1)
    fprintf(fid,'| %s | %s %s |\n', ...
        parameter{k,1},parameter{k,2},parameter{k,3});
end

fprintf(fid,'\n## 3. Model Architecture\n\n');
fprintf(fid,'Three-Phase Source -> Sending-End V-I Measurement -> ');
fprintf(fid,'100 km Three-Phase PI Section Line -> ');
fprintf(fid,'Receiving-End V-I Measurement -> Three-Phase Load.\n\n');

fprintf(fid,'## 4. Logged Signals\n\n');
fprintf(fid,'- Vabc_S: Sending-end voltage\n');
fprintf(fid,'- Iabc_S: Sending-end current\n');
fprintf(fid,'- Vabc_R: Receiving-end voltage\n');
fprintf(fid,'- Iabc_R: Receiving-end current\n\n');

fprintf(fid,'## 5. Simulation Information\n\n');
fprintf(fid,'- Duration: %.6f s\n',t(end)-t(1));
fprintf(fid,'- Number of samples: %d\n',numel(t));
fprintf(fid,'- Average sampling interval: %.9g s\n',mean(diff(t)));
fprintf(fid,'- RMS calculation interval: 0.2 to 0.4 s\n\n');

fprintf(fid,'## 6. RMS Results\n\n');
fprintf(fid,'| Phase | Sending V (kV) | Sending I (A) | Receiving V (kV) | Receiving I (A) |\n');
fprintf(fid,'|---|---:|---:|---:|---:|\n');

phaseNames = {'A','B','C'};

for k = 1:3
    fprintf(fid,'| %s | %.3f | %.3f | %.3f | %.3f |\n', ...
        phaseNames{k},rmsVS(k)/1000,rmsIS(k), ...
        rmsVR(k)/1000,rmsIR(k));
end

fprintf(fid,'\n## 7. Data Integrity\n\n');
fprintf(fid,'| Signal | NaN count | Inf count | Maximum absolute value |\n');
fprintf(fid,'|---|---:|---:|---:|\n');

for k = 1:4
    fprintf(fid,'| %s | %d | %d | %.6f |\n', ...
        signalNames{k},nanCounts(k), ...
        infCounts(k),maxValues(k));
end

fprintf(fid,'\nTotal NaN values: %d\n',totalNaN);
fprintf(fid,'\nTotal Inf values: %d\n\n',totalInf);

fprintf(fid,'## 8. Waveform Evidence\n\n');

for k = 1:numel(figureNames)
    fprintf(fid,'- %s : %s\n',figureNames{k}, ...
        string(figureExists(k)));
end

fprintf(fid,'\nFigure folder: `%s`\n\n',cfg.figureFolder);

fprintf(fid,'## 9. Simulink Model and Source Files\n\n');
fprintf(fid,'- Model: `%s`\n',cfg.model);
fprintf(fid,'- Build script: `%s`\n',cfg.buildScript);
fprintf(fid,'- Dataset: `%s`\n\n',cfg.dataset);

fprintf(fid,'## 10. Engineering Limitations\n\n');
fprintf(fid,'1. Line parameters are illustrative and are not validated against an actual transmission corridor.\n');
fprintf(fid,'2. The initial simulation reported propagation speed of 316228 km/s for mode 2, above the stated 300000 km/s limit.\n');
fprintf(fid,'3. The propagation-speed warning remains unresolved.\n');
fprintf(fid,'4. Power-flow and electrical plausibility checks remain necessary.\n');
fprintf(fid,'5. Fault modelling and classification have not yet been tested.\n\n');

fprintf(fid,'## 11. Validation Status\n\n');
fprintf(fid,'**%s**\n\n',cfg.status);
fprintf(fid,'Successful execution and data-integrity checks do not independently establish electrical model validity.\n');

fclose(fid);

%% 10. SAVE PARAMETER REGISTER

parameterFile = fullfile(registerFolder, ...
    [cfg.id,'_Parameter_Register.csv']);

writetable(parameterTable,parameterFile);

%% 11. SAVE EXPERIMENT RECORD

experiment = struct();

experiment.ID = cfg.id;
experiment.Date = datetime('now');
experiment.RMS.SendingVoltage = rmsVS;
experiment.RMS.SendingCurrent = rmsIS;
experiment.RMS.ReceivingVoltage = rmsVR;
experiment.RMS.ReceivingCurrent = rmsIR;
experiment.NaNCount = totalNaN;
experiment.InfCount = totalInf;
experiment.SampleCount = numel(t);
experiment.SampleInterval = mean(diff(t));
experiment.FigureNames = figureNames;
experiment.FigureExists = figureExists;
experiment.Status = cfg.status;

experimentFile = fullfile( ...
    projectRoot,'07_Experiments','Experiment_Results', ...
    [cfg.id,'_Experiment_Record.mat']);

experimentFolder = fileparts(experimentFile);

if ~isfolder(experimentFolder)
    mkdir(experimentFolder);
end

save(experimentFile,'experiment');

%% 12. CREATE VALIDATION REPORT

validationFile = fullfile(validationFolder, ...
    [cfg.id,'_Validation_Report.txt']);

fid = fopen(validationFile,'w');
assert(fid~=-1,'Cannot create validation report.');

fprintf(fid,'PHASE VALIDATION REPORT\n');
fprintf(fid,'===============================\n\n');
fprintf(fid,'Phase: %s\n',cfg.id);
fprintf(fid,'Generated: %s\n',datestr(now,31));
fprintf(fid,'Status: %s\n\n',cfg.status);

fprintf(fid,'Dataset integrity:\n');
fprintf(fid,'NaN count: %d\n',totalNaN);
fprintf(fid,'Inf count: %d\n',totalInf);
fprintf(fid,'Sample count: %d\n\n',numel(t));

fprintf(fid,'Waveform figures verified: %d of %d\n\n', ...
    sum(figureExists),numel(figureExists));

fprintf(fid,'OPEN ENGINEERING ISSUE:\n');
fprintf(fid,'Propagation speed warning: 316228 km/s.\n');
fprintf(fid,'The stated limit is 300000 km/s.\n');
fprintf(fid,'Further investigation is required.\n\n');

fprintf(fid,'This report does not declare the model electrically validated.\n');

fclose(fid);

%% 13. CREATE EXECUTION LOG

executionFile = fullfile(validationFolder, ...
    [cfg.id,'_Execution_Log.txt']);

fid = fopen(executionFile,'w');
assert(fid~=-1,'Cannot create execution log.');

fprintf(fid,'DOCUMENTATION EXECUTION LOG\n');
fprintf(fid,'===============================\n');
fprintf(fid,'Phase ID: %s\n',cfg.id);
fprintf(fid,'Execution time: %s\n',datestr(now,31));
fprintf(fid,'MATLAB release: %s\n',version('-release'));
fprintf(fid,'Dataset loaded: YES\n');
fprintf(fid,'Model file exists: YES\n');
fprintf(fid,'Build script exists: YES\n');
fprintf(fid,'Report generated: YES\n');
fprintf(fid,'Parameter register generated: YES\n');
fprintf(fid,'Experiment record generated: YES\n');

fclose(fid);

%% 14. UPDATE MASTER PROJECT README

readmeFile = fullfile(projectRoot,'project_readme.md');

startTag = ['<!-- START_',cfg.id,' -->'];
endTag = ['<!-- END_',cfg.id,' -->'];

newSection = sprintf([ ...
    '%s\n\n## %s\n\n' ...
    '- Phase ID: %s\n' ...
    '- Status: %s\n' ...
    '- Technical report: `10_Documentation/Reports/%s_Technical_Report.md`\n' ...
    '- Parameter register: `10_Documentation/Registers/%s_Parameter_Register.csv`\n' ...
    '- Validation report: `08_Validation/%s_Validation_Report.txt`\n' ...
    '- Execution log: `08_Validation/%s_Execution_Log.txt`\n' ...
    '- Experiment record: `07_Experiments/Experiment_Results/%s_Experiment_Record.mat`\n\n' ...
    '%s\n'], ...
    startTag,cfg.title,cfg.id,cfg.status, ...
    cfg.id,cfg.id,cfg.id,cfg.id,cfg.id,endTag);

if isfile(readmeFile)
    oldText = fileread(readmeFile);
else
    oldText = '# Transmission Line Fault Detection Project\n\n';
end

starts = strfind(oldText,startTag);
ends = strfind(oldText,endTag);

if isempty(starts) && isempty(ends)

    updatedText = [oldText,newline,newSection];

elseif numel(starts)==1 && numel(ends)==1 && ends(1)>starts(1)

    afterEnd = ends(1)+numel(endTag);

    updatedText = [oldText(1:starts(1)-1), ...
        newSection,oldText(afterEnd:end)];

else

    error('Master README markers are duplicated or inconsistent.');
end

fid = fopen(readmeFile,'w');
assert(fid~=-1,'Cannot update master README.');

fwrite(fid,updatedText,'char');
fclose(fid);

%% 15. DISPLAY COMPLETION SUMMARY

fprintf('\n============================================\n');
fprintf(' AUTOMATED DOCUMENTATION COMPLETE\n');
fprintf('============================================\n');

fprintf('\nTechnical report:\n%s\n',reportFile);
fprintf('\nParameter register:\n%s\n',parameterFile);
fprintf('\nExperiment record:\n%s\n',experimentFile);
fprintf('\nValidation report:\n%s\n',validationFile);
fprintf('\nExecution log:\n%s\n',executionFile);
fprintf('\nMaster project index:\n%s\n',readmeFile);

fprintf('\nFigures verified: %d/%d\n', ...
    sum(figureExists),numel(figureExists));

fprintf('\nNaN values: %d\n',totalNaN);
fprintf('Inf values: %d\n',totalInf);

fprintf('\nPHASE DOCUMENTATION FINISHED.\n');
fprintf('============================================\n');
