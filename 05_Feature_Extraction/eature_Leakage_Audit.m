
%% FEATURE LEAKAGE AUDIT - STEP 2
% 132 kV Transmission Line Fault Classification
%
% Read-only audit. Does not retrain models or run Simulink.
%
% Checks:
% 1. X-to-datasetTable feature alignment
% 2. Metadata exclusion from X
% 3. Scenario group and class consistency
% 4. Exact and near-duplicate feature rows across groups
% 5. Within-group feature variation
% 6. Individual feature/class association
%
% Output: audit reports in 05_Feature_Extraction\Audit_Results

clc;
clear;
close all;

%% 1. Paths and load

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

dataFile = fullfile(projectRoot, ...
    '05_Feature_Extraction', ...
    'MultiScenario_Fault_Feature_Dataset.mat');

if ~isfile(dataFile)
    error('Dataset not found: %s', dataFile);
end

outDir = fullfile(projectRoot, ...
    '05_Feature_Extraction', 'Audit_Results');

if ~exist(outDir, 'dir')
    mkdir(outDir);
end

D = load(dataFile);

required = {'X','Y','datasetTable','featureNames', ...
    'scenarioGroups','scenarioIDs'};

for k = 1:numel(required)
    if ~isfield(D, required{k})
        error('Missing required variable: %s', required{k});
    end
end

X = D.X;
Y = string(D.Y(:));
T = D.datasetTable;
featureNames = string(D.featureNames(:))';
groups = string(D.scenarioGroups(:));
scenarioIDs = string(D.scenarioIDs(:));

[nRows,nFeatures] = size(X);

if numel(Y) ~= nRows || numel(groups) ~= nRows || ...
        numel(scenarioIDs) ~= nRows
    error('Row-count mismatch between X, Y, groups, or scenarioIDs.');
end

fprintf('\n============================================\n');
fprintf('       FEATURE LEAKAGE AUDIT - STEP 2\n');
fprintf('============================================\n');

%% 2. Verify X matches only the 60 feature columns

fprintf('\n--- CHECK 1: FEATURE COLUMN ALIGNMENT ---\n');

tableNames = string(T.Properties.VariableNames);

missingFeatures = setdiff(featureNames, tableNames);

if ~isempty(missingFeatures)
    disp('Feature names missing from datasetTable:');
    disp(missingFeatures);
    error('Feature alignment cannot be verified.');
end

XfromTable = T{:, cellstr(featureNames)};

if ~isnumeric(XfromTable)
    error('Selected feature columns are not all numeric.');
end

if ~isequal(size(X), size(XfromTable))
    error('X and selected table feature dimensions do not match.');
end

maxAbsDifference = max(abs(X(:) - XfromTable(:)));
fprintf('X dimensions: %d x %d\n', size(X,1), size(X,2));
fprintf('Maximum absolute difference: %.12g\n', maxAbsDifference);

if isequaln(X, XfromTable)
    fprintf('PASS: X exactly matches the named feature columns.\n');
else
    fprintf('WARNING: X does not exactly match table feature columns.\n');
end

metadataNames = ["Class","ScenarioGroup","ScenarioID", ...
    "FaultResistance_Ohm","FaultInception_s","FaultLocation_km"];

fprintf('\nMetadata columns present in X feature names:\n');
metadataLeak = intersect(featureNames, metadataNames);

if isempty(metadataLeak)
    fprintf('None detected by column name.\n');
else
    disp(metadataLeak);
end

%% 3. Check group and label consistency

fprintf('\n--- CHECK 2: GROUP AND LABEL CONSISTENCY ---\n');

classNames = unique(Y);
groupNames = unique(groups);

fprintf('Number of rows: %d\n', nRows);
fprintf('Number of features: %d\n', nFeatures);
fprintf('Number of classes: %d\n', numel(classNames));
fprintf('Number of scenario groups: %d\n', numel(groupNames));

classCount = zeros(numel(classNames),1);

for k = 1:numel(classNames)
    classCount(k) = sum(Y == classNames(k));
    fprintf('%-20s %d rows\n', classNames(k), classCount(k));
end

groupClassErrors = 0;
groupIDErrors = 0;

for k = 1:numel(groupNames)

    idx = groups == groupNames(k);

    if numel(unique(Y(idx))) ~= 1
        groupClassErrors = groupClassErrors + 1;
        fprintf('WARNING: Group has multiple labels: %s\n', ...
            groupNames(k));
    end

    if numel(unique(scenarioIDs(idx))) ~= 1
        groupIDErrors = groupIDErrors + 1;
        fprintf('WARNING: Group has multiple scenario IDs: %s\n', ...
            groupNames(k));
    end
end

fprintf('Groups with multiple class labels: %d\n', groupClassErrors);
fprintf('Groups with multiple scenario IDs: %d\n', groupIDErrors);

if isequal(groups, scenarioIDs)
    fprintf('ScenarioGroups and scenarioIDs are identical row by row.\n');
else
    fprintf('WARNING: ScenarioGroups and scenarioIDs differ.\n');
end

%% 4. Exact duplicate rows across different groups

fprintf('\n--- CHECK 3: EXACT DUPLICATES ACROSS GROUPS ---\n');

[~,~,exactIndex] = unique(X, 'rows');

exactCrossGroupKeys = 0;
exactCrossGroupRows = 0;

for k = 1:max(exactIndex)

    idx = exactIndex == k;

    if sum(idx) > 1 && numel(unique(groups(idx))) > 1
        exactCrossGroupKeys = exactCrossGroupKeys + 1;
        exactCrossGroupRows = exactCrossGroupRows + sum(idx);
    end
end

fprintf('Exact duplicate feature patterns spanning groups: %d\n', ...
    exactCrossGroupKeys);
fprintf('Rows involved in those patterns: %d\n', ...
    exactCrossGroupRows);

%% 5. Near duplicates across different groups
% Normalize each feature to [0,1], then round to 8 decimal places.
% This is a screening test, not proof of identical raw signals.

fprintf('\n--- CHECK 4: NEAR DUPLICATES ACROSS GROUPS ---\n');

featureMin = min(X,[],1);
featureMax = max(X,[],1);
featureRange = featureMax - featureMin;

safeRange = featureRange;
safeRange(safeRange == 0) = 1;

Xscaled = (X - featureMin) ./ safeRange;
Xkey = round(Xscaled, 8);

[~,~,nearIndex] = unique(Xkey, 'rows');

nearCrossGroupKeys = 0;
nearCrossGroupRows = 0;

for k = 1:max(nearIndex)

    idx = nearIndex == k;

    if sum(idx) > 1 && numel(unique(groups(idx))) > 1
        nearCrossGroupKeys = nearCrossGroupKeys + 1;
        nearCrossGroupRows = nearCrossGroupRows + sum(idx);
    end
end

fprintf('Near-duplicate patterns spanning groups: %d\n', ...
    nearCrossGroupKeys);
fprintf('Rows involved in those patterns: %d\n', ...
    nearCrossGroupRows);
fprintf('Near-duplicate tolerance: 1e-8 of each feature range.\n');

%% 6. Within-group variation

fprintf('\n--- CHECK 5: WITHIN-GROUP FEATURE VARIATION ---\n');

groupRows = zeros(numel(groupNames),1);
groupMeanStd = zeros(numel(groupNames),1);
groupMaxStd = zeros(numel(groupNames),1);
groupUniqueRows = zeros(numel(groupNames),1);
groupLabels = strings(numel(groupNames),1);

for k = 1:numel(groupNames)

    idx = groups == groupNames(k);
    Xg = X(idx,:);

    groupRows(k) = sum(idx);
    groupMeanStd(k) = mean(std(Xg,0,1));
    groupMaxStd(k) = max(std(Xg,0,1));
    groupUniqueRows(k) = size(unique(Xg,'rows'),1);
    groupLabels(k) = unique(Y(idx));

end

groupReport = table(groupNames, groupLabels, groupRows, ...
    groupUniqueRows, groupMeanStd, groupMaxStd, ...
    'VariableNames', {'ScenarioGroup','Class','WindowCount', ...
    'UniqueFeatureRows','MeanFeatureStd','MaximumFeatureStd'});

disp('Groups with lowest mean feature variation:');
groupReport = sortrows(groupReport, 'MeanFeatureStd', 'ascend');
disp(groupReport(1:min(15,height(groupReport)),:));

writetable(groupReport, fullfile(outDir, ...
    'Within_Group_Variation.csv'));

%% 7. Individual feature/class association
% One-way ANOVA eta-squared:
% eta^2 = between-class sum of squares / total sum of squares.
% High eta-squared means a feature is strongly associated with class.
% It does NOT, by itself, prove leakage.

fprintf('\n--- CHECK 6: INDIVIDUAL FEATURE CLASS ASSOCIATION ---\n');

etaSquared = zeros(nFeatures,1);
betweenSS = zeros(nFeatures,1);
withinSS = zeros(nFeatures,1);

for j = 1:nFeatures

    x = X(:,j);
    grandMean = mean(x);

    ssBetween = 0;
    ssWithin = 0;

    for k = 1:numel(classNames)

        idx = Y == classNames(k);
        xClass = x(idx);

        ssBetween = ssBetween + ...
            sum(idx) * (mean(xClass) - grandMean)^2;

        ssWithin = ssWithin + ...
            sum((xClass - mean(xClass)).^2);
    end

    totalSS = ssBetween + ssWithin;

    if totalSS > 0
        etaSquared(j) = ssBetween / totalSS;
    else
        etaSquared(j) = NaN;
    end

    betweenSS(j) = ssBetween;
    withinSS(j) = ssWithin;
end

featureReport = table(featureNames(:), etaSquared, ...
    betweenSS, withinSS, ...
    'VariableNames', {'Feature','EtaSquared', ...
    'BetweenClassSS','WithinClassSS'});

featureReport = sortrows(featureReport, ...
    'EtaSquared', 'descend');

fprintf('Top 15 individual features by eta-squared:\n');
disp(featureReport(1:min(15,height(featureReport)),:));

writetable(featureReport, fullfile(outDir, ...
    'Feature_Class_Association.csv'));

%% 8. Check normal-condition variation specifically

fprintf('\n--- CHECK 7: NORMAL CONDITION VARIATION ---\n');

normalIdx = Y == "Normal";
Xnormal = X(normalIdx,:);
normalGroups = unique(groups(normalIdx));

fprintf('Normal rows: %d\n', sum(normalIdx));
fprintf('Normal scenario groups: %d\n', numel(normalGroups));
fprintf('Unique normal feature rows: %d\n', ...
    size(unique(Xnormal,'rows'),1));

for k = 1:numel(normalGroups)

    idx = normalIdx & groups == normalGroups(k);
    Xg = X(idx,:);

    fprintf('%-20s rows=%3d, unique rows=%3d, mean feature std=%.12g\n', ...
        normalGroups(k), sum(idx), ...
        size(unique(Xg,'rows'),1), ...
        mean(std(Xg,0,1)));
end

%% 9. Save audit summary

summaryFile = fullfile(outDir, 'Audit_Summary.txt');
fid = fopen(summaryFile,'w');

if fid < 0
    warning('Could not create audit summary text file.');
else

    fprintf(fid, 'FEATURE LEAKAGE AUDIT - STEP 2\n\n');
    fprintf(fid, 'Rows: %d\n', nRows);
    fprintf(fid, 'Features: %d\n', nFeatures);
    fprintf(fid, 'Classes: %d\n', numel(classNames));
    fprintf(fid, 'Scenario groups: %d\n', numel(groupNames));
    fprintf(fid, 'Maximum X/table feature difference: %.12g\n', ...
        maxAbsDifference);
    fprintf(fid, 'Exact cross-group duplicate patterns: %d\n', ...
        exactCrossGroupKeys);
    fprintf(fid, 'Near cross-group duplicate patterns: %d\n', ...
        nearCrossGroupKeys);
    fprintf(fid, 'Groups with multiple labels: %d\n', ...
        groupClassErrors);
    fprintf(fid, 'Groups with multiple scenario IDs: %d\n', ...
        groupIDErrors);
    fprintf(fid, 'Normal unique feature rows: %d\n', ...
        size(unique(Xnormal,'rows'),1));

    fclose(fid);
end

fprintf('\n============================================\n');
fprintf('STEP 2 AUDIT COMPLETED\n');
fprintf('Reports saved in:\n%s\n', outDir);
fprintf('Original dataset was not modified.\n');
fprintf('============================================\n');
