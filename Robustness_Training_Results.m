
%% CONTROLLED ROBUSTNESS EXPERIMENT
% Compare clean training, noise-augmented training,
% and mixed-contamination training.
% Models: Bagged Trees and Gaussian SVM.

clearvars;
clc;

%% 1. LOAD DATA
S = load('Dataset_25K_Noise_Outlier.mat','Dataset25K');
D = S.Dataset25K;

F = double(D.X);
Y = string(D.Y(:));
C = lower(string(D.contamination(:)));

trainIdx = D.trainIdx(:);
valIdx   = D.valIdx(:);
testIdx  = D.testIdx(:);

classNames = string(D.classNames(:));
classCells = cellstr(classNames);

% Identify contamination categories
isClean = contains(C,'clean');
isNoise = contains(C,'noise');
isOutlier = contains(C,'outlier');

% Check categories
fprintf('\nCONTAMINATION COUNTS\n');
fprintf('Clean: %d\n',sum(isClean));
fprintf('Noise: %d\n',sum(isNoise));
fprintf('Outliers: %d\n',sum(isOutlier));

%% 2. DEFINE TRAINING CONDITIONS
% Experiment A: clean training samples
% Experiment B: clean + noisy training samples
% Experiment C: all training samples

expNames = ["A_Clean";"B_Clean_Noise";"C_Mixed"];

trainMasks = {
    isClean(trainIdx)
    isClean(trainIdx) | isNoise(trainIdx)
    true(numel(trainIdx),1)
};

% Use validation samples for model configuration selection.
% Validation set is not used for final test scoring.
valFeatures = F(valIdx,:);
valLabels = categorical(Y(valIdx),classCells,classCells);

testFeatures = F(testIdx,:);
testLabels = categorical(Y(testIdx),classCells,classCells);

testClean = isClean(testIdx);
testNoise = isNoise(testIdx);
testOutlier = isOutlier(testIdx);

testMasks = {testClean,testNoise,testOutlier};
testGroupNames = ["Clean";"Noise";"Outlier"];

%% 3. RESULT STORAGE
resultRows = {};

%% 4. RUN THREE EXPERIMENTS
for e = 1:3

    fprintf('\n====================================\n');
    fprintf('EXPERIMENT %s\n',expNames(e));
    fprintf('====================================\n');

    selectedTrain = trainIdx(trainMasks{e});

    Xtrain = F(selectedTrain,:);
    Ytrain = categorical(Y(selectedTrain),classCells,classCells);

    fprintf('Training samples: %d\n',numel(selectedTrain));

    %% Standardization for SVM: training samples only
    mu = mean(Xtrain,1);
    sd = std(Xtrain,0,1);
    sd(sd==0) = 1;

    XtrainSVM = (Xtrain-mu)./sd;
    XvalSVM = (valFeatures-mu)./sd;
    XtestSVM = (testFeatures-mu)./sd;

    %% BAGGED TREES
    fprintf('\nTraining Bagged Trees...\n');

    BT = fitcensemble( ...
        Xtrain,Ytrain, ...
        'Method','Bag', ...
        'NumLearningCycles',100, ...
        'Learners',templateTree('MaxNumSplits',50));

    %% GAUSSIAN SVM
    fprintf('Training Gaussian SVM...\n');

    svmTemplate = templateSVM( ...
        'KernelFunction','gaussian', ...
        'KernelScale','auto', ...
        'BoxConstraint',1, ...
        'Standardize',false);

    SVM = fitcecoc( ...
        XtrainSVM,Ytrain, ...
        'Learners',svmTemplate, ...
        'Coding','onevsone');

    %% 5. EVALUATE ON EACH TEST CATEGORY
    for g = 1:3

        mask = testMasks{g};

        if ~any(mask)
            continue;
        end

        actual = testLabels(mask);

        % Bagged Trees predictions
        predBT = predict(BT,testFeatures(mask,:));

        % Gaussian SVM predictions
        predSVM = predict(SVM,XtestSVM(mask,:));

        [accBT,f1BT] = localScore(actual,predBT,classNames);
        [accSVM,f1SVM] = localScore(actual,predSVM,classNames);

        resultRows(end+1,:) = { ...
            char(expNames(e)), ...
            char(testGroupNames(g)), ...
            sum(mask), ...
            100*accBT, ...
            f1BT, ...
            100*accSVM, ...
            f1SVM};

        fprintf('\n%s TEST SAMPLES: %d\n', ...
            testGroupNames(g),sum(mask));

        fprintf('Bagged Trees: Accuracy %.2f%% | Macro-F1 %.4f\n', ...
            100*accBT,f1BT);

        fprintf('Gaussian SVM: Accuracy %.2f%% | Macro-F1 %.4f\n', ...
            100*accSVM,f1SVM);
    end

    clear BT SVM Xtrain XtrainSVM XvalSVM XtestSVM;
end

%% 6. DISPLAY COMPARISON TABLE
ResultsTable = cell2table(resultRows, ...
    'VariableNames',{ ...
    'Experiment','TestGroup','Samples', ...
    'BT_Accuracy_Percent','BT_MacroF1', ...
    'SVM_Accuracy_Percent','SVM_MacroF1'});

fprintf('\n\n========== FINAL COMPARISON ==========\n');
disp(ResultsTable);

%% 7. SAVE RESULTS
save('Controlled_Robustness_Results.mat', ...
    'ResultsTable','-v7.3');

writetable(ResultsTable, ...
    'Controlled_Robustness_Results.csv');

fprintf('\nExperiment completed.\n');
fprintf('Saved Controlled_Robustness_Results.mat\n');
fprintf('Saved Controlled_Robustness_Results.csv\n');

%% LOCAL SCORING FUNCTION
function [accuracy,macroF1] = localScore(actual,predicted,classNames)

    actual = string(actual(:));
    predicted = string(predicted(:));
    classNames = string(classNames(:));

    n = numel(classNames);
    CM = zeros(n,n);

    for i = 1:n
        for j = 1:n
            CM(i,j) = sum( ...
                actual==classNames(i) & ...
                predicted==classNames(j));
        end
    end

    accuracy = sum(diag(CM))/sum(CM,'all');

    precision = zeros(n,1);
    recall = zeros(n,1);
    F1 = zeros(n,1);

    for i = 1:n
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
            F1(i) = 2*precision(i)*recall(i)/ ...
                (precision(i)+recall(i));
        end
    end

    macroF1 = mean(F1);
end
