
%% 05_RLC_Results_Audit.m
% Audit RLC parameter variation results.
% Does not run Simulink or retrain any model.

clc;
clear;
close all;

%% PATHS

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

resultsFolder = fullfile(projectRoot, ...
    '06_Machine_Learning', ...
    'RLC_Parameter_Variation_Results');

summaryFile = fullfile(resultsFolder, ...
    'RLC_Variation_Summary.csv');

classFile = fullfile(resultsFolder, ...
    'RLC_Variation_Class_Results.csv');

completeMatFile = fullfile(resultsFolder, ...
    'RLC_Parameter_Variation_Complete_Results.mat');

datasetFile = fullfile(projectRoot, ...
    '05_Feature_Extraction', ...
    'MultiScenario_Fault_Feature_Dataset.mat');

auditFolder = fullfile(resultsFolder, 'Audit_Results');

if ~exist(auditFolder, 'dir')
    mkdir(auditFolder);
end

%% CHECK FILES

fprintf('\n========================================\n');
fprintf('RLC PARAMETER VARIATION AUDIT\n');
fprintf('========================================\n');

files = {summaryFile, classFile, completeMatFile, datasetFile};

for k = 1:numel(files)
    if exist(files{k}, 'file')
        fprintf('[FOUND] %s\n', files{k});
    else
        fprintf('[MISSING] %s\n', files{k});
    end
end

if ~exist(summaryFile, 'file') || ...
   ~exist(completeMatFile, 'file') || ...
   ~exist(datasetFile, 'file')
    error('One or more required files are missing.');
end

%% LOAD BASELINE DATASET

D = load(datasetFile);

requiredVars = {'X','Y','scenarioGroups'};

for k = 1:numel(requiredVars)
    if ~isfield(D, requiredVars{k})
        error('Baseline dataset missing variable: %s', ...
            requiredVars{k});
    end
end

X = D.X;
Y = string(D.Y);
groups = string(D.scenarioGroups);

fprintf('\n--- BASELINE DATASET ---\n');
fprintf('Feature rows: %d\n', size(X,1));
fprintf('Feature columns: %d\n', size(X,2));
fprintf('Labels: %d\n', numel(Y));
fprintf('Scenario groups: %d\n', numel(unique(groups)));

baselineCount = size(X,1);

assert(size(X,1) == numel(Y), ...
    'Baseline feature and label counts do not match.');

assert(size(X,1) == numel(groups), ...
    'Baseline feature and group counts do not match.');

%% READ RLC SUMMARY

T = readtable(summaryFile);

fprintf('\n--- RLC SUMMARY ---\n');
disp(T);

requiredColumns = {'VariationType','VariationPercent', ...
    'SettingID','Model','Accuracy','MacroF1','TestSamples'};

for k = 1:numel(requiredColumns)
    if ~ismember(requiredColumns{k}, T.Properties.VariableNames)
        error('Summary CSV missing column: %s', ...
            requiredColumns{k});
    end
end

%% CHECK EXPECTED MODEL AND SETTING COUNTS

fprintf('\n--- SETTING COVERAGE ---\n');

settingNames = unique(string(T.SettingID));
modelNames = unique(string(T.Model));

fprintf('Unique parameter settings: %d\n', numel(settingNames));
fprintf('Unique models: %d\n', numel(modelNames));
fprintf('Summary rows: %d\n', height(T));

expectedRows = numel(settingNames) * numel(modelNames);

if height(T) == expectedRows
    fprintf('[PASS] Every setting has the expected model rows.\n');
else
    fprintf('[WARNING] Unexpected number of summary rows.\n');
end

%% CHECK SAMPLE COUNTS

fprintf('\n--- SAMPLE COUNT AUDIT ---\n');

T.ExpectedSamples = repmat(baselineCount, height(T), 1);
T.MissingSamples = T.ExpectedSamples - T.TestSamples;

T.SampleStatus = strings(height(T),1);

for k = 1:height(T)
    if T.TestSamples(k) == baselineCount
        T.SampleStatus(k) = "PASS";
    elseif T.TestSamples(k) < baselineCount
        T.SampleStatus(k) = "MISSING SAMPLES";
    else
        T.SampleStatus(k) = "EXCESS SAMPLES";
    end
end

disp(T(:, {'SettingID','Model','TestSamples', ...
    'ExpectedSamples','MissingSamples','SampleStatus'}));

problemRows = T(T.SampleStatus ~= "PASS", :);

if isempty(problemRows)
    fprintf('[PASS] All settings contain %d test samples.\n', ...
        baselineCount);
else
    fprintf('[WARNING] Settings with sample-count differences:\n');
    disp(problemRows);
end

%% CHECK INDUCTANCE -10 PERCENT

fprintf('\n--- INDUCTANCE -10 PERCENT CHECK ---\n');

idx = contains(string(T.SettingID), "L_-10_percent");

if any(idx)
    disp(T(idx, {'SettingID','Model','TestSamples', ...
        'MissingSamples','Accuracy','MacroF1'}));

    for k = find(idx)'
        if T.TestSamples(k) ~= baselineCount
            fprintf(['[WARNING] %s / %s: %d samples missing.\n'], ...
                string(T.SettingID(k)), ...
                string(T.Model(k)), ...
                T.MissingSamples(k));
        end
    end
else
    fprintf('Inductance -10%% setting not found.\n');
end

%% CHECK CLASS-LEVEL RESULTS

if exist(classFile, 'file')

    fprintf('\n--- CLASS-LEVEL RESULTS ---\n');

    C = readtable(classFile);
    disp(C);

    writetable(C, fullfile(auditFolder, ...
        'Class_Results_Audit_Copy.csv'));
end


%% INVENTORY COMPLETE MAT FILE

fprintf('\n--- COMPLETE MAT FILE INVENTORY ---\n');

matInfo = whos('-file', completeMatFile);

n = numel(matInfo);

variableNames = strings(n,1);
variableClasses = strings(n,1);
variableDimensions = strings(n,1);

for k = 1:n
    variableNames(k) = string(matInfo(k).name);
    variableClasses(k) = string(matInfo(k).class);
    variableDimensions(k) = string(mat2str(matInfo(k).size));
end

inventory = table( ...
    variableNames, ...
    variableClasses, ...
    variableDimensions, ...
    'VariableNames', ...
    {'Variable','Class','Dimensions'});

disp(inventory);

writetable(inventory, fullfile(auditFolder, ...
    'MAT_File_Variable_Inventory.csv'));

%% LOAD MAT RESULTS

R = load(completeMatFile);


%% LOAD MAT RESULTS AND SEARCH FOR SPLIT INFORMATION

R = load(completeMatFile);

fprintf('\n--- TRAIN / TEST SPLIT VARIABLE SEARCH ---\n');

keywords = ["train","test","predict","feature", ...
    "label","group","scenario","partition","fold"];

found = false;

for k = 1:numel(matInfo)

    variableName = string(matInfo(k).name);
    lowerName = lower(variableName);

    if any(contains(lowerName, keywords))
        fprintf('[POSSIBLE SPLIT VARIABLE] %s | %s | %s\n', ...
            variableName, ...
            string(matInfo(k).class), ...
            mat2str(matInfo(k).size));

        found = true;
    end
end

if ~found
    fprintf('No obvious split variables found at MAT-file top level.\n');
end

%% RECURSIVE STRUCTURE INSPECTION

fprintf('\n--- NESTED STRUCTURE INSPECTION ---\n');

inspectValue(R, "ROOT", 0);

%% SAVE AUDIT TABLES

writetable(T, fullfile(auditFolder, ...
    'RLC_Sample_Count_Audit.csv'));

save(fullfile(auditFolder, ...
    'RLC_Audit_Data.mat'), ...
    'T','inventory','problemRows');

%% FINAL REPORT

fprintf('\n========================================\n');
fprintf('AUDIT COMPLETED\n');
fprintf('========================================\n');

fprintf('Baseline samples: %d\n', baselineCount);
fprintf('RLC summary rows: %d\n', height(T));
fprintf('Rows with sample-count differences: %d\n', ...
    height(problemRows));

fprintf('\nIMPORTANT:\n');
fprintf(['A MAT-file variable inventory does not prove that ' ...
    'training and test data are independent.\n']);

fprintf(['The saved results must contain actual training/test ' ...
    'features or scenario IDs to verify separation.\n']);

fprintf('\nAudit folder:\n%s\n', auditFolder);

%% LOCAL FUNCTION

function inspectValue(value, path, depth)

    if depth > 5
        return;
    end

    indent = repmat(' ', 1, depth*2);

    if isstruct(value)

        fields = fieldnames(value);

        for i = 1:numel(value)
            for j = 1:numel(fields)

                fieldName = fields{j};
                fieldValue = value(i).(fieldName);

                currentPath = path + "." + string(fieldName);

                fprintf('%s%s | %s\n', ...
                    indent, currentPath, class(fieldValue));

                inspectValue(fieldValue, currentPath, depth+1);
            end
        end

    elseif istable(value)

        fprintf('%s%s | TABLE: %d rows, %d columns\n', ...
            indent, path, height(value), width(value));

        fprintf('%sColumns: %s\n', ...
            indent, strjoin(value.Properties.VariableNames, ', '));

    elseif iscell(value)

        fprintf('%s%s | CELL: %s\n', ...
            indent, path, mat2str(size(value)));

        for i = 1:min(numel(value),5)
            inspectValue(value{i}, ...
                path + "{" + string(i) + "}", depth+1);
        end

    elseif isnumeric(value) || islogical(value)

        fprintf('%s%s | %s | %s\n', ...
            indent, path, class(value), mat2str(size(value)));

    elseif isstring(value) || ischar(value) || iscategorical(value)

        fprintf('%s%s | %s | %s\n', ...
            indent, path, class(value), mat2str(size(value)));

    end
end
