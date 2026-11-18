
%% MULTI-SCENARIO FEATURE EXTRACTION
% Project: AI-Based Transmission Line Fault Detection
%
% Source datasets:
%   135 fault simulations
%   5 normal simulations
%
% Feature settings:
%   60 features per window
%   20 ms window
%   5 ms step
%
% Classes:
%   Normal, LG, LL, LLG, LLL, LLLG
%
% Scenario IDs are retained for leakage-free splitting.
% NO SIMULINK SIMULATIONS ARE RUN BY THIS SCRIPT.

clear;
clc;

fprintf('\n============================================\n');
fprintf(' MULTI-SCENARIO FEATURE EXTRACTION\n');
fprintf('============================================\n');

%% 1. PATH CONFIGURATION

% This script is stored inside 04_Data_Generation.
scriptFolder = fileparts(mfilename('fullpath'));
projectRoot = fileparts(scriptFolder);

faultFolder = fullfile(scriptFolder, ...
    'MultiScenario_Fault_Data');

normalFolder = fullfile(scriptFolder, ...
    'Normal_MultiScenario_Data');

outputFolder = fullfile(projectRoot, ...
    '05_Feature_Extraction');

% Validate folders.

if ~isfolder(faultFolder)
    error('Fault dataset folder not found:\n%s', faultFolder);
end

if ~isfolder(normalFolder)
    error('Normal dataset folder not found:\n%s', normalFolder);
end

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

fprintf('\nProject root:\n%s\n', projectRoot);

%% 2. FIND SOURCE FILES EXPLICITLY

faultFiles = dir(fullfile(faultFolder, 'Fault_*.mat'));

normalFiles = dir(fullfile(normalFolder, 'Normal_*.mat'));

fprintf('\nSource datasets found:\n');
fprintf('Fault files : %d\n', numel(faultFiles));
fprintf('Normal files: %d\n', numel(normalFiles));

% Expected number of simulations.

if numel(faultFiles) ~= 135
    error('Expected 135 fault files, but found %d.', ...
        numel(faultFiles));
end

if numel(normalFiles) ~= 5
    error('Expected 5 normal files, but found %d.', ...
        numel(normalFiles));
end

fprintf('\nAll 140 source files identified successfully.\n');

%% 3. FEATURE EXTRACTION SETTINGS

windowDuration = 0.020;
stepDuration = 0.005;

signalNames = {'Vabc_S','Iabc_S','Vabc_R','Iabc_R'};

phaseNames = {'A','B','C'};

statNames = {'RMS','MeanAbs','Std','PeakAbs','PeakToPeak'};

% Generate 60 feature names.

featureNames = cell(1,60);

featureIndex = 0;

for s = 1:numel(signalNames)

    for p = 1:numel(phaseNames)

        for m = 1:numel(statNames)

            featureIndex = featureIndex + 1;

            featureNames{featureIndex} = sprintf( ...
                '%s_%s_%s', ...
                signalNames{s}, ...
                phaseNames{p}, ...
                statNames{m});

        end

    end

end

fprintf('\nFeatures per window: %d\n', numel(featureNames));

%% 4. INITIALIZE DATASET VARIABLES

X = zeros(0,60);

Y = strings(0,1);

scenarioGroups = strings(0,1);

scenarioIDs = strings(0,1);

faultResistance = zeros(0,1);

faultInception = zeros(0,1);

faultLocation = zeros(0,1);

%% 5. PROCESS ALL FIVE NORMAL SIMULATIONS

fprintf('\n============================================\n');
fprintf(' PROCESSING NORMAL SIMULATIONS\n');
fprintf('============================================\n');

normalStart = 0.20;
normalEnd = 0.40;

for k = 1:numel(normalFiles)

    filePath = fullfile( ...
        normalFiles(k).folder, ...
        normalFiles(k).name);

    fprintf('\nNormal file %d/%d: %s\n', ...
        k, numel(normalFiles), normalFiles(k).name);

    N = load(filePath);

    % Validate required measurement signals.

    for s = 1:numel(signalNames)

        if ~isfield(N, signalNames{s})

            error('Missing signal %s in %s.', ...
                signalNames{s}, normalFiles(k).name);

        end

    end

    % Use saved scenario ID when available.
    % Otherwise use the filename without extension.

    if isfield(N,'scenarioID')

        normalID = string(N.scenarioID);

    else

        [~,normalID,~] = fileparts(normalFiles(k).name);
        normalID = string(normalID);

    end

    if numel(normalID) ~= 1 || ismissing(normalID)
        error('Invalid normal scenario ID in %s.', ...
            normalFiles(k).name);
    end

    % Extract normal steady-state features.

    [X,Y,scenarioGroups,scenarioIDs, ...
     faultResistance,faultInception,faultLocation] = ...
        appendWindows( ...
        X,Y,scenarioGroups,scenarioIDs, ...
        faultResistance,faultInception,faultLocation, ...
        N,signalNames,featureNames, ...
        normalStart,normalEnd, ...
        windowDuration,stepDuration, ...
        "Normal",normalID,NaN,NaN,NaN);

end

fprintf('\nAll five normal simulations processed.\n');

%% 6. PROCESS ALL 135 FAULT SIMULATIONS

fprintf('\n============================================\n');
fprintf(' PROCESSING FAULT SIMULATIONS\n');
fprintf('============================================\n');

for k = 1:numel(faultFiles)

    filePath = fullfile( ...
        faultFiles(k).folder, ...
        faultFiles(k).name);

    S = load(filePath);

    % Validate measurement signals.

    for s = 1:numel(signalNames)

        if ~isfield(S,signalNames{s})

            error('Missing signal %s in %s.', ...
                signalNames{s},faultFiles(k).name);

        end

    end

    % Validate fault metadata.

    metadataNames = { ...
        'faultTypeSaved', ...
        'faultResistanceSaved', ...
        'faultStartSaved', ...
        'faultEndSaved', ...
        'faultLocationSaved', ...
        'scenarioID'};

    for m = 1:numel(metadataNames)

        if ~isfield(S,metadataNames{m})

            error('Missing metadata %s in %s.', ...
                metadataNames{m},faultFiles(k).name);

        end

    end

    % Read metadata.

    faultType = string(S.faultTypeSaved);

    resistance = double(S.faultResistanceSaved);

    startTime = double(S.faultStartSaved);

    endTime = double(S.faultEndSaved);

    location = double(S.faultLocationSaved);

    scenarioID = string(S.scenarioID);

    % Validate metadata values.

    if numel(faultType) ~= 1 || ...
       numel(resistance) ~= 1 || ...
       numel(startTime) ~= 1 || ...
       numel(endTime) ~= 1 || ...
       numel(location) ~= 1 || ...
       numel(scenarioID) ~= 1

        error('Invalid metadata dimensions in %s.', ...
            faultFiles(k).name);

    end

    if ismissing(faultType) || ismissing(scenarioID) || ...
       ~isfinite(resistance) || ...
       ~isfinite(startTime) || ...
       ~isfinite(endTime) || ...
       ~isfinite(location) || ...
       endTime <= startTime

        error('Invalid fault metadata in %s.', ...
            faultFiles(k).name);

    end

    % Extract features only during the fault interval.

    [X,Y,scenarioGroups,scenarioIDs, ...
     faultResistance,faultInception,faultLocation] = ...
        appendWindows( ...
        X,Y,scenarioGroups,scenarioIDs, ...
        faultResistance,faultInception,faultLocation, ...
        S,signalNames,featureNames, ...
        startTime,endTime, ...
        windowDuration,stepDuration, ...
        faultType,scenarioID, ...
        resistance,startTime,location);

    if mod(k,15)==0 || k==numel(faultFiles)

        fprintf('Processed %d/%d fault simulations.\n', ...
            k,numel(faultFiles));

    end

end

fprintf('\nAll fault simulations processed.\n');

%% 7. VALIDATE COMPLETE DATASET

fprintf('\n============================================\n');
fprintf(' DATASET VALIDATION\n');
fprintf('============================================\n');

expectedFeatures = 60;

if size(X,2) ~= expectedFeatures

    error('Expected 60 features, but obtained %d.',size(X,2));

end

if isempty(X)

    error('Feature dataset is empty.');

end

if any(~isfinite(X(:)))

    error('NaN or Inf detected in extracted feature matrix.');

end

if size(X,1) ~= numel(Y) || ...
   size(X,1) ~= numel(scenarioGroups) || ...
   size(X,1) ~= numel(scenarioIDs)

    error('Feature and metadata dimensions do not match.');

end

if size(X,1) ~= numel(faultResistance) || ...
   size(X,1) ~= numel(faultInception) || ...
   size(X,1) ~= numel(faultLocation)

    error('Fault metadata dimensions do not match.');

end

% Expected window counts:
% Normal: 5 x 37 = 185
% Fault : 135 x 17 = 2295

expectedNormalWindows = 185;

expectedFaultWindows = 2295;

expectedTotalWindows = 2480;

actualNormalWindows = sum(Y=="Normal");

actualFaultWindows = sum(Y~="Normal");

fprintf('Total windows extracted : %d\n',size(X,1));

fprintf('Normal windows           : %d\n',actualNormalWindows);

fprintf('Fault windows            : %d\n',actualFaultWindows);

fprintf('Features per window      : %d\n',size(X,2));

if actualNormalWindows ~= expectedNormalWindows

    warning(['Expected %d normal windows, but obtained %d. ' ...
        'Check normal simulation time intervals.'], ...
        expectedNormalWindows,actualNormalWindows);

end

if actualFaultWindows ~= expectedFaultWindows

    warning(['Expected %d fault windows, but obtained %d. ' ...
        'Check fault simulation time intervals.'], ...
        expectedFaultWindows,actualFaultWindows);

end

if size(X,1) ~= expectedTotalWindows

    warning(['Expected %d total windows, but obtained %d.'], ...
        expectedTotalWindows,size(X,1));

end

%% 8. CREATE FEATURE AND METADATA TABLES

featureTable = array2table(X, ...
    'VariableNames',featureNames);

metadataTable = table( ...
    Y, ...
    scenarioGroups, ...
    scenarioIDs, ...
    faultResistance, ...
    faultInception, ...
    faultLocation, ...
    'VariableNames',{ ...
    'Class', ...
    'ScenarioGroup', ...
    'ScenarioID', ...
    'FaultResistance_Ohm', ...
    'FaultInception_s', ...
    'FaultLocation_km'});

datasetTable = [metadataTable featureTable];

%% 9. CLASS DISTRIBUTION

classes = ["Normal","LG","LL","LLG","LLL","LLLG"];

fprintf('\n============================================\n');
fprintf(' CLASS DISTRIBUTION\n');
fprintf('============================================\n');

for k = 1:numel(classes)

    count = sum(Y==classes(k));

    fprintf('%-8s : %d windows\n', ...
        char(classes(k)),count);

end

%% 10. SCENARIO GROUP VALIDATION

uniqueGroups = unique(scenarioGroups);

fprintf('\nUnique scenario groups: %d\n', ...
    numel(uniqueGroups));

% Each simulation must correspond to one scenario group.

for k = 1:numel(uniqueGroups)

    groupMask = scenarioGroups == uniqueGroups(k);

    groupIDs = unique(scenarioIDs(groupMask));

    if numel(groupIDs) ~= 1

        error('Scenario group contains multiple scenario IDs.');

    end

end

fprintf('Scenario group validation passed.\n');

%% 11. SAVE DATASET

matFile = fullfile(outputFolder, ...
    'MultiScenario_Fault_Feature_Dataset.mat');

csvFile = fullfile(outputFolder, ...
    'MultiScenario_Fault_Feature_Dataset.csv');

save(matFile, ...
    'X', ...
    'Y', ...
    'scenarioGroups', ...
    'scenarioIDs', ...
    'faultResistance', ...
    'faultInception', ...
    'faultLocation', ...
    'featureNames', ...
    'datasetTable', ...
    'windowDuration', ...
    'stepDuration', ...
    '-v7.3');

writetable(datasetTable,csvFile);

%% 12. FINAL SUMMARY

fprintf('\n============================================\n');
fprintf(' FEATURE EXTRACTION COMPLETED\n');
fprintf('============================================\n');

fprintf('Fault simulation files : %d\n',numel(faultFiles));

fprintf('Normal simulation files: %d\n',numel(normalFiles));

fprintf('Total simulations      : %d\n', ...
    numel(faultFiles)+numel(normalFiles));

fprintf('Total feature windows  : %d\n',size(X,1));

fprintf('Features per window    : %d\n',size(X,2));

fprintf('Unique scenario groups : %d\n',numel(uniqueGroups));

fprintf('\nSaved MAT dataset:\n%s\n',matFile);

fprintf('\nSaved CSV dataset:\n%s\n',csvFile);

fprintf('\nNo Simulink simulations were performed.\n');

fprintf('\n============================================\n');

%% LOCAL FUNCTION: FEATURE EXTRACTION

function [X,Y,groups,IDs,resistanceValues, ...
    inceptionValues,locationValues] = ...
    appendWindows(X,Y,groups,IDs,resistanceValues, ...
    inceptionValues,locationValues,S,signalNames, ...
    featureNames,startTime,endTime,windowDuration, ...
    stepDuration,classLabel,scenarioID,resistance, ...
    inception,location)

    % Generate window starting times.

    windowStarts = startTime:stepDuration: ...
        (endTime-windowDuration+1e-10);

    if isempty(windowStarts)

        error('No valid windows for scenario %s.', ...
            char(scenarioID));

    end

    for w = 1:numel(windowStarts)

        ws = windowStarts(w);

        we = ws + windowDuration;

        featureVector = zeros(1,numel(featureNames));

        featureIndex = 0;

        for s = 1:numel(signalNames)

            ts = S.(signalNames{s});

            if ~isa(ts,'timeseries')

                error('%s is not a timeseries.', ...
                    signalNames{s});

            end

            time = double(ts.Time(:));

            data = double(squeeze(ts.Data));

            if size(data,2) ~= 3

                error('%s must contain three phase columns.', ...
                    signalNames{s});

            end

            if size(data,1) ~= numel(time)

                error('Time and data dimensions mismatch in %s.', ...
                    signalNames{s});

            end

            indices = time >= ws & time < we;

            if sum(indices) < 2

                error(['Insufficient samples in %s, ' ...
                    'scenario %s, window %.4f s.'], ...
                    signalNames{s},char(scenarioID),ws);

            end

            windowData = data(indices,:);

            if any(~isfinite(windowData(:)))

                error('NaN or Inf found in %s.', ...
                    signalNames{s});

            end

            for p = 1:3

                x = windowData(:,p);

                values = [ ...
                    sqrt(mean(x.^2)), ...
                    mean(abs(x)), ...
                    std(x,0), ...
                    max(abs(x)), ...
                    max(x)-min(x)];

                featureVector(featureIndex+1:featureIndex+5) = ...
                    values;

                featureIndex = featureIndex+5;

            end

        end

        if featureIndex ~= numel(featureNames)

            error('Unexpected number of extracted features.');

        end

        % Append feature vector.

        X(end+1,:) = featureVector;

        % Append class and scenario metadata.

        Y(end+1,1) = string(classLabel);

        groups(end+1,1) = string(scenarioID);

        IDs(end+1,1) = string(scenarioID);

        resistanceValues(end+1,1) = resistance;

        inceptionValues(end+1,1) = inception;

        locationValues(end+1,1) = location;

    end

end
