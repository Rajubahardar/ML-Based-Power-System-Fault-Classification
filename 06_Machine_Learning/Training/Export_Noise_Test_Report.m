%% EXPORT NOISE ROBUSTNESS RESULTS
clc;
clear;
close all;

projectRoot = 'D:\MATLAB_Projects\TL_Fault_AI';

resultFolder = fullfile(projectRoot, ...
    '06_Machine_Learning', ...
    'Noise_Robustness_Results');

summaryFile = fullfile(resultFolder, ...
    'Noise_Robustness_Summary.csv');

allFile = fullfile(resultFolder, ...
    'Noise_Robustness_All_Results.csv');

%% Check input files
if ~isfile(summaryFile) || ~isfile(allFile)
    error('Noise robustness result files were not found.');
end

%% Load results
S = readtable(summaryFile);
A = readtable(allFile);

%% Display detailed results
fprintf('\nFOLD-WISE RESULTS\n');
disp(A);

fprintf('\nMEAN RESULTS\n');
disp(S);

%% Create consolidated Excel workbook
excelFile = fullfile(resultFolder, ...
    'Noise_Robustness_Final_Report.xlsx');

writetable(A, excelFile, 'Sheet', 'Fold_Wise_Results');
writetable(S, excelFile, 'Sheet', 'Mean_Results');

%% Identify models and noise levels
if iscell(S.Model)
    models = unique(S.Model, 'stable');
else
    models = cellstr(unique(string(S.Model), 'stable'));
end

noiseLevels = unique(S.NoisePercent);
noiseLevels = sort(noiseLevels);

%% Plot accuracy comparison
fig = figure('Color', 'w');
hold on;

for k = 1:numel(models)

    idx = strcmp(string(S.Model), string(models{k}));
    T = S(idx, :);

    T = sortrows(T, 'NoisePercent');

    plot(T.NoisePercent, T.MeanAccuracy * 100, ...
        '-o', ...
        'LineWidth', 1.8, ...
        'MarkerSize', 7, ...
        'DisplayName', strrep(models{k}, '_', ' '));

end

xlabel('Measurement Noise (%)');
ylabel('Mean Accuracy (%)');
title('Noise Robustness - Accuracy Comparison');
legend('Location', 'best');
grid on;
xticks(noiseLevels);
ylim([0 105]);
xlim([min(noiseLevels), max(noiseLevels)]);

exportgraphics(fig, fullfile(resultFolder, ...
    'Final_Accuracy_Comparison.png'), ...
    'Resolution', 300);

savefig(fig, fullfile(resultFolder, ...
    'Final_Accuracy_Comparison.fig'));

%% Plot macro F1 comparison
fig = figure('Color', 'w');
hold on;

for k = 1:numel(models)

    idx = strcmp(string(S.Model), string(models{k}));
    T = S(idx, :);

    T = sortrows(T, 'NoisePercent');

    plot(T.NoisePercent, T.MeanMacroF1 * 100, ...
        '-o', ...
        'LineWidth', 1.8, ...
        'MarkerSize', 7, ...
        'DisplayName', strrep(models{k}, '_', ' '));

end

xlabel('Measurement Noise (%)');
ylabel('Mean Macro F1 (%)');
title('Noise Robustness - Macro F1 Comparison');
legend('Location', 'best');
grid on;
xticks(noiseLevels);
ylim([0 105]);
xlim([min(noiseLevels), max(noiseLevels)]);

exportgraphics(fig, fullfile(resultFolder, ...
    'Final_MacroF1_Comparison.png'), ...
    'Resolution', 300);

savefig(fig, fullfile(resultFolder, ...
    'Final_MacroF1_Comparison.fig'));

%% Export individual model results
for k = 1:numel(models)

    idx = strcmp(string(S.Model), string(models{k}));
    T = S(idx, :);

    modelFile = fullfile(resultFolder, ...
        [models{k}, '_Noise_Robustness.xlsx']);

    writetable(T, modelFile, 'Sheet', 'Mean_Results');

end

%% Completion message
fprintf('\n========================================\n');
fprintf('NOISE ROBUSTNESS REPORT EXPORTED\n');
fprintf('========================================\n');

fprintf('\nExcel report:\n%s\n', excelFile);

fprintf('\nGenerated files:\n');
fprintf('1. Noise_Robustness_Final_Report.xlsx\n');
fprintf('2. Final_Accuracy_Comparison.png\n');
fprintf('3. Final_MacroF1_Comparison.png\n');
fprintf('4. Final_Accuracy_Comparison.fig\n');
fprintf('5. Final_MacroF1_Comparison.fig\n');

fprintf('\nExport completed successfully.\n');