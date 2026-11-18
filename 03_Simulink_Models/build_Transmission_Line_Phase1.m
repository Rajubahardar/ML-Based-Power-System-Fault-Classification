
%% 2. LIBRARY AND MODEL INITIALIZATION

load_system('sps_lib');
load_system('simulink');

if bdIsLoaded(modelName)
    close_system(modelName, 0);
end

% Do not delete or recreate the existing model.
% Load the existing Phase 1 model if it is already saved.
modelFile = fullfile( ...
    'D:\MATLAB_Projects\TL_Fault_AI', ...
    '03_Simulink_Models', ...
    'Phase_1_Normal_Model', ...
    'Transmission_Line_132kV_Phase1.slx');
if isfile(modelFile)
    load_system(modelFile);
    open_system(modelName);
    fprintf('Existing model loaded.\n');
else
    new_system(modelName);
    open_system(modelName);
    fprintf('New model created.\n');
end

%% 3. TRANSMISSION LINE AND MIDPOINT FAULT BLOCK

fprintf('Adding transmission line sections and fault block...\n');

line1Block = [modelName '/50 km PI Line Section 1'];
line2Block = [modelName '/50 km PI Line Section 2'];
faultBlock = [modelName '/Three-Phase Fault'];

% Create first 50 km section
add_block( ...
    'sps_lib/Power Grid Elements/Three-Phase PI Section Line', ...
    line1Block, ...
    'Position', [410 180 510 260]);

% Create second 50 km section
add_block( ...
    'sps_lib/Power Grid Elements/Three-Phase PI Section Line', ...
    line2Block, ...
    'Position', [600 180 700 260]);

% Create midpoint fault block
add_block( ...
    'sps_lib/Power Grid Elements/Three-Phase Fault', ...
    faultBlock, ...
    'Position', [510 330 610 430]);

% Configure each line section
set_param(line1Block, ...
    'Length', '50', ...
    'Frequency', num2str(frequency), ...
    'Resistances', mat2str([R1 R0],12), ...
    'Inductances', mat2str([L1 L0],12), ...
    'Capacitances', mat2str([C1 C0],12));

set_param(line2Block, ...
    'Length', '50', ...
    'Frequency', num2str(frequency), ...
    'Resistances', mat2str([R1 R0],12), ...
    'Inductances', mat2str([L1 L0],12), ...
    'Capacitances', mat2str([C1 C0],12));

% Configure fault timing and resistance
set_param(faultBlock, ...
    'InitialStates', '0', ...
    'SwitchTimes', '[0.10 0.20]', ...
    'External', 'off', ...
    'SwitchStatus', '[1 0]', ...
    'FaultResistance', '0.001', ...
    'GroundResistance', '0.001', ...
    'SnubberResistance', '1e6', ...
    'SnubberCapacitance', 'inf');

fprintf('Two 50 km sections and fault block created.\n');

%% 10. CONNECT THREE-PHASE NETWORK WITH MIDPOINT FAULT

fprintf('\nConnecting transmission line and fault...\n');

% Block paths
sourceBlock = [modelName '/Three-Phase Source'];
sendingBlock = [modelName '/Sending End Measurement'];
receivingBlock = [modelName '/Receiving End Measurement'];
loadBlock = [modelName '/Three-Phase Load'];

line1Block = [modelName '/50 km PI Line Section 1'];
line2Block = [modelName '/50 km PI Line Section 2'];
faultBlock = [modelName '/Three-Phase Fault'];

% Remove the original 100 km line.
% Deleting the block also removes its old electrical connections.
oldLine = [modelName '/100 km PI Transmission Line'];

if getSimulinkBlockHandle(oldLine) ~= -1
    delete_block(oldLine);
end

% Retrieve electrical port handles
sendPorts = get_param(sendingBlock, 'PortHandles');
recvPorts = get_param(receivingBlock, 'PortHandles');

line1Ports = get_param(line1Block, 'PortHandles');
line2Ports = get_param(line2Block, 'PortHandles');

faultPorts = get_param(faultBlock, 'PortHandles');

% Verify three-phase electrical terminals
assert(numel(sendPorts.RConn) == 3, ...
    'Sending measurement must have three right electrical terminals.');

assert(numel(line1Ports.LConn) == 3 && ...
       numel(line1Ports.RConn) == 3, ...
    'First PI section must have three terminals at each end.');

assert(numel(line2Ports.LConn) == 3 && ...
       numel(line2Ports.RConn) == 3, ...
    'Second PI section must have three terminals at each end.');

assert(numel(recvPorts.LConn) == 3, ...
    'Receiving measurement must have three left electrical terminals.');

assert(numel(faultPorts.LConn) == 3, ...
    'Fault block does not expose three expected phase terminals.');

% Connect each phase
for phase = 1:3

    % Sending measurement -> first 50 km section
    add_line(modelName, ...
        sendPorts.RConn(phase), ...
        line1Ports.LConn(phase), ...
        'autorouting', 'on');

    % First section -> second section
    add_line(modelName, ...
        line1Ports.RConn(phase), ...
        line2Ports.LConn(phase), ...
        'autorouting', 'on');

    % Connect fault block in parallel at the midpoint
    add_line(modelName, ...
        line1Ports.RConn(phase), ...
        faultPorts.LConn(phase), ...
        'autorouting', 'on');

    % Second section -> receiving measurement
    add_line(modelName, ...
        line2Ports.RConn(phase), ...
        recvPorts.LConn(phase), ...
        'autorouting', 'on');

end

fprintf('Three-phase electrical network connected.\n');
fprintf('Transmission line: 50 km + 50 km.\n');
fprintf('Fault location: 50 km midpoint.\n');

%% 13. SAVE MODIFIED ORIGINAL MODEL

fprintf('\nSaving modified transmission-line model...\n');

% Save using the original model name and existing file location.
save_system(modelName);

fprintf('\nOriginal model updated successfully:\n');
fprintf('%s.slx\n', modelName);

% Create fault dataset directory
dataFolder = fullfile(pwd, ...
    '04_Data_Generation', 'Fault_Data');

if ~isfolder(dataFolder)
    mkdir(dataFolder);
end

fprintf('Fault dataset directory:\n%s\n', dataFolder);

%% 14. AUTOMATIC FAULT SIMULATION AND DATA GENERATION

fprintf('\n============================================\n');
fprintf('PHASE 2: FAULT DATA GENERATION\n');
fprintf('============================================\n');

faultBlock = [modelName '/Three-Phase Fault'];

% Fault timing and electrical resistance
set_param(faultBlock, ...
    'InitialStates', '0', ...
    'SwitchTimes', '[0.10 0.20]', ...
    'External', 'off', ...
    'SwitchStatus', '[1 0]', ...
    'FaultResistance', '0.001', ...
    'GroundResistance', '0.001', ...
    'SnubberResistance', '1e6', ...
    'SnubberCapacitance', 'inf');

% Fault configurations:
% Columns: Name, Phase A, Phase B, Phase C, Ground
faultCases = {
    'LG',   'on',  'off', 'off', 'on';
    'LL',   'on',  'on',  'off', 'off';
    'LLG',  'on',  'on',  'off', 'on';
    'LLL',  'on',  'on',  'on',  'off';
    'LLLG', 'on',  'on',  'on',  'on'
};

for k = 1:size(faultCases, 1)

    faultName = faultCases{k, 1};

    fprintf('\n--------------------------------------------\n');
    fprintf('Simulating %s fault...\n', faultName);
    fprintf('--------------------------------------------\n');

    % Apply fault configuration
    set_param(faultBlock, ...
        'FaultA', faultCases{k, 2}, ...
        'FaultB', faultCases{k, 3}, ...
        'FaultC', faultCases{k, 4}, ...
        'GroundFault', faultCases{k, 5});

    % Run simulation
    simOut = sim(modelName, ...
        'StopTime', num2str(simulationTime), ...
        'ReturnWorkspaceOutputs', 'on');

    % Retrieve measurements
    Vabc_S = simOut.get('Vabc_S');
    Iabc_S = simOut.get('Iabc_S');

    Vabc_R = simOut.get('Vabc_R');
    Iabc_R = simOut.get('Iabc_R');

    % Verify logged signals
    if isempty(Vabc_S) || isempty(Iabc_S) || ...
       isempty(Vabc_R) || isempty(Iabc_R)

        error('Missing measurement data for %s fault.', faultName);

    end

    % Store experiment information
    metadata = struct();

    metadata.FaultType = faultName;
    metadata.FaultLocation_km = 50;
    metadata.LineLength_km = 100;

    metadata.FaultInceptionTime_s = 0.10;
    metadata.FaultClearingTime_s = 0.20;

    metadata.FaultResistance_ohm = 0.001;
    metadata.GroundResistance_ohm = 0.001;

    metadata.SamplingTime_s = Ts;
    metadata.Frequency_Hz = frequency;
    metadata.NominalVoltage_V = VLL;

    % Save individual fault dataset
    outputFile = fullfile(dataFolder, ...
        ['Fault_' faultName '_Data.mat']);

    save(outputFile, ...
        'Vabc_S', 'Iabc_S', ...
        'Vabc_R', 'Iabc_R', ...
        'metadata', '-v7.3');

    fprintf('Dataset saved: %s\n', outputFile);

    fprintf('Sending voltage samples: %d\n', ...
        size(Vabc_S.Data, 1));

    fprintf('Sending current samples: %d\n', ...
        size(Iabc_S.Data, 1));

    fprintf('Receiving voltage samples: %d\n', ...
        size(Vabc_R.Data, 1));

    fprintf('Receiving current samples: %d\n', ...
        size(Iabc_R.Data, 1));

end

% Save final original model
save_system(modelName);

fprintf('\n============================================\n');
fprintf('FAULT DATA GENERATION COMPLETED\n');
fprintf('============================================\n');

fprintf('\nGenerated datasets:\n');

for k = 1:size(faultCases, 1)
    fprintf('Fault_%s_Data.mat\n', faultCases{k, 1});
end

fprintf('\nDataset location:\n%s\n', dataFolder);

fprintf('\nOriginal model:\n%s\n', modelName);

fprintf('\nPHASE 2 COMPLETED.\n');
