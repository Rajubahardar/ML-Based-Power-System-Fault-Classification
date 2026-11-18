
%% ================================================================
% MEASUREMENT NOISE ROBUSTNESS TEST
%
% Noise is added to raw voltage and current waveforms BEFORE
% feature extraction.
%
% Training data: Clean waveforms
% Testing data: Clean and noisy waveforms
%
% Noise levels: 0, 0.1, 0.5, 1, 2, 5 percent
%
% Models:
%   1. Bagged Trees
%   2. Gaussian SVM
%
% Five classes:
%   Normal, LG, LL, LLG, Three_Phase_Fault
%
% Three unseen-location folds:
%   Fold 1: Test 20 km
%   Fold 2: Test 50 km
%   Fold 3: Test 80 km
%
% No Simulink simulations are performed.
%% ================================================================

clc;
clear;
close all;

rng(42,'twister');

fprintf('\n============================================\n');
fprintf('      NOISE ROBUSTNESS TEST\n');
fprintf('============================================\n');

%% 1. PATH CONFIGURATION

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

faultFolder = fullfile(projectRoot, ...
    '04_Data_Generation', ...
    'MultiScenario_Fault_Data');

normalFolder = fullfile(projectRoot, ...
    '04_Data_Generation', ...
    'Normal_MultiScenario_Data');

outputFolder = fullfile(projectRoot, ...
    '06_Machine_Learning', ...
    'Noise_Robustness_Results');

if ~exist(outputFolder,'dir')
    mkdir(outputFolder);
end

if ~isfolder(faultFolder)
    error('Fault data folder not found: %s',faultFolder);
end

if ~isfolder(normalFolder)
    error('Normal data folder not found: %s',normalFolder);
end

%% 2. EXPERIMENT SETTINGS

windowDuration = 0.020;
stepDuration = 0.005;

normalStart = 0.20;
normalEnd = 0.40;

noiseLevels = [0 0.1 0.5 1 2 5];

expectedLocations = [20;50;80];

classOrder = [ ...
    "Normal"
    "LG"
    "LL"
    "LLG"
    "Three_Phase_Fault"
    ];

numTrees = 150;

%% 3. LOAD RAW WAVEFORM FILES

faultFiles = dir(fullfile(faultFolder,'*.mat'));
normalFiles = dir(fullfile(normalFolder,'*.mat'));

fprintf('\nFault MAT files found: %d\n',numel(faultFiles));
fprintf('Normal MAT files found: %d\n',numel(normalFiles));

if isempty(faultFiles) || isempty(normalFiles)
    error('No MAT files found in one or both data folders.');
end

scenarioData = struct([]);
scenarioCount = 0;

%% 4. READ FAULT SCENARIOS

fprintf('\nLoading fault waveforms...\n');

for k = 1:numel(faultFiles)

    filePath = fullfile(faultFiles(k).folder, ...
        faultFiles(k).name);

    S = load(filePath);

    required = {'Vabc_S','Iabc_S','Vabc_R','Iabc_R', ...
        'faultTypeSaved','faultStartSaved','faultEndSaved', ...
        'faultLocationSaved'};

    if ~all(isfield(S,required))
        continue;
    end

    scenarioCount = scenarioCount + 1;

    scenarioData(scenarioCount).Vabc_S = S.Vabc_S;
    scenarioData(scenarioCount).Iabc_S = S.Iabc_S;
    scenarioData(scenarioCount).Vabc_R = S.Vabc_R;
    scenarioData(scenarioCount).Iabc_R = S.Iabc_R;

    scenarioData(scenarioCount).Class = ...
        string(S.faultTypeSaved);

    scenarioData(scenarioCount).Class = ...
        strtrim(scenarioData(scenarioCount).Class);

    scenarioData(scenarioCount).Class = ...
        replace(scenarioData(scenarioCount).Class," ","");

    if ismember(scenarioData(scenarioCount).Class,["LLL","LLLG"])
        scenarioData(scenarioCount).Class = "Three_Phase_Fault";
    end

    scenarioData(scenarioCount).Group = ...
        getScenarioID(S,filePath);

    scenarioData(scenarioCount).Location = ...
        double(S.faultLocationSaved);

    scenarioData(scenarioCount).StartTime = ...
        double(S.faultStartSaved);

    scenarioData(scenarioCount).EndTime = ...
        double(S.faultEndSaved);

    scenarioData(scenarioCount).IsNormal = false;

end

%% 5. READ NORMAL SCENARIOS

fprintf('Loading normal waveforms...\n');

for k = 1:numel(normalFiles)

    filePath = fullfile(normalFiles(k).folder, ...
        normalFiles(k).name);

    S = load(filePath);

    required = {'Vabc_S','Iabc_S','Vabc_R','Iabc_R'};

    if ~all(isfield(S,required))
        continue;
    end

    scenarioCount = scenarioCount + 1;

    scenarioData(scenarioCount).Vabc_S = S.Vabc_S;
    scenarioData(scenarioCount).Iabc_S = S.Iabc_S;
    scenarioData(scenarioCount).Vabc_R = S.Vabc_R;
    scenarioData(scenarioCount).Iabc_R = S.Iabc_R;

    scenarioData(scenarioCount).Class = "Normal";

    scenarioData(scenarioCount).Group = ...
        getScenarioID(S,filePath);

    scenarioData(scenarioCount).Location = NaN;

    scenarioData(scenarioCount).StartTime = normalStart;
    scenarioData(scenarioCount).EndTime = normalEnd;

    scenarioData(scenarioCount).IsNormal = true;

end

if isempty(scenarioData)
    error('No valid waveform scenarios were loaded.');
end

fprintf('\nValid scenarios loaded: %d\n',scenarioCount);

%% 6. EXTRACT CLEAN FEATURES FROM EVERY SCENARIO

fprintf('\nExtracting clean waveform features...\n');

XClean = [];
Y = strings(0,1);
groups = strings(0,1);
locations = [];

for g = 1:scenarioCount

    fprintf('Processing %d/%d: %s\n', ...
        g,scenarioCount,scenarioData(g).Group);

    signals = getSignalData(scenarioData(g));

    [features,numberOfWindows] = extractFeatures( ...
        signals, ...
        scenarioData(g).StartTime, ...
        scenarioData(g).EndTime, ...
        windowDuration, ...
        stepDuration);

    if numberOfWindows == 0
        error('No feature windows extracted for %s.', ...
            scenarioData(g).Group);
    end

    XClean = [XClean;features];

    Y = [Y;repmat(scenarioData(g).Class,numberOfWindows,1)];

    groups = [groups; ...
        repmat(scenarioData(g).Group,numberOfWindows,1)];

    locations = [locations; ...
        repmat(scenarioData(g).Location,numberOfWindows,1)];

end

fprintf('\nClean feature dataset created.\n');
fprintf('Total windows: %d\n',size(XClean,1));
fprintf('Total features: %d\n',size(XClean,2));

%% 7. VERIFY DATASET

if any(~isfinite(XClean),'all')
    error('Extracted features contain NaN or Inf.');
end

if any(~ismember(unique(Y),classOrder))
    error('Unexpected class label found.');
end

uniqueGroups = unique(groups);

groupClass = strings(numel(uniqueGroups),1);
groupLocation = nan(numel(uniqueGroups),1);

for g = 1:numel(uniqueGroups)

    idx = groups == uniqueGroups(g);

    groupClass(g) = unique(Y(idx));

    loc = unique(locations(idx));

    if groupClass(g) == "Normal"
        groupLocation(g) = NaN;
    else
        loc = loc(~isnan(loc));

        if numel(loc) ~= 1
            error('Inconsistent location in group %s.', ...
                uniqueGroups(g));
        end

        groupLocation(g) = loc;
    end
end

normalGroups = uniqueGroups(groupClass == "Normal");

if numel(normalGroups) < 3
    error('At least three normal scenario groups are required.');
end

%% 8. NORMAL GROUP ALLOCATION

normalGroups = sort(normalGroups);

normalTestFold = mod((0:numel(normalGroups)-1)',3)+1;

%% 9. MODEL CONFIGURATION

treeTemplate = templateTree( ...
    'MaxNumSplits',50);

svmTemplate = templateSVM( ...
    'KernelFunction','gaussian', ...
    'KernelScale','auto', ...
    'Standardize',true);

modelNames = ["Bagged_Trees","Gaussian_SVM"];

numFolds = 3;
numModels = 2;

%% 10. RESULT STORAGE

allResults = table();

confusionResults = struct([]);

resultCounter = 0;

%% 11. THREE LOCATION FOLDS

for fold = 1:numFolds

    heldOutLocation = expectedLocations(fold);

    fprintf('\n============================================\n');
    fprintf('FOLD %d - HELD OUT LOCATION: %d km\n', ...
        fold,heldOutLocation);
    fprintf('============================================\n');

    %% SELECT GROUPS

    trainFaultGroups = uniqueGroups( ...
        groupClass ~= "Normal" & ...
        groupLocation ~= heldOutLocation);

    testFaultGroups = uniqueGroups( ...
        groupClass ~= "Normal" & ...
        groupLocation == heldOutLocation);

    testNormalGroups = normalGroups(normalTestFold == fold);

    trainNormalGroups = normalGroups(normalTestFold ~= fold);

    trainGroups = [trainFaultGroups;trainNormalGroups];

    testGroups = [testFaultGroups;testNormalGroups];

    trainMask = ismember(groups,trainGroups);
    testMask = ismember(groups,testGroups);

    if any(ismember(unique(groups(trainMask)), ...
            unique(groups(testMask))))
        error('Group leakage detected in fold %d.',fold);
    end

    XTrain = XClean(trainMask,:);
    YTrain = Y(trainMask);

    XTestClean = XClean(testMask,:);
    YTest = Y(testMask);

    testGroupLabels = groups(testMask);

    fprintf('Training windows: %d\n',size(XTrain,1));
    fprintf('Testing windows: %d\n',size(XTestClean,1));

    %% TRAIN MODELS ON CLEAN DATA

    models = cell(numModels,1);

    for m = 1:numModels

        fprintf('\nTraining %s...\n',modelNames(m));

        switch m

            case 1

                models{m} = fitcensemble( ...
                    XTrain,YTrain, ...
                    'Method','Bag', ...
                    'NumLearningCycles',numTrees, ...
                    'Learners',treeTemplate);

            case 2

                models{m} = fitcecoc( ...
                    XTrain,YTrain, ...
                    'Learners',svmTemplate, ...
                    'Coding','onevsone');

        end

    end

    %% TEST EACH NOISE LEVEL

    for n = 1:numel(noiseLevels)

        noisePercent = noiseLevels(n);

        fprintf('\n--------------------------------------------\n');
        fprintf('Noise level: %.1f%%\n',noisePercent);
        fprintf('--------------------------------------------\n');

        XTestNoisy = XTestClean;

        %% ADD NOISE TO RAW TEST WAVEFORMS

        if noisePercent > 0

            XTestNoisy = [];

            testScenarioIndices = find( ...
                ismember([scenarioData.Group],testGroups));

            for s = 1:numel(testScenarioIndices)

                scenarioIndex = testScenarioIndices(s);

                signals = getSignalData( ...
                    scenarioData(scenarioIndex));

                % Reproducible independent noise for each
                % scenario and noise level.
                streamSeed = 10000*fold + ...
                    100*n + scenarioIndex;

                noiseStream = RandStream('mt19937ar', ...
                    'Seed',streamSeed);

                noisySignals = addMeasurementNoise( ...
                    signals,noisePercent,noiseStream);

                [noisyFeatures,~] = extractFeatures( ...
                    noisySignals, ...
                    scenarioData(scenarioIndex).StartTime, ...
                    scenarioData(scenarioIndex).EndTime, ...
                    windowDuration, ...
                    stepDuration);

                XTestNoisy = [XTestNoisy;noisyFeatures];

            end

        end

        if size(XTestNoisy,1) ~= numel(YTest)
            error(['Noisy feature count does not match test labels. ' ...
                'Check scenario ordering and window extraction.']);
        end

        %% EVALUATE BOTH MODELS

        for m = 1:numModels

            predicted = string(predict(models{m},XTestNoisy));

            C = confusionmat( ...
                categorical(YTest,classOrder), ...
                categorical(predicted,classOrder), ...
                'Order',categorical(classOrder,classOrder));

            TP = diag(C);

            FP = sum(C,1)' - TP;
            FN = sum(C,2) - TP;

            precision = TP ./ (TP+FP);
            recall = TP ./ (TP+FN);

            precision(isnan(precision)) = 0;
            recall(isnan(recall)) = 0;

            F1 = 2.*precision.*recall ./ ...
                (precision+recall);

            F1(isnan(F1)) = 0;

            accuracy = sum(TP)/sum(C(:));
            macroF1 = mean(F1);

            fprintf('%s: Accuracy = %.4f, Macro F1 = %.4f\n', ...
                modelNames(m),accuracy,macroF1);

            %% SAVE METRICS

            resultCounter = resultCounter+1;

            allResults = [allResults;table( ...
                fold, ...
                heldOutLocation, ...
                noisePercent, ...
                modelNames(m), ...
                accuracy, ...
                macroF1, ...
                'VariableNames', ...
                {'Fold','HeldOutLocation_km','NoisePercent', ...
                'Model','Accuracy','MacroF1'})];

            %% SAVE CONFUSION MATRIX

            confusionResults(resultCounter).Fold = fold;
            confusionResults(resultCounter).NoisePercent = noisePercent;
            confusionResults(resultCounter).Model = modelNames(m);
            confusionResults(resultCounter).ConfusionMatrix = C;

            %% SAVE PREDICTIONS

            predictionTable = table( ...
                repmat(fold,numel(YTest),1), ...
                repmat(heldOutLocation,numel(YTest),1), ...
                repmat(noisePercent,numel(YTest),1), ...
                repmat(modelNames(m),numel(YTest),1), ...
                testGroupLabels, ...
                YTest, ...
                predicted, ...
                'VariableNames', ...
                {'Fold','HeldOutLocation_km','NoisePercent', ...
                'Model','ScenarioGroup','ActualClass', ...
                'PredictedClass'});

            predictionFile = fullfile(outputFolder, ...
                sprintf('Predictions_Fold%d_Noise%.1f_%s.csv', ...
                fold,noisePercent,modelNames(m)));

            writetable(predictionTable,predictionFile);

            %% SAVE CONFUSION MATRIX IMAGE

            fig = figure('Visible','off');

            confusionchart(C,cellstr(classOrder));

            title(sprintf('%s | Fold %d | Noise %.1f%%', ...
                modelNames(m),fold,noisePercent));

            imageFile = fullfile(outputFolder, ...
                sprintf('CM_Fold%d_Noise%.1f_%s.png', ...
                fold,noisePercent,modelNames(m)));

            exportgraphics(fig,imageFile,'Resolution',200);

            close(fig);

        end
    end
end

%% 12. SAVE MAIN RESULTS

writetable(allResults,fullfile(outputFolder, ...
    'Noise_Robustness_All_Results.csv'));

save(fullfile(outputFolder, ...
    'Noise_Robustness_Complete_Results.mat'), ...
    'allResults','confusionResults','noiseLevels', ...
    'expectedLocations','classOrder');

%% 13. CALCULATE MEAN PERFORMANCE ACROSS FOLDS

summaryResults = table();

for m = 1:numModels

    for n = 1:numel(noiseLevels)

        idx = allResults.Model == modelNames(m) & ...
            allResults.NoisePercent == noiseLevels(n);

        rows = allResults(idx,:);

        summaryResults = [summaryResults;table( ...
            modelNames(m), ...
            noiseLevels(n), ...
            mean(rows.Accuracy), ...
            std(rows.Accuracy), ...
            mean(rows.MacroF1), ...
            std(rows.MacroF1), ...
            'VariableNames', ...
            {'Model','NoisePercent','MeanAccuracy', ...
            'StdAccuracy','MeanMacroF1','StdMacroF1'})];

    end
end

writetable(summaryResults,fullfile(outputFolder, ...
    'Noise_Robustness_Summary.csv'));

%% 14. PLOT ACCURACY VS NOISE

for m = 1:numModels

    idx = summaryResults.Model == modelNames(m);

    rows = summaryResults(idx,:);

    fig = figure('Visible','off');

    errorbar(rows.NoisePercent, ...
        rows.MeanAccuracy*100, ...
        rows.StdAccuracy*100, ...
        '-o','LineWidth',1.5);

    xlabel('Measurement noise (%)');
    ylabel('Mean accuracy (%)');

    title(sprintf('%s - Accuracy vs Measurement Noise', ...
        modelNames(m)));

    grid on;

    saveas(fig,fullfile(outputFolder, ...
        sprintf('Accuracy_vs_Noise_%s.png',modelNames(m))));

    close(fig);

end

%% 15. PLOT MACRO F1 VS NOISE

for m = 1:numModels

    idx = summaryResults.Model == modelNames(m);

    rows = summaryResults(idx,:);

    fig = figure('Visible','off');

    errorbar(rows.NoisePercent, ...
        rows.MeanMacroF1*100, ...
        rows.StdMacroF1*100, ...
        '-o','LineWidth',1.5);

    xlabel('Measurement noise (%)');
    ylabel('Mean macro F1 (%)');

    title(sprintf('%s - Macro F1 vs Measurement Noise', ...
        modelNames(m)));

    grid on;

    saveas(fig,fullfile(outputFolder, ...
        sprintf('MacroF1_vs_Noise_%s.png',modelNames(m))));

    close(fig);

end

%% 16. DISPLAY SUMMARY

fprintf('\n============================================\n');
fprintf('NOISE ROBUSTNESS SUMMARY\n');
fprintf('============================================\n');

disp(summaryResults);

fprintf('\nResults saved in:\n%s\n',outputFolder);

fprintf('\n============================================\n');
fprintf('NOISE ROBUSTNESS TEST COMPLETED\n');
fprintf('============================================\n');


%% ================================================================
% LOCAL FUNCTIONS
%% ================================================================

function groupID = getScenarioID(S,filePath)

    if isfield(S,'scenarioID')
        groupID = string(S.scenarioID);
    else
        [~,groupID,~] = fileparts(filePath);
        groupID = string(groupID);
    end

    groupID = strtrim(groupID);

end


function signals = getSignalData(S)

    names = {'Vabc_S','Iabc_S','Vabc_R','Iabc_R'};

    for k = 1:numel(names)

        ts = S.(names{k});

        if ~isa(ts,'timeseries')
            error('%s is not a timeseries object.',names{k});
        end

        t = double(ts.Time(:));
        data = double(squeeze(ts.Data));

        if size(data,1) == 3 && size(data,2) ~= 3
            data = data';
        end

        if size(data,2) ~= 3
            error('%s must contain three phase columns.',names{k});
        end

        if size(data,1) ~= numel(t)
            error('Time and data dimensions do not match for %s.', ...
                names{k});
        end

        if any(~isfinite(data),'all')
            error('Non-finite values found in %s.',names{k});
        end

        signals.(names{k}).Time = t;
        signals.(names{k}).Data = data;

    end

    referenceTime = signals.Vabc_S.Time;

    for k = 2:numel(names)

        if numel(signals.(names{k}).Time) ~= numel(referenceTime) || ...
                any(abs(signals.(names{k}).Time-referenceTime) > 1e-10)

            error('The four signals do not share the same time vector.');
        end

    end

end


function noisySignals = addMeasurementNoise(signals,noisePercent,stream)

    names = {'Vabc_S','Iabc_S','Vabc_R','Iabc_R'};

    noisySignals = signals;

    noiseFraction = noisePercent/100;

    for k = 1:numel(names)

        name = names{k};

        original = signals.(name).Data;

        % Independent Gaussian noise for each phase.
        phaseRMS = sqrt(mean(original.^2,1));

        noiseSigma = noiseFraction.*phaseRMS;

        noise = randn(stream,size(original));

        noise = noise.*noiseSigma;

        noisySignals.(name).Data = original+noise;

    end

end


function [features,numWindows] = extractFeatures( ...
    signals,startTime,endTime,windowDuration,stepDuration)

    signalNames = {'Vabc_S','Iabc_S','Vabc_R','Iabc_R'};

    time = signals.Vabc_S.Time;

    firstStart = startTime;
    lastStart = endTime-windowDuration;

    windowStarts = firstStart:stepDuration: ...
        (lastStart+1e-10);

    features = [];

    for w = 1:numel(windowStarts)

        t1 = windowStarts(w);
        t2 = t1+windowDuration;

        sampleMask = time >= t1 & time < t2;

        if sum(sampleMask) < 2
            continue;
        end

        row = [];

        for s = 1:numel(signalNames)

            data = signals.(signalNames{s}).Data(sampleMask,:);

            for phase = 1:3

                x = data(:,phase);

                rmsValue = sqrt(mean(x.^2));
                meanAbs = mean(abs(x));
                stdValue = std(x,0);
                peakAbs = max(abs(x));
                peakToPeak = max(x)-min(x);

                row = [row, ...
                    rmsValue, ...
                    meanAbs, ...
                    stdValue, ...
                    peakAbs, ...
                    peakToPeak];

            end
        end

        features = [features;row];

    end

    numWindows = size(features,1);

end
