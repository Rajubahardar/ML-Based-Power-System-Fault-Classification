
clc;
clear;

%% TRANSMISSION LINE PROPAGATION SPEED CHECK

% Existing transmission-line parameters
L1 = 0.001;       % Positive-sequence inductance (H/km)
C1 = 0.010e-6;    % Positive-sequence capacitance (F/km)

L0 = 0.003;       % Zero-sequence inductance (H/km)
C0 = 0.006e-6;    % Zero-sequence capacitance (F/km)

% Speed of light (km/s)
c = 300000;

%% Calculate propagation speeds

v1 = 1 / sqrt(L1 * C1);
v0 = 1 / sqrt(L0 * C0);

fprintf('\n===== PROPAGATION SPEED RESULTS =====\n');

fprintf('Positive-sequence speed: %.2f km/s\n', v1);
fprintf('Zero-sequence speed:     %.2f km/s\n', v0);
fprintf('Speed of light:          %.2f km/s\n', c);

%% Check whether warning condition exists

if v1 >= c
    fprintf('\nWARNING: Positive-sequence speed exceeds the speed of light.\n');
else
    fprintf('\nPositive-sequence speed is within the limit.\n');
end

if v0 >= c
    fprintf('WARNING: Zero-sequence speed exceeds the speed of light.\n');
else
    fprintf('Zero-sequence speed is within the limit.\n');
end

%% Calculate minimum capacitance required

C1_min = 1 / (L1 * c^2);
C0_min = 1 / (L0 * c^2);

fprintf('\n===== MINIMUM REQUIRED CAPACITANCE =====\n');

fprintf('Minimum C1: %.8f uF/km\n', C1_min * 1e6);
fprintf('Minimum C0: %.8f uF/km\n', C0_min * 1e6);

fprintf('\n===== IMPORTANT =====\n');
fprintf('No Simulink parameters have been changed.\n');
fprintf('Do not change capacitance until actual line data is verified.\n');
