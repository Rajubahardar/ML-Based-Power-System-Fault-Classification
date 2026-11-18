# ML-Based Power System Fault Classification

A MATLAB/Simulink-based machine learning project for detecting and classifying transmission-line faults using three-phase voltage and current measurements.

## Project Overview

- **System:** 132 kV, 50 Hz, 100 km transmission line
- **Platform:** MATLAB R2024b and Simulink
- **Dataset:** 25,000 samples with 60 statistical features
- **Classes:** Normal, LG, LL, LLG, and Three-Phase Fault
- **Machine Learning Models:** Bagged Trees and Gaussian SVM

## Overall Model Performance

| Metric        | Bagged Trees | Gaussian SVM |
| ------------- | -----------: | -----------: |
| Test Accuracy |       84.37% |       81.73% |
| Test Macro-F1 |       0.8384 |       0.8199 |

## Controlled Robustness Evaluation

Three training strategies were compared:

- **A:** Clean training data
- **B:** Clean + noise training data
- **C:** Mixed training data (clean, noise, and outliers)

| Strategy | Test Condition | Samples | BT Accuracy | BT Macro-F1 | SVM Accuracy | SVM Macro-F1 |
| -------- | -------------- | ------: | ----------: | ----------: | -----------: | -----------: |
| A        | Clean          |   2,597 |     85.984% |     0.85776 |      89.680% |      0.89822 |
| A        | Noise          |     571 |     86.690% |     0.86450 |      91.068% |      0.90981 |
| A        | Outlier        |     582 |     78.351% |     0.77223 |      29.897% |      0.23131 |
| B        | Clean          |   2,597 |     85.907% |     0.85758 |      89.873% |      0.90002 |
| B        | Noise          |     571 |     86.515% |     0.86293 |      92.119% |      0.91965 |
| B        | Outlier        |     582 |     77.320% |     0.76341 |      29.381% |      0.22715 |
| C        | Clean          |   2,597 |     85.714% |     0.85507 |      90.065% |      0.90164 |
| C        | Noise          |     571 |     85.814% |     0.85480 |      91.944% |      0.91823 |
| C        | Outlier        |     582 |     79.725% |     0.78696 |      34.880% |      0.29381 |

## Key Findings

- Gaussian SVM performs better under clean and noisy test conditions.
- Bagged Trees demonstrates stronger robustness against outlier-contaminated samples.
- Including outliers during training improves SVM outlier performance, although its accuracy remains limited.

## Technologies Used

MATLAB, Simulink, Statistics and Machine Learning Toolbox, signal processing, feature extraction, and supervised machine learning.

## Dataset Disclaimer

The original 2,480-sample dataset was generated through MATLAB/Simulink simulations. The extended 25,000-sample dataset is synthetic and includes feature-level noise and outlier variations. Results are intended for algorithm development and experimental comparison; real-grid or field validation has not been claimed.
