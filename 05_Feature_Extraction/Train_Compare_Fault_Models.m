
%% STEP 5 — TRAIN BAGGED TREES AND GAUSSIAN SVM

clc;
clearvars;

projectDir = 'D:\MATLAB_Projects\TL_Fault_AI';
featureDir = fullfile(projectDir,'05_Feature_Extraction');

datasetFile = fullfile(featureDir, ...
    'MultiScenario_Fault_Feature_Dataset.mat');

splitFile = fullfile(featureDir, ...
    'GroupWise_Split_Indices.mat');

load(datasetFile,'X','Y','featureNames');
load(splitFile,'trainIdx','valIdx','testIdx');

%% Prepare data

XTrain = X(trainIdx,:);
YTrain = categorical(Y(trainIdx));

XVal = X(valIdx,:);
YVal = categorical(Y(valIdx));

XTest = X(testIdx,:);
YTest = categorical(Y(testIdx));

classNames = categories(YTrain);

fprintf('\nTraining samples: %d\n',size(XTrain,1));
fprintf('Validation samples: %d\n',size(XVal,1));
fprintf('Testing samples: %d\n',size(XTest,1));

%% Standardize features using training data only

mu = mean(XTrain,1);
sigma = std(XTrain,0,1);
sigma(sigma == 0) = 1;

XTrainScaled = (XTrain-mu)./sigma;
XValScaled = (XVal-mu)./sigma;
XTestScaled = (XTest-mu)./sigma;

%% MODEL 1 — BAGGED TREES

fprintf('\nTraining Bagged Trees...\n');

treeTemplate = templateTree( ...
    'MaxNumSplits',50);

baggedModel = fitcensemble( ...
    XTrain,YTrain, ...
    'Method','Bag', ...
    'NumLearningCycles',100, ...
    'Learners',treeTemplate);

predBagVal = predict(baggedModel,XVal);

bagValidationAccuracy = ...
    mean(predBagVal == YVal)*100;

fprintf('Bagged Trees validation accuracy: %.2f%%\n', ...
    bagValidationAccuracy);

%% MODEL 2 — GAUSSIAN SVM

fprintf('\nTraining Gaussian SVM...\n');

svmModel = fitcecoc( ...
    XTrainScaled,YTrain, ...
    'Learners',templateSVM( ...
        'KernelFunction','gaussian', ...
        'KernelScale','auto', ...
        'Standardize',false), ...
    'Coding','onevsone');

predSVMVal = predict(svmModel,XValScaled);

svmValidationAccuracy = ...
    mean(predSVMVal == YVal)*100;

fprintf('Gaussian SVM validation accuracy: %.2f%%\n', ...
    svmValidationAccuracy);

%% Save trained models

modelFile = fullfile(featureDir, ...
    'Trained_Fault_Classification_Models.mat');

save(modelFile, ...
    'baggedModel','svmModel', ...
    'mu','sigma','classNames','featureNames', ...
    'bagValidationAccuracy','svmValidationAccuracy', ...
    '-v7.3');

fprintf('\nBoth models trained and saved.\n');
fprintf('Model file: %s\n',modelFile);
fprintf('\nSTEP 5 COMPLETED.\n');
