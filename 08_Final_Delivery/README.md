# AI-Assisted Transmission-Line Fault Detection and Classification

## Project Overview

This project develops an AI-assisted system for detecting and classifying faults on a 132 kV transmission line using MATLAB and Simulink. The system uses statistical features extracted from simulated waveform data and machine learning classifiers.

## Project Structure

- 01_Project_Requirements: Project specifications and requirements
- 02_Engineering_Design: Engineering design documentation
- 03_Simulink_Models: Simulink transmission line model
- 04_Data_Generation: Fault scenario generation and simulated data
- 05_Feature_Extraction: Feature extraction scripts and results
- 06_Machine_Learning: Trained models and classification results
- 07_Experiments: Robustness testing and evaluation results
- 08_Final_Delivery: Final delivery files (this directory)
- 09_MATLAB_Dashboard: MATLAB dashboard and demonstration scripts
- 10_Documentation: Additional documentation
- LinkedIn_Package: LinkedIn publication materials

## MATLAB Requirements

- MATLAB R2024b (or newer)
- Statistics and Machine Learning Toolbox (for Bagged Trees and SVM)
- Signal Processing Toolbox (for feature extraction)
- Simulink (for transmission line model)
- Deep Learning Toolbox (optional, for CNN - not used in this version)

## Execution Order

1. Run fault scenario generation in 04_Data_Generation
2. Run feature extraction in 05_Feature_Extraction
3. Run data splitting in 06_Machine_Learning/Split
4. Train classifiers in 06_Machine_Learning
5. Run robustness experiments in 07_Experiments
6. Run integrated detection in 09_MATLAB_Dashboard

## Running the Simulink Model

1. Open `03_Simulink_Models2. Set simulation parameters (duration, fault scenarios)
3. Run the simulation
4. Results available in 04_Data_Generation

## Training Classifiers

1. Run feature extraction scripts to generate the dataset
2. Run `Scenario_Wise_Data_Split_5Class.mat` to split data
3. Train Bagged Trees and Gaussian SVM classifiers
4. Evaluate and save results

## Evaluating Classifiers

1. Load trained models from 06_Machine_Learning
2. Run evaluation scripts for test set and robustness experiments
3. Compare results

## Running Integrated Detection

1. Run `09_MATLAB_Dashboard/Run_Integrated_Detection.m`
2. Input voltage/current waveforms
3. View classification results and timestamps

## Known Limitations

- No real-time hardware deployment tested
- Sequence-component classifier requires improvement
- Deep Learning Toolbox not available for 1D-CNN implementation
- Simulation-based results only (no field testing)

## License

For academic and research use only. Contact project lead for commercial licensing.