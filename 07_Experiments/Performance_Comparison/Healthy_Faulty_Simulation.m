
%% HEALTHY AND FAULTY TRANSMISSION LINE SIMULATION
% Model: Transmission_Line_132kV_Phase1
% MATLAB/Simulink: R2024b
%
% This script runs:
% 1. Healthy operating condition
% 2. Three-phase-to-ground fault condition
%
% It saves:
% - Healthy and faulty waveform figures
% - RMS summary CSV
% - Simulation results MAT file
% - Execution log TXT
%
% The Simulink model is NOT saved by this script.

clearvars;
clc;

%% 1. PROJECT SETTINGS

modelName = 'Transmission_Line_132kV_Phase1';

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

modelFile = fullfile(projectRoot, ...
    '03_Simulink_Models', [modelName '.slx']);

faultBlock = [modelName '/Three-Phase Fault'];

outputFolder = fullfile(projectRoot, ...
    '04_Results', 'Healthy_vs_Faulty');

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

% Signal names saved by the Simulink model
signalNames = {'Vabc_S', 'Iabc_S', 'Vabc_R', 'Iabc_R'};

signalLabels = { ...
    'Sending-end voltage', ...
    'Sending-end current', ...
    'Receiving-end voltage', ...
    'Receiving-end current'};

%% 2. START EXECUTION LOG

logFile = fullfile(outputFolder, ...
    'Healthy_Faulty_Run_Log.txt');

if exist(logFile, 'file')
    delete(logFile);
end

diary(logFile);
diary on;

fprintf('============================================\n');
fprintf('HEALTHY AND FAULTY SIMULATION\n');
fprintf('Started: %s\n', datestr(now));
fprintf('============================================\n');

%% 3. LOAD SIMULINK MODEL

if ~isfile(modelFile)
    error('Model file not found: %s', modelFile);
end

if ~bdIsLoaded(modelName)
    load_system(modelFile);
end

open_system(modelName);

% Verify fault block exists
try
    get_param(faultBlock, 'Handle');
catch
    error('Three-Phase Fault block was not found.');
end

fprintf('\nModel loaded successfully:\n%s\n', modelFile);

%% 4. HEALTHY OPERATING CONDITION

fprintf('\n========== HEALTHY SIMULATION ==========\n');

% Disable all fault phases and ground fault
set_param(faultBlock, ...
    'FaultA', 'off', ...
    'FaultB', 'off', ...
    'FaultC', 'off', ...
    'GroundFault', 'off');

fprintf('FaultA: %s\n', get_param(faultBlock, 'FaultA'));
fprintf('FaultB: %s\n', get_param(faultBlock, 'FaultB'));
fprintf('FaultC: %s\n', get_param(faultBlock, 'FaultC'));
fprintf('GroundFault: %s\n', ...
    get_param(faultBlock, 'GroundFault'));

% Run healthy simulation
healthyOut = sim(modelName);

fprintf('\nHealthy simulation completed.\n');
disp(healthyOut);

%% 5. THREE-PHASE-TO-GROUND FAULT SIMULATION

fprintf('\n========== FAULTY SIMULATION ==========\n');

% Enable all three phases and ground fault
set_param(faultBlock, ...
    'FaultA', 'on', ...
    'FaultB', 'on', ...
    'FaultC', 'on', ...
    'GroundFault', 'on');

fprintf('FaultA: %s\n', get_param(faultBlock, 'FaultA'));
fprintf('FaultB: %s\n', get_param(faultBlock, 'FaultB'));
fprintf('FaultC: %s\n', get_param(faultBlock, 'FaultC'));
fprintf('GroundFault: %s\n', ...
    get_param(faultBlock, 'GroundFault'));

% Read configured fault switching times
faultTimes = str2num(get_param(faultBlock, 'SwitchTimes')); %#ok<ST2NM>

if numel(faultTimes) ~= 2
    error('Expected two fault switching times.');
end

faultStart = faultTimes(1);
faultEnd = faultTimes(2);

fprintf('Fault starts at %.4f seconds.\n', faultStart);
fprintf('Fault clears at %.4f seconds.\n', faultEnd);

% Run faulty simulation
faultyOut = sim(modelName);

fprintf('\nFaulty simulation completed.\n');
disp(faultyOut);

%% 6. CALCULATE RMS VALUES

% Healthy RMS: final 100 ms of simulation
healthyTime = healthyOut.tout;
healthyStart = healthyTime(end) - 0.10;
healthyEnd = healthyTime(end);

healthyRMS = calculateRMS( ...
    healthyOut, signalNames, healthyStart, healthyEnd);

% Fault RMS: exclude switching transients
faultRMSStart = faultStart + 0.01;
faultRMSEnd = faultEnd - 0.01;

faultyRMS = calculateRMS( ...
    faultyOut, signalNames, faultRMSStart, faultRMSEnd);

%% 7. CREATE RMS SUMMARY TABLE

phaseNames = {'A'; 'B'; 'C'};

Case = [repmat({'Healthy'}, 12, 1); ...
        repmat({'Faulty'}, 12, 1)];

Signal = [repelem(signalNames(:), 3); ...
          repelem(signalNames(:), 3)];

Phase = repmat(phaseNames, 8, 1);

RMS_Value = [ ...
    reshape(healthyRMS.', [], 1); ...
    reshape(faultyRMS.', [], 1)];

rmsTable = table(Case, Signal, Phase, RMS_Value);

fprintf('\n========== RMS SUMMARY ==========\n');
disp(rmsTable);

% Save RMS table as CSV
csvFile = fullfile(outputFolder, 'RMS_Summary.csv');

writetable(rmsTable, csvFile);

fprintf('RMS summary saved to:\n%s\n', csvFile);

%% 8. GENERATE HEALTHY WAVEFORM FIGURE

healthyFigure = plotCase( ...
    healthyOut, signalNames, signalLabels, ...
    'Healthy Operating Condition');

healthyFigureFile = fullfile(outputFolder, ...
    'Healthy_Waveforms.png');

exportgraphics(healthyFigure, healthyFigureFile, ...
    'Resolution', 300);

%% 9. GENERATE FAULTY WAVEFORM FIGURE

faultyFigure = plotCase( ...
    faultyOut, signalNames, signalLabels, ...
    'Three-Phase-to-Ground Fault Condition');

faultyFigureFile = fullfile(outputFolder, ...
    'Faulty_Waveforms.png');

exportgraphics(faultyFigure, faultyFigureFile, ...
    'Resolution', 300);

%% 10. SAVE COMPLETE SIMULATION RESULTS

results = struct();

results.modelName = modelName;
results.modelFile = modelFile;
results.createdAt = datetime('now');

results.faultStart = faultStart;
results.faultEnd = faultEnd;

results.healthySimulation = healthyOut;
results.faultySimulation = faultyOut;

results.healthyRMS = healthyRMS;
results.faultyRMS = faultyRMS;
results.rmsTable = rmsTable;

matFile = fullfile(outputFolder, ...
    'Healthy_Faulty_Simulation_Results.mat');

save(matFile, 'results', '-v7.3');

%% 11. DISPLAY SAVED FILES

fprintf('\n========== SAVED RESULTS ==========\n');

fprintf('Healthy graph:\n%s\n', healthyFigureFile);
fprintf('Faulty graph:\n%s\n', faultyFigureFile);
fprintf('RMS summary:\n%s\n', csvFile);
fprintf('MAT results:\n%s\n', matFile);
fprintf('Execution log:\n%s\n', logFile);

fprintf('\nThe Simulink model has NOT been saved.\n');
fprintf('Simulation process completed: %s\n', datestr(now));

diary off;

%% 12. LOCAL FUNCTION: RMS CALCULATION

function rmsMatrix = calculateRMS(simOutput, ...
    signalNames, startTime, endTime)

    rmsMatrix = zeros(numel(signalNames), 3);

    for k = 1:numel(signalNames)

        ts = simOutput.get(signalNames{k});

        t = ts.Time(:);
        data = squeeze(ts.Data);

        % Ensure data has dimensions N-by-3
        if size(data, 1) ~= numel(t) && ...
                size(data, 2) == numel(t)

            data = data.';

        end

        if size(data, 1) ~= numel(t) || size(data, 2) ~= 3
            error('Unexpected signal dimensions for %s.', ...
                signalNames{k});
        end

        idx = t >= startTime & t <= endTime;

        if ~any(idx)
            error('No samples found for %s in RMS interval.', ...
                signalNames{k});
        end

        rmsMatrix(k, :) = sqrt( ...
            mean(data(idx, :).^2, 1));

    end
end

%% 13. LOCAL FUNCTION: WAVEFORM PLOTTING

function fig = plotCase(simOutput, ...
    signalNames, signalLabels, figureTitle)

    fig = figure( ...
        'Color', 'w', ...
        'Name', figureTitle, ...
        'Position', [100 100 1100 800]);

    tiledlayout(4, 1, ...
        'TileSpacing', 'compact', ...
        'Padding', 'compact');

    for k = 1:numel(signalNames)

        ts = simOutput.get(signalNames{k});

        t = ts.Time(:);
        data = squeeze(ts.Data);

        if size(data, 1) ~= numel(t) && ...
                size(data, 2) == numel(t)

            data = data.';

        end

        nexttile;

        plot(t, data(:, 1), 'LineWidth', 0.8);
        hold on;

        plot(t, data(:, 2), 'LineWidth', 0.8);
        plot(t, data(:, 3), 'LineWidth', 0.8);

        grid on;

        xlim([t(1) t(end)]);

        ylabel(signalLabels{k});

        legend('Phase A', 'Phase B', 'Phase C', ...
            'Location', 'eastoutside');

        if k == 1
            title(figureTitle, 'Interpreter', 'none');
        end

        if k == numel(signalNames)
            xlabel('Time (seconds)');
        end

    end
end
