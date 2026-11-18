
%% FIVE-CLASS TRANSMISSION LINE FAULT FEATURE EXTRACTION
% Classes:
% 1. Normal
% 2. LG  - Line to Ground
% 3. LL  - Line to Line
% 4. LLG - Double Line to Ground
% 5. Three Phase Fault
%
% This script does not overwrite the original Simulink model.

clear;
clc;
close all;

%% PROJECT CONFIGURATION

projectDir = 'D:\MATLAB_Projects\TL_Fault_AI';

modelFile = fullfile(projectDir, ...
    '03_Simulink_Models', ...
    'Transmission_Line_132kV_Phase1.slx');

outputDir = fullfile(projectDir, ...
    '05_Feature_Extraction', ...
    'Five_Fault_Comparison');

if ~isfile(modelFile)
    error('Simulink model not found: %s', modelFile);
end

if ~exist(outputDir,'dir')
    mkdir(outputDir);
end

%% SIMULATION SETTINGS

StopTime = 0.4;

FaultStartTime = 0.1;
FaultEndTime = 0.2;

% Initial feature extraction configuration.
% Sampling frequency will be measured from simulation output.
WindowDuration = 0.020;
HopDuration = 0.005;

%% LOAD SIMULINK MODEL

[~,modelName] = fileparts(modelFile);

fprintf('\nLoading model: %s\n',modelName);

load_system(modelFile);

fprintf('Model loaded successfully.\n');

%% FIND FAULT BLOCKS

allBlocks = find_system(modelName, ...
    'LookUnderMasks','all', ...
    'FollowLinks','on', ...
    'Type','Block');

faultCandidates = {};

for k = 1:numel(allBlocks)

    blockName = get_param(allBlocks{k},'Name');

    if contains(lower(blockName),'fault')
        faultCandidates{end+1,1} = allBlocks{k}; %#ok<SAGROW>
    end

end

fprintf('\nFAULT BLOCKS IDENTIFIED:\n');

for k = 1:numel(faultCandidates)
    fprintf('%d. %s\n',k,faultCandidates{k});
end

if isempty(faultCandidates)

    error(['No fault block found. Inspect the Simulink model ' ...
           'and identify its fault block.']);

end

%% DISPLAY FAULT BLOCK PARAMETERS

fprintf('\nFAULT BLOCK PARAMETER INSPECTION\n');

for k = 1:numel(faultCandidates)

    fprintf('\nBlock: %s\n',faultCandidates{k});

    try
        params = get_param(faultCandidates{k}, ...
            'DialogParameters');

        disp(fieldnames(params));

    catch ME
        fprintf('Could not inspect parameters: %s\n',ME.message);
    end

end

fprintf('\nMODEL INSPECTION COMPLETED.\n');
fprintf('Output directory: %s\n',outputDir);


%% CHUNK 2 — FAULT BLOCK AND SIGNAL CONFIGURATION

fprintf('\nAvailable fault blocks:\n');

for k = 1:numel(faultCandidates)
    fprintf('%d. %s\n',k,faultCandidates{k});
end

faultIndex = input('Enter the index of the main Three-Phase Fault block: ');

if isempty(faultIndex) || faultIndex < 1 || ...
        faultIndex > numel(faultCandidates) || ...
        faultIndex ~= floor(faultIndex)
    error('Invalid fault block index.');
end

faultBlockPath = faultCandidates{faultIndex};

faultDialog = get_param(faultBlockPath,'DialogParameters');
availableParams = fieldnames(faultDialog);

fprintf('\nSelected fault block:\n%s\n',faultBlockPath);
fprintf('\nAvailable parameters:\n');
disp(availableParams);

requiredParams = {'FaultA','FaultB','FaultC','GroundFault','SwitchTimes'};

for k = 1:numel(requiredParams)
    if ~ismember(requiredParams{k},availableParams)
        error(['Required parameter "%s" was not found. ' ...
            'Do not continue until the correct fault block is identified.'], ...
            requiredParams{k});
    end
end

%% SIGNAL CONFIGURATION

% These are the expected measurement variable names.
% Confirm that the model logs these signals using To Workspace blocks.

signalNames = {'Vabc_S','Iabc_S','Vabc_R','Iabc_R'};

fprintf('\nExpected logged signals:\n');
disp(signalNames');

fprintf('\nSearching model for To Workspace blocks...\n');

workspaceBlocks = find_system(modelName, ...
    'LookUnderMasks','all', ...
    'FollowLinks','on', ...
    'BlockType','ToWorkspace');

for k = 1:numel(workspaceBlocks)
    try
        variableName = get_param(workspaceBlocks{k},'VariableName');
        fprintf('%s  -->  %s\n',workspaceBlocks{k},variableName);
    catch
        fprintf('%s  --> variable name unavailable\n',workspaceBlocks{k});
    end
end

fprintf('\nSignal names must match the To Workspace variable names.\n');
fprintf('If they differ, edit signalNames in this script before running.\n');

%% DEFINE FIVE FAULT SCENARIOS

faultCases = struct([]);

faultCases(1).Label = 'Normal';
faultCases(1).FaultA = 'off';
faultCases(1).FaultB = 'off';
faultCases(1).FaultC = 'off';
faultCases(1).GroundFault = 'off';

faultCases(2).Label = 'LG';
faultCases(2).FaultA = 'on';
faultCases(2).FaultB = 'off';
faultCases(2).FaultC = 'off';
faultCases(2).GroundFault = 'on';

faultCases(3).Label = 'LL';
faultCases(3).FaultA = 'off';
faultCases(3).FaultB = 'on';
faultCases(3).FaultC = 'on';
faultCases(3).GroundFault = 'off';

faultCases(4).Label = 'LLG';
faultCases(4).FaultA = 'off';
faultCases(4).FaultB = 'on';
faultCases(4).FaultC = 'on';
faultCases(4).GroundFault = 'on';

faultCases(5).Label = 'Three_Phase_Fault';
faultCases(5).FaultA = 'on';
faultCases(5).FaultB = 'on';
faultCases(5).FaultC = 'on';
faultCases(5).GroundFault = 'off';

fprintf('\nFive scenarios configured.\n');

%% CHUNK 3 — RUN FIVE SIMULATIONS

fprintf('\n============================================\n');
fprintf('STARTING FIVE-CLASS SIMULATION\n');
fprintf('============================================\n');

simulationResults = cell(numel(faultCases),1);

% Apply the same fault inception and clearing times to faulted cases.
switchTimeString = mat2str([FaultStartTime FaultEndTime]);

for k = 1:numel(faultCases)

    currentCase = faultCases(k);

    fprintf('\n--------------------------------------------\n');
    fprintf('Running case %d of %d: %s\n', ...
        k,numel(faultCases),currentCase.Label);
    fprintf('--------------------------------------------\n');

    % Configure fault type.
    set_param(faultBlockPath, ...
        'FaultA',currentCase.FaultA, ...
        'FaultB',currentCase.FaultB, ...
        'FaultC',currentCase.FaultC, ...
        'GroundFault',currentCase.GroundFault, ...
        'SwitchTimes',switchTimeString);

    % Run model without saving changes to the original SLX file.
    try
        simOut = sim(modelName, ...
            'StopTime',num2str(StopTime), ...
            'ReturnWorkspaceOutputs','on');

        simulationResults{k} = simOut;

        fprintf('Simulation completed: %s\n',currentCase.Label);

    catch ME
        fprintf(2,'Simulation failed for %s:\n%s\n', ...
            currentCase.Label,ME.message);
        rethrow(ME);
    end

end

%% SAVE RAW SIMULATION OUTPUTS

rawOutputFile = fullfile(outputDir, ...
    'Five_Fault_Raw_Simulation_Outputs.mat');

save(rawOutputFile, ...
    'simulationResults','faultCases', ...
    'FaultStartTime','FaultEndTime','StopTime', ...
    'signalNames','modelName','-v7.3');

fprintf('\nAll five simulations completed.\n');
fprintf('Raw simulation outputs saved to:\n%s\n',rawOutputFile);

%% CHUNK 4 — FEATURE EXTRACTION AND DATASET SAVING

fprintf('\n============================================\n');
fprintf('STARTING FEATURE EXTRACTION\n');
fprintf('============================================\n');

signalPrefixes = {'Vs','Is','Vr','Ir'};
phaseNames = {'A','B','C'};
statNames = {'RMS','MeanAbs','Std','PeakAbs','PeakToPeak'};

featureNames = cell(1,60);
featureCounter = 0;

for s = 1:4
    for p = 1:3
        for f = 1:5
            featureCounter = featureCounter + 1;
            featureNames{featureCounter} = sprintf('%s_%s_%s', ...
                signalPrefixes{s},phaseNames{p},statNames{f});
        end
    end
end

featureMatrix = [];
labelList = {};
simulationIDList = {};
windowStartList = [];
windowEndList = [];

for k = 1:numel(faultCases)

    currentCase = faultCases(k);
    simOut = simulationResults{k};

    fprintf('\nExtracting features: %s\n',currentCase.Label);

    % Read all four logged signals.
    signalData = cell(4,1);
    commonTime = [];

    for s = 1:4

        signalData{s} = readLoggedSignal(simOut,signalNames{s});

        if isempty(commonTime)
            commonTime = signalData{s}.Time;
        else
            if numel(signalData{s}.Time) ~= numel(commonTime) || ...
                    max(abs(signalData{s}.Time(:)-commonTime(:))) > 1e-9
                error('Signal time vectors do not match for %s.', ...
                    currentCase.Label);
            end
        end

        if size(signalData{s}.Data,2) ~= 3
            error(['Signal %s must contain three phase columns. ' ...
                'Actual size: %s'],signalNames{s}, ...
                mat2str(size(signalData{s}.Data)));
        end

    end

    % Confirm uniform sampling.
    timeStep = median(diff(commonTime));

    if timeStep <= 0 || ...
            max(abs(diff(commonTime)-timeStep)) > 1e-6*timeStep
        error('Nonuniform or invalid sampling time detected.');
    end

    Fs = 1/timeStep;

    windowSamples = round(WindowDuration*Fs);
    hopSamples = round(HopDuration*Fs);

    if windowSamples < 2 || hopSamples < 1
        error('Invalid window or hop configuration.');
    end

    fprintf('Sampling frequency: %.2f Hz\n',Fs);
    fprintf('Window length: %d samples (%.2f ms)\n', ...
        windowSamples,1000*windowSamples/Fs);
    fprintf('Hop length: %d samples (%.2f ms)\n', ...
        hopSamples,1000*hopSamples/Fs);

    if abs(windowSamples/Fs-WindowDuration) > timeStep
        warning('Window duration is not represented exactly by samples.');
    end

    % Build complete windows.
    finalStart = numel(commonTime)-windowSamples+1;
    startIndices = 1:hopSamples:finalStart;

    caseFeatureRows = [];
    caseStartTimes = [];
    caseEndTimes = [];

    for w = 1:numel(startIndices)

        firstIndex = startIndices(w);
        lastIndex = firstIndex+windowSamples-1;

        tStart = commonTime(firstIndex);
        tEnd = commonTime(lastIndex);

        % Select only unambiguous windows.
        if strcmp(currentCase.Label,'Normal')

            validWindow = (tEnd <= FaultStartTime) || ...
                          (tStart >= FaultEndTime);

        else

            validWindow = (tStart >= FaultStartTime) && ...
                          (tEnd <= FaultEndTime);

        end

        if ~validWindow
            continue;
        end

        row = zeros(1,60);
        featureIndex = 0;

        for s = 1:4

            segment = signalData{s}.Data(firstIndex:lastIndex,:);

            for p = 1:3

                x = segment(:,p);
                x = x(isfinite(x));

                if isempty(x)
                    error('Empty or invalid signal window detected.');
                end

                values = [ ...
                    sqrt(mean(x.^2)), ...
                    mean(abs(x)), ...
                    std(x), ...
                    max(abs(x)), ...
                    max(x)-min(x)];

                for f = 1:5
                    featureIndex = featureIndex+1;
                    row(featureIndex) = values(f);
                end

            end
        end

        if any(~isfinite(row))
            error('Invalid feature values detected in %s.', ...
                currentCase.Label);
        end

        caseFeatureRows = [caseFeatureRows;row]; %#ok<AGROW>
        caseStartTimes = [caseStartTimes;tStart]; %#ok<AGROW>
        caseEndTimes = [caseEndTimes;tEnd]; %#ok<AGROW>

    end

    if isempty(caseFeatureRows)
        warning('No valid windows extracted for %s.',currentCase.Label);
        continue;
    end

    nRows = size(caseFeatureRows,1);

    featureMatrix = [featureMatrix;caseFeatureRows]; %#ok<AGROW>

    labelList = [labelList;repmat({currentCase.Label},nRows,1)]; %#ok<AGROW>

    simulationIDList = [simulationIDList; ...
        repmat({sprintf('SIM_%02d',k)},nRows,1)]; %#ok<AGROW>

    windowStartList = [windowStartList;caseStartTimes]; %#ok<AGROW>
    windowEndList = [windowEndList;caseEndTimes]; %#ok<AGROW>

    fprintf('Valid windows extracted: %d\n',nRows);

end

%% CREATE FINAL FEATURE TABLE

if isempty(featureMatrix)
    error(['No feature windows were extracted. Check the logged ' ...
        'signals and fault timing.']);
end

featureTable = array2table(featureMatrix, ...
    'VariableNames',featureNames);

featureTable.Label = categorical(labelList);
featureTable.Simulation_ID = simulationIDList;
featureTable.WindowStart_s = windowStartList;
featureTable.WindowEnd_s = windowEndList;

%% DATA QUALITY CHECKS

numericFeatures = featureTable{:,featureNames};

if any(~isfinite(numericFeatures(:)))
    error('Dataset contains NaN or Inf feature values.');
end

fprintf('\n============================================\n');
fprintf('DATASET SUMMARY\n');
fprintf('============================================\n');

summaryTable = groupsummary(featureTable,'Label','numel','Label');

disp(summaryTable);

fprintf('Total feature windows: %d\n',height(featureTable));
fprintf('Number of features: %d\n',numel(featureNames));

%% SAVE OUTPUTS

matFile = fullfile(outputDir, ...
    'Five_Fault_Feature_Dataset.mat');

csvFile = fullfile(outputDir, ...
    'Five_Fault_Feature_Dataset.csv');

featureDefinitionFile = fullfile(outputDir, ...
    'Feature_Definitions.csv');

save(matFile, ...
    'featureTable','featureNames','signalNames', ...
    'WindowDuration','HopDuration','FaultStartTime', ...
    'FaultEndTime','StopTime','faultCases','-v7.3');

writetable(featureTable,csvFile);

featureDefinitions = table(featureNames(:), ...
    repmat({'RMS, MeanAbs, Std, PeakAbs, PeakToPeak'},60,1), ...
    'VariableNames',{'FeatureName','FeatureFamily'});

writetable(featureDefinitions,featureDefinitionFile);

fprintf('\nFEATURE EXTRACTION COMPLETED.\n');
fprintf('MAT file: %s\n',matFile);
fprintf('CSV file: %s\n',csvFile);
fprintf('Feature definitions: %s\n',featureDefinitionFile);

%% LOCAL FUNCTION — READ LOGGED SIGNAL

function result = readLoggedSignal(simOut,variableName)

    try
        raw = simOut.get(variableName);
    catch
        error(['Could not find logged signal "%s" in simulation output. ' ...
            'Check the To Workspace variable name and logging settings.'], ...
            variableName);
    end

    if isa(raw,'timeseries')

        t = raw.Time;
        x = raw.Data;

    elseif isa(raw,'Simulink.SimulationData.Signal')

        t = raw.Values.Time;
        x = raw.Values.Data;

    elseif isstruct(raw) && ...
            isfield(raw,'time') && isfield(raw,'signals')

        t = raw.time;
        x = raw.signals.values;

    else

        error(['Unsupported data format for signal "%s". ' ...
            'Expected timeseries, Simulink Signal, or time/signals struct.'], ...
            variableName);

    end

    t = double(t(:));
    x = squeeze(double(x));

    if ismatrix(x) && size(x,1) == 3 && size(x,2) == numel(t)
        x = x.';
    end

    if size(x,1) ~= numel(t)
        error('Time and data dimensions do not match for %s.',variableName);
    end

    if size(x,2) ~= 3
        error('Expected three-phase data for %s.',variableName);
    end

    if any(~isfinite(t)) || any(~isfinite(x(:)))
        error('Signal %s contains invalid values.',variableName);
    end

    result.Time = t;
    result.Data = x;

end
