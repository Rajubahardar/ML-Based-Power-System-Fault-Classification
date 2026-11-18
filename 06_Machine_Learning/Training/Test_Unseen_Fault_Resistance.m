
%% ROBUSTNESS TEST - CORRECTED VERSION
% Leave-One-Fault-Resistance-Out
% All 5 normal scenarios are included in the pooled test results.
%
% Models: Bagged Trees and Gaussian SVM
% No Simulink simulations are performed.

clear;
clc;
close all;

rng(42,'twister');

%% 1. PATHS

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

datasetFile = fullfile(projectRoot, ...
    '05_Feature_Extraction', ...
    'MultiScenario_Fault_Feature_Dataset.mat');

outputFolder = fullfile(projectRoot, ...
    '06_Machine_Learning');

if ~isfile(datasetFile)
    error('Dataset file not found: %s',datasetFile);
end

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

%% 2. LOAD DATA

D = load(datasetFile);

X = double(D.X);
Y = string(D.Y(:));
groups = string(D.scenarioGroups(:));

if size(X,1) ~= numel(Y) || numel(Y) ~= numel(groups)
    error('Feature, label and group dimensions do not match.');
end

if any(~isfinite(X(:)))
    error('Features contain NaN or Inf.');
end

% Merge LLL and LLLG into one three-phase class.

Y(Y=="LLL" | Y=="LLLG") = "Three_Phase_Fault";

classOrder = ["Normal","LG","LL","LLG","Three_Phase_Fault"];

if ~all(ismember(unique(Y),classOrder))
    error('Unexpected class labels found.');
end

fprintf('\nTotal samples: %d\n',size(X,1));
fprintf('Total features: %d\n',size(X,2));
fprintf('Total scenario groups: %d\n',numel(unique(groups)));

%% 3. IDENTIFY RESISTANCE FOR EACH SCENARIO GROUP

uniqueGroups = unique(groups);

groupResistance = strings(size(uniqueGroups));

for k = 1:numel(uniqueGroups)

    groupName = char(uniqueGroups(k));

    token = regexp(groupName,'_R([^_]+)_','tokens','once');

    if isempty(token)
        groupResistance(k) = "Normal";
    else
        groupResistance(k) = string(token{1});
    end

end

resistanceLevels = ["0p1","1","5"];

normalGroups = uniqueGroups(groupResistance=="Normal");

if numel(normalGroups) ~= 5
    error('Expected five normal groups, but found %d.', ...
        numel(normalGroups));
end

faultGroups = uniqueGroups(groupResistance~="Normal");

if any(groupResistance(groupResistance~="Normal") ...
        ~= resistanceLevels(1) & ...
       groupResistance(groupResistance~="Normal") ...
        ~= resistanceLevels(2) & ...
       groupResistance(groupResistance~="Normal") ...
        ~= resistanceLevels(3))

    error('Unexpected fault resistance group detected.');
end

fprintf('\nNormal scenario groups:\n');
disp(normalGroups);

%% 4. DISTRIBUTE ALL FIVE NORMAL GROUPS ACROSS THREE FOLDS

% Fold 1 tests Normal groups 1 and 2.
% Fold 2 tests Normal groups 3 and 4.
% Fold 3 tests Normal group 5.
%
% Every normal group is tested exactly once.

normalTestGroups = cell(3,1);

normalTestGroups{1} = normalGroups(1:2);
normalTestGroups{2} = normalGroups(3:4);
normalTestGroups{3} = normalGroups(5);

%% 5. INITIALIZE RESULTS

modelNames = ["Bagged Trees","Gaussian SVM"];

nClasses = numel(classOrder);
nFolds = numel(resistanceLevels);

aggregateConfusion = struct();

for m = 1:numel(modelNames)

    fieldName = matlab.lang.makeValidName( ...
        char(strrep(modelNames(m),' ','_')));

    aggregateConfusion.(fieldName) = zeros(nClasses);

end

allResults = table( ...
    'Size',[0 7], ...
    'VariableTypes',{ ...
        'double','string','string','double','double','double','double'}, ...
    'VariableNames',{ ...
        'Experiment','UnseenResistance','Model', ...
        'TrainSamples','TestSamples','Accuracy','MacroF1'});

%% 6. RUN THREE RESISTANCE EXPERIMENTS

for fold = 1:nFolds

    heldOutResistance = resistanceLevels(fold);

    fprintf('\n============================================\n');
    fprintf('EXPERIMENT %d: UNSEEN RESISTANCE %s OHM\n', ...
        fold,strrep(heldOutResistance,'p','.'));
    fprintf('============================================\n');

    %% Define test groups

    testFaultGroups = uniqueGroups( ...
        groupResistance==heldOutResistance);

    testNormalGroups = normalTestGroups{fold};

    testGroups = [testFaultGroups;testNormalGroups];

    %% Define training groups

    trainFaultGroups = uniqueGroups( ...
        groupResistance~="Normal" & ...
        groupResistance~=heldOutResistance);

    trainNormalGroups = normalGroups( ...
        ~ismember(normalGroups,testNormalGroups));

    trainGroups = [trainFaultGroups;trainNormalGroups];

    %% Create sample masks

    trainMask = ismember(groups,trainGroups);
    testMask = ismember(groups,testGroups);

    if any(trainMask & testMask)
        error('Group leakage detected in experiment %d.',fold);
    end

    if any(~(trainMask | testMask))
        error('Some samples were not assigned in experiment %d.',fold);
    end

    if numel(unique(groups(trainMask))) ~= numel(trainGroups)
        error('Training group count mismatch.');
    end

    if numel(unique(groups(testMask))) ~= numel(testGroups)
        error('Test group count mismatch.');
    end

    XTrain = X(trainMask,:);
    YTrain = Y(trainMask);

    XTest = X(testMask,:);
    YTest = Y(testMask);

    fprintf('\nTraining samples: %d\n',numel(YTrain));
    fprintf('Testing samples:  %d\n',numel(YTest));

    fprintf('Training groups: %d\n',numel(unique(groups(trainMask))));
    fprintf('Testing groups:  %d\n',numel(unique(groups(testMask))));

    fprintf('Normal groups tested in this fold:\n');
    disp(testNormalGroups);

    %% Check all five classes

    if ~all(ismember(classOrder,unique(YTrain)))
        error('Training partition is missing a class.');
    end

    if ~all(ismember(classOrder,unique(YTest)))
        error('Test partition is missing a class.');
    end

    %% Check exact feature overlap between partitions

    [commonRows,~,~] = intersect(XTrain,XTest,'rows');

    duplicateCount = size(commonRows,1);

    fprintf('Exact feature rows shared by train/test: %d\n', ...
        duplicateCount);

    if duplicateCount > 0
        warning(['Exact feature vectors occur in both partitions. ' ...
            'Investigate possible duplicated samples.']);
    end

    %% Train and evaluate models

    for m = 1:numel(modelNames)

        modelName = modelNames(m);

        fprintf('\nTraining %s...\n',modelName);

        switch modelName

            case "Bagged Trees"

                tree = templateTree('MaxNumSplits',50);

                model = fitcensemble( ...
                    XTrain,categorical(YTrain), ...
                    'Method','Bag', ...
                    'NumLearningCycles',150, ...
                    'Learners',tree);

            case "Gaussian SVM"

                svmTemplate = templateSVM( ...
                    'KernelFunction','gaussian', ...
                    'KernelScale','auto', ...
                    'Standardize',true);

                model = fitcecoc( ...
                    XTrain,categorical(YTrain), ...
                    'Learners',svmTemplate, ...
                    'Coding','onevsone');

        end

        prediction = string(predict(model,XTest));

        %% Confusion matrix

        C = zeros(nClasses);

        for i = 1:nClasses
            for j = 1:nClasses

                C(i,j) = sum( ...
                    YTest==classOrder(i) & ...
                    prediction==classOrder(j));

            end
        end

        %% Fold metrics

        TP = diag(C);
        actualCount = sum(C,2);
        predictedCount = sum(C,1)';

        precision = TP ./ max(predictedCount,1);
        recall = TP ./ max(actualCount,1);

        F1 = 2*(precision.*recall) ./ ...
            max(precision+recall,eps);

        accuracy = sum(TP)/sum(C(:));
        macroF1 = mean(F1);

        fprintf('\n%s results:\n',modelName);
        fprintf('Accuracy: %.2f%%\n',accuracy*100);
        fprintf('Macro F1: %.2f%%\n',macroF1*100);

        %% Add to pooled confusion matrix

        fieldName = matlab.lang.makeValidName( ...
            char(strrep(modelName,' ','_')));

        aggregateConfusion.(fieldName) = ...
            aggregateConfusion.(fieldName)+C;

        %% Store fold results

        newRow = table( ...
            fold, ...
            heldOutResistance, ...
            modelName, ...
            size(XTrain,1), ...
            size(XTest,1), ...
            accuracy, ...
            macroF1, ...
            'VariableNames',allResults.Properties.VariableNames);

        allResults = [allResults;newRow];

    end
end

%% 7. POOLED RESULTS

fprintf('\n============================================\n');
fprintf('POOLED ROBUSTNESS RESULTS\n');
fprintf('============================================\n');

disp(allResults);

%% 8. CALCULATE FINAL METRICS FROM POOLED CONFUSION MATRICES

pooledMetrics = table();

for m = 1:numel(modelNames)

    modelName = modelNames(m);

    fieldName = matlab.lang.makeValidName( ...
        char(strrep(modelName,' ','_')));

    C = aggregateConfusion.(fieldName);

    TP = diag(C);
    actualCount = sum(C,2);
    predictedCount = sum(C,1)';

    precision = TP ./ max(predictedCount,1);
    recall = TP ./ max(actualCount,1);

    F1 = 2*(precision.*recall) ./ ...
        max(precision+recall,eps);

    accuracy = sum(TP)/sum(C(:));
    macroF1 = mean(F1);

    fprintf('\n%s pooled results:\n',modelName);
    fprintf('Pooled accuracy: %.2f%%\n',accuracy*100);
    fprintf('Pooled macro F1: %.2f%%\n',macroF1*100);

    fprintf('\nPer-class results:\n');

    classMetrics = table( ...
        classOrder(:),precision,recall,F1,actualCount, ...
        'VariableNames',{ ...
        'Class','Precision','Recall','F1','Support'});

    disp(classMetrics);

    pooledMetrics = [pooledMetrics;table( ...
        modelName,accuracy,macroF1, ...
        'VariableNames',{'Model','PooledAccuracy','PooledMacroF1'})];

    %% Save confusion matrix image

    fig = figure('Visible','off','Color','w');

    imagesc(C);
    colorbar;
    axis square;

    xticks(1:nClasses);
    yticks(1:nClasses);

    xticklabels(cellstr(classOrder));
    yticklabels(cellstr(classOrder));

    xtickangle(30);

    xlabel('Predicted Class');
    ylabel('Actual Class');

    title(sprintf('%s - Pooled Unseen Resistance Test', ...
        char(modelName)));

    for i = 1:nClasses
        for j = 1:nClasses

            text(j,i,num2str(C(i,j)), ...
                'HorizontalAlignment','center', ...
                'FontWeight','bold');

        end
    end

    imageFile = fullfile(outputFolder, ...
        sprintf('Unseen_Resistance_%s.png',fieldName));

    exportgraphics(fig,imageFile,'Resolution',300);

    close(fig);

    %% Save confusion matrix CSV

    confusionTable = array2table(C, ...
        'RowNames',cellstr(classOrder), ...
        'VariableNames',cellstr(classOrder));

    confusionFile = fullfile(outputFolder, ...
        sprintf('Unseen_Resistance_%s_Confusion.csv',fieldName));

    writetable(confusionTable,confusionFile, ...
        'WriteRowNames',true);

end

%% 9. VERIFY TOTAL TEST COVERAGE

fprintf('\n============================================\n');
fprintf('TEST COVERAGE VERIFICATION\n');
fprintf('============================================\n');

fprintf('Expected normal windows: 185\n');
fprintf('Actual normal windows tested: %d\n', ...
    sum(Y=="Normal" & ismember(groups, ...
    vertcat(normalTestGroups{:}))));

fprintf('Expected fault windows: 2295\n');
fprintf('Total fault windows tested: %d\n', ...
    sum(Y~="Normal" & ismember(groups, ...
    uniqueGroups(groupResistance~="Normal"))));

fprintf('Expected total test windows: 2480\n');

%% 10. SAVE RESULTS

resultsMAT = fullfile(outputFolder, ...
    'Unseen_Resistance_Robustness_Results_Corrected.mat');

resultsCSV = fullfile(outputFolder, ...
    'Unseen_Resistance_Robustness_Results_Corrected.csv');

pooledCSV = fullfile(outputFolder, ...
    'Unseen_Resistance_Pooled_Metrics.csv');

save(resultsMAT, ...
    'allResults', ...
    'pooledMetrics', ...
    'aggregateConfusion', ...
    'classOrder', ...
    'resistanceLevels', ...
    'normalTestGroups');

writetable(allResults,resultsCSV);
writetable(pooledMetrics,pooledCSV);

fprintf('\n============================================\n');
fprintf('CORRECTED ROBUSTNESS TEST COMPLETED\n');
fprintf('============================================\n');

fprintf('\nResults saved in:\n%s\n',outputFolder);

fprintf('\nNo Simulink simulations were performed.\n');
