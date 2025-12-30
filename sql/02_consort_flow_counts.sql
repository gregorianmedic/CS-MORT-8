-- ============================================================================
-- CONSORT FLOW DIAGRAM - CARDIOGENIC SHOCK COHORT
-- ============================================================================
-- Database: MIMIC-IV v3.1 (PhysioNet)
-- This query generates counts for each step of cohort selection
-- suitable for creating a CONSORT flow diagram for publication.
-- ============================================================================

WITH 
-- ============================================================================
-- STEP 0: Total ICU admissions in MIMIC-IV
-- ============================================================================
step0_all_icu AS (
  SELECT COUNT(DISTINCT stay_id) AS n
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- ============================================================================
-- STEP 1: CCU admissions only
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

step1_count AS (
  SELECT COUNT(DISTINCT stay_id) AS n FROM step1_all_ccu
),

-- ============================================================================
-- STEP 2: Add CS documentation flags
-- ============================================================================
cs_icd AS (
  SELECT DISTINCT c.stay_id, 1 AS has_cs_icd
  FROM step1_all_ccu c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON c.hadm_id = dx.hadm_id
  WHERE dx.icd_code IN ('78551', 'R570')
),

cs_note AS (
  SELECT DISTINCT c.stay_id, 1 AS has_cs_note
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
    CASE WHEN COALESCE(icd.has_cs_icd, 0) = 1 OR COALESCE(note.has_cs_note, 0) = 1 
      THEN 1 ELSE 0 END AS has_cs_documentation
  FROM step1_all_ccu c
  LEFT JOIN cs_icd icd ON c.stay_id = icd.stay_id
  LEFT JOIN cs_note note ON c.stay_id = note.stay_id
),

-- ============================================================================
-- STEP 3: Add cardiac diagnosis flags
-- ============================================================================
cardiac_dx AS (
  SELECT DISTINCT c.stay_id,
    MAX(CASE WHEN dx.icd_code LIKE '410%' OR dx.icd_code LIKE 'I21%' THEN 1 ELSE 0 END) AS has_ami,
    MAX(CASE WHEN dx.icd_code LIKE '428%' OR dx.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_hf,
    MAX(CASE WHEN dx.icd_code LIKE '425%' OR dx.icd_code LIKE 'I42%' THEN 1 ELSE 0 END) AS has_cardiomyopathy,
    MAX(CASE WHEN dx.icd_code LIKE '427%' OR dx.icd_code LIKE 'I49%' THEN 1 ELSE 0 END) AS has_arrhythmia,
    MAX(CASE WHEN dx.icd_code LIKE '424%' OR dx.icd_code LIKE 'I0%' OR dx.icd_code LIKE 'I3%' THEN 1 ELSE 0 END) AS has_valvular
  FROM step2_cs_documentation c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx ON c.hadm_id = dx.hadm_id
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
    CASE WHEN COALESCE(dx.has_ami, 0) = 1 OR COALESCE(dx.has_hf, 0) = 1
           OR COALESCE(dx.has_cardiomyopathy, 0) = 1 OR COALESCE(dx.has_arrhythmia, 0) = 1
           OR COALESCE(dx.has_valvular, 0) = 1 THEN 1 ELSE 0 END AS has_cardiac_dx
  FROM step2_cs_documentation c
  LEFT JOIN cardiac_dx dx ON c.stay_id = dx.stay_id
),

-- ============================================================================
-- STEP 4: Add blood culture flags (any time)
-- ============================================================================
positive_cultures AS (
  SELECT DISTINCT c.stay_id, 1 AS has_positive_blood_culture
  FROM step3_cardiac_dx c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` micro
    ON c.hadm_id = micro.hadm_id
  WHERE micro.spec_type_desc LIKE '%BLOOD%'
    AND micro.org_name IS NOT NULL AND micro.org_name != 'UNSPECIFIED'
),

step4_blood_cultures AS (
  SELECT c.*, COALESCE(pc.has_positive_blood_culture, 0) AS has_positive_blood_culture
  FROM step3_cardiac_dx c
  LEFT JOIN positive_cultures pc ON c.stay_id = pc.stay_id
),

-- ============================================================================
-- STEP 5: Calculate shock criteria (0-24h window)
-- ============================================================================
shock_24h AS (
  SELECT c.stay_id,
    MAX(CASE WHEN ce.valuenum < 90 AND ce.valuenum > 0 THEN 1 ELSE 0 END) AS has_hypotension_24h,
    MAX(CASE WHEN va.norepinephrine IS NOT NULL OR va.epinephrine IS NOT NULL 
              OR va.dopamine > 5 OR va.vasopressin IS NOT NULL 
              OR va.phenylephrine IS NOT NULL THEN 1 ELSE 0 END) AS has_vasopressor_24h,
    MAX(CASE WHEN lab.valuenum >= 2.0 THEN 1 ELSE 0 END) AS has_lactate_24h
  FROM step4_blood_cultures c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id AND ce.itemid IN (220050, 220179)
    AND ce.charttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
    AND ce.valuenum < 90 AND ce.valuenum > 0
  LEFT JOIN `physionet-data.mimiciv_3_1_derived.vasoactive_agent` va
    ON c.stay_id = va.stay_id
    AND va.starttime <= DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON c.hadm_id = lab.hadm_id AND lab.itemid = 50813
    AND lab.charttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 24 HOUR)
    AND lab.valuenum >= 2.0
  GROUP BY c.stay_id
),

criteria_0to24h AS (
  SELECT c.*,
    COALESCE(s24.has_hypotension_24h, 0) AS has_hypotension_24h,
    COALESCE(s24.has_vasopressor_24h, 0) AS has_vasopressor_24h,
    COALESCE(s24.has_lactate_24h, 0) AS has_lactate_24h,
    (COALESCE(s24.has_hypotension_24h, 0) + COALESCE(s24.has_vasopressor_24h, 0) 
     + COALESCE(s24.has_lactate_24h, 0)) AS criteria_0to24h_count
  FROM step4_blood_cultures c
  LEFT JOIN shock_24h s24 ON c.stay_id = s24.stay_id
),

-- ============================================================================
-- STEP 6: Recalculate for final filtering
-- ============================================================================
positive_blood_culture_24h AS (
  SELECT DISTINCT micro.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` micro
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON micro.hadm_id = icu.hadm_id
  WHERE micro.spec_type_desc LIKE '%BLOOD%'
    AND micro.org_name IS NOT NULL AND micro.org_name != 'UNSPECIFIED'
    AND micro.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
),

cs_documentation AS (
  SELECT DISTINCT hadm_id FROM (
    SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN ('78551', 'R570')
    UNION DISTINCT
    SELECT DISTINCT hadm_id FROM `physionet-data.mimiciv_note.discharge`
    WHERE LOWER(text) LIKE '%cardiogenic%shock%'
  )
),

-- ============================================================================
-- STEP 7: Apply filters and add demographics
-- ============================================================================
with_final_flags AS (
  SELECT c.*,
    CASE WHEN cs.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_cs_doc,
    CASE WHEN bc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_positive_bc_24h,
    pat.anchor_age AS age,
    pat.gender
  FROM criteria_0to24h c
  LEFT JOIN cs_documentation cs ON c.hadm_id = cs.hadm_id
  LEFT JOIN positive_blood_culture_24h bc ON c.hadm_id = bc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON c.subject_id = pat.subject_id
)

-- ============================================================================
-- OUTPUT: CONSORT Flow Diagram Data
-- ============================================================================
SELECT 
  'Step 0: All ICU Admissions' AS step,
  (SELECT n FROM step0_all_icu) AS n,
  NULL AS excluded
UNION ALL
SELECT 
  'Step 1: CCU Admissions',
  (SELECT n FROM step1_count),
  (SELECT n FROM step0_all_icu) - (SELECT n FROM step1_count)
UNION ALL
SELECT 
  'Step 2a: Age >= 18 years',
  (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags WHERE age >= 18),
  (SELECT n FROM step1_count) - (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags WHERE age >= 18)
UNION ALL
SELECT 
  'Step 2b: ICU LOS >= 8 hours',
  (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags WHERE age >= 18 AND icu_los_hours >= 8),
  (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags WHERE age >= 18) - 
  (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags WHERE age >= 18 AND icu_los_hours >= 8)
UNION ALL
SELECT 
  'Step 3: Cardiac Diagnosis',
  (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags WHERE age >= 18 AND icu_los_hours >= 8 AND has_cardiac_dx = 1),
  (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags WHERE age >= 18 AND icu_los_hours >= 8) - 
  (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags WHERE age >= 18 AND icu_los_hours >= 8 AND has_cardiac_dx = 1)
UNION ALL
SELECT 
  'Step 4: CS Documented OR >= 2 Criteria',
  (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags 
   WHERE age >= 18 AND icu_los_hours >= 8 AND has_cardiac_dx = 1 
   AND (has_cs_doc = 1 OR criteria_0to24h_count >= 2)),
  (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags WHERE age >= 18 AND icu_los_hours >= 8 AND has_cardiac_dx = 1) - 
  (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags 
   WHERE age >= 18 AND icu_los_hours >= 8 AND has_cardiac_dx = 1 
   AND (has_cs_doc = 1 OR criteria_0to24h_count >= 2))
UNION ALL
SELECT 
  'Step 5: Excluded Primary Sepsis',
  (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags 
   WHERE age >= 18 AND icu_los_hours >= 8 AND has_cardiac_dx = 1 
   AND (has_cs_doc = 1 OR criteria_0to24h_count >= 2)
   AND (has_positive_bc_24h = 1 AND has_cs_doc = 0)),
  NULL
UNION ALL
SELECT 
  'FINAL COHORT',
  (SELECT COUNT(DISTINCT stay_id) FROM with_final_flags 
   WHERE age >= 18 AND icu_los_hours >= 8 AND has_cardiac_dx = 1 
   AND (has_cs_doc = 1 OR criteria_0to24h_count >= 2)
   AND NOT (has_positive_bc_24h = 1 AND has_cs_doc = 0)),
  NULL;
