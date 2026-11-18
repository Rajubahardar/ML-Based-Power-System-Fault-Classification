
%% ================================================================
%  UNSEEN FAULT LOCATION GENERALIZATION TEST
%
%  Project: AI-Based Fault Detection and Classification
%  Dataset: Existing 2480-window feature dataset
%
%  Five classes:
%    Normal, LG, LL, LLG, Three_Phase_Fault
%
%  Three folds:
%    Fold 1: Train fault locations 50, 80 km; test 20 km
%    Fold 2: Train fault locations 20, 80 km; test 50 km
%    Fold 3: Train fault locations 20, 50 km; test 80 km
%
%  Normal simulation groups are also separated between train/test.
%  No Simulink simulations are performed.
%% ================================================================

clc;
clear;
close all;

rng(42, 'twister');

fprintf('\n====================================================\n');
fprintf('       UNSEEN FAULT LOCATION TEST\n');
fprintf('====================================================\n');


%% 1. PATH CONFIGURATION

% Explicit project root directory
projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

% Dataset location
datasetFile = fullfile(projectRoot, ...
    '05_Feature_Extraction', ...
    'MultiScenario_Fault_Feature_Dataset.mat');

% Output location
outputFolder = fullfile(projectRoot, ...
    '06_Machine_Learning', ...
    'Unseen_Location_Results');

% Create output directory if necessary
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

% Verify dataset exists
fprintf('\nChecking dataset path:\n%s\n', datasetFile);

if ~isfile(datasetFile)
    error('Dataset not found. Check the project folder and filename.');
end

fprintf('Dataset found successfully.\n');


%% 2. LOAD DATASET

D = load(datasetFile);

requiredVariables = ...
    {'X', 'Y', 'scenarioGroups', 'faultLocation'};

for k = 1:numel(requiredVariables)
    if ~isfield(D, requiredVariables{k})
        error('Required variable missing: %s', ...
            requiredVariables{k});
    end
end

X = double(D.X);
Y = string(D.Y(:));
groups = string(D.scenarioGroups(:));
faultLocation = double(D.faultLocation(:));

if size(X,1) ~= numel(Y) || ...
        numel(Y) ~= numel(groups) || ...
        numel(Y) ~= numel(faultLocation)

    error('Dataset dimensions are inconsistent.');
end

if any(~isfinite(X), 'all')
    error('Feature matrix contains NaN or Inf values.');
end

fprintf('\nDataset loaded successfully.\n');
fprintf('Total windows: %d\n', size(X,1));
fprintf('Total features: %d\n', size(X,2));
fprintf('Total simulation groups: %d\n', ...
    numel(unique(groups)));

%% 3. MERGE SIX CLASSES INTO FIVE CLASSES

Y5 = Y;

Y5(ismember(Y5, ["LLL", "LLLG"])) = ...
    "Three_Phase_Fault";

classOrder = [ ...
    "Normal"
    "LG"
    "LL"
    "LLG"
    "Three_Phase_Fault"
    ];

if any(~ismember(unique(Y5), classOrder))
    error('Unexpected class label detected.');
end

fprintf('\nFive-class distribution:\n');

for k = 1:numel(classOrder)
    fprintf('%-22s %d windows\n', ...
        classOrder(k), sum(Y5 == classOrder(k)));
end

%% 4. IDENTIFY SIMULATION GROUPS

uniqueGroups = unique(groups);

groupClass = strings(numel(uniqueGroups),1);
groupLocation = nan(numel(uniqueGroups),1);

for g = 1:numel(uniqueGroups)

    idx = groups == uniqueGroups(g);

    groupLabels = unique(Y5(idx));

    if numel(groupLabels) ~= 1
        error('Group contains multiple class labels: %s', ...
            uniqueGroups(g));
    end

    groupClass(g) = groupLabels;

    locations = unique(faultLocation(idx));

    if groupClass(g) == "Normal"

        if any(~isnan(locations))
            error('Normal group has a non-NaN fault location.');
        end

    else

        locations = locations(~isnan(locations));

        if numel(locations) ~= 1
            error('Fault group has inconsistent fault locations: %s', ...
                uniqueGroups(g));
        end

        groupLocation(g) = locations;
    end
end

normalGroups = uniqueGroups(groupClass == "Normal");

faultGroups = uniqueGroups(groupClass ~= "Normal");

faultLocations = unique(groupLocation(~isnan(groupLocation)));

expectedLocations = [20; 50; 80];

if ~isequal(sort(faultLocations(:)), expectedLocations)
    error('Expected fault locations 20, 50, and 80 km were not found.');
end

fprintf('\nNormal simulation groups: %d\n', ...
    numel(normalGroups));

fprintf('Fault simulation groups: %d\n', ...
    numel(faultGroups));

fprintf('Fault locations: %s km\n', ...
    mat2str(faultLocations(:)'));

if numel(normalGroups) < 3
    error('At least three normal groups are required.');
end

%% 5. ASSIGN NORMAL GROUPS TO TEST FOLDS

% Each normal group is assigned to exactly one test fold.
% Remaining normal groups are used for training in that fold.

normalGroups = sort(normalGroups);

normalTestFold = mod((0:numel(normalGroups)-1)', 3) + 1;

fprintf('\nNormal group allocation:\n');

for fold = 1:3

    assigned = normalGroups(normalTestFold == fold);

    fprintf('Fold %d test normal groups: ', fold);
    fprintf('%s ', assigned);
    fprintf('\n');
end

%% 6. MODEL CONFIGURATION

treeTemplate = templateTree( ...
    'MaxNumSplits', 50);

svmTemplate = templateSVM( ...
    'KernelFunction', 'gaussian', ...
    'KernelScale', 'auto', ...
    'Standardize', true);

numTrees = 150;

modelNames = ["Bagged_Trees", "Gaussian_SVM"];

numFolds = 3;
numModels = numel(modelNames);
numClasses = numel(classOrder);

%% 7. INITIALIZE RESULT STORAGE

foldAccuracy = nan(numFolds, numModels);
foldMacroF1 = nan(numFolds, numModels);

allResults = table();

predictionResults = table();

confusionMatrices = cell(numFolds, numModels);

%% 8. RUN THREE UNSEEN-LOCATION FOLDS

for fold = 1:numFolds

    fprintf('\n\n====================================================\n');
    fprintf('FOLD %d\n', fold);
    fprintf('====================================================\n');

    heldOutLocation = expectedLocations(fold);

    fprintf('Held-out fault location: %d km\n', ...
        heldOutLocation);

    %% 8.1 SELECT FAULT GROUPS

    testFaultGroups = uniqueGroups( ...
        groupClass ~= "Normal" & ...
        groupLocation == heldOutLocation);

    trainFaultGroups = uniqueGroups( ...
        groupClass ~= "Normal" & ...
        groupLocation ~= heldOutLocation);

    %% 8.2 SELECT NORMAL GROUPS

    testNormalGroups = normalGroups(normalTestFold == fold);

    trainNormalGroups = normalGroups(normalTestFold ~= fold);

    %% 8.3 COMBINE TRAINING AND TEST GROUPS

    trainGroups = [trainFaultGroups; trainNormalGroups];

    testGroups = [testFaultGroups; testNormalGroups];

    trainMask = ismember(groups, trainGroups);
    testMask = ismember(groups, testGroups);

    XTrain = X(trainMask,:);
    XTest = X(testMask,:);

    YTrain = Y5(trainMask);
    YTest = Y5(testMask);

    trainGroupCount = numel(unique(groups(trainMask)));
    testGroupCount = numel(unique(groups(testMask)));

    %% 8.4 VERIFY GROUP SEPARATION

    overlappingGroups = intersect( ...
        unique(groups(trainMask)), ...
        unique(groups(testMask)));

    if ~isempty(overlappingGroups)
        error('Group leakage detected in fold %d.', fold);
    end

    if any(ismember(groups(trainMask), testGroups))
        error('Training group overlap detected.');
    end

    if any(ismember(groups(testMask), trainGroups))
        error('Testing group overlap detected.');
    end

    %% 8.5 VERIFY LOCATION SEPARATION

    trainFaultRows = trainMask & ...
        ~isnan(faultLocation);

    testFaultRows = testMask & ...
        ~isnan(faultLocation);

    if any(faultLocation(trainFaultRows) == heldOutLocation)
        error('Held-out location found in training data.');
    end

    if any(faultLocation(testFaultRows) ~= heldOutLocation)
        error('Unexpected fault location found in test data.');
    end

    %% 8.6 VERIFY ALL FIVE CLASSES

    if ~all(ismember(classOrder, unique(YTrain)))
        error('A class is missing from training data in fold %d.', fold);
    end

    if ~all(ismember(classOrder, unique(YTest)))
        error('A class is missing from test data in fold %d.', fold);
    end

    fprintf('\nTraining windows: %d\n', size(XTrain,1));
    fprintf('Testing windows:  %d\n', size(XTest,1));

    fprintf('Training groups: %d\n', trainGroupCount);
    fprintf('Testing groups:  %d\n', testGroupCount);

    fprintf('Group overlap: %d\n', numel(overlappingGroups));

    fprintf('\nTraining class distribution:\n');

    for c = 1:numClasses
        fprintf('%-22s %d\n', ...
            classOrder(c), sum(YTrain == classOrder(c)));
    end

    fprintf('\nTesting class distribution:\n');

    for c = 1:numClasses
        fprintf('%-22s %d\n', ...
            classOrder(c), sum(YTest == classOrder(c)));
    end

    %% 8.7 TRAIN AND EVALUATE MODELS

    for model = 1:numModels

        fprintf('\n--------------------------------------------\n');
        fprintf('Training model: %s\n', modelNames(model));
        fprintf('--------------------------------------------\n');

        switch model

            case 1

                mdl = fitcensemble( ...
                    XTrain, YTrain, ...
                    'Method', 'Bag', ...
                    'NumLearningCycles', numTrees, ...
                    'Learners', treeTemplate);

            case 2

                mdl = fitcecoc( ...
                    XTrain, YTrain, ...
                    'Learners', svmTemplate, ...
                    'Coding', 'onevsone');

        end

        %% PREDICTION

        predictedLabels = string(predict(mdl, XTest));

        %% CONFUSION MATRIX

        C = zeros(numClasses, numClasses);

        for i = 1:numClasses
            for j = 1:numClasses

                C(i,j) = sum( ...
                    YTest == classOrder(i) & ...
                    predictedLabels == classOrder(j));

            end
        end

        confusionMatrices{fold,model} = C;

        %% PERFORMANCE METRICS

        TP = diag(C);

        FP = sum(C,1)' - TP;

        FN = sum(C,2) - TP;

        precision = TP ./ (TP + FP);
        recall = TP ./ (TP + FN);

        precision(isnan(precision)) = 0;
        recall(isnan(recall)) = 0;

        F1 = 2 .* precision .* recall ./ ...
            (precision + recall);

        F1(isnan(F1)) = 0;

        accuracy = sum(TP) / sum(C(:));

        macroF1 = mean(F1);

        foldAccuracy(fold,model) = accuracy;
        foldMacroF1(fold,model) = macroF1;

        %% DISPLAY RESULTS

        fprintf('\nAccuracy: %.4f (%.2f%%)\n', ...
            accuracy, accuracy*100);

        fprintf('Macro F1: %.4f\n', macroF1);

        fprintf('\nConfusion matrix:\n');
        fprintf('Rows = Actual, Columns = Predicted\n');

        disp(array2table(C, ...
            'VariableNames', cellstr(classOrder), ...
            'RowNames', cellstr(classOrder)));

        fprintf('\nPer-class performance:\n');

        metricTable = table( ...
            classOrder, precision, recall, F1, ...
            sum(C,2), ...
            'VariableNames', ...
            {'Class','Precision','Recall','F1','Support'});

        disp(metricTable);

        %% SAVE FOLD METRICS

        resultRow = table( ...
            fold, ...
            heldOutLocation, ...
            modelNames(model), ...
            accuracy, ...
            macroF1, ...
            size(XTrain,1), ...
            size(XTest,1), ...
            trainGroupCount, ...
            testGroupCount, ...
            'VariableNames', ...
            {'Fold','HeldOutLocation_km','Model', ...
            'Accuracy','MacroF1', ...
            'TrainWindows','TestWindows', ...
            'TrainGroups','TestGroups'});

        allResults = [allResults; resultRow];

        %% SAVE PREDICTIONS

        currentPredictions = table( ...
            repmat(fold,size(YTest,1),1), ...
            repmat(heldOutLocation,size(YTest,1),1), ...
            groups(testMask), ...
            YTest, ...
            predictedLabels, ...
            'VariableNames', ...
            {'Fold','HeldOutLocation_km','ScenarioGroup', ...
            'ActualClass','PredictedClass'});

        predictionResults = [ ...
            predictionResults; currentPredictions];

        %% SAVE CONFUSION MATRIX IMAGE

        fig = figure('Visible','off');

        confusionchart(C, cellstr(classOrder));

        title(sprintf('%s - Fold %d - Unseen %d km', ...
            modelNames(model), fold, heldOutLocation));

        imageFile = fullfile(outputFolder, ...
            sprintf('Confusion_%s_Fold%d.png', ...
            modelNames(model), fold));

        exportgraphics(fig, imageFile, 'Resolution', 200);

        close(fig);

    end
end

%% 9. DISPLAY FOLD-WISE COMPARISON

fprintf('\n\n====================================================\n');
fprintf('FOLD-WISE PERFORMANCE COMPARISON\n');
fprintf('====================================================\n');

disp(allResults);

%% 10. CALCULATE MEAN AND STANDARD DEVIATION

fprintf('\n====================================================\n');
fprintf('MEAN PERFORMANCE ACROSS THREE FOLDS\n');
fprintf('====================================================\n');

meanAccuracy = mean(foldAccuracy,1);
stdAccuracy = std(foldAccuracy,0,1);

meanMacroF1 = mean(foldMacroF1,1);
stdMacroF1 = std(foldMacroF1,0,1);

summaryTable = table( ...
    modelNames(:), ...
    meanAccuracy(:), ...
    stdAccuracy(:), ...
    meanMacroF1(:), ...
    stdMacroF1(:), ...
    'VariableNames', ...
    {'Model','MeanAccuracy','StdAccuracy', ...
    'MeanMacroF1','StdMacroF1'});

disp(summaryTable);

%% 11. SAVE RESULTS

writetable(allResults, ...
    fullfile(outputFolder, ...
    'Unseen_Location_Fold_Results.csv'));

writetable(summaryTable, ...
    fullfile(outputFolder, ...
    'Unseen_Location_Summary.csv'));

writetable(predictionResults, ...
    fullfile(outputFolder, ...
    'Unseen_Location_Predictions.csv'));

save(fullfile(outputFolder, ...
    'Unseen_Location_Complete_Results.mat'), ...
    'allResults', ...
    'summaryTable', ...
    'predictionResults', ...
    'confusionMatrices', ...
    'foldAccuracy', ...
    'foldMacroF1', ...
    'classOrder', ...
    'expectedLocations');

%% 12. FINAL VERIFICATION

fprintf('\n====================================================\n');
fprintf('FINAL VERIFICATION\n');
fprintf('====================================================\n');

fprintf('Total original windows: %d\n', size(X,1));

fprintf('Total tested windows across folds: %d\n', ...
    height(predictionResults) / numModels);

for fold = 1:numFolds

    fprintf('Fold %d: held-out location = %d km\n', ...
        fold, expectedLocations(fold));

end

fprintf('\nResults saved in:\n%s\n', outputFolder);

fprintf('\n====================================================\n');
fprintf('UNSEEN LOCATION TEST COMPLETED\n');
fprintf('====================================================\n');
