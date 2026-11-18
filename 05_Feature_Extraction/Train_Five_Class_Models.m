
clc;
clear;

%% Paths
projectPath = 'D:\MATLAB_Projects\TL_Fault_AI';
featurePath = fullfile(projectPath, '05_Feature_Extraction');

%% Load dataset and split
load(fullfile(featurePath, ...
    'Five_Class_Fault_Feature_Dataset.mat'));

load(fullfile(featurePath, ...
    'Five_Class_GroupWise_Split.mat'));

X = FiveClassDataset.X;
Y = categorical(FiveClassDataset.Y);

%% Prepare training and validation data
XTrain = X(trainIdx,:);
YTrain = Y(trainIdx);

XVal = X(valIdx,:);
YVal = Y(valIdx);

%% Standardize using training data only
mu = mean(XTrain,1);
sigma = std(XTrain,0,1);
sigma(sigma == 0) = 1;

XTrainScaled = (XTrain - mu) ./ sigma;
XValScaled = (XVal - mu) ./ sigma;

%% Model 1: Bagged Trees
fprintf('Training Bagged Trees...\n');

treeTemplate = templateTree('MaxNumSplits',50);

baggedModel = fitcensemble( ...
    XTrain, YTrain, ...
    'Method','Bag', ...
    'NumLearningCycles',100, ...
    'Learners',treeTemplate);

predBag = predict(baggedModel,XVal);

bagAccuracy = mean(predBag == YVal) * 100;

%% Model 2: Gaussian SVM
fprintf('Training Gaussian SVM...\n');

svmTemplate = templateSVM( ...
    'KernelFunction','gaussian', ...
    'KernelScale','auto', ...
    'Standardize',false);

svmModel = fitcecoc( ...
    XTrainScaled,YTrain, ...
    'Learners',svmTemplate, ...
    'Coding','onevsone');

predSVM = predict(svmModel,XValScaled);

svmAccuracy = mean(predSVM == YVal) * 100;

%% Display validation results
fprintf('\nFIVE-CLASS VALIDATION RESULTS\n');
fprintf('Bagged Trees : %.2f%%\n',bagAccuracy);
fprintf('Gaussian SVM : %.2f%%\n',svmAccuracy);

%% Save models
save(fullfile(featurePath, ...
    'Five_Class_Trained_Models.mat'), ...
    'baggedModel','svmModel','mu','sigma', ...
    'bagAccuracy','svmAccuracy','classNames');

fprintf('\nModels saved successfully.\n');
