
%% GENERATE MULTIPLE NORMAL-OPERATION DATASETS
clear;
clc;

%% 1. PROJECT AND OUTPUT FOLDERS

scriptFolder = fileparts(mfilename('fullpath'));

if isempty(scriptFolder)
    scriptFolder = pwd;
end

[~, folderName] = fileparts(scriptFolder);

if strcmpi(folderName, '04_Data_Generation')
    projectRoot = fileparts(scriptFolder);
else
    projectRoot = scriptFolder;
    scriptFolder = fullfile(projectRoot, '04_Data_Generation');
end

outputFolder = fullfile(scriptFolder, ...
    'Normal_MultiScenario_Data');

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

fprintf('Project root: %s\n', projectRoot);
fprintf('Output folder: %s\n', outputFolder);

%% 2. LOCATE AND LOAD MODEL

modelName = 'Transmission_Line_132kV_Phase1';

if bdIsLoaded(modelName)

    modelFile = get_param(modelName, 'FileName');

    if isempty(modelFile)
        error('Loaded model has no saved file path.');
    end

else

    modelFiles = dir(fullfile(projectRoot, '**', ...
        'Transmission_Line_132kV_Phase1.slx'));

    if isempty(modelFiles)
        error('Transmission line model not found.');
    end

    if numel(modelFiles) > 1
        error(['Multiple model files found. Load the intended ' ...
            'model in Simulink before running this script.']);
    end

    modelFile = fullfile(modelFiles(1).folder, ...
        modelFiles(1).name);

    load_system(modelFile);
end

fprintf('Using model: %s\n', modelFile);

%% 3. FIND THREE-PHASE PARALLEL RLC LOAD

allBlocks = find_system(modelName, ...
    'LookUnderMasks', 'all', ...
    'FollowLinks', 'on', ...
    'Type', 'Block');

loadCandidates = {};

for k = 1:numel(allBlocks)

    try
        maskType = get_param(allBlocks{k}, 'MaskType');
        params = get_param(allBlocks{k}, 'DialogParameters');

        if strcmpi(maskType, 'Three-Phase Parallel RLC Load') && ...
                isfield(params, 'ActivePower') && ...
                isfield(params, 'InductivePower')

            loadCandidates{end+1} = allBlocks{k};

        end
    catch
    end
end

if isempty(loadCandidates)
    error('Three-Phase Parallel RLC Load not found.');
end

if numel(loadCandidates) > 1
    error('Multiple compatible load blocks found.');
end

loadBlock = loadCandidates{1};

fprintf('Load block: %s\n', loadBlock);

%% 4. FIND THREE-PHASE FAULT BLOCK

faultBlocks = find_system(modelName, ...
    'LookUnderMasks', 'all', ...
    'FollowLinks', 'on', ...
    'MaskType', 'Three-Phase Fault');

if isempty(faultBlocks)
    error('Three-Phase Fault block not found.');
end

if numel(faultBlocks) > 1
    error('Multiple Three-Phase Fault blocks found.');
end

faultBlock = faultBlocks{1};

fprintf('Fault block: %s\n', faultBlock);

%% 5. SAVE ORIGINAL PARAMETERS

originalP = get_param(loadBlock, 'ActivePower');
originalQ = get_param(loadBlock, 'InductivePower');

faultParameters = { ...
    'FaultA', 'FaultB', 'FaultC', 'GroundFault'};

for k = 1:numel(faultParameters)

    parameterName = faultParameters{k};

    originalFault.(parameterName) = ...
        get_param(faultBlock, parameterName);

end

% Automatic restoration if an error occurs.
cleanupObject = onCleanup(@() restoreParameters( ...
    loadBlock, faultBlock, originalP, originalQ, ...
    originalFault, faultParameters));

%% 6. DISABLE FAULT FOR NORMAL OPERATION

set_param(faultBlock, ...
    'FaultA', 'off', ...
    'FaultB', 'off', ...
    'FaultC', 'off', ...
    'GroundFault', 'off');

fprintf('Fault successfully disabled.\n');

%% 7. DEFINE OPERATING CONDITIONS

loadLevels_MW = [40 45 50 55 60];
powerFactor = 0.95;

totalRuns = numel(loadLevels_MW);

results = table( ...
    zeros(totalRuns,1), ...
    zeros(totalRuns,1), ...
    zeros(totalRuns,1), ...
    strings(totalRuns,1), ...
    strings(totalRuns,1), ...
    'VariableNames', ...
    {'Load_MW','ReactivePower_MVAr', ...
     'PowerFactor','Status','Message'});

%% 8. RUN SIMULATIONS

for k = 1:totalRuns

    P_MW = loadLevels_MW(k);
    P_W = P_MW * 1e6;

    Q_var = P_W * tan(acos(powerFactor));
    Q_MVAr = Q_var / 1e6;

    scenarioID = sprintf('Normal_%02dMW', P_MW);

    fprintf('\n================================\n');
    fprintf('Scenario %d/%d: %s\n', ...
        k, totalRuns, scenarioID);
    fprintf('P = %.2f MW\n', P_MW);
    fprintf('Q = %.3f MVAr\n', Q_MVAr);
    fprintf('PF = %.2f lagging\n', powerFactor);
    fprintf('================================\n');

    try

        % Correct parameters for this load block:
        % ActivePower and InductivePower

        set_param(loadBlock, ...
            'ActivePower', num2str(P_W,16), ...
            'InductivePower', num2str(Q_var,16));

        simOut = sim(modelName, ...
            'StopTime', '0.40', ...
            'ReturnWorkspaceOutputs', 'on');

        %% Retrieve measurements

        Vabc_S = simOut.get('Vabc_S');
        Iabc_S = simOut.get('Iabc_S');
        Vabc_R = simOut.get('Vabc_R');
        Iabc_R = simOut.get('Iabc_R');

        signals = {Vabc_S,Iabc_S,Vabc_R,Iabc_R};

        signalNames = { ...
            'Vabc_S','Iabc_S','Vabc_R','Iabc_R'};

        %% Validate measurements

        for s = 1:4

            if isempty(signals{s})
                error('%s is missing.', signalNames{s});
            end

            if ~isa(signals{s}, 'timeseries')
                error('%s is not a timeseries.', ...
                    signalNames{s});
            end

            if isempty(signals{s}.Data) || ...
                    any(~isfinite(signals{s}.Data(:)))

                error('%s contains invalid data.', ...
                    signalNames{s});

            end
        end

        %% Save scenario

        loadPowerSaved = P_MW;
        reactivePowerSaved = Q_var;
        reactivePowerMVArSaved = Q_MVAr;
        powerFactorSaved = powerFactor;
        operatingConditionSaved = 'Normal';

        outputFile = fullfile(outputFolder, ...
            [scenarioID '.mat']);

        save(outputFile, ...
            'Vabc_S','Iabc_S','Vabc_R','Iabc_R', ...
            'scenarioID','loadPowerSaved', ...
            'reactivePowerSaved', ...
            'reactivePowerMVArSaved', ...
            'powerFactorSaved', ...
            'operatingConditionSaved', ...
            '-v7.3');

        results.Load_MW(k) = P_MW;
        results.ReactivePower_MVAr(k) = Q_MVAr;
        results.PowerFactor(k) = powerFactor;
        results.Status(k) = "SUCCESS";
        results.Message(k) = "Saved";

        fprintf('SUCCESS: %s\n', outputFile);

    catch ME

        results.Load_MW(k) = P_MW;
        results.ReactivePower_MVAr(k) = Q_MVAr;
        results.PowerFactor(k) = powerFactor;
        results.Status(k) = "FAILED";
        results.Message(k) = string(ME.message);

        warning('Scenario failed: %s', ME.message);

    end
end


%% 9. SAVE SUMMARY

summaryFile = fullfile(outputFolder, ...
    'Normal_Simulation_Summary.csv');

writetable(results, summaryFile);

successfulRuns = sum(results.Status == "SUCCESS");
failedRuns = sum(results.Status == "FAILED");

fprintf('\n========================================\n');
fprintf(' NORMAL DATA GENERATION SUMMARY\n');
fprintf('========================================\n');

fprintf('Successful: %d/%d\n', ...
    successfulRuns, totalRuns);

fprintf('Failed: %d/%d\n', ...
    failedRuns, totalRuns);

fprintf('Summary: %s\n', summaryFile);
fprintf('Dataset folder: %s\n', outputFolder);

disp(results);

%% 10. RESTORE ORIGINAL MODEL PARAMETERS

clear cleanupObject;

fprintf('\nOriginal model parameters restored.\n');
fprintf('Dataset generation completed.\n');

%% LOCAL RESTORATION FUNCTION

function restoreParameters(loadBlock, faultBlock, ...
    originalP, originalQ, originalFault, faultParameters)

    try

        set_param(loadBlock, ...
            'ActivePower', originalP, ...
            'InductivePower', originalQ);

        for j = 1:numel(faultParameters)

            parameterName = faultParameters{j};

            set_param(faultBlock, parameterName, ...
                originalFault.(parameterName));

        end

        fprintf('\nOriginal load and fault settings restored.\n');

    catch ME

        warning('Restoration issue: %s', ME.message);

    end
end
