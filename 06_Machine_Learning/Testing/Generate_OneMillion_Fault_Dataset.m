
%% GENERATE ONE MILLION TRANSMISSION-LINE FAULT DATA WINDOWS
% Classes:
% 1. Normal
% 2. LG
% 3. LL
% 4. LLG
% 5. Three-phase fault (LLL)
%
% Dataset target: 1,000,000 UNIQUE feature windows
% Window duration: 20 ms
% Hop duration: 5 ms (75% overlap)
%
% IMPORTANT:
% This script does not duplicate existing feature rows to reach the target.

clear;
clc;

rng('shuffle');

%% PROJECT PATHS

projectDir = 'D:\MATLAB_Projects\TL_Fault_AI';

modelFile = fullfile(projectDir, ...
    '03_Simulink_Models', ...
    'Transmission_Line_132kV_Phase1.slx');

outputDir = fullfile(projectDir, ...
    '05_Feature_Extraction', ...
    'OneMillion_Dataset');

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

if ~isfile(modelFile)
    error('Simulink model not found: %s', modelFile);
end

%% DATASET CONFIGURATION

targetTotal = 1000000;
numberOfClasses = 5;

targetPerClass = targetTotal / numberOfClasses;

classNames = { ...
    'Normal', ...
    'LG', ...
    'LL', ...
    'LLG', ...
    'Three_Phase_Fault'};

%% SIMULATION CONFIGURATION

StopTime = 0.4;

FaultStartTime = 0.1;
FaultEndTime = 0.2;

WindowDuration = 0.020;
HopDuration = 0.005;

% Expected model sampling frequency
Fs = 50000;

WindowSamples = round(WindowDuration * Fs);
HopSamples = round(HopDuration * Fs);

if WindowSamples ~= 1000 || HopSamples ~= 250
    error('Unexpected window or hop sample count.');
end

%% SIGNAL CONFIGURATION

signalNames = { ...
    'Vabc_S', ...
    'Iabc_S', ...
    'Vabc_R', ...
    'Iabc_R'};

%% FEATURE CONFIGURATION

statNames = { ...
    'RMS', ...
    'MeanAbs', ...
    'Std', ...
    'PeakAbs', ...
    'PeakToPeak'};

numberOfFeatures = 4 * 3 * 5;

%% GENERATION COUNTERS

classCounts = zeros(numberOfClasses, 1);

simulationCounter = 0;
uniqueWindowCounter = 0;
duplicateWindowCounter = 0;

%% RANDOMIZATION SEED

generationSeed = randi(2^31 - 1);
rng(generationSeed, 'twister');

%% SAVE INITIAL CONFIGURATION

save(fullfile(outputDir, 'Generation_Configuration.mat'), ...
    'projectDir', 'modelFile', 'targetTotal', ...
    'targetPerClass', 'classNames', ...
    'StopTime', 'FaultStartTime', 'FaultEndTime', ...
    'WindowDuration', 'HopDuration', 'Fs', ...
    'WindowSamples', 'HopSamples', ...
    'signalNames', 'statNames', ...
    'generationSeed');

%% LOAD SIMULINK MODEL

[~, modelName] = fileparts(modelFile);

load_system(modelFile);

fprintf('\n============================================\n');
fprintf(' ONE MILLION DATASET GENERATOR\n');
fprintf('============================================\n');

fprintf('Model: %s\n', modelName);
fprintf('Target windows: %d\n', targetTotal);
fprintf('Target per class: %d\n', targetPerClass);
fprintf('Features per window: %d\n', numberOfFeatures);
fprintf('Sampling frequency: %d Hz\n', Fs);
fprintf('Window duration: %.3f seconds\n', WindowDuration);
fprintf('Hop duration: %.3f seconds\n', HopDuration);

fprintf('\nOutput directory:\n%s\n', outputDir);

fprintf('\nModel loaded successfully.\n');

%% CHUNK 2 — COMPACT MODEL INSPECTION

reportFile = fullfile(outputDir, 'Model_Inspection.txt');
fid = fopen(reportFile, 'w');

if fid == -1
    error('Cannot create model inspection report.');
end

%% FIND FAULT BLOCKS

faultBlocks = find_system(modelName, ...
    'LookUnderMasks', 'all', ...
    'FollowLinks', 'on', ...
    'Type', 'Block');

faultBlocks = faultBlocks(contains(lower(faultBlocks), 'fault'));

fprintf(fid, 'FAULT BLOCKS:\n');

for k = 1:numel(faultBlocks)
    fprintf(fid, '%d. %s\n', k, faultBlocks{k});

    try
        params = get_param(faultBlocks{k}, 'DialogParameters');
        names = fieldnames(params);

        fprintf(fid, 'Parameters: %s\n', strjoin(names, ', '));

        for j = 1:numel(names)
            try
                value = get_param(faultBlocks{k}, names{j});
                fprintf(fid, '  %s = %s\n', ...
                    names{j}, string(value));
            catch
            end
        end
    catch
    end
end

%% FIND LOGGED SIGNALS

toWorkspaceBlocks = find_system(modelName, ...
    'LookUnderMasks', 'all', ...
    'FollowLinks', 'on', ...
    'BlockType', 'ToWorkspace');

fprintf(fid, '\nTO WORKSPACE SIGNALS:\n');

for k = 1:numel(toWorkspaceBlocks)
    try
        variableName = get_param(toWorkspaceBlocks{k}, 'VariableName');
        fprintf(fid, '%s\n', variableName);
    catch
    end
end

%% SOLVER SETTINGS

fprintf(fid, '\nSOLVER SETTINGS:\n');

settings = {'SolverType','Solver','FixedStep','MaxStep','StopTime'};

for k = 1:numel(settings)
    try
        fprintf(fid, '%s = %s\n', settings{k}, ...
            get_param(modelName, settings{k}));
    catch
    end
end

fclose(fid);

%% SHORT COMMAND WINDOW OUTPUT

fprintf('\nMODEL INSPECTION COMPLETED.\n');
fprintf('Fault blocks found: %d\n', numel(faultBlocks));
fprintf('To Workspace blocks found: %d\n', numel(toWorkspaceBlocks));
fprintf('Detailed report saved:\n%s\n', reportFile);

for k = 1:numel(faultBlocks)
    fprintf('Fault block %d: %s\n', k, faultBlocks{k});
end

fprintf('\nOpen Model_Inspection.txt and paste its contents here.\n');
%% CHUNK 3 — VERIFY FAULT CONTROL AND SIGNAL LOGGING

faultBlock = [modelName '/Three-Phase Fault'];

requiredParams = {'FaultA','FaultB','FaultC', ...
    'GroundFault','SwitchTimes','FaultResistance', ...
    'GroundResistance'};

for k = 1:numel(requiredParams)
    value = get_param(faultBlock, requiredParams{k});
    fprintf('%s = %s\n', requiredParams{k}, string(value));
end

signalBlocks = {'Vabc_S','Iabc_S','Vabc_R','Iabc_R'};

for k = 1:numel(signalBlocks)
    blockPath = [modelName '/To Workspace ' signalBlocks{k}];

    if getSimulinkBlockHandle(blockPath) == -1
        error('Missing signal block: %s', blockPath);
    end

    variableName = get_param(blockPath,'VariableName');

    if ~strcmp(variableName,signalBlocks{k})
        error('Unexpected variable name in %s',blockPath);
    end
end

fprintf('\nCHUNK 3 COMPLETED: Fault controls and four signals verified.\n');
%% CHUNK 4 — RANDOMIZED SCENARIO CONFIGURATION

% Fault block
faultBlock = [modelName '/Three-Phase Fault'];

% Five fault classes:
% Normal, LG, LL, LLG, Three-phase (LLL)
faultPatterns = [
    0 0 0 0
    1 0 0 1
    0 1 1 0
    0 1 1 1
    1 1 1 0
];

% Randomization ranges
faultResistanceRange = [0.01 20];   % Ohms
groundResistanceRange = [0.01 20];  % Ohms
faultStartRange = [0.08 0.15];      % Seconds
faultDurationRange = [0.06 0.12];  % Seconds

% Scenario tracking
simulationID = 0;
acceptedWindows = zeros(numberOfClasses,1);

% Dataset storage
featureData = zeros(targetTotal,numberOfFeatures,'single');
classLabels = zeros(targetTotal,1,'uint8');
scenarioIDs = zeros(targetTotal,1,'uint32');

% Randomized scenario generator
generateScenario = @(classIndex) struct( ...
    'FaultA', faultPatterns(classIndex,1), ...
    'FaultB', faultPatterns(classIndex,2), ...
    'FaultC', faultPatterns(classIndex,3), ...
    'GroundFault', faultPatterns(classIndex,4), ...
    'FaultResistance', faultResistanceRange(1) + ...
        rand()*diff(faultResistanceRange), ...
    'GroundResistance', groundResistanceRange(1) + ...
        rand()*diff(groundResistanceRange), ...
    'FaultStart', faultStartRange(1) + ...
        rand()*diff(faultStartRange), ...
    'FaultDuration', faultDurationRange(1) + ...
        rand()*diff(faultDurationRange));

fprintf('\nCHUNK 4 COMPLETED.\n');
fprintf('Five fault classes configured.\n');
fprintf('Randomized fault parameters configured.\n');
fprintf('Dataset storage initialized.\n');
%% CHUNK 5 — FEATURE EXTRACTION FUNCTION

function features = extractWindowFeatures(Vs, Is, Vr, Ir)

    signals = {Vs, Is, Vr, Ir};
    features = zeros(1,60);

    col = 1;

    for s = 1:4
        data = double(signals{s});

        % Require three-phase data
        if size(data,2) ~= 3
            if size(data,1) == 3
                data = data.';
            else
                error('Expected three-phase signal data.');
            end
        end

        for phase = 1:3
            x = data(:,phase);

            stats = [
                sqrt(mean(x.^2))
                mean(abs(x))
                std(x)
                max(abs(x))
                max(x)-min(x)
            ];

            features(col:col+4) = stats.';
            col = col + 5;
        end
    end
end
%% CHUNK 6 — READ SOURCE AND LOAD PARAMETERS

sourceBlock = [modelName '/Three-Phase Source'];
loadBlock   = [modelName '/Three-Phase Load'];

sourceParams = {'Voltage','PhaseAngle','Frequency', ...
                'Resistance','Inductance'};

loadParams = {'NominalVoltage','NominalFrequency', ...
              'ActivePower','InductivePower', ...
              'CapacitivePower'};

fprintf('\nSOURCE PARAMETERS:\n');

for k = 1:numel(sourceParams)
    try
        fprintf('%s = %s\n', sourceParams{k}, ...
            string(get_param(sourceBlock,sourceParams{k})));
    catch
        fprintf('%s = unavailable\n',sourceParams{k});
    end
end

fprintf('\nLOAD PARAMETERS:\n');

for k = 1:numel(loadParams)
    try
        fprintf('%s = %s\n', loadParams{k}, ...
            string(get_param(loadBlock,loadParams{k})));
    catch
        fprintf('%s = unavailable\n',loadParams{k});
    end
end

fprintf('\nCHUNK 6 COMPLETED.\n');
%% CHUNK 7 — ONE MILLION WINDOW SIMULATION

checkpointFile = fullfile(outputDir,'Dataset_Checkpoint.mat');
logFile = fullfile(outputDir,'Generation_Log.txt');

logID = fopen(logFile,'w');

if logID == -1
    error('Cannot create generation log.');
end

% Parameter ranges
voltageRange = [0.95 1.05] * 132000;
powerRange = [40e6 60e6];
pfRange = [0.90 0.99];

switchText = {'off','on'};

% Start generation
for classIndex = 1:numberOfClasses

    fprintf('\nGenerating class: %s\n',classNames{classIndex});

    while acceptedWindows(classIndex) < targetPerClass

        simulationID = simulationID + 1;

        % Random operating conditions
        sourceVoltage = voltageRange(1) + ...
            rand()*diff(voltageRange);

        activePower = powerRange(1) + ...
            rand()*diff(powerRange);

        powerFactor = pfRange(1) + rand()*diff(pfRange);

        inductivePower = activePower * ...
            tan(acos(powerFactor));

        % Random fault scenario
        scenario = generateScenario(classIndex);

        faultEnd = scenario.FaultStart + ...
            scenario.FaultDuration;

        % Convert fault switches to on/off
        pattern = faultPatterns(classIndex,:);

        % Create simulation input
        simIn = Simulink.SimulationInput(modelName);

        simIn = simIn.setBlockParameter(sourceBlock, ...
            'Voltage',num2str(sourceVoltage,15));

        simIn = setBlockParameter(simIn, loadBlock, ...
    'ActivePower', num2str(activePower,15), ...
    'InductivePower', num2str(inductivePower,15));

        simIn = simIn.setBlockParameter(faultBlock, ...
            'FaultA',switchText{pattern(1)+1}, ...
            'FaultB',switchText{pattern(2)+1}, ...
            'FaultC',switchText{pattern(3)+1}, ...
            'GroundFault',switchText{pattern(4)+1}, ...
            'SwitchTimes',sprintf('[%.9f %.9f]', ...
                scenario.FaultStart,faultEnd), ...
            'FaultResistance',num2str(scenario.FaultResistance,15), ...
            'GroundResistance',num2str(scenario.GroundResistance,15));

        simIn = simIn.setModelParameter('StopTime', ...
            num2str(StopTime));

        % Run simulation
        try
            simOut = sim(simIn);

            Vs = simOut.get('Vabc_S');
            Is = simOut.get('Iabc_S');
            Vr = simOut.get('Vabc_R');
            Ir = simOut.get('Iabc_R');

            % Convert timeseries data
            time = Vs.Time(:);

            dataSignals = {Vs.Data,Is.Data,Vr.Data,Ir.Data};

            for s = 1:4
                dataSignals{s} = double(squeeze(dataSignals{s}));

                if size(dataSignals{s},2) ~= 3 && ...
                        size(dataSignals{s},1) == 3
                    dataSignals{s} = dataSignals{s}.';
                end

                if size(dataSignals{s},1) ~= numel(time) || ...
                        size(dataSignals{s},2) ~= 3
                    error('Invalid signal dimensions.');
                end
            end

            % Find valid windows
            starts = 1:HopSamples:(numel(time)-WindowSamples+1);

            for w = starts

                windowStart = time(w);

                % Normal: all valid windows
                % Fault classes: windows fully inside fault interval
                if classIndex > 1 && ...
                        (windowStart < scenario.FaultStart || ...
                        windowStart + WindowDuration > faultEnd)
                    continue;
                end

                if acceptedWindows(classIndex) >= targetPerClass
                    break;
                end

                indices = w:(w+WindowSamples-1);

                rowFeatures = extractWindowFeatures( ...
                    dataSignals{1}(indices,:), ...
                    dataSignals{2}(indices,:), ...
                    dataSignals{3}(indices,:), ...
                    dataSignals{4}(indices,:));

                if any(~isfinite(rowFeatures))
                    continue;
                end

                row = sum(acceptedWindows) + 1;

                featureData(row,:) = single(rowFeatures);
                classLabels(row) = uint8(classIndex);
                scenarioIDs(row) = uint32(simulationID);

                acceptedWindows(classIndex) = ...
                    acceptedWindows(classIndex) + 1;
            end

        catch ME
            fprintf(logID,'Simulation %d failed: %s\n', ...
                simulationID,ME.message);
        end

        % Save checkpoint every 100 simulations
        if mod(simulationID,100) == 0
            save(checkpointFile, ...
                'featureData','classLabels','scenarioIDs', ...
                'acceptedWindows','simulationID','-v7.3');

            fprintf('Simulations: %d | Windows: %d / %d\n', ...
                simulationID,sum(acceptedWindows),targetTotal);
        end
    end
end

% Final checkpoint
save(checkpointFile, ...
    'featureData','classLabels','scenarioIDs', ...
    'acceptedWindows','simulationID','-v7.3');

fprintf(logID,'Generation finished. Simulations: %d\n',simulationID);
fprintf(logID,'Accepted windows: %d\n',sum(acceptedWindows));

fclose(logID);

fprintf('\nCHUNK 7 COMPLETED.\n');
%% CHUNK 8 — DATASET VALIDATION

clear; clc;

projectDir = 'D:\MATLAB_Projects\TL_Fault_AI';
outputDir = fullfile(projectDir, ...
    '05_Feature_Extraction','OneMillion_Dataset');

checkpointFile = fullfile(outputDir,'Dataset_Checkpoint.mat');

load(checkpointFile, ...
    'featureData','classLabels','scenarioIDs', ...
    'acceptedWindows','simulationID');

classNames = {'Normal','LG','LL','LLG','Three_Phase_Fault'};

fprintf('\nDATASET VALIDATION\n');

% Basic dimensions
[nRows,nFeatures] = size(featureData);

fprintf('Rows: %d\n',nRows);
fprintf('Features: %d\n',nFeatures);
fprintf('Simulations: %d\n',simulationID);

assert(nRows == 1000000, ...
    'Dataset does not contain exactly one million rows.');

assert(nFeatures == 60, ...
    'Dataset does not contain exactly 60 features.');

assert(all(isfinite(featureData(:))), ...
    'Dataset contains NaN or Inf values.');

% Class distribution
classCounts = zeros(5,1);

for k = 1:5
    classCounts(k) = sum(classLabels == k);
    fprintf('%s: %d windows\n',classNames{k},classCounts(k));
end

assert(all(classCounts == 200000), ...
    'Dataset classes are not balanced.');

% Exact duplicate audit
fprintf('\nChecking duplicate feature rows...\n');

[~,uniqueIndices] = unique(featureData,'rows');
duplicateCount = nRows - numel(uniqueIndices);

fprintf('Duplicate rows: %d\n',duplicateCount);

assert(duplicateCount == 0, ...
    'Duplicate feature rows detected. Dataset rejected.');

% Save validated dataset
validatedFile = fullfile(outputDir, ...
    'OneMillion_Validated_Dataset.mat');

save(validatedFile, ...
    'featureData','classLabels','scenarioIDs', ...
    'classCounts','simulationID','-v7.3');

fprintf('\nVALIDATION PASSED.\n');
fprintf('Saved: %s\n',validatedFile);