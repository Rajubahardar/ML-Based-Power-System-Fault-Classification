
%% ================================================================
%  TRANSMISSION LINE FAULT DATASET GENERATION AND FEATURE EXTRACTION
%  MATLAB R2024b
%
%  Classes:
%  1. Normal
%  2. LG
%  3. LL
%  4. LLG
%  5. Three_Phase_Fault (three-phase-to-ground)
%
%  Features:
%  4 signals x 3 phases x 5 statistics = 60 features
%
%  This script does not save or overwrite the Simulink model.
%% ================================================================

clc;
clearvars;
close all;

fprintf('\n============================================\n');
fprintf('FAULT DATASET GENERATION AND FEATURE EXTRACTION\n');
fprintf('============================================\n');

%% 1. PROJECT PATHS

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

modelPath = fullfile(projectRoot, ...
    '03_Simulink_Models', ...
    'Transmission_Line_132kV_Phase1.slx');

modelName = 'Transmission_Line_132kV_Phase1';

outputFolder = fullfile(projectRoot, ...
    '05_AI_Dataset');

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

if ~isfile(modelPath)
    error('Simulink model not found: %s', modelPath);
end

%% 2. SIMULATION AND FEATURE SETTINGS

simulationStopTime = 0.4;

faultStart = 0.10;
faultEnd   = 0.20;

windowSeconds = 0.020;
hopSeconds    = 0.005;

faultBlock = [modelName '/Three-Phase Fault'];

signalNames = {'Vabc_S', 'Iabc_S', 'Vabc_R', 'Iabc_R'};

phaseNames = {'A', 'B', 'C'};

statNames = {'RMS', 'MeanAbs', 'Std', ...
             'PeakAbs', 'PeakToPeak'};

%% 3. DEFINE THE FIVE DATASET CLASSES

% FaultA, FaultB and FaultC determine the affected phases.
% GroundFault determines whether ground is involved.

scenarios = struct( ...
    'Name', {}, ...
    'Class', {}, ...
    'FaultA', {}, ...
    'FaultB', {}, ...
    'FaultC', {}, ...
    'GroundFault', {});

scenarios(1) = struct( ...
    'Name', 'Normal', ...
    'Class', 'Normal', ...
    'FaultA', 'off', ...
    'FaultB', 'off', ...
    'FaultC', 'off', ...
    'GroundFault', 'off');

scenarios(2) = struct( ...
    'Name', 'LG', ...
    'Class', 'LG', ...
    'FaultA', 'on', ...
    'FaultB', 'off', ...
    'FaultC', 'off', ...
    'GroundFault', 'on');

scenarios(3) = struct( ...
    'Name', 'LL', ...
    'Class', 'LL', ...
    'FaultA', 'on', ...
    'FaultB', 'on', ...
    'FaultC', 'off', ...
    'GroundFault', 'off');

scenarios(4) = struct( ...
    'Name', 'LLG', ...
    'Class', 'LLG', ...
    'FaultA', 'on', ...
    'FaultB', 'on', ...
    'FaultC', 'off', ...
    'GroundFault', 'on');

scenarios(5) = struct( ...
    'Name', 'Three_Phase_Fault', ...
    'Class', 'Three_Phase_Fault', ...
    'FaultA', 'on', ...
    'FaultB', 'on', ...
    'FaultC', 'on', ...
    'GroundFault', 'on');

%% 4. LOAD MODEL

fprintf('\nLoading Simulink model...\n');

load_system(modelPath);

if ~strcmp(get_param(faultBlock, 'MaskType'), ...
        'Three-Phase Fault')
    error('The expected Three-Phase Fault block was not found.');
end

% Preserve original model settings.
oldStopTime = get_param(modelName, 'StopTime');

oldFaultSettings = struct( ...
    'FaultA', get_param(faultBlock, 'FaultA'), ...
    'FaultB', get_param(faultBlock, 'FaultB'), ...
    'FaultC', get_param(faultBlock, 'FaultC'), ...
    'GroundFault', get_param(faultBlock, 'GroundFault'), ...
    'SwitchTimes', get_param(faultBlock, 'SwitchTimes'));

% Restore original settings if the script exits.
restoreGuard = onCleanup(@() restoreModelSettings( ...
    modelName, faultBlock, oldStopTime, oldFaultSettings));

set_param(modelName, ...
    'StopTime', num2str(simulationStopTime));

%% 5. INITIALIZE DATA STORAGE

metadataRows = {};
featureRows = [];

rawData = struct();

featureNames = {};

scenarioCounter = 0;

fprintf('\nStarting scenario simulations...\n');

%% 6. RUN ALL SCENARIOS AND EXTRACT FEATURES

for k = 1:numel(scenarios)

    scenarioCounter = scenarioCounter + 1;

    currentScenario = scenarios(k);

    fprintf('\n--------------------------------------------\n');
    fprintf('Scenario %d/%d: %s\n', ...
        k, numel(scenarios), currentScenario.Name);

    %% Configure the top-level fault block

    set_param(faultBlock, ...
        'FaultA', currentScenario.FaultA, ...
        'FaultB', currentScenario.FaultB, ...
        'FaultC', currentScenario.FaultC, ...
        'GroundFault', currentScenario.GroundFault, ...
        'SwitchTimes', '[0.10 0.20]');

    fprintf('FaultA: %s\n', currentScenario.FaultA);
    fprintf('FaultB: %s\n', currentScenario.FaultB);
    fprintf('FaultC: %s\n', currentScenario.FaultC);
    fprintf('GroundFault: %s\n', currentScenario.GroundFault);

    %% Run simulation

    fprintf('Running simulation...\n');

    simOut = sim(modelName);

    if ~isempty(simOut.ErrorMessage)
        error('Simulation failed for scenario %s: %s', ...
            currentScenario.Name, simOut.ErrorMessage);
    end

    fprintf('Simulation completed successfully.\n');

    %% Extract the four measured signals

    signals = struct();

    for s = 1:numel(signalNames)

        signalName = signalNames{s};

        signalObject = simOut.get(signalName);

        if isempty(signalObject) || ~isa(signalObject, 'timeseries')
            error('Signal %s is missing or is not a timeseries.', ...
                signalName);
        end

        timeVector = signalObject.Time(:);
        signalData = squeeze(signalObject.Data);

        % Ensure data has dimensions: samples x 3 phases.
        if size(signalData, 1) == 3 && ...
                size(signalData, 2) == numel(timeVector)
            signalData = signalData.';
        end

        if size(signalData, 1) ~= numel(timeVector) || ...
                size(signalData, 2) ~= 3
            error('Unexpected dimensions for signal %s.', signalName);
        end

        if any(~isfinite(signalData), 'all')
            error('Non-finite values found in signal %s.', signalName);
        end

        signals.(signalName) = signalData;
    end

    %% Check sampling interval

    dt = median(diff(timeVector));

    if dt <= 0
        error('Invalid simulation sampling interval.');
    end

    if max(abs(diff(timeVector) - dt)) > 1e-6 * dt
        error('Nonuniform sampling detected. Review model logging.');
    end

    windowSamples = round(windowSeconds / dt);
    hopSamples = round(hopSeconds / dt);

    if windowSamples < 2 || hopSamples < 1
        error('Invalid feature window or hop size.');
    end

    %% Select windows from 0.10 to 0.20 seconds

    firstIndex = find(timeVector >= faultStart - dt/2, ...
        1, 'first');

    lastIndex = find(timeVector <= faultEnd + dt/2, ...
        1, 'last');

    if isempty(firstIndex) || isempty(lastIndex)
        error('Requested feature time interval is unavailable.');
    end

    lastWindowStart = lastIndex - windowSamples + 1;

    if lastWindowStart < firstIndex
        error('Not enough samples for one complete feature window.');
    end

    windowStarts = firstIndex:hopSamples:lastWindowStart;

    fprintf('Number of feature windows: %d\n', ...
        numel(windowStarts));

    %% Save raw simulation signals

    rawData.(currentScenario.Name).Time = timeVector;
    rawData.(currentScenario.Name).Signals = signals;
    rawData.(currentScenario.Name).Class = currentScenario.Class;

    %% Extract 60 features from each window

    for w = 1:numel(windowStarts)

        startIndex = windowStarts(w);

        endIndex = startIndex + windowSamples - 1;

        featureVector = zeros(1, 60);

        featureIndex = 1;

        % Four signal groups.
        for s = 1:numel(signalNames)

            signalData = signals.(signalNames{s});

            % Three phases.
            for p = 1:3

                x = signalData(startIndex:endIndex, p);

                % Five statistical features.
                featureVector(featureIndex) = ...
                    sqrt(mean(x.^2));

                featureIndex = featureIndex + 1;

                featureVector(featureIndex) = ...
                    mean(abs(x));

                featureIndex = featureIndex + 1;

                featureVector(featureIndex) = ...
                    std(x, 0);

                featureIndex = featureIndex + 1;

                featureVector(featureIndex) = ...
                    max(abs(x));

                featureIndex = featureIndex + 1;

                featureVector(featureIndex) = ...
                    max(x) - min(x);

                featureIndex = featureIndex + 1;

            end
        end

        if numel(featureVector) ~= 60
            error('Feature extraction did not produce 60 features.');
        end

        if any(~isfinite(featureVector))
            error('Invalid feature value detected.');
        end

        % Create feature names once.
        if isempty(featureNames)

            for s = 1:numel(signalNames)
                for p = 1:3
                    for m = 1:numel(statNames)

                        featureNames{end+1} = sprintf( ...
                            '%s_%s_%s', ...
                            signalNames{s}, ...
                            phaseNames{p}, ...
                            statNames{m});
                    end
                end
            end

        end

        featureRows(end+1, :) = featureVector;

        scenarioID = sprintf('SCN_%03d', scenarioCounter);

        metadataRows(end+1, :) = { ...
            currentScenario.Class, ...
            scenarioID, ...
            timeVector(startIndex), ...
            timeVector(endIndex)};
    end

    fprintf('Features extracted for %s.\n', ...
        currentScenario.Name);

end

%% 7. CREATE FINAL FEATURE TABLE

fprintf('\nCreating final feature table...\n');

metadataTable = table( ...
    string(metadataRows(:, 1)), ...
    string(metadataRows(:, 2)), ...
    cell2mat(metadataRows(:, 3)), ...
    cell2mat(metadataRows(:, 4)), ...
    'VariableNames', { ...
        'Class', ...
        'ScenarioID', ...
        'WindowStart_s', ...
        'WindowEnd_s'});

featureTableOnly = array2table( ...
    featureRows, ...
    'VariableNames', featureNames);

featureTable = [metadataTable, featureTableOnly];

%% 8. DATASET VALIDATION

fprintf('\n============================================\n');
fprintf('DATASET SUMMARY\n');
fprintf('============================================\n');

fprintf('Total feature windows: %d\n', height(featureTable));

fprintf('Total extracted features: %d\n', ...
    numel(featureNames));

fprintf('Number of classes: %d\n', ...
    numel(unique(featureTable.Class)));

disp(groupsummary(featureTable, 'Class'));

if width(featureTableOnly) ~= 60
    error('The final feature count is not 60.');
end

if any(~isfinite(featureRows), 'all')
    error('The feature dataset contains invalid values.');
end

%% 9. SAVE DATASET FILES

csvFile = fullfile(outputFolder, ...
    'Fault_Feature_Dataset.csv');

matFile = fullfile(outputFolder, ...
    'Fault_Feature_Dataset.mat');

rawFile = fullfile(outputFolder, ...
    'Raw_Fault_Simulation_Data.mat');

writetable(featureTable, csvFile);

save(matFile, ...
    'featureTable', ...
    'featureNames', ...
    'scenarios', ...
    'windowSeconds', ...
    'hopSeconds', ...
    'faultStart', ...
    'faultEnd');

save(rawFile, ...
    'rawData', ...
    '-v7.3');

%% 10. FINAL REPORT

fprintf('\n============================================\n');
fprintf('DATASET GENERATION COMPLETED\n');
fprintf('============================================\n');

fprintf('CSV dataset:\n%s\n\n', csvFile);

fprintf('MAT feature dataset:\n%s\n\n', matFile);

fprintf('Raw simulation data:\n%s\n\n', rawFile);

fprintf('Total windows: %d\n', height(featureTable));
fprintf('Features per window: %d\n', width(featureTableOnly));

fprintf('\nSimulink model was not saved or overwritten.\n');
fprintf('Original model parameters will be restored.\n');

fprintf('\nPROCESS COMPLETED.\n');

%% ================================================================
%  LOCAL FUNCTION: RESTORE ORIGINAL MODEL SETTINGS
%% ================================================================

function restoreModelSettings(modelName, faultBlock, oldStopTime, old)

    if ~bdIsLoaded(modelName)
        return;
    end

    try
        set_param(faultBlock, ...
            'FaultA', old.FaultA, ...
            'FaultB', old.FaultB, ...
            'FaultC', old.FaultC, ...
            'GroundFault', old.GroundFault, ...
            'SwitchTimes', old.SwitchTimes);

        set_param(modelName, 'StopTime', oldStopTime);

        fprintf('\nOriginal model settings restored.\n');

    catch ME
        warning('Could not restore all original model settings: %s', ...
            ME.message);
    end
end
