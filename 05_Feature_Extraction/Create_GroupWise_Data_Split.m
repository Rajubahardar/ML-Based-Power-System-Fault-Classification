
%% STEP 4 — SCENARIO-WISE TRAIN / VALIDATION / TEST SPLIT

clc;
clearvars;

datasetFile = ...
'D:\MATLAB_Projects\TL_Fault_AI\05_Feature_Extraction\MultiScenario_Fault_Feature_Dataset.mat';

outputDir = ...
'D:\MATLAB_Projects\TL_Fault_AI\05_Feature_Extraction';

load(datasetFile,'X','Y','scenarioGroups','scenarioIDs');

rng(42,'twister');

classNames = unique(Y);

trainGroups = strings(0,1);
valGroups   = strings(0,1);
testGroups  = strings(0,1);

%% Allocate complete scenarios separately for each class

for k = 1:numel(classNames)

    currentClass = classNames(k);

    groups = unique(scenarioGroups(Y == currentClass));
    groups = groups(randperm(numel(groups)));

    n = numel(groups);

    if n < 3
        error('Class %s has fewer than 3 scenarios.',currentClass);
    end

    nTrain = max(1,round(0.70*n));
    nVal   = max(1,round(0.15*n));

    % Ensure at least one scenario remains for testing
    if nTrain + nVal >= n
        nTrain = n - 2;
        nVal = 1;
    end

    nTest = n - nTrain - nVal;

    trainGroups = [trainGroups; groups(1:nTrain)];
    valGroups   = [valGroups; groups(nTrain+1:nTrain+nVal)];
    testGroups  = [testGroups; groups(nTrain+nVal+1:end)];

    fprintf('%-15s | Train: %2d | Validation: %2d | Test: %2d\n', ...
        char(currentClass),nTrain,nVal,nTest);
end

%% Generate sample indices

trainIdx = find(ismember(scenarioGroups,trainGroups));
valIdx   = find(ismember(scenarioGroups,valGroups));
testIdx  = find(ismember(scenarioGroups,testGroups));

%% Verify no scenario leakage

assert(isempty(intersect(trainGroups,valGroups)));
assert(isempty(intersect(trainGroups,testGroups)));
assert(isempty(intersect(valGroups,testGroups)));

assert(numel(trainIdx)+numel(valIdx)+numel(testIdx)==size(X,1));

%% Display sample counts

fprintf('\n========== SPLIT SUMMARY ==========\n');

fprintf('Training samples:   %d\n',numel(trainIdx));
fprintf('Validation samples: %d\n',numel(valIdx));
fprintf('Testing samples:    %d\n',numel(testIdx));

fprintf('\nClass distribution by samples:\n');

for k = 1:numel(classNames)

    c = classNames(k);

    fprintf('\n%s\n',char(c));

    fprintf('  Train: %d\n',sum(Y(trainIdx)==c));
    fprintf('  Val:   %d\n',sum(Y(valIdx)==c));
    fprintf('  Test:  %d\n',sum(Y(testIdx)==c));
end

%% Save indices and group assignments

splitFile = fullfile(outputDir,'GroupWise_Split_Indices.mat');

save(splitFile, ...
    'trainIdx','valIdx','testIdx', ...
    'trainGroups','valGroups','testGroups', ...
    'classNames','-v7.3');

fprintf('\nSplit saved successfully:\n%s\n',splitFile);
fprintf('\nGROUP-WISE SPLIT COMPLETED.\n');
