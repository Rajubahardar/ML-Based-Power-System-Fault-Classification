clc;
clear;
close all;

%% 1. PROJECT FOLDERS

projectFolder = 'D:\MATLAB_Projects\TL_Fault_AI';

normalFolder = fullfile(projectFolder, ...
    '04_Data_Generation', 'Normal_Data');

faultFolder = fullfile(projectFolder, ...
    '04_Data_Generation', 'Fault_Data');

outputFolder = fullfile(projectFolder, ...
    '05_Feature_Extraction');

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

%% 2. INPUT FILES AND CLASS LABELS

fileNames = {
    'Phase1_Normal_Operation_Data.mat'
    'Fault_LG_Data.mat'
    'Fault_LL_Data.mat'
    'Fault_LLG_Data.mat'
    'Fault_LLL_Data.mat'
    'Fault_LLLG_Data.mat'
};

classLabels = {
    'Normal'
    'LG'
    'LL'
    'LLG'
    'LLL'
    'LLLG'
};

inputFolders = {
    normalFolder
    faultFolder
    faultFolder
    faultFolder
    faultFolder
    faultFolder
};

requiredSignals = {'Vabc_S','Iabc_S','Vabc_R','Iabc_R'};

%% 3. WINDOW SETTINGS

windowDuration = 0.020;  % 20 ms = one 50 Hz cycle
windowStep = 0.005;      % 5 ms sliding step

% Normal data: use steady-state interval
normalStart = 0.200;
normalEnd = 0.400;

% Fault data: use fault-on interval
faultStart = 0.100;
faultEnd = 0.200;

%% 4. FEATURE NAMES

featureTypes = {'RMS','MeanAbs','Std','PeakAbs','PeakToPeak'};
phaseNames = {'A','B','C'};

featureNames = {};

for s = 1:numel(requiredSignals)
    for p = 1:numel(phaseNames)
        for f = 1:numel(featureTypes)

            featureNames{end+1} = sprintf('%s_%s_%s', ...
                requiredSignals{s}, ...
                phaseNames{p}, ...
                featureTypes{f});

        end
    end
end

%% 5. INITIALIZE DATASET

allFeatures = [];
allLabels = strings(0,1);
allWindowStarts = [];
allWindowEnds = [];
allSourceFiles = strings(0,1);

fprintf('\nFeature extraction preparation completed.\n');
%% 6. PROCESS ALL SIX DATASETS

fprintf('\n===== STARTING FEATURE EXTRACTION =====\n');

for fileIndex = 1:numel(fileNames)

    inputFile = fullfile(inputFolders{fileIndex}, ...
        fileNames{fileIndex});

    if ~isfile(inputFile)
        error('File not found: %s', inputFile);
    end

    fprintf('\nProcessing: %s\n', classLabels{fileIndex});

    S = load(inputFile);

    signalData = cell(1,4);
    referenceTime = [];

    %% Load four measurement signals

    for k = 1:4

        signalName = requiredSignals{k};

        if ~isfield(S, signalName)
            error('Missing variable %s in %s', ...
                signalName, fileNames{fileIndex});
        end

        ts = S.(signalName);

        if ~isa(ts, 'timeseries')
            error('%s is not a timeseries.', signalName);
        end

        t = double(ts.Time(:));
        values = double(squeeze(ts.Data));

        % Ensure rows represent time samples
        if size(values,1) ~= numel(t) && ...
                size(values,2) == numel(t)
            values = values.';
        end

        if size(values,1) ~= numel(t) || size(values,2) < 3
            error('Incorrect signal dimensions in %s.', signalName);
        end

        values = values(:,1:3);

        if any(~isfinite(values(:))) || any(~isfinite(t))
            error('NaN or Inf found in %s.', signalName);
        end

        if isempty(referenceTime)
            referenceTime = t;
        elseif numel(t) ~= numel(referenceTime) || ...
                any(abs(t-referenceTime) > 1e-9)
            error('Measurement time vectors do not match.');
        end

        signalData{k} = values;

    end

    t = referenceTime;

    %% Select the correct time interval for each class

    if strcmp(classLabels{fileIndex}, 'Normal')
        startTime = normalStart;
        endTime = normalEnd;
    else
        startTime = faultStart;
        endTime = faultEnd;
    end

    windowStarts = startTime:windowStep: ...
        (endTime-windowDuration+1e-10);

    classFeatures = [];
    classStarts = [];

    %% Extract features from each window

    for w = 1:numel(windowStarts)

        tStart = windowStarts(w);
        tStop = tStart + windowDuration;

        tolerance = 1e-10;

        sampleIndices = find( ...
            t >= tStart-tolerance & ...
            t < tStop-tolerance);

        if isempty(sampleIndices)
            continue;
        end

        row = zeros(1, numel(featureNames));
        featureIndex = 0;

        for s = 1:4

            windowData = signalData{s}(sampleIndices,:);

            for p = 1:3

                x = windowData(:,p);

                % Calculate five statistical features
                featureValues = [
                    sqrt(mean(x.^2)), ...
                    mean(abs(x)), ...
                    std(x,0), ...
                    max(abs(x)), ...
                    max(x)-min(x)
                ];

                for f = 1:5
                    featureIndex = featureIndex + 1;
                    row(featureIndex) = featureValues(f);
                end

            end
        end

        classFeatures = [classFeatures; row]; %#ok<AGROW>
        classStarts = [classStarts; tStart]; %#ok<AGROW>

    end

    if isempty(classFeatures)
        error('No features extracted for class %s.', ...
            classLabels{fileIndex});
    end

    %% Add extracted features to the complete dataset

    numberOfWindows = size(classFeatures,1);

    allFeatures = [allFeatures; classFeatures];

    allLabels = [allLabels; ...
        repmat(string(classLabels{fileIndex}), numberOfWindows, 1)];

    allWindowStarts = [allWindowStarts; classStarts];

    allWindowEnds = [allWindowEnds; ...
        classStarts + windowDuration];

    allSourceFiles = [allSourceFiles; ...
        repmat(string(fileNames{fileIndex}), numberOfWindows, 1)];

    fprintf('Extracted windows: %d\n', numberOfWindows);

end

fprintf('\nFeature extraction from all six classes completed.\n');
%% 7. CREATE FINAL FEATURE TABLE

featureTable = array2table(allFeatures, ...
    'VariableNames', featureNames);

featureTable.Label = categorical(allLabels, classLabels);

featureTable.WindowStart_s = allWindowStarts;
featureTable.WindowEnd_s = allWindowEnds;

featureTable.SourceFile = allSourceFiles;

% Separate machine-learning inputs and target labels
X = allFeatures;
Y = categorical(allLabels, classLabels);

%% 8. SAVE DATASET

matFile = fullfile(outputFolder, ...
    'Transmission_Line_Fault_Feature_Dataset.mat');

csvFile = fullfile(outputFolder, ...
    'Transmission_Line_Fault_Feature_Dataset.csv');

save(matFile, 'X', 'Y', 'featureTable', ...
    'featureNames', 'windowDuration', 'windowStep', ...
    'normalStart', 'normalEnd', ...
    'faultStart', 'faultEnd');

writetable(featureTable, csvFile);

%% 9. CREATE SUMMARY REPORT

summaryFile = fullfile(outputFolder, ...
    'Feature_Extraction_Summary.txt');

fid = fopen(summaryFile, 'w');

if fid == -1
    error('Could not create summary report.');
end

fprintf(fid, 'TRANSMISSION LINE FAULT FEATURE EXTRACTION\n');
fprintf(fid, '==========================================\n\n');

fprintf(fid, 'Total windows: %d\n', size(X,1));
fprintf(fid, 'Features per window: %d\n\n', size(X,2));

fprintf(fid, 'CLASS DISTRIBUTION\n');
fprintf(fid, '------------------\n');

for k = 1:numel(classLabels)

    count = sum(allLabels == string(classLabels{k}));

    fprintf(fid, '%s: %d windows\n', ...
        classLabels{k}, count);

end

fprintf(fid, '\nFEATURE NAMES\n');
fprintf(fid, '-------------\n');

for k = 1:numel(featureNames)
    fprintf(fid, '%s\n', featureNames{k});
end

fprintf(fid, '\nOUTPUT FILES\n');
fprintf(fid, '%s\n', matFile);
fprintf(fid, '%s\n', csvFile);

fclose(fid);

%% 10. DISPLAY FINAL RESULTS

fprintf('\n====================================\n');
fprintf(' FEATURE EXTRACTION COMPLETED\n');
fprintf('====================================\n');

fprintf('Total windows: %d\n', size(X,1));
fprintf('Features per window: %d\n', size(X,2));

fprintf('\nClass distribution:\n');

for k = 1:numel(classLabels)

    count = sum(allLabels == string(classLabels{k}));

    fprintf('%-6s : %d windows\n', ...
        classLabels{k}, count);

end

fprintf('\nThree output files saved successfully:\n');
fprintf('%s\n', matFile);
fprintf('%s\n', csvFile);
fprintf('%s\n', summaryFile);

fprintf('\n====================================\n');
