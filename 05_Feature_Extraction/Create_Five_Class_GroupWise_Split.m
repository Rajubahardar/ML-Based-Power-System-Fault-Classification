
clc;
clear;

%% Load five-class dataset
projectPath = 'D:\MATLAB_Projects\TL_Fault_AI';

dataPath = fullfile(projectPath, ...
    '05_Feature_Extraction', ...
    'Five_Class_Fault_Feature_Dataset.mat');

load(dataPath);

Y = FiveClassDataset.Y;
groups = FiveClassDataset.scenarioGroups;

%% Reproducible random split
rng(42, 'twister');

classNames = ["LG", "LL", "LLG", ...
              "Three_Phase_Fault", "Normal"];

trainIdx = [];
valIdx = [];
testIdx = [];

for k = 1:numel(classNames)

    currentClass = classNames(k);

    classGroups = unique(groups(Y == currentClass));

    classGroups = classGroups(randperm(numel(classGroups)));

    n = numel(classGroups);

    nTrain = floor(0.70 * n);
    nVal = floor(0.15 * n);

    trainGroups_k = classGroups(1:nTrain);
    valGroups_k = classGroups(nTrain+1:nTrain+nVal);
    testGroups_k = classGroups(nTrain+nVal+1:end);

    trainIdx = [trainIdx; find( ...
        Y == currentClass & ismember(groups, trainGroups_k))];

    valIdx = [valIdx; find( ...
        Y == currentClass & ismember(groups, valGroups_k))];

    testIdx = [testIdx; find( ...
        Y == currentClass & ismember(groups, testGroups_k))];

end

%% Save split
outputPath = fullfile(projectPath, ...
    '05_Feature_Extraction', ...
    'Five_Class_GroupWise_Split.mat');

save(outputPath, 'trainIdx', 'valIdx', 'testIdx', ...
    'classNames');

%% Display results
fprintf('\nFIVE-CLASS GROUP-WISE SPLIT\n');
fprintf('Training samples   : %d\n', numel(trainIdx));
fprintf('Validation samples : %d\n', numel(valIdx));
fprintf('Testing samples    : %d\n', numel(testIdx));

fprintf('\nUnique groups:\n');
fprintf('Training   : %d\n', numel(unique(groups(trainIdx))));
fprintf('Validation : %d\n', numel(unique(groups(valIdx))));
fprintf('Testing    : %d\n', numel(unique(groups(testIdx))));

%% Verify no group leakage
assert(isempty(intersect(groups(trainIdx), groups(valIdx))));
assert(isempty(intersect(groups(trainIdx), groups(testIdx))));
assert(isempty(intersect(groups(valIdx), groups(testIdx))));

fprintf('\nGroup leakage check: PASSED\n');
fprintf('Split saved successfully.\n');
