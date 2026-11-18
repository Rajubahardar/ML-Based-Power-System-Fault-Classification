
clc;
clear;

%% Load original dataset
projectPath = 'D:\MATLAB_Projects\TL_Fault_AI';

datasetPath = fullfile(projectPath, ...
    '05_Feature_Extraction', ...
    'MultiScenario_Fault_Feature_Dataset.mat');

load(datasetPath);

%% Convert original labels into five classes
Y_five = string(Y);

% Merge LLL and LLLG
Y_five(Y_five == "LLL" | Y_five == "LLLG") = ...
    "Three_Phase_Fault";

%% Check class distribution
[classNames, ~, classIndex] = unique(Y_five);
classCounts = accumarray(classIndex, 1);

fprintf('\nFIVE-CLASS DATASET SUMMARY\n');
fprintf('Total samples: %d\n\n', numel(Y_five));

for k = 1:numel(classNames)
    fprintf('%-22s : %d\n', classNames(k), classCounts(k));
end

%% Save new dataset separately
FiveClassDataset = struct();

FiveClassDataset.X = X;
FiveClassDataset.Y = Y_five;
FiveClassDataset.featureNames = featureNames;
FiveClassDataset.scenarioGroups = scenarioGroups;
FiveClassDataset.scenarioIDs = scenarioIDs;
FiveClassDataset.faultInception = faultInception;
FiveClassDataset.faultLocation = faultLocation;
FiveClassDataset.faultResistance = faultResistance;

outputPath = fullfile(projectPath, ...
    '05_Feature_Extraction', ...
    'Five_Class_Fault_Feature_Dataset.mat');

save(outputPath, 'FiveClassDataset', '-v7.3');

fprintf('\nFive-class dataset saved successfully.\n');
