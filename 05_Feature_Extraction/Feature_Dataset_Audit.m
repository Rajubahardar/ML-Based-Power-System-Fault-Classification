
%% FEATURE DATASET AUDIT - STEP 1
% Project: 132 kV Transmission Line Fault Classification
% Purpose:
%   1. Inspect the saved feature dataset.
%   2. Identify feature, label, and simulation-group variables.
%   3. Check dimensions, data types, missing values, and duplicate rows.
%
% IMPORTANT:
%   This script does not modify the original dataset.
%   It does not run Simulink or train any ML model.

clc;
clear;
close all;

%% 1. Dataset location

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

datasetFile = fullfile(projectRoot, ...
    '05_Feature_Extraction', ...
    'MultiScenario_Fault_Feature_Dataset.mat');

if ~isfile(datasetFile)
    error('Dataset file not found: %s', datasetFile);
end

fprintf('\n============================================\n');
fprintf('       FEATURE DATASET AUDIT - STEP 1\n');
fprintf('============================================\n');

%% 2. Inspect MAT-file contents

fileInfo = whos('-file', datasetFile);

fprintf('\n--- VARIABLES STORED IN MAT FILE ---\n');

for k = 1:numel(fileInfo)
    fprintf('\nVariable %d\n', k);
    fprintf('Name: %s\n', fileInfo(k).name);
    fprintf('Size: %s\n', mat2str(fileInfo(k).size));
    fprintf('Class: %s\n', fileInfo(k).class);
    fprintf('Bytes: %d\n', fileInfo(k).bytes);
end

%% 3. Load dataset without modifying source file

D = load(datasetFile);

variableNames = fieldnames(D);

fprintf('\n--- VARIABLE DETAILS ---\n');

for k = 1:numel(variableNames)

    name = variableNames{k};
    value = D.(name);

    fprintf('\nVariable: %s\n', name);
    fprintf('Class: %s\n', class(value));
    fprintf('Size: %s\n', mat2str(size(value)));

    if isnumeric(value)

        fprintf('NaN count: %d\n', sum(isnan(value(:))));
        fprintf('Inf count: %d\n', sum(isinf(value(:))));

        if ~isempty(value) && isreal(value)
            fprintf('Minimum: %.6g\n', min(value(:)));
            fprintf('Maximum: %.6g\n', max(value(:)));
        end

    elseif iscategorical(value) || isstring(value) || iscellstr(value)

        try
            categoriesFound = unique(string(value));
            fprintf('Unique values:\n');
            disp(categoriesFound);
        catch
            fprintf('Could not display unique values automatically.\n');
        end

    elseif istable(value)

        fprintf('Table variable names:\n');
        disp(value.Properties.VariableNames);

        fprintf('First five rows:\n');
        disp(value(1:min(5,height(value)), :));

    elseif isstruct(value)

        fprintf('Structure fields:\n');
        disp(fieldnames(value));

    end
end

%% 4. Check duplicate rows in numeric matrices

fprintf('\n--- EXACT DUPLICATE CHECK ---\n');

for k = 1:numel(variableNames)

    name = variableNames{k};
    value = D.(name);

    if isnumeric(value) && ismatrix(value) && ...
            size(value,1) > 1 && size(value,2) > 1

        % Only check reasonably sized matrices.
        if size(value,1) <= 100000

            [~, uniqueIndices] = unique(value, 'rows');
            duplicateCount = size(value,1) - numel(uniqueIndices);

            fprintf('%s: %d exact duplicate rows\n', ...
                name, duplicateCount);
        end
    end
end

%% 5. Inspect CSV dataset, if available

csvFile = fullfile(projectRoot, ...
    '05_Feature_Extraction', ...
    'MultiScenario_Fault_Feature_Dataset.csv');

if isfile(csvFile)

    fprintf('\n--- CSV DATASET INSPECTION ---\n');

    T = readtable(csvFile);

    fprintf('CSV rows: %d\n', height(T));
    fprintf('CSV columns: %d\n', width(T));

    fprintf('\nCSV column names:\n');
    disp(T.Properties.VariableNames);

    fprintf('\nFirst five CSV rows:\n');
    disp(T(1:min(5,height(T)), :));

else
    fprintf('\nCSV file not found. MAT-file inspection completed.\n');
end

fprintf('\n============================================\n');
fprintf('STEP 1 AUDIT COMPLETED\n');
fprintf('No original files were modified.\n');
fprintf('============================================\n');
