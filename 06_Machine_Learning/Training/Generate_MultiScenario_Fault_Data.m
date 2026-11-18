
%% MULTI-SCENARIO TRANSMISSION LINE FAULT DATA GENERATION
% Project: AI-Based Fault Detection and Classification
% Model: Transmission_Line_132kV_Phase1
%
% Generates 135 independent fault simulation scenarios.
% The existing Simulink model is modified temporarily and restored
% to its original parameter values when the script finishes.

clear;
clc;


%% 1. PROJECT PATHS AND AUTOMATIC MODEL DETECTION

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

if ~isfolder(projectRoot)
    error('Project folder not found: %s', projectRoot);
end

% Search all subfolders for Simulink models.
modelFiles = dir(fullfile(projectRoot, '**', '*.slx'));

if isempty(modelFiles)
    error(['No SLX model found inside: %s\n' ...
        'Check where your remaining model file is saved.'], projectRoot);
end

if numel(modelFiles) > 1
    fprintf('\nMultiple SLX files found:\n');

    for k = 1:numel(modelFiles)
        fprintf('%d. %s\n', k, ...
            fullfile(modelFiles(k).folder, modelFiles(k).name));
    end

    error('More than one model found. Keep only the intended model or specify its path.');
end

modelFile = fullfile(modelFiles(1).folder, modelFiles(1).name);

[~, modelName] = fileparts(modelFile);

outputFolder = fullfile(projectRoot, ...
    '04_Data_Generation', 'MultiScenario_Fault_Data');

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

fprintf('\nModel automatically detected:\n%s\n', modelFile);



%% 2. LOAD EXISTING MODEL WITHOUT NAME CONFLICT

% Check whether a model with this name is already loaded.
if bdIsLoaded(modelName)

    loadedFile = get_param(modelName, 'FileName');

    % Compare the currently loaded model with the intended model.
    if ~strcmpi(loadedFile, modelFile)

        fprintf('Closing previously loaded model:\n%s\n', loadedFile);

        % Do not silently discard unsaved model changes.
        if strcmp(get_param(modelName, 'Dirty'), 'on')
            error(['The previously loaded model has unsaved changes. ' ...
                'Save or explicitly close it in Simulink, then rerun.']);
        end

        close_system(modelName, 0);
    end
end

% Load only if it is not already loaded.
if ~bdIsLoaded(modelName)
    load_system(modelFile);
end

fprintf('\nActive model:\n%s\n', ...
    get_param(modelName, 'FileName'));


%% 3. IDENTIFY MODEL BLOCKS

line1 = [modelName '/50 km PI Line Section 1'];
line2 = [modelName '/50 km PI Line Section 2'];

if getSimulinkBlockHandle(line1) == -1
    error('First PI line block not found: %s', line1);
end

if getSimulinkBlockHandle(line2) == -1
    error('Second PI line block not found: %s', line2);
end

% Locate the Three-Phase Fault block automatically.
faultBlocks = find_system(modelName, ...
    'LookUnderMasks', 'all', ...
    'FollowLinks', 'on', ...
    'MaskType', 'Three-Phase Fault');

if isempty(faultBlocks)
    error(['Three-Phase Fault block was not found. ' ...
        'Check its MaskType and update the script.']);
end

if numel(faultBlocks) > 1
    error(['More than one Three-Phase Fault block was found. ' ...
        'Specify the correct block path manually.']);
end

faultBlock = faultBlocks{1};

fprintf('Model: %s\n', modelName);
fprintf('Fault block: %s\n', faultBlock);

%% 4. CHECK LINE LENGTH PARAMETERS

line1Params = get_param(line1, 'DialogParameters');
line2Params = get_param(line2, 'DialogParameters');

if ~isfield(line1Params, 'Length') || ...
        ~isfield(line2Params, 'Length')
    error(['The PI line blocks do not expose a Length parameter. ' ...
        'Check the block mask before running this script.']);
end

%% 5. SAVE ORIGINAL PARAMETERS FOR RESTORATION

original.line1Length = get_param(line1, 'Length');
original.line2Length = get_param(line2, 'Length');

faultParameters = { ...
    'FaultA', ...
    'FaultB', ...
    'FaultC', ...
    'GroundFault', ...
    'SwitchTimes', ...
    'SwitchStatus', ...
    'FaultResistance', ...
    'GroundResistance'};

for k = 1:numel(faultParameters)
    original.fault.(faultParameters{k}) = ...
        get_param(faultBlock, faultParameters{k});
end

% Automatically restore the original model parameters when the
% script completes or stops with an error.
cleanupObject = onCleanup(@() restoreOriginalModel( ...
    line1, line2, faultBlock, original)); %#ok<NASGU>

%% 6. DEFINE EXPERIMENTAL SCENARIOS

faultTypes = {'LG', 'LL', 'LLG', 'LLL', 'LLLG'};

faultResistances = [0.1, 1, 5];       % Ohms
faultInceptionTimes = [0.08, 0.10, 0.12]; % Seconds
faultLocations = [20, 50, 80];        % Kilometres

totalLineLength = 100;                % km
faultDuration = 0.10;                 % seconds
simulationStopTime = '0.40';

totalScenarios = numel(faultTypes) * ...
    numel(faultResistances) * ...
    numel(faultInceptionTimes) * ...
    numel(faultLocations);

fprintf('\nTotal planned simulations: %d\n', totalScenarios);

%% 7. DEFINE FAULT CONFIGURATIONS

% Columns: [FaultA FaultB FaultC GroundFault]
faultConfigurations = {
    'LG',   {'on',  'off', 'off', 'on'}
    'LL',   {'on',  'on',  'off', 'off'}
    'LLG',  {'on',  'on',  'off', 'on'}
    'LLL',  {'on',  'on',  'on',  'off'}
    'LLLG', {'on',  'on',  'on',  'on'}
};

%% 8. PREPARE RESULTS TABLE

results = table( ...
    strings(totalScenarios, 1), ...
    strings(totalScenarios, 1), ...
    zeros(totalScenarios, 1), ...
    zeros(totalScenarios, 1), ...
    zeros(totalScenarios, 1), ...
    strings(totalScenarios, 1), ...
    'VariableNames', { ...
        'ScenarioID', ...
        'FaultType', ...
        'FaultResistance_Ohm', ...
        'FaultInception_s', ...
        'FaultLocation_km', ...
        'Status'});

scenarioCounter = 0;

%% 9. RUN ALL SIMULATION SCENARIOS

for f = 1:numel(faultTypes)

    faultType = faultTypes{f};

    % Get the corresponding phase and ground configuration.
    configIndex = find(strcmp( ...
        faultConfigurations(:,1), faultType), 1);

    config = faultConfigurations{configIndex, 2};

    fprintf('\n----------------------------------------\n');
    fprintf('FAULT TYPE: %s\n', faultType);
    fprintf('----------------------------------------\n');

    for r = 1:numel(faultResistances)

        resistance = faultResistances(r);

        for t = 1:numel(faultInceptionTimes)

            faultStart = faultInceptionTimes(t);
            faultEnd = faultStart + faultDuration;

            for loc = 1:numel(faultLocations)

                locationKm = faultLocations(loc);

                scenarioCounter = scenarioCounter + 1;

                %% 9.1 UPDATE FAULT LOCATION

                firstSectionLength = locationKm;
                secondSectionLength = totalLineLength - locationKm;

                set_param(line1, ...
                    'Length', num2str(firstSectionLength));

                set_param(line2, ...
                    'Length', num2str(secondSectionLength));

                %% 9.2 UPDATE FAULT TYPE

                set_param(faultBlock, ...
                    'FaultA', config{1}, ...
                    'FaultB', config{2}, ...
                    'FaultC', config{3}, ...
                    'GroundFault', config{4});

                %% 9.3 UPDATE FAULT RESISTANCE AND TIMING

                set_param(faultBlock, ...
                    'FaultResistance', num2str(resistance), ...
                    'GroundResistance', num2str(resistance), ...
                    'SwitchTimes', mat2str([faultStart faultEnd]), ...
                    'SwitchStatus', '[1 0]');

                %% 9.4 CREATE SCENARIO IDENTIFIER

                scenarioID = sprintf( ...
                    '%s_R%s_T%s_L%03d', ...
                    faultType, ...
                    strrep(num2str(resistance), '.', 'p'), ...
                    strrep(num2str(faultStart), '.', 'p'), ...
                    locationKm);

                fprintf('\nScenario %d/%d: %s\n', ...
                    scenarioCounter, totalScenarios, scenarioID);

                %% 9.5 RUN SIMULATION

                try

                    simOut = sim(modelName, ...
                        'StopTime', simulationStopTime, ...
                        'ReturnWorkspaceOutputs', 'on');

                    %% 9.6 EXTRACT MEASUREMENTS

                    Vabc_S = simOut.get('Vabc_S');
                    Iabc_S = simOut.get('Iabc_S');
                    Vabc_R = simOut.get('Vabc_R');
                    Iabc_R = simOut.get('Iabc_R');

                    signals = {Vabc_S, Iabc_S, Vabc_R, Iabc_R};

                    signalNames = {'Vabc_S', 'Iabc_S', ...
                        'Vabc_R', 'Iabc_R'};

                    for s = 1:numel(signals)

                        if isempty(signals{s})
                            error('Missing signal: %s', signalNames{s});
                        end

                        if ~isa(signals{s}, 'timeseries')
                            error(['Signal %s is not a timeseries. ' ...
                                'Check the To Workspace block format.'], ...
                                signalNames{s});
                        end

                        signalData = signals{s}.Data;

                        if any(~isfinite(signalData(:)))
                            error('Signal %s contains NaN or Inf.', ...
                                signalNames{s});
                        end

                    end

                    %% 9.7 SAVE SCENARIO DATA

                    faultTypeSaved = faultType;
                    faultResistanceSaved = resistance;
                    faultStartSaved = faultStart;
                    faultEndSaved = faultEnd;
                    faultLocationSaved = locationKm;

                    outputFile = fullfile(outputFolder, ...
                        ['Fault_' scenarioID '.mat']);

                    save(outputFile, ...
                        'Vabc_S', 'Iabc_S', ...
                        'Vabc_R', 'Iabc_R', ...
                        'faultTypeSaved', ...
                        'faultResistanceSaved', ...
                        'faultStartSaved', ...
                        'faultEndSaved', ...
                        'faultLocationSaved', ...
                        'scenarioID', ...
                        '-v7.3');

                    %% 9.8 RECORD SUCCESS

                    results.ScenarioID(scenarioCounter) = string(scenarioID);
                    results.FaultType(scenarioCounter) = string(faultType);
                    results.FaultResistance_Ohm(scenarioCounter) = resistance;
                    results.FaultInception_s(scenarioCounter) = faultStart;
                    results.FaultLocation_km(scenarioCounter) = locationKm;
                    results.Status(scenarioCounter) = "SUCCESS";

                    fprintf('Saved: %s\n', outputFile);

                catch ME

                    results.ScenarioID(scenarioCounter) = string(scenarioID);
                    results.FaultType(scenarioCounter) = string(faultType);
                    results.FaultResistance_Ohm(scenarioCounter) = resistance;
                    results.FaultInception_s(scenarioCounter) = faultStart;
                    results.FaultLocation_km(scenarioCounter) = locationKm;
                    results.Status(scenarioCounter) = "FAILED";

                    warning('Scenario failed: %s\n%s', ...
                        scenarioID, ME.message);

                end

            end
        end
    end
end

%% 10. SAVE EXPERIMENT SUMMARY

summaryFile = fullfile(outputFolder, ...
    'MultiScenario_Simulation_Summary.csv');

writetable(results, summaryFile);

successfulRuns = sum(results.Status == "SUCCESS");
failedRuns = sum(results.Status == "FAILED");

fprintf('\n========================================\n');
fprintf(' MULTI-SCENARIO GENERATION COMPLETED\n');
fprintf('========================================\n');

fprintf('Total scenarios: %d\n', totalScenarios);
fprintf('Successful runs: %d\n', successfulRuns);
fprintf('Failed runs: %d\n', failedRuns);

fprintf('\nOutput folder:\n%s\n', outputFolder);

fprintf('\nSummary file:\n%s\n', summaryFile);

%% 11. RESTORE ORIGINAL MODEL PARAMETERS

% The onCleanup object also performs this restoration automatically.
restoreOriginalModel(line1, line2, faultBlock, original);

fprintf('\nOriginal model parameters restored.\n');
fprintf('The original model structure has not been rebuilt.\n');

%% LOCAL FUNCTION: RESTORE ORIGINAL PARAMETERS

function restoreOriginalModel(line1, line2, faultBlock, original)

    try
        set_param(line1, 'Length', original.line1Length);
        set_param(line2, 'Length', original.line2Length);

        parameterNames = fieldnames(original.fault);

        for k = 1:numel(parameterNames)
            parameterName = parameterNames{k};

            set_param(faultBlock, parameterName, ...
                original.fault.(parameterName));
        end

    catch ME
        warning('Could not restore all original parameters: %s', ...
            ME.message);
    end

end
