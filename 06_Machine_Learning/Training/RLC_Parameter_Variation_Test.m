
%% RLC PARAMETER VARIATION ROBUSTNESS TEST
% Project: AI-Based Fault Detection and Classification
% Model: Transmission_Line_132kV_Phase1
%
% Training: Original nominal 60-feature dataset.
% Testing: Independently simulated RLC variation scenarios.
%
% R, L and C are varied independently by -20%, -10%, +10%, +20%.
% Both PI line sections receive identical percentage changes.
%
% Expected per setting:
%   135 fault scenarios + 5 normal scenarios = 140 groups
%   135*17 fault windows + 5*37 normal windows = 2480 windows
%
% Completed feature datasets are reused when valid.

clc;
clear;
close all;

rng(42,'twister');

%% 1. PROJECT PATHS

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

modelFile = fullfile(projectRoot, ...
    '03_Simulink_Models', ...
    'Transmission_Line_132kV_Phase1.slx');

featureFile = fullfile(projectRoot, ...
    '05_Feature_Extraction', ...
    'MultiScenario_Fault_Feature_Dataset.mat');

outputRoot = fullfile(projectRoot,'06_Machine_Learning');

dataFolder = fullfile(projectRoot, ...
    '04_Data_Generation', ...
    'RLC_Parameter_Variation_Data');

resultFolder = fullfile(outputRoot,'result');

auditFolder = fullfile(resultFolder,'Audit_Results');

if ~isfile(modelFile)
    error('Simulink model not found: %s',modelFile);
end

if ~isfile(featureFile)
    error('Original feature dataset not found: %s',featureFile);
end

if ~isfolder(dataFolder)
    mkdir(dataFolder);
end

if ~isfolder(resultFolder)
    mkdir(resultFolder);
end

if ~isfolder(auditFolder)
    mkdir(auditFolder);
end

fprintf('\nProject paths verified.\n');

%% 2. LOAD NOMINAL TRAINING DATASET

D = load(featureFile, ...
    'X','Y','featureNames','scenarioGroups');

XTrain = double(D.X);

YOriginal = string(D.Y);

featureNames = D.featureNames;

trainingGroups = string(D.scenarioGroups);

if size(XTrain,2) ~= 60
    error('Expected 60 features; found %d.',size(XTrain,2));
end

if numel(YOriginal) ~= size(XTrain,1) || ...
   numel(trainingGroups) ~= size(XTrain,1)

    error(['Training features, labels and groups ' ...
        'have inconsistent sizes.']);
end

if any(~isfinite(XTrain(:)))
    error('Training features contain NaN or Inf.');
end

%% 3. MERGE FAULT CLASSES

% Merge LLL and LLLG into Three_Phase_Fault.

YTrainString = YOriginal;

YTrainString(YOriginal == "LLL" | ...
             YOriginal == "LLLG") = "Three_Phase_Fault";

classNames = { ...
    'Normal', ...
    'LG', ...
    'LL', ...
    'LLG', ...
    'Three_Phase_Fault'};

YTrain = categorical( ...
    YTrainString,classNames,classNames);

YTrain = reordercats(YTrain,classNames);

if any(isundefined(YTrain))
    error('Training data contains an undefined class.');
end

fprintf('\n========== NOMINAL TRAINING DATA ==========\n');

fprintf('Training samples: %d\n',size(XTrain,1));

fprintf('Number of features: %d\n',size(XTrain,2));

fprintf('Training scenario groups: %d\n', ...
    numel(unique(trainingGroups)));

trainingTable = table( ...
    string(classNames(:)), ...
    countcats(YTrain), ...
    'VariableNames',{'Class','SampleCount'});

disp(trainingTable);

%% 4. TRAIN BAGGED TREES CLASSIFIER

fprintf('\nTraining Bagged Trees...\n');

treeTemplate = templateTree( ...
    'MaxNumSplits',50);

bagModel = fitcensemble( ...
    XTrain,YTrain, ...
    'Method','Bag', ...
    'NumLearningCycles',150, ...
    'Learners',treeTemplate);

fprintf('Bagged Trees training completed.\n');

%% 5. TRAIN GAUSSIAN SVM CLASSIFIER

fprintf('\nTraining Gaussian SVM...\n');

svmTemplate = templateSVM( ...
    'KernelFunction','gaussian', ...
    'KernelScale','auto', ...
    'Standardize',true);

svmModel = fitcecoc( ...
    XTrain,YTrain, ...
    'Learners',svmTemplate, ...
    'Coding','onevsone');

fprintf('Gaussian SVM training completed.\n');

%% 6. LOAD SIMULINK MODEL

[~,modelName] = fileparts(modelFile);

if bdIsLoaded(modelName)

    loadedFile = get_param(modelName,'FileName');

    if ~strcmpi(loadedFile,modelFile)

        if strcmp(get_param(modelName,'Dirty'),'on')

            error(['The loaded model has unsaved changes. ' ...
                'Save or close it before running this experiment.']);

        end

        close_system(modelName,0);
    end
end

if ~bdIsLoaded(modelName)
    load_system(modelFile);
end

fprintf('\nLoaded Simulink model: %s\n',modelName);

%% 7. IDENTIFY PI LINE BLOCKS

line1 = [modelName '/50 km PI Line Section 1'];

line2 = [modelName '/50 km PI Line Section 2'];

if getSimulinkBlockHandle(line1) == -1 || ...
   getSimulinkBlockHandle(line2) == -1

    error('One or both PI line blocks were not found.');
end

%% 8. IDENTIFY FAULT BLOCK

faultBlocks = find_system(modelName, ...
    'LookUnderMasks','all', ...
    'FollowLinks','on', ...
    'MaskType','Three-Phase Fault');

if numel(faultBlocks) ~= 1

    error(['Expected exactly one Three-Phase Fault block; ' ...
        'found %d.'],numel(faultBlocks));

end

faultBlock = faultBlocks{1};

%% 9. IDENTIFY THREE-PHASE LOAD BLOCK

allBlocks = find_system(modelName, ...
    'LookUnderMasks','all', ...
    'FollowLinks','on', ...
    'Type','Block');

loadCandidates = {};

for k = 1:numel(allBlocks)

    try

        maskType = get_param(allBlocks{k},'MaskType');

        params = get_param(allBlocks{k},'DialogParameters');

        if strcmpi(maskType,'Three-Phase Parallel RLC Load') && ...
           isfield(params,'ActivePower') && ...
           isfield(params,'InductivePower')

            loadCandidates{end+1} = allBlocks{k}; %#ok<AGROW>

        end

    catch
    end
end

if numel(loadCandidates) ~= 1

    error(['Expected exactly one compatible three-phase load block; ' ...
        'found %d.'],numel(loadCandidates));

end

loadBlock = loadCandidates{1};

fprintf('\n========== IDENTIFIED MODEL BLOCKS ==========\n');

fprintf('Line 1: %s\n',line1);

fprintf('Line 2: %s\n',line2);

fprintf('Fault:  %s\n',faultBlock);

fprintf('Load:   %s\n',loadBlock);

%% 10. CAPTURE ORIGINAL MODEL PARAMETERS

lineParameterNames = { ...
    'Resistances', ...
    'Inductances', ...
    'Capacitances'};

original.line1Length = get_param(line1,'Length');

original.line2Length = get_param(line2,'Length');

for k = 1:numel(lineParameterNames)

    p = lineParameterNames{k};

    original.line1.(p) = get_param(line1,p);

    original.line2.(p) = get_param(line2,p);

    original.line1Numeric.(p) = ...
        str2num(original.line1.(p)); %#ok<ST2NM>

    original.line2Numeric.(p) = ...
        str2num(original.line2.(p)); %#ok<ST2NM>

    if isempty(original.line1Numeric.(p)) || ...
       isempty(original.line2Numeric.(p))

        error('Could not convert original parameter %s.',p);

    end
end

original.loadP = get_param(loadBlock,'ActivePower');

original.loadQ = get_param(loadBlock,'InductivePower');

faultParameterNames = { ...
    'FaultA', ...
    'FaultB', ...
    'FaultC', ...
    'GroundFault', ...
    'SwitchTimes', ...
    'SwitchStatus', ...
    'FaultResistance', ...
    'GroundResistance'};

for k = 1:numel(faultParameterNames)

    p = faultParameterNames{k};

    original.fault.(p) = get_param(faultBlock,p);

end

% Restore original parameters automatically if execution fails.
cleanupObject = onCleanup(@() restoreOriginal( ...
    line1,line2,faultBlock,loadBlock,original));

fprintf('\nOriginal model parameters captured.\n');

%% 11. DEFINE EXPERIMENT SETTINGS

variationPercentages = [-20 -10 10 20];

variationTypes = { ...
    'Resistance', ...
    'Inductance', ...
    'Capacitance'};

shortNames = {'R','L','C'};

faultTypes = {'LG','LL','LLG','LLL','LLLG'};

faultConfigurations = {
    'LG',   {'on','off','off','on'}
    'LL',   {'on','on','off','off'}
    'LLG',  {'on','on','off','on'}
    'LLL',  {'on','on','on','off'}
    'LLLG', {'on','on','on','on'}
};

faultResistances = [0.1 1 5];

faultInceptionTimes = [0.08 0.10 0.12];

faultLocations = [20 50 80];

faultDuration = 0.10;

stopTime = '0.40';

normalLoadLevels = [40 45 50 55 60];

powerFactor = 0.95;

expectedFaultWindows = 17;

expectedNormalWindows = 37;

totalFaultScenarios = ...
    numel(faultTypes)* ...
    numel(faultResistances)* ...
    numel(faultInceptionTimes)* ...
    numel(faultLocations);

totalNormalScenarios = numel(normalLoadLevels);

expectedGroups = ...
    totalFaultScenarios + totalNormalScenarios;

expectedWindows = ...
    totalFaultScenarios*expectedFaultWindows + ...
    totalNormalScenarios*expectedNormalWindows;

fprintf('\n========== EXPERIMENT SETTINGS ==========\n');

fprintf('RLC settings: %d\n', ...
    numel(variationTypes)*numel(variationPercentages));

fprintf('Fault scenarios per setting: %d\n', ...
    totalFaultScenarios);

fprintf('Normal scenarios per setting: %d\n', ...
    totalNormalScenarios);

fprintf('Expected groups per setting: %d\n', ...
    expectedGroups);

fprintf('Expected windows per setting: %d\n', ...
    expectedWindows);

fprintf('Maximum planned simulations: %d\n', ...
    numel(variationTypes)* ...
    numel(variationPercentages)*expectedGroups);

%% 12. INITIALIZE RESULT LOGS

summaryRows = cell(0,8);

classRows = cell(0,8);

scenarioLog = table( ...
    strings(0,1), ...
    strings(0,1), ...
    strings(0,1), ...
    strings(0,1), ...
    double.empty(0,1), ...
    double.empty(0,1), ...
    double.empty(0,1), ...
    false(0,1), ...
    zeros(0,1), ...
    strings(0,1), ...
    'VariableNames',{ ...
    'SettingID','ScenarioID','ScenarioType','FaultType', ...
    'FaultResistance','FaultInception','FaultLocation', ...
    'Success','WindowCount','ErrorMessage'});

fprintf('\nChunk 1 completed: initialization and training ready.\n');

%% 13. RUN RLC PARAMETER VARIATION EXPERIMENT

for v = 1:numel(variationTypes)

    variationType = variationTypes{v};

    shortName = shortNames{v};

    switch variationType

        case 'Resistance'
            parameterName = 'Resistances';

        case 'Inductance'
            parameterName = 'Inductances';

        case 'Capacitance'
            parameterName = 'Capacitances';

        otherwise
            error('Unknown variation type: %s',variationType);

    end

    for level = 1:numel(variationPercentages)

        percentage = variationPercentages(level);

        scaleFactor = 1 + percentage/100;

        settingID = sprintf('%s_%+03d_percent', ...
            shortName,percentage);

        fprintf('\n\n========================================\n');

        fprintf('CURRENT SETTING: %s\n',settingID);

        fprintf('========================================\n');

        %% 13.1 RESET MODEL TO ORIGINAL PARAMETERS

        % Reset all RLC parameters before applying the new variation.
        % This prevents cumulative parameter changes.

        for j = 1:numel(lineParameterNames)

            p = lineParameterNames{j};

            set_param(line1,p,original.line1.(p));

            set_param(line2,p,original.line2.(p));

        end

        set_param(line1,'Length',original.line1Length);

        set_param(line2,'Length',original.line2Length);

        set_param(loadBlock, ...
            'ActivePower',original.loadP, ...
            'InductivePower',original.loadQ);

        %% 13.2 APPLY RLC PARAMETER VARIATION

        newLine1 = ...
            original.line1Numeric.(parameterName)*scaleFactor;

        newLine2 = ...
            original.line2Numeric.(parameterName)*scaleFactor;

        set_param(line1,parameterName,mat2str(newLine1,16));

        set_param(line2,parameterName,mat2str(newLine2,16));

        % Verify the applied values.

        appliedLine1 = str2num( ...
            get_param(line1,parameterName)); %#ok<ST2NM>

        appliedLine2 = str2num( ...
            get_param(line2,parameterName)); %#ok<ST2NM>

        if isempty(appliedLine1) || isempty(appliedLine2)

            error('Could not verify applied RLC values for %s.', ...
                settingID);

        end

        if max(abs(appliedLine1(:)-newLine1(:))) > 1e-10 || ...
           max(abs(appliedLine2(:)-newLine2(:))) > 1e-10

            error('RLC parameter verification failed for %s.', ...
                settingID);

        end

        fprintf('Variation type: %s\n',variationType);

        fprintf('Variation percentage: %+.0f%%\n',percentage);

        %% 13.3 INITIALIZE TEST DATA

        XTest = zeros(0,size(XTrain,2));

        YTestString = strings(0,1);

        groupTest = strings(0,1);

        simulationSuccess = 0;

        simulationFailure = 0;

        reuseExisting = false;

        settingDataFile = fullfile(dataFolder, ...
            [settingID '_Feature_Data.mat']);

        %% 13.4 CHECK FOR PREVIOUSLY COMPLETED FEATURE DATA

        % Reuse an existing dataset only when all required variables
        % are present and the dataset passes completeness checks.

        if isfile(settingDataFile)

            fprintf('\nExisting feature dataset found:\n');

            fprintf('%s\n',settingDataFile);

            savedData = load(settingDataFile);

            requiredVariables = { ...
                'XTest', ...
                'YTestString', ...
                'groupTest', ...
                'settingID', ...
                'settingComplete', ...
                'settingScenarioLog', ...
                'actualWindows', ...
                'actualGroups'};

            variablesAvailable = all( ...
                isfield(savedData,requiredVariables));

            if variablesAvailable

                savedSettingMatches = ...
                    strcmp(savedData.settingID,settingID);

                savedDatasetComplete = ...
                    savedData.settingComplete && ...
                    savedData.actualWindows == expectedWindows && ...
                    savedData.actualGroups == expectedGroups && ...
                    size(savedData.XTest,1) == expectedWindows && ...
                    size(savedData.XTest,2) == size(XTrain,2) && ...
                    numel(savedData.YTestString) == expectedWindows && ...
                    numel(savedData.groupTest) == expectedWindows;

                savedFeaturesFinite = ...
                    all(isfinite(savedData.XTest(:)));

                savedLabelsValid = ...
                    all(ismember( ...
                    string(savedData.YTestString), ...
                    ["Normal","LG","LL","LLG","Three_Phase_Fault"]));

                if savedSettingMatches && ...
                   savedDatasetComplete && ...
                   savedFeaturesFinite && ...
                   savedLabelsValid

                    XTest = double(savedData.XTest);

                    YTestString = string(savedData.YTestString);

                    groupTest = string(savedData.groupTest);

                    settingScenarioLog = ...
                        savedData.settingScenarioLog;

                    actualWindows = size(XTest,1);

                    actualGroups = numel(unique(groupTest));

                    if actualWindows == expectedWindows && ...
                       actualGroups == expectedGroups

                        reuseExisting = true;

                        simulationSuccess = expectedGroups;

                        simulationFailure = 0;

                        scenarioLog = [scenarioLog; ...
                            settingScenarioLog]; %#ok<AGROW>

                        fprintf('\nVALID SAVED DATASET REUSED.\n');

                        fprintf('Feature windows: %d\n',actualWindows);

                        fprintf('Scenario groups: %d\n',actualGroups);

                        fprintf('New simulations required: 0\n');

                    end
                end
            end

            if ~reuseExisting

                fprintf(['Existing dataset is incomplete or failed ' ...
                    'validation.\n']);

                fprintf('The setting will be simulated again.\n');

            end

        else

            fprintf('\nNo previous feature dataset found.\n');

            fprintf('Starting new simulations.\n');

        end

        %% 13.5 GENERATE SCENARIOS ONLY IF DATASET IS NOT REUSED

        if ~reuseExisting

            %% 13.5.1 GENERATE FAULT SCENARIOS

            for f = 1:numel(faultTypes)

                faultType = faultTypes{f};

                configIndex = find(strcmp( ...
                    faultConfigurations(:,1),faultType),1);

                if isempty(configIndex)

                    error('Fault configuration not found for %s.', ...
                        faultType);

                end

                config = faultConfigurations{configIndex,2};

                for r = 1:numel(faultResistances)

                    resistance = faultResistances(r);

                    for t = 1:numel(faultInceptionTimes)

                        faultStart = faultInceptionTimes(t);

                        faultEnd = faultStart + faultDuration;

                        for loc = 1:numel(faultLocations)

                            locationKm = faultLocations(loc);

                            scenarioID = sprintf( ...
                                '%s_Fault_%s_R%s_T%s_L%03d', ...
                                settingID, ...
                                faultType, ...
                                strrep(num2str(resistance),'.','p'), ...
                                strrep(num2str(faultStart),'.','p'), ...
                                locationKm);

                            fprintf('\nRunning: %s\n',scenarioID);

                            try

                                %% Set nominal load

                                set_param(loadBlock, ...
                                    'ActivePower',original.loadP, ...
                                    'InductivePower',original.loadQ);

                                %% Set fault location

                                set_param(line1, ...
                                    'Length',num2str(locationKm));

                                set_param(line2, ...
                                    'Length',num2str(100-locationKm));

                                %% Configure fault block

                                set_param(faultBlock, ...
                                    'FaultA',config{1}, ...
                                    'FaultB',config{2}, ...
                                    'FaultC',config{3}, ...
                                    'GroundFault',config{4}, ...
                                    'FaultResistance', ...
                                    num2str(resistance,16), ...
                                    'GroundResistance', ...
                                    num2str(resistance,16), ...
                                    'SwitchTimes', ...
                                    mat2str([faultStart faultEnd],16), ...
                                    'SwitchStatus','[1 0]');

                                %% Run Simulink simulation

                                simOut = sim(modelName, ...
                                    'StopTime',stopTime, ...
                                    'ReturnWorkspaceOutputs','on');

                                %% Extract simulation signals

                                signals = getSignals(simOut);

                                %% Extract fault features

                                [Xnew,~] = extractFeatures( ...
                                    signals,faultStart,faultEnd);

                                if size(Xnew,1) ~= expectedFaultWindows

                                    error(['Expected %d fault windows; ' ...
                                        'extracted %d.'], ...
                                        expectedFaultWindows, ...
                                        size(Xnew,1));

                                end

                                if size(Xnew,2) ~= size(XTrain,2)

                                    error(['Feature dimension mismatch. ' ...
                                        'Expected %d features; got %d.'], ...
                                        size(XTrain,2),size(Xnew,2));

                                end

                                %% Save raw simulation data

                                Vabc_S = signals{1};

                                Iabc_S = signals{2};

                                Vabc_R = signals{3};

                                Iabc_R = signals{4};

                                faultTypeSaved = faultType;

                                faultResistanceSaved = resistance;

                                faultStartSaved = faultStart;

                                faultEndSaved = faultEnd;

                                faultLocationSaved = locationKm;

                                variationTypeSaved = variationType;

                                variationPercentSaved = percentage;

                                variationSettingSaved = settingID;

                                outputFile = fullfile(dataFolder, ...
                                    [scenarioID '.mat']);

                                save(outputFile, ...
                                    'Vabc_S','Iabc_S', ...
                                    'Vabc_R','Iabc_R', ...
                                    'faultTypeSaved', ...
                                    'faultResistanceSaved', ...
                                    'faultStartSaved', ...
                                    'faultEndSaved', ...
                                    'faultLocationSaved', ...
                                    'variationTypeSaved', ...
                                    'variationPercentSaved', ...
                                    'variationSettingSaved', ...
                                    'scenarioID','-v7.3');

                                %% Append features

                                XTest = [XTest;Xnew]; %#ok<AGROW>

                                mappedClass = faultType;

                                if strcmp(faultType,'LLL') || ...
                                   strcmp(faultType,'LLLG')

                                    mappedClass = 'Three_Phase_Fault';

                                end

                                YTestString = [YTestString; ...
                                    repmat(string(mappedClass), ...
                                    size(Xnew,1),1)]; %#ok<AGROW>

                                groupTest = [groupTest; ...
                                    repmat(string(scenarioID), ...
                                    size(Xnew,1),1)]; %#ok<AGROW>

                                simulationSuccess = ...
                                    simulationSuccess + 1;

                                scenarioLog = [scenarioLog; ...
                                    makeScenarioLogRow( ...
                                    settingID, ...
                                    scenarioID, ...
                                    'Fault', ...
                                    faultType, ...
                                    resistance, ...
                                    faultStart, ...
                                    locationKm, ...
                                    true, ...
                                    size(Xnew,1), ...
                                    "")]; %#ok<AGROW>

                                fprintf('SUCCESS: %d windows\n', ...
                                    size(Xnew,1));

                            catch ME

                                simulationFailure = ...
                                    simulationFailure + 1;

                                scenarioLog = [scenarioLog; ...
                                    makeScenarioLogRow( ...
                                    settingID, ...
                                    scenarioID, ...
                                    'Fault', ...
                                    faultType, ...
                                    resistance, ...
                                    faultStart, ...
                                    locationKm, ...
                                    false, ...
                                    0, ...
                                    string(ME.message))]; %#ok<AGROW>

                                warning( ...
                                    'Fault scenario failed: %s\n%s', ...
                                    scenarioID,ME.message);

                            end

                        end
                    end
                end
            end

            %% END OF FAULT SCENARIO GENERATION

            % Chunk 3 continues here with normal scenario simulations,
            % feature dataset validation and classifier evaluation.


            %% 13.5.2 GENERATE NORMAL SCENARIOS

            for n = 1:numel(normalLoadLevels)

                P_MW = normalLoadLevels(n);

                P_W = P_MW*1e6;

                Q_var = P_W*tan(acos(powerFactor));

                scenarioID = sprintf( ...
                    '%s_Normal_%02dMW',settingID,P_MW);

                fprintf('\nRunning: %s\n',scenarioID);

                try

                    %% Set nominal line location

                    set_param(line1,'Length','50');

                    set_param(line2,'Length','50');

                    %% Disable all fault phases

                    set_param(faultBlock, ...
                        'FaultA','off', ...
                        'FaultB','off', ...
                        'FaultC','off', ...
                        'GroundFault','off');

                    %% Set normal load

                    set_param(loadBlock, ...
                        'ActivePower',num2str(P_W,16), ...
                        'InductivePower',num2str(Q_var,16));

                    %% Run simulation

                    simOut = sim(modelName, ...
                        'StopTime',stopTime, ...
                        'ReturnWorkspaceOutputs','on');

                    %% Extract signals

                    signals = getSignals(simOut);

                    %% Extract normal features

                    [Xnew,~] = extractFeatures(signals,0.20,0.40);

                    if size(Xnew,1) ~= expectedNormalWindows

                        error(['Expected %d normal windows; ' ...
                            'extracted %d.'], ...
                            expectedNormalWindows,size(Xnew,1));

                    end

                    if size(Xnew,2) ~= size(XTrain,2)

                        error('Normal feature dimension mismatch.');

                    end

                    %% Save raw normal simulation data

                    Vabc_S = signals{1};

                    Iabc_S = signals{2};

                    Vabc_R = signals{3};

                    Iabc_R = signals{4};

                    loadPowerSaved = P_MW;

                    reactivePowerSaved = Q_var;

                    powerFactorSaved = powerFactor;

                    variationTypeSaved = variationType;

                    variationPercentSaved = percentage;

                    variationSettingSaved = settingID;

                    outputFile = fullfile(dataFolder, ...
                        [scenarioID '.mat']);

                    save(outputFile, ...
                        'Vabc_S','Iabc_S','Vabc_R','Iabc_R', ...
                        'loadPowerSaved', ...
                        'reactivePowerSaved', ...
                        'powerFactorSaved', ...
                        'variationTypeSaved', ...
                        'variationPercentSaved', ...
                        'variationSettingSaved', ...
                        'scenarioID','-v7.3');

                    %% Append features and labels

                    XTest = [XTest;Xnew]; %#ok<AGROW>

                    YTestString = [YTestString; ...
                        repmat("Normal",size(Xnew,1),1)]; %#ok<AGROW>

                    groupTest = [groupTest; ...
                        repmat(string(scenarioID), ...
                        size(Xnew,1),1)]; %#ok<AGROW>

                    simulationSuccess = simulationSuccess+1;

                    scenarioLog = [scenarioLog; ...
                        makeScenarioLogRow( ...
                        settingID, ...
                        scenarioID, ...
                        'Normal', ...
                        'Normal', ...
                        NaN,NaN,NaN, ...
                        true, ...
                        size(Xnew,1), ...
                        "")]; %#ok<AGROW>

                    fprintf('SUCCESS: %d windows\n',size(Xnew,1));

                catch ME

                    simulationFailure = simulationFailure+1;

                    scenarioLog = [scenarioLog; ...
                        makeScenarioLogRow( ...
                        settingID, ...
                        scenarioID, ...
                        'Normal', ...
                        'Normal', ...
                        NaN,NaN,NaN, ...
                        false,0, ...
                        string(ME.message))]; %#ok<AGROW>

                    warning('Normal scenario failed: %s\n%s', ...
                        scenarioID,ME.message);

                end
            end

            %% 13.5.3 CREATE SETTING AUDIT TABLE

            settingScenarioLog = scenarioLog( ...
                scenarioLog.SettingID == string(settingID),:);

            %% 13.5.4 COUNT ACTUAL GROUPS AND WINDOWS

            actualWindows = size(XTest,1);

            actualGroups = numel(unique(groupTest));

            %% 13.5.5 VERIFY SCENARIO EXECUTION

            settingComplete = ...
                actualWindows == expectedWindows && ...
                actualGroups == expectedGroups && ...
                simulationSuccess == expectedGroups && ...
                simulationFailure == 0;

            %% 13.5.6 SAVE FEATURE DATASET

            save(settingDataFile, ...
                'XTest', ...
                'YTestString', ...
                'groupTest', ...
                'variationType', ...
                'percentage', ...
                'settingID', ...
                'featureNames', ...
                'trainingGroups', ...
                'expectedWindows', ...
                'expectedGroups', ...
                'actualWindows', ...
                'actualGroups', ...
                'settingComplete', ...
                'settingScenarioLog', ...
                '-v7.3');

            fprintf('\nFeature dataset saved:\n%s\n',settingDataFile);

        else

            %% EXISTING FEATURE DATASET WAS REUSED

            % The scenario log was loaded from the saved dataset.
            % No new simulations or duplicate audit entries are needed.

            settingScenarioLog = scenarioLog( ...
                scenarioLog.SettingID == string(settingID),:);

            actualWindows = size(XTest,1);

            actualGroups = numel(unique(groupTest));

            settingComplete = ...
                actualWindows == expectedWindows && ...
                actualGroups == expectedGroups;

        end

        %% 13.6 SAVE CUMULATIVE SCENARIO AUDIT

        writetable(scenarioLog,fullfile(auditFolder, ...
            'RLC_Scenario_Execution_Log.csv'));

        %% 13.7 DISPLAY SETTING AUDIT

        fprintf('\n========== SETTING AUDIT: %s ==========\n',settingID);

        fprintf('Successful simulations: %d\n',simulationSuccess);

        fprintf('Failed simulations: %d\n',simulationFailure);

        fprintf('Actual feature windows: %d / %d\n', ...
            actualWindows,expectedWindows);

        fprintf('Actual scenario groups: %d / %d\n', ...
            actualGroups,expectedGroups);

        %% 13.8 VALIDATE DATASET COMPLETENESS

        if ~settingComplete

            warning(['SETTING %s IS INCOMPLETE. ' ...
                'Classifier evaluation will be skipped.'],settingID);

            fprintf('\nScenario problems for %s:\n',settingID);

            problemRows = settingScenarioLog( ...
                ~settingScenarioLog.Success | ...
                settingScenarioLog.WindowCount == 0,:);

            disp(problemRows);

            %% Save progress before continuing

            save(fullfile(resultFolder,'RLC_Progress_Backup.mat'), ...
                'summaryRows', ...
                'classRows', ...
                'scenarioLog', ...
                'variationTypes', ...
                'variationPercentages', ...
                'classNames', ...
                'featureNames', ...
                '-v7.3');

            continue;

        end

        %% 13.9 CHECK FEATURE DIMENSIONS AND VALUES

        if size(XTest,2) ~= size(XTrain,2)

            error(['Training and testing feature dimensions ' ...
                'do not match for %s.'],settingID);

        end

        if any(~isfinite(XTest(:)))

            error('Test features contain NaN or Inf for %s.',settingID);

        end

        if numel(YTestString) ~= actualWindows || ...
           numel(groupTest) ~= actualWindows

            error('Test features, labels and groups have inconsistent sizes.');

        end

        %% 13.10 VERIFY CLASS LABELS

        validClasses = [ ...
            "Normal"; ...
            "LG"; ...
            "LL"; ...
            "LLG"; ...
            "Three_Phase_Fault"];

        if any(~ismember(YTestString,validClasses))

            error('Unknown test class detected in %s.',settingID);

        end

        %% 13.11 VERIFY EACH GROUP WINDOW COUNT

        [groupNames,~,groupIndex] = unique(groupTest);

        groupCounts = accumarray(groupIndex,1);

        expectedGroupCounts = zeros(numel(groupNames),1);

        for g = 1:numel(groupNames)

            if contains(groupNames(g),"_Fault_")

                expectedGroupCounts(g) = expectedFaultWindows;

            elseif contains(groupNames(g),"_Normal_")

                expectedGroupCounts(g) = expectedNormalWindows;

            else

                error('Unrecognized scenario group: %s',groupNames(g));

            end
        end

        if any(groupCounts ~= expectedGroupCounts)

            error(['At least one scenario group has an incorrect ' ...
                'number of feature windows in %s.'],settingID);

        end

        %% 13.12 VERIFY CLASS DISTRIBUTION

        classDistribution = table( ...
            validClasses, ...
            zeros(numel(validClasses),1), ...
            'VariableNames',{'Class','SampleCount'});

        for c = 1:numel(validClasses)

            classDistribution.SampleCount(c) = ...
                sum(YTestString == validClasses(c));

        end

        fprintf('\nTest class distribution:\n');

        disp(classDistribution);

        %% 13.13 FINAL COMPLETENESS CHECK

        if size(XTest,1) ~= expectedWindows || ...
           numel(unique(groupTest)) ~= expectedGroups

            error('Final dataset completeness check failed for %s.', ...
                settingID);

        end

        fprintf('\nDataset validation PASSED for %s.\n',settingID);

        fprintf('Ready for classifier evaluation.\n');

        %% CHUNK 4 CONTINUES HERE


        %% 14. EVALUATE CLASSIFIERS

        % Use the fixed class order for actual and predicted labels.

        YTest = categorical( ...
            YTestString,classNames,classNames);

        YTest = reordercats(YTest,classNames);

        if any(isundefined(YTest))
            error('Test dataset contains an undefined class.');
        end

        modelNames = {'Bagged_Trees','Gaussian_SVM'};

        %% Generate predictions

        predictions = cell(numel(modelNames),1);

        predictions{1} = predict(bagModel,XTest);

        predictions{2} = predict(svmModel,XTest);

        %% Evaluate each classifier

        for m = 1:numel(modelNames)

            modelNameResult = modelNames{m};

            fprintf('\n========================================\n');

            fprintf('SETTING: %s\n',settingID);

            fprintf('CLASSIFIER: %s\n',modelNameResult);

            fprintf('========================================\n');

            %% Convert predictions to fixed categorical order

            YPredString = string(predictions{m});

            YPred = categorical( ...
                YPredString,classNames,classNames);

            YPred = reordercats(YPred,classNames);

            if any(isundefined(YPred))
                error('%s produced an undefined class.',modelNameResult);
            end

            %% Calculate overall accuracy

            accuracy = mean(YPred == YTest);

            %% Calculate confusion matrix

            confusionOrder = categorical(classNames,classNames);

            confusionMatrix = confusionmat( ...
                YTest,YPred,'Order',confusionOrder);

            %% Calculate class-wise metrics

            TP = diag(confusionMatrix);

            FP = sum(confusionMatrix,1)' - TP;

            FN = sum(confusionMatrix,2) - TP;

            precision = TP ./ max(TP+FP,eps);

            recall = TP ./ max(TP+FN,eps);

            F1 = 2.*precision.*recall ./ ...
                max(precision+recall,eps);

            %% Calculate macro F1

            macroF1 = mean(F1);

            %% Store overall results

            summaryRows(end+1,:) = { ...
                variationType, ...
                percentage, ...
                settingID, ...
                modelNameResult, ...
                accuracy, ...
                macroF1, ...
                size(XTest,1), ...
                numel(unique(groupTest))}; %#ok<AGROW>

            %% Store class-wise results

            for c = 1:numel(classNames)

                classRows(end+1,:) = { ...
                    variationType, ...
                    percentage, ...
                    settingID, ...
                    modelNameResult, ...
                    classNames{c}, ...
                    precision(c), ...
                    recall(c), ...
                    F1(c)}; %#ok<AGROW>

            end

            %% Display evaluation results

            fprintf('\nAccuracy: %.4f (%.2f%%)\n', ...
                accuracy,accuracy*100);

            fprintf('Macro F1: %.4f (%.2f%%)\n', ...
                macroF1,macroF1*100);

            fprintf('Test windows: %d\n',size(XTest,1));

            fprintf('Test scenario groups: %d\n', ...
                numel(unique(groupTest)));

            fprintf('\nConfusion matrix:\n');

            disp(confusionMatrix);

            classMetricTable = table( ...
                string(classNames(:)), ...
                precision, ...
                recall, ...
                F1, ...
                'VariableNames',{ ...
                'Class','Precision','Recall','F1'});

            fprintf('\nClass-wise performance:\n');

            disp(classMetricTable);

            %% SAVE CONFUSION MATRIX

            fig = figure( ...
                'Visible','off', ...
                'Color','w');

            cmChart = confusionchart(YTest,YPred);

            cmChart.Title = sprintf( ...
                '%s - %s Confusion Matrix', ...
                settingID,modelNameResult);

            cmChart.RowSummary = 'row-normalized';

            cmChart.ColumnSummary = 'column-normalized';

            chartFile = fullfile(resultFolder, ...
                sprintf('%s_%s_Confusion_Matrix.png', ...
                settingID,modelNameResult));

            exportgraphics(fig,chartFile,'Resolution',300);

            close(fig);

            fprintf('Confusion matrix saved:\n%s\n',chartFile);

            %% SAVE PREDICTIONS AND EVALUATION DATA

            predictionFile = fullfile(resultFolder, ...
                sprintf('%s_%s_Predictions.mat', ...
                settingID,modelNameResult));

            save(predictionFile, ...
                'XTrain', ...
                'YTrain', ...
                'trainingGroups', ...
                'XTest', ...
                'YTest', ...
                'YPred', ...
                'YPredString', ...
                'groupTest', ...
                'confusionMatrix', ...
                'accuracy', ...
                'macroF1', ...
                'precision', ...
                'recall', ...
                'F1', ...
                'classNames', ...
                'featureNames', ...
                'variationType', ...
                'percentage', ...
                'settingID', ...
                'expectedWindows', ...
                'expectedGroups', ...
                'actualWindows', ...
                'actualGroups', ...
                'settingScenarioLog', ...
                '-v7.3');

            fprintf('Prediction data saved:\n%s\n',predictionFile);

        end

        %% 15. SAVE PROGRESS AFTER EACH SETTING

        save(fullfile(resultFolder,'RLC_Progress_Backup.mat'), ...
            'summaryRows', ...
            'classRows', ...
            'scenarioLog', ...
            'variationTypes', ...
            'variationPercentages', ...
            'classNames', ...
            'featureNames', ...
            'XTrain', ...
            'YTrain', ...
            'trainingGroups', ...
            '-v7.3');

        fprintf('\nCompleted evaluation for %s.\n',settingID);

    end
end

%% END OF ALL 12 RLC VARIATION SETTINGS

%% 16. CHECK WHETHER ANY SETTINGS WERE EVALUATED

if isempty(summaryRows)

    writetable(scenarioLog,fullfile(auditFolder, ...
        'RLC_Scenario_Execution_Log.csv'));

    error(['No complete RLC variation setting was evaluated. ' ...
        'Inspect the scenario execution log.']);

end

%% 17. CONVERT RESULTS INTO TABLES

Summary = cell2table(summaryRows, ...
    'VariableNames',{ ...
    'VariationType', ...
    'VariationPercent', ...
    'SettingID', ...
    'Model', ...
    'Accuracy', ...
    'MacroF1', ...
    'TestSamples', ...
    'TestGroups'});

ClassResults = cell2table(classRows, ...
    'VariableNames',{ ...
    'VariationType', ...
    'VariationPercent', ...
    'SettingID', ...
    'Model', ...
    'Class', ...
    'Precision', ...
    'Recall', ...
    'F1'});

%% 18. EXPORT SCENARIO AUDIT LOG

scenarioCSV = fullfile(auditFolder, ...
    'RLC_Scenario_Execution_Log.csv');

writetable(scenarioLog,scenarioCSV);

%% 19. EXPORT CSV RESULTS

summaryCSV = fullfile(resultFolder, ...
    'RLC_Variation_Summary.csv');

classCSV = fullfile(resultFolder, ...
    'RLC_Variation_Class_Results.csv');

writetable(Summary,summaryCSV);

writetable(ClassResults,classCSV);

fprintf('\nCSV files exported.\n');

%% 20. EXPORT EXCEL WORKBOOK

excelFile = fullfile(resultFolder, ...
    'RLC_Parameter_Variation_Final_Report.xlsx');

writetable(Summary,excelFile, ...
    'Sheet','Overall_Results');

writetable(ClassResults,excelFile, ...
    'Sheet','Class_Results');

writetable(scenarioLog,excelFile, ...
    'Sheet','Scenario_Audit');

fprintf('Excel report exported.\n');

%% 21. PLOT CLASSIFIER ACCURACY

modelNames = {'Bagged_Trees','Gaussian_SVM'};

for v = 1:numel(variationTypes)

    variationType = variationTypes{v};

    fig = figure('Color','w');

    hold on;

    for m = 1:numel(modelNames)

        idx = strcmp(Summary.VariationType,variationType) & ...
              strcmp(Summary.Model,modelNames{m});

        T = Summary(idx,:);

        if isempty(T)
            continue;
        end

        T = sortrows(T,'VariationPercent');

        plot(T.VariationPercent,T.Accuracy*100, ...
            '-o', ...
            'LineWidth',1.8, ...
            'MarkerSize',7, ...
            'DisplayName',strrep(modelNames{m},'_',' '));

    end

    xlabel([variationType ' Variation (%)']);

    ylabel('Accuracy (%)');

    title([variationType ' Variation - Classifier Accuracy']);

    legend('Location','best');

    grid on;

    ylim([0 105]);

    xticks(variationPercentages);

    chartFile = fullfile(resultFolder, ...
        [variationType '_Accuracy.png']);

    exportgraphics(fig,chartFile,'Resolution',300);

    savefig(fig,fullfile(resultFolder, ...
        [variationType '_Accuracy.fig']));

    close(fig);

    fprintf('Accuracy plot saved: %s\n',chartFile);

end

%% 22. PLOT CLASSIFIER MACRO F1

for v = 1:numel(variationTypes)

    variationType = variationTypes{v};

    fig = figure('Color','w');

    hold on;

    for m = 1:numel(modelNames)

        idx = strcmp(Summary.VariationType,variationType) & ...
              strcmp(Summary.Model,modelNames{m});

        T = Summary(idx,:);

        if isempty(T)
            continue;
        end

        T = sortrows(T,'VariationPercent');

        plot(T.VariationPercent,T.MacroF1*100, ...
            '-o', ...
            'LineWidth',1.8, ...
            'MarkerSize',7, ...
            'DisplayName',strrep(modelNames{m},'_',' '));

    end

    xlabel([variationType ' Variation (%)']);

    ylabel('Macro F1 (%)');

    title([variationType ' Variation - Macro F1']);

    legend('Location','best');

    grid on;

    ylim([0 105]);

    xticks(variationPercentages);

    chartFile = fullfile(resultFolder, ...
        [variationType '_MacroF1.png']);

    exportgraphics(fig,chartFile,'Resolution',300);

    savefig(fig,fullfile(resultFolder, ...
        [variationType '_MacroF1.fig']));

    close(fig);

    fprintf('Macro F1 plot saved: %s\n',chartFile);

end

%% 23. SAVE COMPLETE EXPERIMENT RESULTS

completeFile = fullfile(resultFolder, ...
    'RLC_Parameter_Variation_Complete_Results.mat');

save(completeFile, ...
    'Summary', ...
    'ClassResults', ...
    'scenarioLog', ...
    'variationTypes', ...
    'variationPercentages', ...
    'classNames', ...
    'featureNames', ...
    'XTrain', ...
    'YTrain', ...
    'trainingGroups', ...
    'expectedWindows', ...
    'expectedGroups', ...
    'expectedFaultWindows', ...
    'expectedNormalWindows', ...
    '-v7.3');

fprintf('\nComplete experiment results saved.\n');

%% 24. SAVE FINAL PROGRESS BACKUP

save(fullfile(resultFolder,'RLC_Progress_Backup.mat'), ...
    'Summary', ...
    'ClassResults', ...
    'summaryRows', ...
    'classRows', ...
    'scenarioLog', ...
    'variationTypes', ...
    'variationPercentages', ...
    'classNames', ...
    'featureNames', ...
    '-v7.3');

%% 25. RESTORE ORIGINAL SIMULINK PARAMETERS

% Clearing cleanupObject invokes restoreOriginal().

clear cleanupObject;

%% 26. DISPLAY FINAL RESULTS

fprintf('\n============================================\n');

fprintf('RLC PARAMETER VARIATION EXPERIMENT FINISHED\n');

fprintf('============================================\n');

fprintf('\nResults folder:\n%s\n',resultFolder);

fprintf('\nSummary CSV:\n%s\n',summaryCSV);

fprintf('\nClass results CSV:\n%s\n',classCSV);

fprintf('\nScenario audit CSV:\n%s\n',scenarioCSV);

fprintf('\nExcel report:\n%s\n',excelFile);

fprintf('\nComplete MAT file:\n%s\n',completeFile);

fprintf('\nEvaluated settings: %d\n', ...
    numel(unique(Summary.SettingID)));

fprintf('Expected settings: %d\n', ...
    numel(variationTypes)*numel(variationPercentages));

fprintf('\n========== OVERALL RESULTS ==========\n');

disp(Summary);

fprintf('\n========== SCENARIO EXECUTION SUMMARY ==========\n');

% Generate scenario execution summary without groupsummary
[G, settingID, success] = findgroups( ...
    scenarioLog.SettingID, scenarioLog.Success);

scenarioCount = splitapply( ...
    @numel, scenarioLog.ScenarioID, G);

scenarioSummary = table( ...
    settingID, success, scenarioCount, ...
    'VariableNames', ...
    {'SettingID', 'Success', 'ScenarioCount'});

disp('========== SCENARIO EXECUTION SUMMARY ==========');
disp(scenarioSummary);

writetable(scenarioSummary, ...
    fullfile(resultFolder, 'RLC_Scenario_Summary.csv'));


fprintf('\nOriginal model parameters restored.\n');

fprintf('\nExperiment completed.\n');

%% ============================================================
% LOCAL FUNCTION 1: RESTORE ORIGINAL MODEL PARAMETERS
% ============================================================

function restoreOriginal(line1,line2,faultBlock,loadBlock,original)

    try

        set_param(line1,'Length',original.line1Length);

        set_param(line2,'Length',original.line2Length);

        parameterNames = { ...
            'Resistances', ...
            'Inductances', ...
            'Capacitances'};

        for k = 1:numel(parameterNames)

            p = parameterNames{k};

            set_param(line1,p,original.line1.(p));

            set_param(line2,p,original.line2.(p));

        end

        set_param(loadBlock, ...
            'ActivePower',original.loadP, ...
            'InductivePower',original.loadQ);

        faultNames = fieldnames(original.fault);

        for k = 1:numel(faultNames)

            p = faultNames{k};

            set_param(faultBlock,p,original.fault.(p));

        end

        fprintf('\nOriginal Simulink parameters restored.\n');

    catch ME

        warning('Model restoration failed: %s',ME.message);

    end
end

%% ============================================================
% LOCAL FUNCTION 2: CREATE SCENARIO AUDIT ROW
% ============================================================

function row = makeScenarioLogRow( ...
    settingID,scenarioID,scenarioType,faultType, ...
    resistance,inception,location,success,windowCount,errorMessage)

    row = table( ...
        string(settingID), ...
        string(scenarioID), ...
        string(scenarioType), ...
        string(faultType), ...
        double(resistance), ...
        double(inception), ...
        double(location), ...
        logical(success), ...
        double(windowCount), ...
        string(errorMessage), ...
        'VariableNames',{ ...
        'SettingID', ...
        'ScenarioID', ...
        'ScenarioType', ...
        'FaultType', ...
        'FaultResistance', ...
        'FaultInception', ...
        'FaultLocation', ...
        'Success', ...
        'WindowCount', ...
        'ErrorMessage'});

end

%% ============================================================
% LOCAL FUNCTION 3: EXTRACT SIMULATION SIGNALS
% ============================================================

function signals = getSignals(simOut)

    names = {'Vabc_S','Iabc_S','Vabc_R','Iabc_R'};

    signals = cell(1,4);

    for k = 1:4

        signals{k} = simOut.get(names{k});

        if isempty(signals{k})

            error('Missing simulation signal: %s',names{k});

        end

        if ~isa(signals{k},'timeseries')

            error('%s must be a timeseries.',names{k});

        end

        if any(~isfinite(signals{k}.Data(:)))

            error('%s contains NaN or Inf.',names{k});

        end

        if any(~isfinite(signals{k}.Time(:)))

            error('%s time vector contains NaN or Inf.',names{k});

        end

    end
end

%% ============================================================
% LOCAL FUNCTION 4: FEATURE EXTRACTION
% ============================================================

function [Xfeatures,featureNames] = ...
    extractFeatures(signals,startTime,endTime)

    windowDuration = 0.020;

    stepDuration = 0.005;

    signalNames = {'Vabc_S','Iabc_S','Vabc_R','Iabc_R'};

    phaseNames = {'A','B','C'};

    statNames = { ...
        'RMS', ...
        'MeanAbs', ...
        'Std', ...
        'PeakAbs', ...
        'PeakToPeak'};

    %% Convert signals to N-by-3 matrices

    data = cell(1,4);

    time = cell(1,4);

    for s = 1:4

        time{s} = double(signals{s}.Time(:));

        data{s} = double(signals{s}.Data);

        if size(data{s},2) ~= 3 && size(data{s},1) == 3

            data{s} = data{s}.';

        end

        if size(data{s},2) ~= 3

            error('Expected three-phase data for %s.',signalNames{s});

        end

        if numel(time{s}) ~= size(data{s},1)

            error('Time and data dimensions differ for %s.', ...
                signalNames{s});

        end

        if any(~isfinite(data{s}(:)))

            error('%s contains non-finite values.',signalNames{s});

        end

    end

    %% Check time alignment

    referenceTime = time{1};

    for s = 2:4

        if numel(time{s}) ~= numel(referenceTime) || ...
           max(abs(time{s}-referenceTime)) > 1e-9

            error('Measurement signal time vectors are not aligned.');

        end

    end

    %% Generate 60 feature names

    featureNames = cell(1,60);

    featureCounter = 0;

    for s = 1:4

        for p = 1:3

            for st = 1:5

                featureCounter = featureCounter+1;

                featureNames{featureCounter} = sprintf( ...
                    '%s_%s_%s', ...
                    signalNames{s}, ...
                    phaseNames{p}, ...
                    statNames{st});

            end

        end

    end

    %% Generate feature window start times

    windowStarts = startTime:stepDuration: ...
        (endTime-windowDuration+1e-12);

    Xfeatures = zeros(numel(windowStarts),60);

    validRows = 0;

    %% Extract statistical features

    for w = 1:numel(windowStarts)

        ws = windowStarts(w);

        we = ws+windowDuration;

        indices = find( ...
            referenceTime >= ws & referenceTime < we);

        if numel(indices) < 2

            continue;

        end

        featureVector = zeros(1,60);

        featureCounter = 0;

        for s = 1:4

            segment = data{s}(indices,:);

            for p = 1:3

                x = segment(:,p);

                values = [ ...
                    sqrt(mean(x.^2)), ...
                    mean(abs(x)), ...
                    std(x,0), ...
                    max(abs(x)), ...
                    max(x)-min(x)];

                for st = 1:5

                    featureCounter = featureCounter+1;

                    featureVector(featureCounter) = values(st);

                end

            end

        end

        validRows = validRows+1;

        Xfeatures(validRows,:) = featureVector;

    end

    Xfeatures = Xfeatures(1:validRows,:);

    if any(~isfinite(Xfeatures(:)))

        error('Extracted features contain NaN or Inf.');

    end

end
