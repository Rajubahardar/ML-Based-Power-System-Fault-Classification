clc; clear; close all;
projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';
%% 1. LOAD VALIDATED DATASET AND SPLIT
fprintf('=== TRAINING: Loading data and split ===\n\n');
dataFile = fullfile(projectRoot, '05_Feature_Extraction', 'MultiScenario_Fault_Feature_Dataset.mat');
D = load(dataFile, 'X', 'Y', 'featureNames');
X = double(D.X);
Y = string(D.Y(:));
featureNames = string(D.featureNames(:));
[nRows, nFeatures] = size(X);
splitFile = fullfile(projectRoot, '06_Machine_Learning', 'Scenario_Wise_Data_Split_5Class.mat');
D2 = load(splitFile);
trainMask = D2.trainMask;
testMask = D2.testMask;
valMask = D2.valMask;
classOrder = D2.classOrder;
XTrain = X(trainMask, :);
YTrain = Y(trainMask);
XVal = X(valMask, :);
YVal = Y(valMask);
XTest = X(testMask, :);
YTest = Y(testMask);
fprintf('Training set: %d windows\n', numel(YTrain));
fprintf('Validation set: %d windows\n', numel(YVal));
fprintf('Test set: %d windows\n', numel(YTest));
fprintf('Feature dimensions: %d x %d\n', nFeatures, size(XTrain, 2));
fprintf('Class order: %s\n', strjoin(classOrder, ','));
%% 2. TRAIN BAGGED TREES CLASSIFIER
fprintf('\n=== Training Bagged Trees ===\n');
rng(42, 'twister');
treeTemplate = templateTree('MaxNumSplits', 50);
bagModel = fitcensemble(XTrain, YTrain, 'Method', 'Bag', ...
    'Learners', treeTemplate, 'NumLearningCycles', 150);
fprintf('Bagged Trees trained: %d learning cycles\n', 150);
fprintf('  Training completed.\n');
%% 3. TRAIN GAUSSIAN SVM CLASSIFIER
fprintf('\n=== Training Gaussian SVM ===\n');
svmTemplate = templateSVM('KernelFunction', 'gaussian', ...
    'KernelScale', 'auto', 'Standardize', true);
svmModel = fitcecoc(XTrain, YTrain, 'Learners', svmTemplate, 'Coding', 'onevsone');
fprintf('Gaussian SVM trained:\n');
fprintf('  Kernel: Gaussian\n');
fprintf('  KernelScale: auto\n');
fprintf('  Standardize: true (fit on training data only)\n');
fprintf('  Coding: onevsone\n');
fprintf('  SVM training completed.\n');
%% 4. EVALUATE ON VALIDATION SET (462 windows)
fprintf('\n=== Validation Evaluation (462 windows) ===\n');
YPredBagVal = predict(bagModel, XVal);
YPredSVMVal = predict(svmModel, XVal);
[~, bagValAccuracy, bagValPrecision, bagValRecall, bagValF1] = ...
    calculateCorrectedMetrics(YVal, YPredBagVal, classOrder);
[~, svmValAccuracy, svmValPrecision, svmValRecall, svmValF1] = ...
    calculateCorrectedMetrics(YVal, YPredSVMVal, classOrder);
fprintf('Bagged Trees - Validation Accuracy: %.4f (%.2f%%)\n', bagValAccuracy, bagValAccuracy*100);
fprintf('Bagged Trees - Validation Macro Precision: %.4f (%.2f%%)\n', mean(bagValPrecision), mean(bagValPrecision)*100);
fprintf('Bagged Trees - Validation Macro Recall: %.4f (%.2f%%)\n', mean(bagValRecall), mean(bagValRecall)*100);
fprintf('Bagged Trees - Validation Macro F1: %.4f (%.2f%%)\n\n', mean(bagValF1), mean(bagValF1)*100);
fprintf('SVM - Validation Accuracy: %.4f (%.2f%%)\n', svmValAccuracy, svmValAccuracy*100);
fprintf('SVM - Validation Macro Precision: %.4f (%.2f%%)\n', mean(svmValPrecision), mean(svmValPrecision)*100);
fprintf('SVM - Validation Macro Recall: %.4f (%.2f%%)\n', mean(svmValRecall), mean(svmValRecall)*100);
fprintf('SVM - Validation Macro F1: %.4f (%.2f%%)\n\n', mean(svmValF1), mean(svmValF1)*100);
%% 5. SAVE TRAINED MODELS
fprintf('=== Saving trained models ===\n');
modelDir = fullfile(projectRoot, '06_Machine_Learning', 'Corrected_Experiments', 'Models');
if ~exist(modelDir, 'dir'), mkdir(modelDir); end
modelsStructure.trainModel = bagModel;
modelsStructure.svmModel = svmModel;
modelsStructure.classOrder = classOrder;
modelsStructure.featureNames = featureNames;
modelsStructure.trainMask = trainMask;
modelsStructure.testMask = testMask;
modelsStructure.valMask = valMask;
modelsStructure.nTrain = numel(YTrain);
modelsStructure.nVal = numel(YVal);
modelsStructure.nTest = numel(YTest);
modelsStructure.XTrain = XTrain;
modelsStructure.YTrain = YTrain;
modelsStructure.XVal = XVal;
modelsStructure.YVal = YVal;
modelsStructure.XTest = XTest;
modelsStructure.YTest = YTest;
save(fullfile(modelDir, 'Corrected_Fault_Models.mat'), 'modelsStructure', '-v7.3');
save(fullfile(modelDir, 'bagged_trees_model.mat'), 'bagModel', '-v7.3');
save(fullfile(modelDir, 'gaussian_svm_model.mat'), 'svmModel', '-v7.3');
fprintf('  Models saved.\n');
fprintf('\n=== TRAINING COMPLETE ===\n');
fprintf('Both classifiers trained on 83 training groups (1,471 windows).\n');
fprintf('Validation set (462 windows) used for performance assessment.\n');
fprintf('Test set (547 windows) remains untouched for final evaluation.\n');
function [accuracy, precision, recall, f1] = calculateCorrectedMetrics(actual, predicted, classOrder)
actual = string(actual(:));
predicted = string(predicted(:));
numberOfClasses = numel(classOrder);
C = zeros(numberOfClasses);
for i = 1:numberOfClasses
    for j = 1:numberOfClasses
        C(i,j) = sum(actual == classOrder(i) & predicted == classOrder(j));
    end
end
accuracy = sum(diag(C)) / max(sum(C(:)), 1);
truePositive = diag(C);
actualCount = sum(C, 2);
predictedCount = sum(C, 1)';
precision = truePositive ./ max(predictedCount, 1);
recall = truePositive ./ max(actualCount, 1);
f1 = 2 .* precision .* recall ./ max(precision + recall, eps);
precision = precision(:)';
recall = recall(:)';
f1 = f1(:)';
end