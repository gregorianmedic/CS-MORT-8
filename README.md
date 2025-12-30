# CS-MORT-8: A Bedside Risk Score for In-Hospital Mortality in Cardiogenic Shock

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.XXXXXXX.svg)](https://doi.org/10.5281/zenodo.XXXXXXX)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.9+](https://img.shields.io/badge/python-3.9+-blue.svg)](https://www.python.org/downloads/)

This repository contains the complete analytical code for developing and validating CS-MORT-8, a parsimonious 8-variable bedside risk score for predicting in-hospital mortality in patients with cardiogenic shock.

## Overview

CS-MORT-8 uses eight routinely available clinical variables to stratify mortality risk without requiring echocardiography:

| Variable | Points |
|----------|--------|
| Lactate (mmol/L) | 0-12 |
| Age (years) | 0-3 |
| Blood urea nitrogen (mg/dL) | 0-4 |
| Urine output (mL/kg/hr) | 0-2 |
| Number of vasopressors | 0-2 |
| Invasive mechanical ventilation | 0-2 |
| Acute myocardial infarction | 0-2 |
| Hemoglobin (g/dL) | 0-1 |

**Total score range: 0-28 points**

### Risk Stratification

| Category | Score | Mortality |
|----------|-------|-----------|
| Low | 0-5 | 8.7% |
| Moderate | 6-10 | 20.9% |
| High | 11-15 | 42.2% |
| Very High | ≥16 | 86.5% |

### Performance

- **Internal validation (MIMIC-IV):** AUROC 0.761 (95% CI: 0.728-0.795)
- **External validation (eICU):** AUROC 0.712 (95% CI: 0.687-0.740)

## Repository Structure

```
CS-MORT-8/
├── README.md                        # This file
├── LICENSE                          # MIT License
├── requirements.txt                 # Python dependencies
├── CS_MORT_8_Analysis_Code.ipynb   # Complete analysis notebook
├── sql/                             # BigQuery cohort definition queries
│   ├── README.md                    # SQL documentation
│   ├── 01_cohort_generation.sql    # Primary cohort (MIMIC-IV, n=3,405)
│   └── 02_consort_flow_counts.sql  # CONSORT flow diagram counts
└── outputs/                         # Generated figures and tables (after running)
```

## Data Access

This analysis uses two credentialed-access databases from PhysioNet:

### MIMIC-IV v3.1 (Derivation Cohort)
- **Source:** Beth Israel Deaconess Medical Center (2008-2022)
- **Sample size:** n = 3,405
- **Access:** https://physionet.org/content/mimiciv/3.1/

### eICU Collaborative Research Database (External Validation)
- **Source:** 208 US hospitals (2014-2015)
- **Sample size:** n = 1,869
- **Access:** https://physionet.org/content/eicu-crd/2.0/

### Requirements for Data Access
1. Complete CITI Program training in human subjects research
2. Sign the PhysioNet Credentialed Health Data Use Agreement
3. Link your Google Cloud project to PhysioNet BigQuery datasets

## Quick Start

### Option A: Google Colab (Recommended)

1. Download `CS_MORT_8_Analysis_Code.ipynb`
2. Upload to [Google Colab](https://colab.research.google.com/)
3. Edit the `PROJECT_ID` variable with your Google Cloud project ID
4. Run all cells sequentially

### Option B: Local Environment

```bash
# Clone the repository
git clone https://github.com/[username]/CS-MORT-8.git
cd CS-MORT-8

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure Google Cloud credentials
export GOOGLE_APPLICATION_CREDENTIALS="path/to/your/credentials.json"

# Launch Jupyter
jupyter notebook CS_MORT_8_Analysis_Code.ipynb
```

## Reproducibility

| Parameter | Value |
|-----------|-------|
| Random Seed | 42 |
| Train/Test Split | 70%/30% (stratified by outcome) |
| Bootstrap Iterations | 1000 |
| Cross-Validation | 5-fold stratified |
| Python Version | 3.9+ |

All stochastic operations use the same random seed for reproducibility. Running the notebook from start to finish will regenerate all results reported in the manuscript.

## Expected Runtime

| Section | Estimated Time |
|---------|---------------|
| Data Acquisition (Parts 1-2) | 5-10 minutes |
| Preprocessing & Model Development (Parts 3-12) | 15-20 minutes |
| Validation & Comparison (Parts 13-18) | 20-30 minutes |
| Tables & Figures (Parts 19-22) | 10-15 minutes |
| **Total** | **~60-75 minutes** |

Runtime estimates assume Google Colab with standard CPU runtime.

## Citation

If you use this code or the CS-MORT-8 score in your research, please cite:

```
Otabor E, Lo KB, Okunlola A, Lam J, Alomari L, Hamilton M, Idowu A, Hassan A, 
Afolabi-Brown O. Development and External Validation of CS-MORT-8: A Parsimonious 
Risk Score for In-Hospital Mortality in Cardiogenic Shock. 
[Journal and DOI to be added upon publication]
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contact

**Corresponding Author:**  
Emmanuel Otabor, MD  
Department of Medicine, Jefferson Einstein Philadelphia Hospital  
Email: emmanuel.otabor@jefferson.edu

## Acknowledgments

- MIMIC-IV is provided by the MIT Laboratory for Computational Physiology
- eICU Collaborative Research Database is provided by Philips Healthcare in partnership with MIT
- Both databases are hosted on PhysioNet

---

**Disclaimer:** CS-MORT-8 is intended for research purposes and clinical decision support. It should not replace clinical judgment. Prospective validation is recommended before implementation in clinical practice.
