
%% MACHINE LEARNING: TRANSMISSION LINE FAULT CLASSIFICATION
% Revised classification: FIVE CLASSES
%
% 1. Normal
% 2. LG
% 3. LL
% 4. LLG
% 5. Three_Phase_Fault (LLL + LLLG)
%
% Models:
% 1. Bagged Trees
% 2. Gaussian SVM
% 3. AdaBoostM2
%
% Dataset: 2480 windows x 60 features
% Split: 60% Train / 20% Validation / 20% Test
% Splitting: Scenario-wise group splitting
%
% No Simulink simulations are performed.

clear;
clc;
close all;

rng(42,'twister');

fprintf('\n============================================\n');
fprintf(' FIVE-CLASS TRANSMISSION LINE FAULT CLASSIFICATION\n');
fprintf('============================================\n');


%% 1. PROJECT PATHS

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

datasetFile = fullfile(projectRoot, ...
    '05_Feature_Extraction', ...
    'MultiScenario_Fault_Feature_Dataset.mat');

outputFolder = fullfile(projectRoot, ...
    '06_Machine_Learning');

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

if ~isfile(datasetFile)
    error('Feature dataset not found: %s',datasetFile);
end

fprintf('\nFeature dataset found:\n%s\n',datasetFile);


%% 2. LOAD DATASET

D = load(datasetFile);

requiredVariables = { ...
    'X','Y','scenarioGroups','scenarioIDs','featureNames'};

for k = 1:numel(requiredVariables)

    if ~isfield(D,requiredVariables{k})
        error('Dataset is missing variable: %s', ...
            requiredVariables{k});
    end

end

X = double(D.X);

YOriginal = string(D.Y(:));

scenarioGroups = string(D.scenarioGroups(:));

scenarioIDs = string(D.scenarioIDs(:));

featureNames = D.featureNames;

if size(X,1) ~= numel(YOriginal) || ...
   size(X,1) ~= numel(scenarioGroups) || ...
   size(X,1) ~= numel(scenarioIDs)

    error('Feature and metadata dimensions do not match.');

end

if size(X,2) ~= 60
    error('Expected 60 features, but found %d.',size(X,2));
end

if any(~isfinite(X(:)))
    error('Feature matrix contains NaN or Inf.');
end

if any(ismissing(YOriginal)) || ...
   any(ismissing(scenarioGroups)) || ...
   any(strlength(scenarioGroups)==0)

    error('Missing class labels or scenario groups detected.');

end


%% 3. MERGE LLL AND LLLG

fprintf('\n============================================\n');
fprintf(' MERGING THREE-PHASE FAULT CLASSES\n');
fprintf('============================================\n');

originalClassOrder = ...
    ["Normal","LG","LL","LLG","LLL","LLLG"];

classOrder = ...
    ["Normal","LG","LL","LLG","Three_Phase_Fault"];

% Verify the original six classes exist.

if ~all(ismember(originalClassOrder,unique(YOriginal))) || ...
   ~all(ismember(unique(YOriginal),originalClassOrder))

    error('Original dataset does not contain the expected six classes.');

end

% Merge LLL and LLLG.

Y = YOriginal;

Y(Y=="LLL" | Y=="LLLG") = "Three_Phase_Fault";

% Verify the five-class labels.

if ~all(ismember(unique(Y),classOrder)) || ...
   ~all(ismember(classOrder,unique(Y)))

    error('Five-class label conversion failed.');

end

fprintf('\nOriginal class distribution:\n');

for k = 1:numel(originalClassOrder)

    fprintf('%-8s : %d\n', ...
        originalClassOrder(k), ...
        sum(YOriginal==originalClassOrder(k)));

end

fprintf('\nNew five-class distribution:\n');

for k = 1:numel(classOrder)

    fprintf('%-20s : %d\n', ...
        classOrder(k),sum(Y==classOrder(k)));

end

fprintf('\nOriginal samples : %d\n',numel(YOriginal));
fprintf('Features         : %d\n',size(X,2));
fprintf('New classes      : %d\n',numel(classOrder));
fprintf('Scenario groups  : %d\n',numel(unique(scenarioGroups)));

fprintf('\nLLL and LLLG successfully merged.\n');


%% 4. SCENARIO-WISE TRAIN / VALIDATION / TEST SPLIT

fprintf('\n============================================\n');
fprintf(' SCENARIO-WISE DATA SPLITTING\n');
fprintf('============================================\n');

% Split after label merging.
% All windows from one simulation remain together.

[trainMask,valMask,testMask] = ...
    groupedSplit(Y,scenarioGroups,classOrder);

XTrain = X(trainMask,:);
YTrain = Y(trainMask);

XVal = X(valMask,:);
YVal = Y(valMask);

XTest = X(testMask,:);
YTest = Y(testMask);

fprintf('\nTraining samples  : %d\n',size(XTrain,1));
fprintf('Validation samples: %d\n',size(XVal,1));
fprintf('Testing samples   : %d\n',size(XTest,1));

trainGroups = unique(scenarioGroups(trainMask));
valGroups = unique(scenarioGroups(valMask));
testGroups = unique(scenarioGroups(testMask));

fprintf('\nScenario groups:\n');
fprintf('Training  : %d\n',numel(trainGroups));
fprintf('Validation: %d\n',numel(valGroups));
fprintf('Testing   : %d\n',numel(testGroups));

% Verify no group leakage.

if ~isempty(intersect(trainGroups,valGroups)) || ...
   ~isempty(intersect(trainGroups,testGroups)) || ...
   ~isempty(intersect(valGroups,testGroups))

    error('Scenario leakage detected between partitions.');

end

if ~all(trainMask | valMask | testMask)
    error('Some samples were not assigned to a partition.');
end

fprintf('\nScenario leakage check passed.\n');


%% 5. CLASS DISTRIBUTION

fprintf('\n============================================\n');
fprintf(' CLASS DISTRIBUTION BY PARTITION\n');
fprintf('============================================\n');

for k = 1:numel(classOrder)

    fprintf('\n%s\n',classOrder(k));

    fprintf(' Train      : %d\n',sum(YTrain==classOrder(k)));

    fprintf(' Validation : %d\n',sum(YVal==classOrder(k)));

    fprintf(' Test       : %d\n',sum(YTest==classOrder(k)));

end


%% 6. DEFINE CLASSIFIERS

modelNames = { ...
    'Bagged Trees', ...
    'Gaussian SVM', ...
    'AdaBoostM2'};

numberOfModels = numel(modelNames);

results = table('Size',[0 7], ...
    'VariableTypes',{ ...
    'string','double','double','double', ...
    'double','double','double'}, ...
    'VariableNames',{ ...
    'Model', ...
    'ValidationAccuracy', ...
    'ValidationMacroPrecision', ...
    'ValidationMacroRecall', ...
    'ValidationMacroF1', ...
    'TestAccuracy', ...
    'TestMacroF1'});

trainedModels = struct();

confusionMatrices = struct();

perClassResults = struct();


%% 7. TRAIN AND EVALUATE CLASSIFIERS

for m = 1:numberOfModels

    modelName = modelNames{m};

    fprintf('\n============================================\n');
    fprintf(' TRAINING: %s\n',modelName);
    fprintf('============================================\n');

    try

        %% Train using training partition.

        model = trainClassifier( ...
            modelName,XTrain,YTrain);

        %% Validation evaluation.

        valPrediction = predict(model,XVal);

        valPrediction = string(valPrediction);

        valMetrics = calculateMetrics( ...
            YVal,valPrediction,classOrder);

        fprintf('\nValidation Accuracy: %.2f%%\n', ...
            valMetrics.Accuracy*100);

        fprintf('Validation Macro Precision: %.2f%%\n', ...
            valMetrics.MacroPrecision*100);

        fprintf('Validation Macro Recall: %.2f%%\n', ...
            valMetrics.MacroRecall*100);

        fprintf('Validation Macro F1: %.2f%%\n', ...
            valMetrics.MacroF1*100);


        %% Refit using training + validation data.

        % Test data remains untouched.

        XDevelopment = [XTrain;XVal];

        YDevelopment = [YTrain;YVal];

        finalModel = trainClassifier( ...
            modelName,XDevelopment,YDevelopment);


        %% Independent test evaluation.

        testPrediction = predict(finalModel,XTest);

        testPrediction = string(testPrediction);

        testMetrics = calculateMetrics( ...
            YTest,testPrediction,classOrder);

        fprintf('\nTest Accuracy: %.2f%%\n', ...
            testMetrics.Accuracy*100);

        fprintf('Test Macro Precision: %.2f%%\n', ...
            testMetrics.MacroPrecision*100);

        fprintf('Test Macro Recall: %.2f%%\n', ...
            testMetrics.MacroRecall*100);

        fprintf('Test Macro F1: %.2f%%\n', ...
            testMetrics.MacroF1*100);


        %% Save final model.

        modelField = matlab.lang.makeValidName( ...
            strrep(modelName,' ','_'));

        trainedModels.(modelField) = finalModel;


        %% Save confusion matrix.

        confusionMatrices.(modelField) = ...
            testMetrics.ConfusionMatrix;


        %% Save per-class metrics.

        perClassResults.(modelField) = table( ...
            classOrder(:), ...
            testMetrics.Precision(:), ...
            testMetrics.Recall(:), ...
            testMetrics.F1(:), ...
            testMetrics.Support(:), ...
            'VariableNames',{ ...
            'Class','Precision','Recall','F1','Support'});


        %% Append comparison results.

        newResult = table( ...
            string(modelName), ...
            valMetrics.Accuracy, ...
            valMetrics.MacroPrecision, ...
            valMetrics.MacroRecall, ...
            valMetrics.MacroF1, ...
            testMetrics.Accuracy, ...
            testMetrics.MacroF1, ...
            'VariableNames',results.Properties.VariableNames);

        results = [results;newResult];

        fprintf('\n%s completed successfully.\n',modelName);

    catch ME

        fprintf(2,'\nERROR training %s:\n%s\n', ...
            modelName,ME.message);

        fprintf(2,'This classifier will be skipped.\n');

    end

end


%% 8. MODEL COMPARISON

fprintf('\n============================================\n');
fprintf(' FIVE-CLASS MODEL COMPARISON\n');
fprintf('============================================\n');

if isempty(results)
    error('All classifiers failed. No results available.');
end

disp(results);


%% 9. IDENTIFY BEST MODEL USING VALIDATION MACRO F1

% Do not select the best model using test performance.
% The test set is reserved for final independent evaluation.

[~,bestIndex] = max(results.ValidationMacroF1);

bestModelName = results.Model(bestIndex);

fprintf('\nBest model based on Validation Macro F1:\n');

fprintf('%s\n',bestModelName);

fprintf('Validation Macro F1: %.2f%%\n', ...
    results.ValidationMacroF1(bestIndex)*100);

fprintf('Independent Test Macro F1: %.2f%%\n', ...
    results.TestMacroF1(bestIndex)*100);


%% 10. PER-CLASS TEST PERFORMANCE

fprintf('\n============================================\n');
fprintf(' PER-CLASS TEST PERFORMANCE\n');
fprintf('============================================\n');

modelFields = fieldnames(perClassResults);

for k = 1:numel(modelFields)

    fprintf('\n%s\n',modelFields{k});

    disp(perClassResults.(modelFields{k}));

end


%% 11. CONFUSION MATRICES

fprintf('\nGenerating five-class confusion matrices...\n');

for k = 1:numel(modelFields)

    modelField = modelFields{k};

    C = confusionMatrices.(modelField);

    fig = figure( ...
        'Name',modelField, ...
        'Color','w');

    imagesc(C);

    colorbar;

    axis square;

    xticks(1:numel(classOrder));
    yticks(1:numel(classOrder));

    xticklabels(classOrder);
    yticklabels(classOrder);

    xtickangle(30);

    xlabel('Predicted Class');
    ylabel('Actual Class');

    title(['Five-Class Confusion Matrix - ', ...
        strrep(modelField,'_',' ')]);

    for i = 1:size(C,1)

        for j = 1:size(C,2)

            text(j,i,num2str(C(i,j)), ...
                'HorizontalAlignment','center', ...
                'FontWeight','bold');

        end

    end

    figureFile = fullfile(outputFolder, ...
        ['Confusion_Matrix_5Class_',modelField,'.png']);

    saveas(fig,figureFile);

end


%% 12. SAVE RESULTS

% Separate filenames preserve the original six-class results.

resultsFile = fullfile(outputFolder, ...
    'Fault_Classification_Results_5Class.mat');

resultsCSV = fullfile(outputFolder, ...
    'Fault_Classification_Comparison_5Class.csv');

splitFile = fullfile(outputFolder, ...
    'Scenario_Wise_Data_Split_5Class.mat');

classMapping = ...
    "LLL and LLLG merged into Three_Phase_Fault";

save(resultsFile, ...
    'trainedModels', ...
    'results', ...
    'confusionMatrices', ...
    'perClassResults', ...
    'classOrder', ...
    'originalClassOrder', ...
    'classMapping', ...
    'bestModelName', ...
    'featureNames', ...
    '-v7.3');

writetable(results,resultsCSV);

save(splitFile, ...
    'trainMask', ...
    'valMask', ...
    'testMask', ...
    'trainGroups', ...
    'valGroups', ...
    'testGroups', ...
    'classOrder', ...
    'originalClassOrder', ...
    'classMapping');


%% 13. FINAL SUMMARY

fprintf('\n============================================\n');
fprintf(' FIVE-CLASS MACHINE LEARNING COMPLETED\n');
fprintf('============================================\n');

fprintf('\nModels successfully trained: %d/%d\n', ...
    height(results),numberOfModels);

fprintf('\nClassification classes:\n');

for k = 1:numel(classOrder)
    fprintf('%d. %s\n',k,classOrder(k));
end

fprintf('\nBest model: %s\n',bestModelName);

fprintf('\nResults saved:\n%s\n',resultsFile);

fprintf('\nComparison CSV:\n%s\n',resultsCSV);

fprintf('\nData split saved:\n%s\n',splitFile);

fprintf('\nOutput folder:\n%s\n',outputFolder);

fprintf('\nNo Simulink simulations were performed.\n');

fprintf('\n============================================\n');


%% LOCAL FUNCTION 1: GROUPED DATA SPLITTING

function [trainMask,valMask,testMask] = ...
    groupedSplit(Y,groups,classOrder)

    n = numel(Y);

    trainMask = false(n,1);
    valMask = false(n,1);
    testMask = false(n,1);

    for c = 1:numel(classOrder)

        className = classOrder(c);

        classMask = Y==className;

        classGroups = unique(groups(classMask));

        % Every scenario group must contain only one class.

        for g = 1:numel(classGroups)

            groupMask = groups==classGroups(g);

            if numel(unique(Y(groupMask))) ~= 1

                error('Scenario group contains multiple classes.');

            end

        end

        numberOfGroups = numel(classGroups);

        if numberOfGroups < 3

            error('Class %s has fewer than 3 scenario groups.', ...
                className);

        end

        % Shuffle scenario groups.

        order = randperm(numberOfGroups);

        classGroups = classGroups(order);

        % 60% training, 20% validation, remaining testing.

        nTrain = floor(0.60*numberOfGroups);

        nVal = floor(0.20*numberOfGroups);

        nTest = numberOfGroups-nTrain-nVal;

        if nTrain < 1 || nVal < 1 || nTest < 1

            error('Insufficient scenario groups for class %s.', ...
                className);

        end

        trainGroupsClass = classGroups(1:nTrain);

        valGroupsClass = classGroups(nTrain+1:nTrain+nVal);

        testGroupsClass = classGroups(nTrain+nVal+1:end);

        trainMask = trainMask | ...
            ismember(groups,trainGroupsClass);

        valMask = valMask | ...
            ismember(groups,valGroupsClass);

        testMask = testMask | ...
            ismember(groups,testGroupsClass);

        fprintf('%-20s: Train %2d | Validation %2d | Test %2d groups\n', ...
            className,nTrain,nVal,nTest);

    end

    if any(trainMask & valMask) || ...
       any(trainMask & testMask) || ...
       any(valMask & testMask)

        error('Overlapping data partitions detected.');

    end

    if ~all(trainMask | valMask | testMask)

        error('Some samples were not assigned to a partition.');

    end

end


%% LOCAL FUNCTION 2: TRAIN CLASSIFIER

function model = trainClassifier(modelName,XTrain,YTrain)

    YTrain = categorical(YTrain);

    tree = templateTree( ...
        'MaxNumSplits',50);

    switch modelName

        case 'Bagged Trees'

            model = fitcensemble( ...
                XTrain,YTrain, ...
                'Method','Bag', ...
                'NumLearningCycles',150, ...
                'Learners',tree);

        case 'Gaussian SVM'

            svmTemplate = templateSVM( ...
                'KernelFunction','gaussian', ...
                'KernelScale','auto', ...
                'Standardize',true);

            model = fitcecoc( ...
                XTrain,YTrain, ...
                'Learners',svmTemplate, ...
                'Coding','onevsone');

        case 'AdaBoostM2'

            model = fitcensemble( ...
                XTrain,YTrain, ...
                'Method','AdaBoostM2', ...
                'NumLearningCycles',100, ...
                'Learners',tree);

        otherwise

            error('Unknown classifier: %s',modelName);

    end

end


%% LOCAL FUNCTION 3: CALCULATE CLASSIFICATION METRICS

function metrics = calculateMetrics(YTrue,YPred,classOrder)

    YTrue = string(YTrue(:));

    YPred = string(YPred(:));

    numberOfClasses = numel(classOrder);

    C = zeros(numberOfClasses);

    % Rows: actual classes.
    % Columns: predicted classes.

    for i = 1:numberOfClasses

        for j = 1:numberOfClasses

            C(i,j) = sum( ...
                YTrue==classOrder(i) & ...
                YPred==classOrder(j));

        end

    end

    TP = diag(C);

    actualCount = sum(C,2);

    predictedCount = sum(C,1)';

    precision = TP ./ max(predictedCount,1);

    recall = TP ./ max(actualCount,1);

    f1 = 2*(precision.*recall) ./ ...
        max(precision+recall,eps);

    accuracy = sum(TP)/max(sum(C(:)),1);

    macroPrecision = mean(precision);

    macroRecall = mean(recall);

    macroF1 = mean(f1);

    metrics.Accuracy = accuracy;

    metrics.MacroPrecision = macroPrecision;

    metrics.MacroRecall = macroRecall;

    metrics.MacroF1 = macroF1;

    metrics.Precision = precision;

    metrics.Recall = recall;

    metrics.F1 = f1;

    metrics.Support = actualCount;

    metrics.ConfusionMatrix = C;

end
