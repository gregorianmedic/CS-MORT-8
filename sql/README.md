# SQL Queries for CS-MORT-8

This folder contains the BigQuery SQL queries used to extract and define the study cohorts from PhysioNet databases.

## Prerequisites

1. **PhysioNet Credentialed Access** to:
   - MIMIC-IV v3.1: https://physionet.org/content/mimiciv/3.1/
   - eICU-CRD: https://physionet.org/content/eicu-crd/2.0/

2. **Google Cloud Project** linked to PhysioNet BigQuery datasets

## Query Files

| File | Description | Output |
|------|-------------|--------|
| `01_cohort_generation.sql` | Primary cohort definition for MIMIC-IV | N = 3,405 ICU stays |
| `02_consort_flow_counts.sql` | Generates counts for CONSORT flow diagram | Step-by-step exclusion counts |

## Usage

### Option 1: BigQuery Console
1. Navigate to [BigQuery Console](https://console.cloud.google.com/bigquery)
2. Ensure your project has access to PhysioNet datasets
3. Copy and paste the SQL query
4. Run the query

### Option 2: Command Line (bq tool)
```bash
bq query --use_legacy_sql=false < 01_cohort_generation.sql
```

### Option 3: Python (pandas-gbq)
```python
import pandas as pd
from google.cloud import bigquery

client = bigquery.Client(project='your-project-id')

with open('01_cohort_generation.sql', 'r') as f:
    query = f.read()

df = client.query(query).to_dataframe()
```

## Cohort Definition Summary

### Inclusion Criteria
- First care unit = Coronary Care Unit (CCU)
- Age ≥18 years
- ICU length of stay ≥8 hours
- Primary cardiac diagnosis (AMI, HF, cardiomyopathy, arrhythmia, or valvular disease)
- Cardiogenic shock: documented diagnosis OR ≥2 hemodynamic criteria within 24h

### Hemodynamic Criteria (need ≥2 within 24h)
- Systolic blood pressure <90 mmHg
- Vasopressor requirement
- Lactate ≥2.0 mmol/L

### Exclusion Criteria
- Positive blood culture within 24h WITHOUT documented cardiogenic shock diagnosis

## Data Sources

| Table | Description |
|-------|-------------|
| `mimiciv_3_1_icu.icustays` | ICU stay information |
| `mimiciv_3_1_hosp.patients` | Patient demographics |
| `mimiciv_3_1_hosp.admissions` | Hospital admissions and outcomes |
| `mimiciv_3_1_hosp.diagnoses_icd` | ICD diagnosis codes |
| `mimiciv_3_1_hosp.labevents` | Laboratory results |
| `mimiciv_3_1_hosp.microbiologyevents` | Microbiology cultures |
| `mimiciv_3_1_icu.chartevents` | Vital signs and assessments |
| `mimiciv_3_1_derived.vasoactive_agent` | Vasopressor administration |
| `mimiciv_note.discharge` | Discharge summaries (for text search) |

## Expected Output

The `01_cohort_generation.sql` query returns one row per ICU stay with the following key columns:

| Column | Description |
|--------|-------------|
| `stay_id` | Unique ICU stay identifier |
| `subject_id` | Patient identifier |
| `hadm_id` | Hospital admission identifier |
| `age` | Age at ICU admission |
| `gender` | Patient sex |
| `cs_etiology` | Cardiogenic shock etiology (AMI-CS, HF-CS, etc.) |
| `hospital_expire_flag` | In-hospital mortality (0/1) |
| `has_cs_doc` | CS documentation present (0/1) |
| `criteria_0to24h_count` | Number of hemodynamic criteria met |

## Notes

- Queries are written for Google BigQuery SQL syntax
- The `physionet-data` project prefix assumes standard PhysioNet BigQuery access
- Runtime: approximately 2-5 minutes per query depending on resources
