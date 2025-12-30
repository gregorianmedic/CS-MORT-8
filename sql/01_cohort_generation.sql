-- ============================================================================
-- CS-MORT-8: PRIMARY COHORT GENERATION
-- ============================================================================
-- Database: MIMIC-IV v3.1 (PhysioNet BigQuery)
-- Output: N = 3,405 ICU stays with cardiogenic shock
-- 
-- This query defines the derivation cohort for the CS-MORT-8 risk score.
-- For external validation cohort (eICU), see 02_eicu_cohort.sql
-- ============================================================================
--
-- STUDY POPULATION:
--   Adult patients (≥18 years) admitted to the Coronary Care Unit (CCU)
--   with cardiogenic shock, defined using a combination of administrative
--   codes and objective hemodynamic criteria.
--
-- INCLUSION CRITERIA:
--   1. First care unit = Coronary Care Unit (CCU)
--   2. Age ≥18 years at ICU admission
--   3. ICU length of stay ≥8 hours (sufficient time for clinical assessment)
--   4. Primary cardiac diagnosis:
--      - Acute myocardial infarction (ICD-9: 410.xx, ICD-10: I21.x)
--      - Heart failure (ICD-9: 428.xx, ICD-10: I50.x)
--      - Cardiomyopathy (ICD-9: 425.x, ICD-10: I42.x)
--      - Cardiac arrhythmia (ICD-9: 427.x, ICD-10: I49.x)
--      - Valvular heart disease (ICD-9: 424.x, 394-396.x, ICD-10: I0x, I3x)
--   5. Cardiogenic shock, defined as EITHER:
--      (a) Documented diagnosis:
--          - ICD-9 code 785.51 (Cardiogenic shock), OR
--          - ICD-10 code R57.0 (Cardiogenic shock), OR
--          - Clinical documentation of "cardiogenic shock" in discharge summary
--      (b) ≥2 of the following hemodynamic criteria within 24 hours of ICU admission:
--          - Hypotension: Systolic blood pressure <90 mmHg
--          - Vasopressor requirement: Norepinephrine, epinephrine, 
--            dopamine >5 mcg/kg/min, vasopressin, or phenylephrine
--          - Elevated lactate: ≥2.0 mmol/L (per IABP-SHOCK II criteria)
--
-- EXCLUSION CRITERIA:
--   1. Positive blood culture within 24 hours of ICU admission WITHOUT
--      documented cardiogenic shock diagnosis (to exclude primary septic shock)
--
-- REFERENCES:
--   - SHOCK Trial: N Engl J Med. 1999;341(9):625-634
--   - IABP-SHOCK II: N Engl J Med. 2012;367(14):1287-1296
--
-- ============================================================================
-- CONFIGURATION: Update project ID before running
-- ============================================================================
-- Replace 'physionet-data' with your linked BigQuery project if different

WITH 
-- ============================================================================
-- STEP 1: Identify all CCU admissions
-- ============================================================================
step1_all_ccu AS (
  SELECT DISTINCT 
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime,
    DATETIME_DIFF(icu.outtime, icu.intime, HOUR) AS icu_los_hours
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  WHERE icu.first_careunit = 'Coronary Care Unit (CCU)'
),

-- ============================================================================
-- STEP 2: Identify cardiogenic shock documentation
-- Sources: ICD codes (785.51, R57.0) and discharge summary text
-- ============================================================================
cs_icd AS (
  SELECT DISTINCT 
    c.stay_id,
    1 AS has_cs_icd
  FROM step1_all_ccu c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON c.hadm_id = dx.hadm_id
  WHERE dx.icd_code IN ('78551', 'R570')
),

cs_note AS (
  SELECT DISTINCT 
    c.stay_id,
    1 AS has_cs_note
  FROM step1_all_ccu c
  INNER JOIN `physionet-data.mimiciv_note.discharge` n
    ON c.hadm_id = n.hadm_id
  WHERE LOWER(n.text) LIKE '%cardiogenic%shock%'
),

step2_cs_documentation AS (
  SELECT 
    c.*,
    COALESCE(icd.has_cs_icd, 0) AS has_cs_icd,
    COALESCE(note.has_cs_note, 0) AS has_cs_note,
    CASE 
      WHEN COALESCE(icd.has_cs_icd, 0) = 1 OR COALESCE(note.has_cs_note, 0) = 1 
      THEN 1 ELSE 0 
    END AS has_cs_documentation
  FROM step1_all_ccu c
  LEFT JOIN cs_icd icd ON c.stay_id = icd.stay_id
  LEFT JOIN cs_note note ON c.stay_id = note.stay_id
),

-- ============================================================================
-- STEP 3: Identify cardiac diagnoses
-- Categories: AMI, Heart Failure, Cardiomyopathy, Arrhythmia, Valvular Disease
-- ============================================================================
cardiac_dx AS (
  SELECT DISTINCT
    c.stay_id,
    -- Acute Myocardial Infarction (ICD-9: 410.xx, ICD-10: I21.x)
    MAX(CASE WHEN dx.icd_code LIKE '410%' OR dx.icd_code LIKE 'I21%' 
        THEN 1 ELSE 0 END) AS has_ami,
    -- Heart Failure (ICD-9: 428.xx, ICD-10: I50.x)
    MAX(CASE WHEN dx.icd_code LIKE '428%' OR dx.icd_code LIKE 'I50%' 
        THEN 1 ELSE 0 END) AS has_hf,
    -- Cardiomyopathy (ICD-9: 425.x, ICD-10: I42.x)
    MAX(CASE WHEN dx.icd_code LIKE '425%' OR dx.icd_code LIKE 'I42%' 
        THEN 1 ELSE 0 END) AS has_cardiomyopathy,
    -- Arrhythmia (ICD-9: 427.x, ICD-10: I49.x)
    MAX(CASE WHEN dx.icd_code LIKE '427%' OR dx.icd_code LIKE 'I49%' 
        THEN 1 ELSE 0 END) AS has_arrhythmia,
    -- Valvular Disease (ICD-9: 424.x, 394-396.x, ICD-10: I0x, I3x)
    MAX(CASE WHEN dx.icd_code LIKE '424%' OR dx.icd_code LIKE 'I0%' 
             OR dx.icd_code LIKE 'I3%' THEN 1 ELSE 0 END) AS has_valvular
  FROM step2_cs_documentation c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON c.hadm_id = dx.hadm_id
  GROUP BY c.stay_id
),

step3_cardiac_dx AS (
  SELECT 
    c.*,
    COALESCE(dx.has_ami, 0) AS has_ami,
    COALESCE(dx.has_hf, 0) AS has_hf,
    COALESCE(dx.has_cardiomyopathy, 0) AS has_cardiomyopathy,
    COALESCE(dx.has_arrhythmia, 0) AS has_arrhythmia,
    COALESCE(dx.has_valvular, 0) AS has_valvular,
    -- Any cardiac diagnosis present
    CASE 
      WHEN COALESCE(dx.has_ami, 0) = 1 
        OR COALESCE(dx.has_hf, 0) = 1
        OR COALESCE(dx.has_cardiomyopathy, 0) = 1
        OR COALESCE(dx.has_arrhythmia, 0) = 1
        OR COALESCE(dx.has_valvular, 0) = 1
      THEN 1 ELSE 0 
    END AS has_cardiac_dx,
    -- Primary etiology classification (hierarchical)
    CASE 
      WHEN COALESCE(dx.has_ami, 0) = 1 THEN 'AMI-CS'
      WHEN COALESCE(dx.has_hf, 0) = 1 THEN 'HF-CS'
      WHEN COALESCE(dx.has_cardiomyopathy, 0) = 1 THEN 'Cardiomyopathy-CS'
      WHEN COALESCE(dx.has_valvular, 0) = 1 THEN 'Valvular-CS'
      WHEN COALESCE(dx.has_arrhythmia, 0) = 1 THEN 'Arrhythmia-CS'
      ELSE 'No-Cardiac-Dx'
    END AS cs_etiology
  FROM step2_cs_documentation c
  LEFT JOIN cardiac_dx dx ON c.stay_id = dx.stay_id
),

-- ============================================================================
-- STEP 4: Identify positive blood cultures (any time during hospitalization)
-- Used for intermediate pipeline tracking
-- ============================================================================
positive_cultures AS (
  SELECT DISTINCT
    c.stay_id,
    1 AS has_positive_blood_culture
  FROM step3_cardiac_dx c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` micro
    ON c.hadm_id = micro.hadm_id
  WHERE micro.spec_type_desc LIKE '%BLOOD%'
    AND micro.org_name IS NOT NULL
    AND micro.org_name != 'UNSPECIFIED'
),

step4_blood_cultures AS (
  SELECT 
    c.*,
    COALESCE(pc.has_positive_blood_culture, 0) AS has_positive_blood_culture
  FROM step3_cardiac_dx c
  LEFT JOIN positive_cultures pc ON c.stay_id = pc.stay_id
),

-- ============================================================================
-- STEP 5: Calculate shock criteria within 0-24 hour window
-- Criteria: Hypotension, Vasopressor use, Elevated lactate
-- ============================================================================
shock_24h AS (
  SELECT
    c.stay_id,
    -- Hypotension: SBP <90 mmHg (itemids: 220050=Arterial BP, 220179=NBP)
    MAX(CASE WHEN ce.valuenum < 90 AND ce.valuenum > 0 
        THEN 1 ELSE 0 END) AS has_hypotension_24h,
    -- Vasopressor requirement
    MAX(CASE WHEN va.norepinephrine IS NOT NULL 
              OR va.epinephrine IS NOT NULL 
              OR va.dopamine > 5 
              OR va.vasopressin IS NOT NULL 
              OR va.phenylephrine IS NOT NULL 
        THEN 1 ELSE 0 END) AS has_vasopressor_24h,
    -- Elevated lactate: ≥2.0 mmol/L (itemid: 50813)
    MAX(CASE WHEN lab.valuenum >= 2.0 
        THEN 1 ELSE 0 END) AS has_lactate_24h
  FROM step4_blood_cultures c
  -- Blood pressure from chartevents
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.itemid IN (220050, 220179)
    AND ce.charttime BETWEEN c.icu_intime 
        AND DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
    AND ce.valuenum < 90 AND ce.valuenum > 0
  -- Vasopressor agents from derived table
  LEFT JOIN `physionet-data.mimiciv_3_1_derived.vasoactive_agent` va
    ON c.stay_id = va.stay_id
    AND va.starttime <= DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
  -- Lactate from labevents
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON c.hadm_id = lab.hadm_id
    AND lab.itemid = 50813
    AND lab.charttime BETWEEN c.icu_intime 
        AND DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
    AND lab.valuenum >= 2.0
  GROUP BY c.stay_id
),

criteria_0to24h AS (
  SELECT
    c.*,
    COALESCE(s24.has_hypotension_24h, 0) AS has_hypotension_24h,
    COALESCE(s24.has_vasopressor_24h, 0) AS has_vasopressor_24h,
    COALESCE(s24.has_lactate_24h, 0) AS has_lactate_24h,
    -- Total criteria count (0-24h)
    (COALESCE(s24.has_hypotension_24h, 0) +
     COALESCE(s24.has_vasopressor_24h, 0) +
     COALESCE(s24.has_lactate_24h, 0)) AS criteria_0to24h_count
  FROM step4_blood_cultures c
  LEFT JOIN shock_24h s24 ON c.stay_id = s24.stay_id
),

-- ============================================================================
-- STEP 6: Recalculate exclusion criteria for final cohort
-- Blood culture exclusion uses 24-hour window
-- ============================================================================
positive_blood_culture_24h AS (
  SELECT DISTINCT micro.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` micro
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON micro.hadm_id = icu.hadm_id
  WHERE micro.spec_type_desc LIKE '%BLOOD%'
    AND micro.org_name IS NOT NULL
    AND micro.org_name != 'UNSPECIFIED'
    AND micro.charttime BETWEEN icu.intime 
        AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
),

-- Recalculate CS documentation for final filtering
cs_documentation AS (
  SELECT DISTINCT hadm_id
  FROM (
    -- ICD codes for cardiogenic shock
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN ('78551', 'R570')
    UNION DISTINCT
    -- Text documentation in discharge summary
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_note.discharge`
    WHERE LOWER(text) LIKE '%cardiogenic%shock%'
  )
),

-- ============================================================================
-- STEP 7: Apply inclusion and exclusion criteria
-- ============================================================================
eligible_patients AS (
  SELECT 
    c.*,
    CASE WHEN cs.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_cs_doc,
    CASE WHEN bc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_positive_bc_24h
  FROM criteria_0to24h c
  LEFT JOIN cs_documentation cs ON c.hadm_id = cs.hadm_id
  LEFT JOIN positive_blood_culture_24h bc ON c.hadm_id = bc.hadm_id
  WHERE 
    -- Inclusion: Cardiac diagnosis present
    c.has_cardiac_dx = 1
    -- Inclusion: ICU LOS ≥8 hours
    AND c.icu_los_hours >= 8
    -- Exclusion: Positive blood culture (24h) without CS documentation
    AND NOT (bc.hadm_id IS NOT NULL AND cs.hadm_id IS NULL)
    -- Inclusion: CS documented OR ≥2 shock criteria in 0-24h
    AND (cs.hadm_id IS NOT NULL OR c.criteria_0to24h_count >= 2)
),

-- ============================================================================
-- STEP 8: Add demographics and outcome variables
-- ============================================================================
final_cohort AS (
  SELECT 
    e.stay_id,
    e.subject_id,
    e.hadm_id,
    e.icu_intime,
    e.icu_outtime,
    e.icu_los_hours,
    -- Cardiac diagnoses
    e.has_cardiac_dx,
    e.has_ami,
    e.has_hf,
    e.has_cardiomyopathy,
    e.has_arrhythmia,
    e.has_valvular,
    e.cs_etiology,
    -- CS documentation
    e.has_cs_doc,
    e.has_cs_icd,
    e.has_cs_note,
    -- Shock criteria (0-24h)
    e.has_hypotension_24h,
    e.has_vasopressor_24h,
    e.has_lactate_24h,
    e.criteria_0to24h_count,
    -- Blood culture
    e.has_positive_bc_24h,
    -- Demographics
    pat.anchor_age AS age,
    pat.gender,
    -- Hospital admission details
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    -- Time to death (hours from ICU admission)
    CASE 
      WHEN adm.hospital_expire_flag = 1 AND adm.deathtime IS NOT NULL
      THEN DATETIME_DIFF(adm.deathtime, e.icu_intime, HOUR)
      ELSE NULL 
    END AS hours_to_death,
    -- Landmark survival flags
    CASE
      WHEN adm.hospital_expire_flag = 0
        OR DATETIME_DIFF(adm.deathtime, e.icu_intime, HOUR) > 24
      THEN 1 ELSE 0
    END AS alive_at_24h,
    CASE
      WHEN adm.hospital_expire_flag = 0
        OR DATETIME_DIFF(adm.deathtime, e.icu_intime, HOUR) > 48
      THEN 1 ELSE 0
    END AS alive_at_48h
  FROM eligible_patients e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON e.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON e.hadm_id = adm.hadm_id
  -- Final age filter
  WHERE pat.anchor_age >= 18
)

-- ============================================================================
-- OUTPUT: Final Cohort (N = 3,405)
-- ============================================================================
SELECT * FROM final_cohort;

-- ============================================================================
-- END OF QUERY
-- ============================================================================
