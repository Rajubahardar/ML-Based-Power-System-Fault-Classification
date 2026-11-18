
%% ROBUSTNESS TRAINING: BAGGED TREES vs GAUSSIAN SVM
clearvars;
clc;
close all;

%% 1. LOAD DATASET
dataFile = 'Dataset_25K_Noise_Outlier.mat';

if ~isfile(dataFile)
    error('Dataset file not found in the current folder.');
end

loadedData = load(dataFile, 'Dataset25K');
D = loadedData.Dataset25K;

features = double(D.X);
labels = string(D.Y(:));
contaminationLabels = lower(string(D.contamination(:)));

trainIdx = D.trainIdx(:);
valIdx   = D.valIdx(:);
testIdx  = D.testIdx(:);

classNames = string(D.classNames(:));
classNamesCell = cellstr(classNames);

assert(size(features,1) == numel(labels), ...
    'Feature and label counts do not match.');
assert(numel(contaminationLabels) == numel(labels), ...
    'Contamination labels do not match sample count.');
assert(all(isfinite(features(:))), ...
    'Features contain NaN or Inf values.');

fprintf('\nDataset loaded: %d samples, %d features\n', ...
    size(features,1), size(features,2));

%% 2. VERIFY DATA SPLITS
assert(isempty(intersect(trainIdx,valIdx)), ...
    'Training and validation indices overlap.');
assert(isempty(intersect(trainIdx,testIdx)), ...
    'Training and test indices overlap.');
assert(isempty(intersect(valIdx,testIdx)), ...
    'Validation and test indices overlap.');

trainFeatures = features(trainIdx,:);
valFeatures   = features(valIdx,:);
testFeatures  = features(testIdx,:);

trainLabels = categorical(labels(trainIdx), ...
    classNamesCell, classNamesCell);
valLabels = categorical(labels(valIdx), ...
    classNamesCell, classNamesCell);
testLabels = categorical(labels(testIdx), ...
    classNamesCell, classNamesCell);

%% 3. STANDARDIZE FEATURES FOR SVM
% Statistics are calculated using training data only.
featureMean = mean(trainFeatures,1);
featureStd = std(trainFeatures,0,1);
featureStd(featureStd == 0) = 1;

trainZ = (trainFeatures-featureMean)./featureStd;
valZ   = (valFeatures-featureMean)./featureStd;
testZ  = (testFeatures-featureMean)./featureStd;

%% 4. TUNE BAGGED TREES USING VALIDATION MACRO-F1
fprintf('\n========== BAGGED TREES TUNING ==========\n');

treeCounts = [50 100];
splitLimits = [20 50];

bestBTScore = -Inf;
bestBTModel = [];
bestBTConfig = [];

for k = 1:numel(treeCounts)

    fprintf('Training Bagged Trees: %d trees, %d splits\n', ...
        treeCounts(k), splitLimits(k));

    treeTemplate = templateTree( ...
        'MaxNumSplits', splitLimits(k));

    candidateBT = fitcensemble( ...
        trainFeatures, trainLabels, ...
        'Method','Bag', ...
        'NumLearningCycles',treeCounts(k), ...
        'Learners',treeTemplate);

    valPrediction = predict(candidateBT,valFeatures);

    [~,valMacroF1] = calculateMetrics( ...
        valLabels,valPrediction,classNames);

    fprintf('Validation macro-F1: %.4f\n',valMacroF1);

    if valMacroF1 > bestBTScore
        bestBTScore = valMacroF1;
        bestBTModel = candidateBT;
        bestBTConfig = [treeCounts(k),splitLimits(k)];
    end

    clear candidateBT valPrediction;
end

fprintf('Selected Bagged Trees: %d trees, %d splits\n', ...
    bestBTConfig(1),bestBTConfig(2));

%% 5. TUNE GAUSSIAN SVM USING VALIDATION MACRO-F1
fprintf('\n========== GAUSSIAN SVM TUNING ==========\n');

boxConstraints = [0.1 1];

bestSVMScore = -Inf;
bestSVMModel = [];
bestSVMBox = NaN;

for k = 1:numel(boxConstraints)

    fprintf('Training Gaussian SVM: BoxConstraint = %.2f\n', ...
        boxConstraints(k));

    svmTemplate = templateSVM( ...
        'KernelFunction','gaussian', ...
        'KernelScale','auto', ...
        'BoxConstraint',boxConstraints(k), ...
        'Standardize',false);

    candidateSVM = fitcecoc( ...
        trainZ,trainLabels, ...
        'Learners',svmTemplate, ...
        'Coding','onevsone');

    valPrediction = predict(candidateSVM,valZ);

    [~,valMacroF1] = calculateMetrics( ...
        valLabels,valPrediction,classNames);

    fprintf('Validation macro-F1: %.4f\n',valMacroF1);

    if valMacroF1 > bestSVMScore
        bestSVMScore = valMacroF1;
        bestSVMModel = candidateSVM;
        bestSVMBox = boxConstraints(k);
    end

    clear candidateSVM valPrediction;
end

fprintf('Selected SVM BoxConstraint: %.2f\n',bestSVMBox);

%% 6. FINAL TEST EVALUATION
% The test set has not been used for model selection.
fprintf('\n========== FINAL TEST EVALUATION ==========\n');

btPrediction = predict(bestBTModel,testFeatures);
svmPrediction = predict(bestSVMModel,testZ);

[btAccuracy,btMacroF1,btCM,btClassMetrics] = ...
    calculateMetrics(testLabels,btPrediction,classNames);

[svmAccuracy,svmMacroF1,svmCM,svmClassMetrics] = ...
    calculateMetrics(testLabels,svmPrediction,classNames);

fprintf('\nBAGGED TREES\n');
fprintf('Test accuracy: %.2f%%\n',100*btAccuracy);
fprintf('Test macro-F1: %.4f\n',btMacroF1);

fprintf('\nGAUSSIAN SVM\n');
fprintf('Test accuracy: %.2f%%\n',100*svmAccuracy);
fprintf('Test macro-F1: %.4f\n',svmMacroF1);

%% 7. SEPARATE CLEAN, NOISE AND OUTLIER TEST RESULTS
testContamination = contaminationLabels(testIdx);

isNoise = contains(testContamination,'noise');
isOutlier = contains(testContamination,'outlier');
isClean = ~(isNoise | isOutlier);

groups = {isClean,isNoise,isOutlier};
groupNames = ["Clean";"Noise";"Outlier"];

BT_Group_Accuracy = zeros(3,1);
BT_Group_MacroF1 = zeros(3,1);
SVM_Group_Accuracy = zeros(3,1);
SVM_Group_MacroF1 = zeros(3,1);
Sample_Count = zeros(3,1);

fprintf('\n========== CONTAMINATION-WISE RESULTS ==========\n');

for k = 1:3

    mask = groups{k};
    Sample_Count(k) = sum(mask);

    if Sample_Count(k) == 0
        warning('No test samples found for %s.',groupNames(k));
        continue;
    end

    [BT_Group_Accuracy(k),BT_Group_MacroF1(k)] = ...
        calculateMetrics(testLabels(mask), ...
        btPrediction(mask),classNames);

    [SVM_Group_Accuracy(k),SVM_Group_MacroF1(k)] = ...
        calculateMetrics(testLabels(mask), ...
        svmPrediction(mask),classNames);

    fprintf('\n%s samples: %d\n', ...
        groupNames(k),Sample_Count(k));

    fprintf('Bagged Trees accuracy: %.2f%% | Macro-F1: %.4f\n', ...
        100*BT_Group_Accuracy(k),BT_Group_MacroF1(k));

    fprintf('Gaussian SVM accuracy: %.2f%% | Macro-F1: %.4f\n', ...
        100*SVM_Group_Accuracy(k),SVM_Group_MacroF1(k));
end

RobustnessTable = table( ...
    groupNames,Sample_Count, ...
    100*BT_Group_Accuracy,BT_Group_MacroF1, ...
    100*SVM_Group_Accuracy,SVM_Group_MacroF1, ...
    'VariableNames',{'TestGroup','Samples', ...
    'BT_Accuracy_Percent','BT_MacroF1', ...
    'SVM_Accuracy_Percent','SVM_MacroF1'});

fprintf('\n');
disp(RobustnessTable);

%% 8. CONFUSION MATRICES
figure('Name','Bagged Trees Confusion Matrix');
confusionchart(testLabels,btPrediction);
title('Bagged Trees - Test Confusion Matrix');

figure('Name','Gaussian SVM Confusion Matrix');
confusionchart(testLabels,svmPrediction);
title('Gaussian SVM - Test Confusion Matrix');

%% 9. SAVE RESULTS
Results = struct();

Results.BaggedTrees.Model = bestBTModel;
Results.BaggedTrees.Configuration = bestBTConfig;
Results.BaggedTrees.ValidationMacroF1 = bestBTScore;
Results.BaggedTrees.TestAccuracy = btAccuracy;
Results.BaggedTrees.TestMacroF1 = btMacroF1;
Results.BaggedTrees.ConfusionMatrix = btCM;
Results.BaggedTrees.ClassMetrics = btClassMetrics;

Results.GaussianSVM.Model = bestSVMModel;
Results.GaussianSVM.BoxConstraint = bestSVMBox;
Results.GaussianSVM.FeatureMean = featureMean;
Results.GaussianSVM.FeatureStd = featureStd;
Results.GaussianSVM.ValidationMacroF1 = bestSVMScore;
Results.GaussianSVM.TestAccuracy = svmAccuracy;
Results.GaussianSVM.TestMacroF1 = svmMacroF1;
Results.GaussianSVM.ConfusionMatrix = svmCM;
Results.GaussianSVM.ClassMetrics = svmClassMetrics;

Results.RobustnessTable = RobustnessTable;
Results.ClassNames = classNames;

save('Robustness_Training_Results.mat', ...
    'Results','-v7.3');

writetable(RobustnessTable, ...
    'Contamination_Wise_Performance.csv');

fprintf('\n========================================\n');
fprintf('TRAINING AND EVALUATION COMPLETED.\n');
fprintf('Results saved successfully.\n');
fprintf('========================================\n');

%% LOCAL METRIC FUNCTION
function [accuracy,macroF1,CM,classMetrics] = ...
    calculateMetrics(actual,predicted,classNames)

    actual = string(actual(:));
    predicted = string(predicted(:));
    classNames = string(classNames(:));

    nClasses = numel(classNames);
    CM = zeros(nClasses,nClasses);

    for i = 1:nClasses
        for j = 1:nClasses
            CM(i,j) = sum( ...
                actual == classNames(i) & ...
                predicted == classNames(j));
        end
    end

    total = sum(CM,'all');

    if total == 0
        accuracy = NaN;
        macroF1 = NaN;
        classMetrics = table();
        return;
    end

    accuracy = sum(diag(CM))/total;

    precision = zeros(nClasses,1);
    recall = zeros(nClasses,1);
    f1 = zeros(nClasses,1);

    for i = 1:nClasses

        TP = CM(i,i);
        FP = sum(CM(:,i))-TP;
        FN = sum(CM(i,:))-TP;

        if TP+FP > 0
            precision(i) = TP/(TP+FP);
        end

        if TP+FN > 0
            recall(i) = TP/(TP+FN);
        end

        if precision(i)+recall(i) > 0
            f1(i) = 2*precision(i)*recall(i)/ ...
                (precision(i)+recall(i));
        end
    end

    macroF1 = mean(f1);

    classMetrics = table( ...
        classNames,precision,recall,f1, ...
        'VariableNames',{'Class','Precision','Recall','F1'});
end
