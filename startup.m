
%% ============================================================
% STARTUP.M
% 132 kV TRANSMISSION LINE FAULT DETECTION PROJECT
% MATLAB R2024b
%
% Purpose:
% 1. Initialize project paths.
% 2. Define engineering assumptions.
% 3. Calculate electrical quantities.
% 4. Populate MATLAB base workspace.
% 5. Load and configure Phase 1 Simulink model.
%
% IMPORTANT:
% Electrical parameters are provisional assumptions.
% They are not verified data for a real transmission corridor.
%% ============================================================

clc;

fprintf('\n============================================\n');
fprintf(' 132 kV TRANSMISSION LINE PROJECT STARTUP\n');
fprintf('============================================\n');

%% 1. PROJECT PATHS

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

modelFolder = fullfile(projectRoot, '03_Simulink_Models');

modelName = 'Transmission_Line_132kV_Phase1';

modelFile = fullfile(modelFolder, [modelName '.slx']);

% Verify project directory

if ~isfolder(projectRoot)
    error('Project folder not found: %s', projectRoot);
end

if ~isfolder(modelFolder)
    error('Simulink model folder not found: %s', modelFolder);
end

% Verify model file

if ~isfile(modelFile)
    error(['Phase 1 model not found: %s\n' ...
           'Check the model filename and location.'], modelFile);
end

fprintf('\nProject directory verified.\n');
fprintf('Model file verified:\n%s\n', modelFile);

%% 2. ENGINEERING ASSUMPTIONS

% Electrical system

V_LL = 132e3;             % Line-to-line voltage [V RMS]
f = 50;                   % Frequency [Hz]
omega = 2*pi*f;           % Angular frequency [rad/s]

% Transmission line

lineLength = 100;         % Line length [km]

R1 = 0.03;                % Positive-sequence resistance [ohm/km]
R0 = 0.30;                % Zero-sequence resistance [ohm/km]

L1 = 1e-3;                % Positive-sequence inductance [H/km]
L0 = 3e-3;                % Zero-sequence inductance [H/km]

C1 = 0.012e-6;            % Positive-sequence capacitance [F/km]
C0 = 0.006e-6;            % Zero-sequence capacitance [F/km]

% NOTE:
% These are provisional model assumptions.
% C1 must not be considered physically validated merely
% because its calculated propagation velocity is below c.

% Source

sourceSsc = 1000e6;       % Short-circuit level [VA]
sourceXR = 10;            % X/R ratio

% Load

loadP = 50e6;             % Active power [W]
loadPF = 0.95;            % Lagging power factor
loadQ = loadP*tan(acos(loadPF));

% Simulation

simulationTime = 0.4;     % Simulation duration [s]
Ts = 20e-6;               % Sampling time [s]

%% 3. DERIVED ELECTRICAL QUANTITIES

% Phase voltage

V_phase = V_LL/sqrt(3);
V_phase_peak = sqrt(2)*V_phase;

% Load calculations

loadS = loadP/loadPF;
loadI = loadS/(sqrt(3)*V_LL);

loadR = V_LL^2/loadS;
loadX = loadQ/(3*loadI^2);
loadL = loadX/omega;

% Source impedance calculations

sourceIsc = sourceSsc/(sqrt(3)*V_LL);
sourceZ = V_LL^2/sourceSsc;

sourceR = sourceZ/sqrt(1 + sourceXR^2);
sourceX = sourceXR*sourceR;
sourceL = sourceX/omega;

% Total line parameters

R1_total = R1*lineLength;
R0_total = R0*lineLength;

L1_total = L1*lineLength;
L0_total = L0*lineLength;

C1_total = C1*lineLength;
C0_total = C0*lineLength;

% Propagation velocity
% With L and C expressed per km, the result is km/s.

v1 = 1/sqrt(L1*C1);
v0 = 1/sqrt(L0*C0);

% Characteristic impedance

Z1 = sqrt(L1/C1);
Z0 = sqrt(L0/C0);

% Speed of light in vacuum [km/s]

speedOfLight = 299792.458;

%% 4. BASIC PARAMETER CHECKS

parameterValues = [V_LL, f, lineLength, R1, R0, ...
                   L1, L0, C1, C0, Ts];

if any(~isfinite(parameterValues)) || any(parameterValues <= 0)
    error('Invalid or non-positive engineering parameter detected.');
end

if loadPF <= 0 || loadPF > 1
    error('Load power factor must be greater than 0 and <= 1.');
end

if v1 >= speedOfLight || v0 >= speedOfLight
    warning(['Calculated propagation velocity exceeds the speed ' ...
             'of light. Review line parameter units and assumptions.']);
end

%% 5. CENTRAL PROJECT CONFIGURATION STRUCTURE

TL = struct();

TL.project.name = ...
    'AI-Assisted Transmission Line Fault Detection';

TL.project.root = projectRoot;
TL.project.model = modelName;
TL.project.release = 'MATLAB R2024b';

TL.electrical.voltage_LL = V_LL;
TL.electrical.voltage_phase = V_phase;
TL.electrical.frequency = f;
TL.electrical.angular_frequency = omega;

TL.line.length_km = lineLength;

TL.line.R1 = R1;
TL.line.R0 = R0;

TL.line.L1 = L1;
TL.line.L0 = L0;

TL.line.C1 = C1;
TL.line.C0 = C0;

TL.line.R1_total = R1_total;
TL.line.R0_total = R0_total;

TL.line.L1_total = L1_total;
TL.line.L0_total = L0_total;

TL.line.C1_total = C1_total;
TL.line.C0_total = C0_total;

TL.line.v1_km_s = v1;
TL.line.v0_km_s = v0;

TL.line.Z1_ohm = Z1;
TL.line.Z0_ohm = Z0;

TL.line.parameter_status = 'PROVISIONAL ASSUMPTIONS';

TL.source.short_circuit_MVA = sourceSsc/1e6;
TL.source.XR_ratio = sourceXR;
TL.source.resistance = sourceR;
TL.source.inductance = sourceL;

TL.load.active_power = loadP;
TL.load.reactive_power = loadQ;
TL.load.apparent_power = loadS;
TL.load.power_factor = loadPF;
TL.load.current = loadI;

TL.simulation.duration = simulationTime;
TL.simulation.sample_time = Ts;
TL.simulation.sampling_frequency = 1/Ts;

TL.status = 'PRELIMINARY - ELECTRICAL VALIDATION PENDING';

fprintf('\nElectrical calculations completed.\n');

%% 6. MATLAB PATH MANAGEMENT

% Add project root if not already present

currentPaths = strsplit(path, pathsep);

if ~any(strcmpi(currentPaths, projectRoot))
    addpath(projectRoot);
end

rehash;

%% 7. LOAD THE CORRECT SIMULINK MODEL

% Check whether a model with the same name is already loaded.

if bdIsLoaded(modelName)

    loadedFile = get_param(modelName, 'FileName');

    if isempty(loadedFile) || ~strcmpi(loadedFile, modelFile)

        close_system(modelName, 0);
        load_system(modelFile);

    end

else

    load_system(modelFile);

end

% Verify loaded model

actualModelFile = get_param(modelName, 'FileName');

if isempty(actualModelFile) || ~strcmpi(actualModelFile, modelFile)
    error('Incorrect Simulink model loaded.');
end

fprintf('\nCorrect Phase 1 model loaded:\n%s\n', actualModelFile);

%% 8. APPLY SOURCE PARAMETERS

sourceBlock = find_system(modelName, ...
    'SearchDepth', 1, ...
    'Name', 'Three-Phase Source');

if numel(sourceBlock) ~= 1
    error(['Could not uniquely identify the Three-Phase Source block. ' ...
           'Check its exact name in the Simulink model.']);
end

set_param(sourceBlock{1}, ...
    'InternalConnection', 'Yg', ...
    'Voltage', num2str(V_LL,17), ...
    'Frequency', num2str(f,17), ...
    'SpecifyImpedance', 'on', ...
    'ShortCircuitLevel', num2str(sourceSsc,17), ...
    'BaseVoltage', num2str(V_LL,17), ...
    'XRratio', num2str(sourceXR,17));

%% 9. APPLY TRANSMISSION LINE PARAMETERS

% The 100 km line is implemented as TWO series-connected 50 km
% Three-Phase PI Section Line blocks in this Simulink model.

lineBlocks = {
    [modelName '/50 km PI Line Section 1']
    [modelName '/50 km PI Line Section 2']
};

% Confirm that both expected blocks exist and have the correct mask.
for k = 1:numel(lineBlocks)

    blockPath = lineBlocks{k};
    blockHandle = getSimulinkBlockHandle(blockPath);

    if blockHandle == -1
        error('Transmission-line block not found: %s', blockPath);
    end

    blockMask = get_param(blockPath, 'MaskType');

    if ~strcmp(blockMask, 'Three-Phase PI Section Line')
        error('Unexpected transmission-line block type at: %s', blockPath);
    end

    % Confirm that the required parameters are available before changing
    % either line section.
    availableParams = get_param(blockPath, 'DialogParameters');
    requiredParams = {'Length', 'Frequency', 'Resistances', ...
                       'Inductances', 'Capacitances'};

    for p = 1:numel(requiredParams)
        if ~isfield(availableParams, requiredParams{p})
            error('Parameter "%s" is unavailable on block: %s', ...
                  requiredParams{p}, blockPath);
        end
    end
end

% Each section is 50 km. The total line length is therefore 100 km.
sectionLength = lineLength / numel(lineBlocks);

if abs(sectionLength - 50) > 1e-9
    error(['The current model contains two 50 km sections. ' ...
           'The configured total line length must be 100 km.']);
end

% Apply identical per-kilometre sequence parameters to both sections.
for k = 1:numel(lineBlocks)

    set_param(lineBlocks{k}, ...
        'Length', num2str(sectionLength, 17), ...
        'Frequency', num2str(f, 17), ...
        'Resistances', mat2str([R1 R0], 15), ...
        'Inductances', mat2str([L1 L0], 15), ...
        'Capacitances', mat2str([C1 C0], 15));

    fprintf('Configured line section %d: %s\n', k, lineBlocks{k});
end

% Verify the resulting total line length.
configuredTotalLength = 0;

for k = 1:numel(lineBlocks)
    configuredTotalLength = configuredTotalLength + ...
        str2double(get_param(lineBlocks{k}, 'Length'));
end

if abs(configuredTotalLength - lineLength) > 1e-9
    error('Configured PI line sections do not total %.1f km.', lineLength);
end

fprintf('Transmission line configured and verified: %.1f km total.\n', ...
        configuredTotalLength);

%% 10. APPLY LOAD PARAMETERS

loadBlock = find_system(modelName, ...
    'SearchDepth', 1, ...
    'Name', 'Three-Phase Load');

if numel(loadBlock) ~= 1
    error(['Could not uniquely identify the Three-Phase Load block. ' ...
           'Check its exact name in the Simulink model.']);
end

set_param(loadBlock{1}, ...
    'Configuration', 'Y (grounded)', ...
    'NominalVoltage', num2str(V_LL,17), ...
    'NominalFrequency', num2str(f,17), ...
    'LoadType', 'constant PQ', ...
    'ActivePower', num2str(loadP,17), ...
    'InductivePower', num2str(loadQ,17), ...
    'CapacitivePower', '0');

%% 11. CONFIGURE POWERGUI

powerguiBlock = find_system(modelName, ...
    'SearchDepth', 1, ...
    'Name', 'powergui');

if numel(powerguiBlock) ~= 1
    error('Could not uniquely identify the powergui block.');
end

set_param(powerguiBlock{1}, ...
    'SimulationMode', 'Discrete', ...
    'SampleTime', num2str(Ts,17));

%% 12. SIMULATION SETTINGS

set_param(modelName, ...
    'StopTime', num2str(simulationTime,17));

%% 13. POPULATE MATLAB BASE WORKSPACE

assignin('base', 'TL', TL);

assignin('base', 'V_LL', V_LL);
assignin('base', 'V_phase', V_phase);
assignin('base', 'V_phase_peak', V_phase_peak);

assignin('base', 'f', f);
assignin('base', 'omega', omega);
assignin('base', 'Ts', Ts);

assignin('base', 'loadP', loadP);
assignin('base', 'loadQ', loadQ);
assignin('base', 'loadS', loadS);
assignin('base', 'loadPF', loadPF);
assignin('base', 'loadI', loadI);

assignin('base', 'sourceSsc', sourceSsc);
assignin('base', 'sourceXR', sourceXR);
assignin('base', 'sourceR', sourceR);
assignin('base', 'sourceL', sourceL);

assignin('base', 'lineLength', lineLength);

assignin('base', 'R1', R1);
assignin('base', 'R0', R0);
assignin('base', 'L1', L1);
assignin('base', 'L0', L0);
assignin('base', 'C1', C1);
assignin('base', 'C0', C0);

assignin('base', 'v1', v1);
assignin('base', 'v0', v0);
assignin('base', 'Z1', Z1);
assignin('base', 'Z0', Z0);

%% 14. OPEN MODEL

open_system(modelName);

%% 15. STARTUP SUMMARY

fprintf('\n============================================\n');
fprintf(' PROJECT STARTUP COMPLETED\n');
fprintf('============================================\n');

fprintf('Model                 : %s\n', modelName);
fprintf('Nominal voltage       : %.1f kV\n', V_LL/1e3);
fprintf('Frequency             : %.1f Hz\n', f);
fprintf('Line length           : %.1f km\n', lineLength);

fprintf('Load active power     : %.2f MW\n', loadP/1e6);
fprintf('Load reactive power   : %.3f MVAr\n', loadQ/1e6);
fprintf('Load current estimate : %.2f A\n', loadI);

fprintf('Source short circuit  : %.1f MVA\n', sourceSsc/1e6);
fprintf('Sampling interval     : %.2f us\n', Ts*1e6);
fprintf('Simulation duration   : %.2f s\n', simulationTime);

fprintf('\nPositive-sequence propagation velocity: %.2f km/s\n',v1);
fprintf('Zero-sequence propagation velocity    : %.2f km/s\n',v0);

fprintf('\nPositive-sequence characteristic impedance: %.2f ohm\n',Z1);
fprintf('Zero-sequence characteristic impedance    : %.2f ohm\n',Z0);

fprintf('\nParameter status: %s\n', TL.line.parameter_status);
fprintf('Project status  : %s\n', TL.status);

fprintf('\nSimulink model is open and configured.\n');
fprintf('Simulation has NOT been started.\n');

fprintf('\n============================================\n');
