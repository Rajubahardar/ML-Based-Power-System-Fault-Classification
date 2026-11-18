
clc;
clear;
close all;

%% =========================================================
% 1. PROJECT PATHS AND DATA LOADING
% ==========================================================

projectFolder = 'D:\MATLAB_Projects\TL_Fault_AI';

featureFolder = fullfile(projectFolder, ...
    '05_Feature_Extraction');

dataFile = fullfile(featureFolder, ...
    'Transmission_Line_Fault_Feature_Dataset.mat');

outputFolder = fullfile(projectFolder, ...
    '06_Machine_Learning');

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

if ~isfile(dataFile)
    error('Feature dataset not found: %s', dataFile);
end

load(dataFile, 'X', 'Y', 'featureTable', 'featureNames');

X = double(X);
Y = categorical(Y(:));

if size(X,1) ~= numel(Y)
    error('Number of feature rows and labels does not match.');
end

if any(~isfinite(X(:)))
    error('Feature matrix contains NaN or Inf values.');
end

classOrder = categories(Y);

fprintf('\n========================================\n');
fprintf(' TRANSMISSION LINE FAULT CLASSIFICATION\n');
fprintf('========================================\n');

fprintf('Total samples: %d\n', size(X,1));
fprintf('Features per sample: %d\n', size(X,2));
fprintf('Number of classes: %d\n', numel(classOrder));


%% =========================================================
% 2. CHRONOLOGICAL TRAINING AND TESTING SPLIT
% ==========================================================

% The windows overlap by 15 ms because:
% Window duration = 20 ms
% Window step     = 5 ms
%
% Therefore, a random split could cause data leakage.
%
% For each class:
%   First 60%  = Training
%   Middle     = Purged gap
%   Last 20%   = Testing
%
% This is a preliminary temporal evaluation.
% It does not replace testing on independent simulations.

trainIdx = [];
testIdx  = [];
gapIdx   = [];

for k = 1:numel(classOrder)

    currentClass = categorical(classOrder(k), classOrder);

    idx = find(Y == currentClass);

    % Sort samples chronologically
    [~, order] = sort(featureTable.WindowStart_s(idx));
    idx = idx(order);

    n = numel(idx);

    nTrain = floor(0.60*n);
    nTest  = floor(0.20*n);

    if nTrain < 1 || nTest < 1
        error('Insufficient samples for class %s.', classOrder{k});
    end

    trainIdx = [trainIdx; idx(1:nTrain)];

    testStart = n - nTest + 1;
    testIdx = [testIdx; idx(testStart:end)];

    if testStart > nTrain + 1
        gapIdx = [gapIdx; idx(nTrain+1:testStart-1)];
    end

    fprintf('%-8s Training: %2d | Gap: %2d | Testing: %2d\n', ...
        classOrder{k}, nTrain, ...
        max(0,testStart-nTrain-1), nTest);

end

XTrain = X(trainIdx,:);
YTrain = Y(trainIdx);

XTest = X(testIdx,:);
YTest = Y(testIdx);

fprintf('\nTraining samples: %d\n', numel(YTrain));
fprintf('Testing samples:  %d\n', numel(YTest));
fprintf('Purged samples:   %d\n', numel(gapIdx));


%% =========================================================
% 3. CLASSIFIER 1 - BAGGED DECISION TREES
% ==========================================================

fprintf('\nTraining Bagged Decision Trees...\n');

treeTemplate = templateTree( ...
    'MinLeafSize', 2);

bagModel = fitcensemble( ...
    XTrain, YTrain, ...
    'Method', 'Bag', ...
    'Learners', treeTemplate, ...
    'NumLearningCycles', 150);

predBag = predict(bagModel, XTest);

fprintf('Bagged Trees training completed.\n');


%% =========================================================
% 4. CLASSIFIER 2 - SUPPORT VECTOR MACHINE
% ==========================================================

fprintf('\nTraining SVM...\n');

svmTemplate = templateSVM( ...
    'KernelFunction', 'gaussian', ...
    'KernelScale', 'auto', ...
    'Standardize', true);

svmModel = fitcecoc( ...
    XTrain, YTrain, ...
    'Learners', svmTemplate, ...
    'Coding', 'onevsone');

predSVM = predict(svmModel, XTest);

fprintf('SVM training completed.\n');


%% =========================================================
% 5. CLASSIFIER 3 - ADABOOSTM2
% ==========================================================

fprintf('\nTraining AdaBoostM2...\n');

boostTree = templateTree( ...
    'MaxNumSplits', 20, ...
    'MinLeafSize', 2);

boostModel = fitcensemble( ...
    XTrain, YTrain, ...
    'Method', 'AdaBoostM2', ...
    'Learners', boostTree, ...
    'NumLearningCycles', 100);

predBoost = predict(boostModel, XTest);

fprintf('AdaBoostM2 training completed.\n');


%% =========================================================
% 6. EVALUATION FUNCTION
% ==========================================================

evaluateModel = @(actual,predicted) ...
    calculateMetrics(actual,predicted,classOrder);


%% =========================================================
% 7. EVALUATE ALL THREE MODELS
% ==========================================================

[accuracyBag, precisionBag, recallBag, f1Bag, Cbag] = ...
    evaluateModel(YTest, predBag);

[accuracySVM, precisionSVM, recallSVM, f1SVM, Csvm] = ...
    evaluateModel(YTest, predSVM);

[accuracyBoost, precisionBoost, recallBoost, f1Boost, Cboost] = ...
    evaluateModel(YTest, predBoost);


%% =========================================================
% 8. DISPLAY PERFORMANCE COMPARISON
% ==========================================================

Model = [
    "Bagged Trees";
    "SVM";
    "AdaBoostM2"
];

Accuracy = [
    accuracyBag;
    accuracySVM;
    accuracyBoost
];

MacroPrecision = [
    mean(precisionBag);
    mean(precisionSVM);
    mean(precisionBoost)
];

MacroRecall = [
    mean(recallBag);
    mean(recallSVM);
    mean(recallBoost)
];

MacroF1Score = [
    mean(f1Bag);
    mean(f1SVM);
    mean(f1Boost)
];

metricsTable = table( ...
    Model, Accuracy, MacroPrecision, ...
    MacroRecall, MacroF1Score);

fprintf('\n========================================\n');
fprintf(' MODEL PERFORMANCE COMPARISON\n');
fprintf('========================================\n');

disp(metricsTable);


%% =========================================================
% 9. CONFUSION MATRICES
% ==========================================================

figure('Name','Bagged Trees Confusion Matrix');

confusionchart(YTest, predBag);
title('Bagged Trees - Confusion Matrix');

exportgraphics(gcf, fullfile(outputFolder, ...
    'Bagged_Trees_Confusion_Matrix.png'));

figure('Name','SVM Confusion Matrix');

confusionchart(YTest, predSVM);
title('SVM - Confusion Matrix');

exportgraphics(gcf, fullfile(outputFolder, ...
    'SVM_Confusion_Matrix.png'));

figure('Name','AdaBoostM2 Confusion Matrix');

confusionchart(YTest, predBoost);
title('AdaBoostM2 - Confusion Matrix');

exportgraphics(gcf, fullfile(outputFolder, ...
    'AdaBoostM2_Confusion_Matrix.png'));


%% =========================================================
% 10. SAVE TRAINED MODELS AND RESULTS
% ==========================================================

save(fullfile(outputFolder, ...
    'Transmission_Line_Fault_Classification_Models.mat'), ...
    'bagModel', 'svmModel', 'boostModel', ...
    'metricsTable', ...
    'Cbag', 'Csvm', 'Cboost', ...
    'trainIdx', 'testIdx', 'gapIdx', ...
    'classOrder', 'featureNames');

writetable(metricsTable, fullfile(outputFolder, ...
    'Classifier_Performance_Comparison.csv'));

fprintf('\n========================================\n');
fprintf(' MACHINE LEARNING COMPLETED\n');
fprintf('========================================\n');

fprintf('Models and results saved in:\n%s\n', outputFolder);

fprintf('\nIMPORTANT:\n');
fprintf(['These results are preliminary because the dataset ', ...
    'contains only one simulation per class.\n']);

fprintf(['Independent simulation scenarios are required ', ...
    'for reliable generalization testing.\n']);


%% =========================================================
% 11. LOCAL FUNCTION FOR CLASSIFICATION METRICS
% ==========================================================


function [accuracy, precision, recall, f1, C] = ...
    calculateMetrics(actual, predicted, classOrder)

    % Calculate confusion matrix using explicit class order
    C = confusionmat(actual, predicted, 'Order', classOrder);

    % Overall accuracy
    accuracy = sum(diag(C)) / max(sum(C(:)), 1);

    % True positives
    truePositive = diag(C);

    % Precision for each class
    precision = truePositive ./ max(sum(C,1)', 1);

    % Recall for each class
    recall = truePositive ./ max(sum(C,2), 1);

    % F1-score for each class
    f1 = 2 .* precision .* recall ./ ...
        max(precision + recall, eps);

end

