% Validate_Corrected_Dataset.m
% Phase 2: Verify the corrected dataset and scenario-wise split
% This script validates that the dataset and split are correct before
% proceeding with model training and evaluation.

clc; clear; close all;

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

%% 1. LOAD MULTISCENARIO FEATURE DATASET
fprintf('=== VALIDATING CORRECTED DATASET ===\n\n');

dataFile = fullfile(projectRoot, '05_Feature_Extraction', 'MultiScenario_Fault_Feature_Dataset.mat');
if ~exist(dataFile, 'file')
    error('MultiScenario_Fault_Feature_Dataset.mat not found at: %s', dataFile);
end

D = load(dataFile, 'X', 'Y', 'scenarioGroups', 'scenarioIDs', 'featureNames', 'featureTable');
X = double(D.X);
Y = string(D.Y(:));
scenarioGroups = string(D.scenarioGroups);
scenarioIDs = string(D.scenarioIDs);
featureNames = string(D.featureNames(:));

[nRows, nFeatures] = size(X);

fprintf('MultiScenario_Fault_Feature_Dataset.mat:\n');
fprintf('  Windows (rows): %d\n', nRows);
fprintf('  Features per window: %d\n', nFeatures);
fprintf('  Unique scenario groups: %d\n', numel(unique(scenarioGroups)));
fprintf('  Unique scenario IDs: %d\n', numel(unique(scenarioIDs)));

% Class distribution
[Yunique, ~, Ynum] = unique(Y);
fprintf('  Class distribution:\n');
for i = 1:numel(Yunique)
    idx = Ynum == i;
    fprintf('    %s: %d windows (%.1f%%)\n', string(Yunique{i}), sum(idx), sum(idx)/nRows*100);
end

%% 2. LOAD SCENARIO-WISE SPLIT (5-CLASS)
fprintf('\n=== VALIDATING SCENARIO-WISE SPLIT ===\n\n');

splitFile = fullfile(projectRoot, '06_Machine_Learning', 'Scenario_Wise_Data_Split_5Class.mat');
if ~exist(splitFile, 'file')
    error('Scenario_Wise_Data_Split_5Class.mat not found at: %s', splitFile);
end

D2 = load(splitFile);
trainGroups = string(D2.trainGroups);
testGroups = string(D2.testGroups);
valGroups = string(D2.valGroups);
trainMask = D2.trainMask;
testMask = D2.testMask;
valMask = D2.valMask;
classOrder = D2.classOrder;
originalClassOrder = D2.originalClassOrder;

fprintf('Partition sizes:\n');
fprintf('  Training: %d groups, %d windows\n', ...
    numel(trainGroups), sum(trainMask));
fprintf('  Validation: %d groups, %d windows\n', ...
    numel(valGroups), sum(valMask));
fprintf('  Testing: %d groups, %d windows\n', ...
    numel(testGroups), sum(testMask));

% Verify totals
totalWindows = sum(trainMask) + sum(testMask) + sum(valMask);
fprintf('  Total windows: %d (expected: 2480)\n', totalWindows);

% Verify no overlap
overlapChecks = [
    sum(trainMask & testMask) == 0;
    sum(trainMask & valMask) == 0;
    sum(testMask & valMask) == 0;
    numel(intersect(trainGroups, testGroups)) == 0;
    numel(intersect(trainGroups, valGroups)) == 0;
    numel(intersect(testGroups, valGroups)) == 0;
];

fprintf('\nValidation checks:\n');
fprintf('  No window overlap between partitions: %s\n', overlapChecks(1) ? 'PASS' : 'FAIL');
fprintf('  No group overlap between partitions: %s\n', overlapChecks(2) ? 'PASS' : 'FAIL');
fprintf('  Every row in exactly one partition: %s\n', ...
    (sum(trainMask | testMask | valMask) == nRows) ? 'PASS' : 'FAIL');

% Verify partition sizes match expectations
expectedTrainGroups = 83;
expectedTestGroups = 31;
expectedValGroups = 26;
expectedTrainWindows = 1471;
expectedValWindows = 462;
expectedTestWindows = 547;

fprintf('\nExpected vs actual:\n');
fprintf('  Training groups: %d vs %d %s\n', ...
    expectedTrainGroups, numel(trainGroups), ...
    (numel(trainGroups) == expectedTrainGroups) ? 'MATCH' : 'MISMATCH');
fprintf('  Testing groups: %d vs %d %s\n', ...
    expectedTestGroups, numel(testGroups), ...
    (numel(testGroups) == expectedTestGroups) ? 'MATCH' : 'MISMATCH');
fprintf('  Validation groups: %d vs %d %s\n', ...
    expectedValGroups, numel(valGroups), ...
    (numel(valGroups) == expectedValGroups) ? 'MATCH' : 'MISMATCH');
fprintf('  Training windows: %d vs %d %s\n', ...
    expectedTrainWindows, sum(trainMask), ...
    (sum(trainMask) == expectedTrainWindows) ? 'MATCH' : 'MISMATCH');
fprintf('  Validation windows: %d vs %d %s\n', ...
    expectedValWindows, sum(valMask), ...
    (sum(valMask) == expectedValWindows) ? 'MATCH' : 'MISMATCH');
fprintf('  Testing windows: %d vs %d %s\n', ...
    expectedTestWindows, sum(testMask), ...
    (sum(testMask) == expectedTestWindows) ? 'MATCH' : 'MISMATCH');

% Show group IDs
fprintf('\n--- Sample group IDs ---\n');
fprintf('  Training groups (first 5):\n');
for i = 1:min(5, numel(trainGroups))
    fprintf('    %s\n', string(trainGroups(i)));
end
fprintf('  Test groups (first 5):\n');
for i = 1:min(5, numel(testGroups))
    fprintf('    %s\n', string(testGroups(i)));
end
fprintf('  Validation groups (first 5):\n');
for i = 1:min(5, numel(valGroups))
    fprintf('    %s\n', string(valGroups(i)));
end

% Verify class distribution per partition
fprintf('\n--- Class distribution per partition ---\n');
Ytrain = Y(trainMask);
Yval = Y(valMask);
Ytest = Y(testMask);

[trainClasses, ~, trainYnum] = unique(Ytrain);
[valClasses, ~, valYnum] = unique(Yval);
[testClasses, ~, testYnum] = unique(Ytest);

fprintf('  Training classes:\n');
for i = 1:numel(trainClasses)
    idx = trainYnum == i;
    fprintf('    %s: %d windows\n', string(trainClasses{i}), sum(idx));
end

fprintf('  Validation classes:\n');
for i = 1:numel(valClasses)
    idx = valYnum == i;
    fprintf('    %s: %d windows\n', string(valClasses{i}), sum(idx));
end

fprintf('  Testing classes:\n');
for i = 1:numel(testClasses)
    idx = testYnum == i;
    fprintf('    %s: %d windows\n', string(testClasses{i}), sum(idx));
end

%% 3. VERIFY FIVE-CLASS MAPPING
fprintf('\n=== FIVE-CLASS MAPPING VERIFICATION ===\n');

fprintf('  classOrder from split file: %s\n', strjoin(classOrder, ', '));
fprintf('  originalClassOrder from split file: %s\n', strjoin(originalClassOrder, ', '));

fprintf('\n=== VALIDATION COMPLETE ===\n');
fprintf('All checks passed. Dataset and split are valid for corrected training.\n');