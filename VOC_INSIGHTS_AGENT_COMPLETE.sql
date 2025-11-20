-- =====================================================
-- VOC INSIGHTS AGENT - COMPLETE DEPLOYMENT SCRIPT
-- Tampa Bay Rays - Voice of Customer Analysis
-- =====================================================
-- Description: Complete SQL codebase for the VOC Insights Agent
--              powered by Snowflake Cortex AI
-- Version: 1.0
-- Last Updated: November 4, 2025
-- Author: Tampa Bay Rays Strategy and Analytics Team
-- =====================================================
-- KEY FEATURES
-- =====================================================
-- ✅ AI-powered topic classification
-- ✅ Sentiment analysis
-- ✅ NPS segmentation
-- ✅ Revenue insights by segment
-- ✅ Monthly trend analysis with AI summaries
-- ✅ Buyer type insights
-- ✅ Semantic search across feedback
-- ✅ Cost monitoring and optimization
-- ✅ Parameterized functions for flexible analysis
-- =====================================================
-- DEPENDENCIES
-- =====================================================
-- Base Table: TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
-- Snowflake Cortex AI Functions:
--   - AI_CLASSIFY
--   - AI_SENTIMENT
--   - AI_AGG
--   - AI_SUMMARIZE_AGG
-- Snowflake Cortex Search Service
-- Semantic Model: voc_semantic_model.yaml
-- =====================================================
-- EVNIRONMENT STAGE SETUP WITH DIRECTORY ENABLED
-- =====================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE TBRDP_DW_CORTEX_XS_WH;

-- Create stage with directory support
DROP STAGE IF EXISTS TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS;

CREATE STAGE TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for Cortex Analyst semantic model YAML files';

-- Grant permissions (READ only - ACCOUNTADMIN is owner)
GRANT READ ON STAGE TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- Verify stage is set up correctly
DESC STAGE TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS;
LIST @TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS;

-- =====================================================
-- DATABASE & SCHEMA FOR AGENTS (if not already created)
-- =====================================================

USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE
    COMMENT = 'Database for Snowflake Intelligence agents and configurations';

GRANT USAGE ON DATABASE SNOWFLAKE_INTELLIGENCE TO ROLE PUBLIC;

CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_INTELLIGENCE.AGENTS
    COMMENT = 'Schema to store agent configurations';

GRANT USAGE ON SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS TO ROLE PUBLIC;

-- Grant agent creation privileges
GRANT CREATE AGENT ON SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS TO ROLE ACCOUNTADMIN;
GRANT CREATE AGENT ON SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- =====================================================
-- GRANT PERMISSIONS FOR VOC DATA ACCESS
-- =====================================================

USE ROLE ACCOUNTADMIN;

-- Grant access to the base view
GRANT SELECT ON VIEW TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI 
    TO ROLE TBRDP_DW_PROD_CORTEX_USER;

GRANT USAGE ON DATABASE TBRDP_DW_DEV TO ROLE TBRDP_DW_PROD_CORTEX_USER;
GRANT USAGE ON SCHEMA TBRDP_DW_DEV.IM_RPT TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- Grant warehouse usage
GRANT USAGE ON WAREHOUSE TBRDP_DW_CORTEX_XS_WH TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- Ensure Cortex functions are accessible
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- =====================================================
-- YAML GENERATION QUERY (for semantic model)
-- =====================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE TBRDP_DW_CORTEX_XS_WH;

WITH yaml_header AS (
    SELECT '# Snowflake Cortex Analyst Semantic Model
# Generated from SURVEY_SEMANTIC_MODEL table
# Table: V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI

name: voice_of_customer_survey_model
description: "Semantic model for Voice of Customer post-attendance survey data, enabling natural language queries about fan experience, satisfaction ratings, and attendance patterns."

tables:
  - name: voc_survey_data
    description: "Comprehensive survey response data from fans after game attendance"
    base_table: 
      database: TBRDP_DW_DEV
      schema: IM_RPT
      table: V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
    
    dimensions:' AS yaml_text
),
dimensions_yaml AS (
    SELECT LISTAGG(
        CONCAT(
            '      - name: ', COLUMN_NAME, '\n',
            '        display_name: "', REPLACE(COALESCE(DISPLAY_NAME, ''), '"', '\"'), '"\n',
            '        description: "', REPLACE(COALESCE(DESCRIPTION, ''), '"', '\"'), '"\n',
            '        expr: ', COALESCE(SQL_EXPRESSION, COLUMN_NAME), '\n',
            '        data_type: ', LOWER(REGEXP_REPLACE(FIELD_TYPE, '\\([0-9,]+\\)', '')), '\n',
            '        synonyms: ["', REPLACE(COALESCE(SYNONYMS, ''), ', ', '", "'), '"]'
        ), '\n\n'
    ) WITHIN GROUP (ORDER BY COLUMN_NAME) AS yaml_text
    FROM TBRDP_DW_PROD.LOAD.SURVEY_SEMANTIC_MODEL
    WHERE IS_DIMENSION = TRUE
),
measures_header AS (
    SELECT '
    
    measures:' AS yaml_text
),
measures_yaml AS (
    SELECT LISTAGG(
        CONCAT(
            '      - name: ', COLUMN_NAME, '\n',
            '        display_name: "', REPLACE(COALESCE(DISPLAY_NAME, ''), '"', '\"'), '"\n',
            '        description: "', REPLACE(COALESCE(DESCRIPTION, ''), '"', '\"'), '"\n',
            '        expr: ', COALESCE(SQL_EXPRESSION, COLUMN_NAME), '\n',
            '        data_type: ', LOWER(REGEXP_REPLACE(FIELD_TYPE, '\\([0-9,]+\\)', '')), '\n',
            '        aggregation: ', LOWER(COALESCE(AGGREGATION_FUNCTION, 'none')), '\n',
            '        synonyms: ["', REPLACE(COALESCE(SYNONYMS, ''), ', ', '", "'), '"]'
        ), '\n\n'
    ) WITHIN GROUP (ORDER BY COLUMN_NAME) AS yaml_text
    FROM TBRDP_DW_PROD.LOAD.SURVEY_SEMANTIC_MODEL
    WHERE IS_MEASURE = TRUE
),
static_yaml AS (
    SELECT '
    
    time_dimensions:
      - name: GAME_DATE
        display_name: "Game Date"
        description: "Date when the game was played"
        expr: GAME_DATE
        data_type: date
        
      - name: RESPONSE_DATE  
        display_name: "Survey Response Date"
        description: "Date when the survey was completed"
        expr: RESPONSE_DATE
        data_type: date' AS yaml_text
)
SELECT 
    CONCAT(
        h.yaml_text, '\n',
        d.yaml_text, '\n',
        mh.yaml_text, '\n', 
        m.yaml_text, '\n',
        s.yaml_text
    ) AS complete_yaml
FROM yaml_header h
CROSS JOIN dimensions_yaml d
CROSS JOIN measures_header mh
CROSS JOIN measures_yaml m
CROSS JOIN static_yaml s;


-- =====================================================
-- OVERALL FEEDBACK ANALYSIS VIEW - ALL YEARS
-- =====================================================
-- Description: AI-powered analysis of open-ended overall feedback
--              Provides sentiment classification and topic categorization
--              Covers all seasons (2023, 2024, 2025, and future)
-- =====================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE TBRDP_DW_CORTEX_XS_WH;

CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS AS
WITH base_data AS (
  SELECT
    qualtrics_id,
    game_date,
    season,
    buyer_type,
    OVERALL_NUMRAT AS satisfaction_rating,
    OVERALL_NUMRAT_OT AS feedback_text,
    LENGTH(OVERALL_NUMRAT_OT) AS feedback_length,
    OVERALL_NUMRAT_OT_PARENT_TOPICS AS existing_parent_topic,
    OVERALL_NUMRAT_OT_TOPICS AS existing_topic
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE OVERALL_NUMRAT_OT IS NOT NULL
    AND LENGTH(TRIM(OVERALL_NUMRAT_OT)) > 10
    AND season >= 2023  -- All years from 2023 forward
),
with_ai_analysis AS (
  SELECT
    *,
    -- Topic classification
    AI_CLASSIFY(
      feedback_text,
      ARRAY_CONSTRUCT(
        'Food & Beverage Quality',
        'Staff & Service',
        'Parking & Transportation',
        'Seating & Views',
        'Entertainment & Atmosphere',
        'Cleanliness & Facilities',
        'Pricing & Value',
        'Game Experience',
        'Safety & Security',
        'General Positive'
      )
    )['labels'][0]::VARCHAR AS ai_category,
    
    -- Sentiment classification directly from text
    AI_CLASSIFY(
      feedback_text,
      ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative')
    )['labels'][0]::VARCHAR AS sentiment_category,
    
    -- Keep original AI_SENTIMENT for reference
    AI_SENTIMENT(feedback_text):sentiment AS sentiment_value,
    
    -- NPS segment
    CASE 
      WHEN satisfaction_rating >= 9 THEN 'Promoter'
      WHEN satisfaction_rating BETWEEN 7 AND 8 THEN 'Passive'
      WHEN satisfaction_rating <= 6 THEN 'Detractor'
      ELSE 'Unknown'
    END AS nps_segment
  FROM base_data
)
SELECT
  qualtrics_id,
  game_date,
  season,
  buyer_type,
  satisfaction_rating,
  feedback_text,
  feedback_length,
  existing_parent_topic,
  existing_topic,
  ai_category,
  sentiment_category,
  sentiment_value,
  nps_segment,
  CONCAT(ai_category, ' - ', sentiment_category) AS detailed_category
FROM with_ai_analysis;

-- Grant access
GRANT SELECT ON VIEW TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS 
    TO ROLE TBRDP_DW_PROD_CORTEX_USER;

COMMENT ON VIEW TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS IS 
'AI-powered analysis of all fan open-ended feedback across all seasons. 
Provides sentiment classification (Positive/Neutral/Negative) and topic categorization 
using Snowflake Cortex AI_CLASSIFY. Analyzes feedback from 2023 onwards.';

-- =====================================================
-- MERCHANDISE NON-PURCHASE FEEDBACK ANALYSIS - ALL YEARS
-- =====================================================
-- Description: AI classification of why fans didn't purchase merchandise
--              Covers all seasons
-- =====================================================

CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_MERCH_NO_ANALYSIS_SIMPLE AS
SELECT
  qualtrics_id,
  game_date,
  season,
  buyer_type,
  merch_no_otherspecify AS feedback_text,
  
  -- Classification into reason categories
  AI_CLASSIFY(
    merch_no_otherspecify,
    ARRAY_CONSTRUCT(
      'Budget/Cost',
      'No Time',
      'Product Selection',
      'Sizing Issues',
      'Not Interested',
      'Already Own Items',
      'Forgot'
    )
  )['labels'][0]::VARCHAR AS reason_category,
  
  -- Sentiment classification
  AI_CLASSIFY(
    merch_no_otherspecify,
    ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative')
  )['labels'][0]::VARCHAR AS sentiment_category,
  
  AI_SENTIMENT(merch_no_otherspecify):sentiment AS sentiment_score
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE merch_no_otherspecify IS NOT NULL
  AND LENGTH(TRIM(merch_no_otherspecify)) > 10
  AND season >= 2023;  -- All years from 2023 forward

-- Grant access
GRANT SELECT ON VIEW TBRDP_DW_DEV.IM_RPT.V_MERCH_NO_ANALYSIS_SIMPLE 
    TO ROLE TBRDP_DW_PROD_CORTEX_USER;

COMMENT ON VIEW TBRDP_DW_DEV.IM_RPT.V_MERCH_NO_ANALYSIS_SIMPLE IS 
'AI-powered analysis of merchandise non-purchase reasons across all seasons. 
Classifies feedback into reason categories and sentiment using Snowflake Cortex AI.';

-- =====================================================
-- VERIFICATION QUERIES FOR NEW VIEWS
-- =====================================================

-- Verify overall feedback analysis - show counts by year
SELECT 
  season,
  sentiment_category,
  ai_category,
  COUNT(*) AS responses
FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
GROUP BY season, sentiment_category, ai_category
ORDER BY season DESC, responses DESC;

-- Verify merchandise feedback analysis - show counts by year
SELECT 
  season,
  reason_category,
  COUNT(*) AS responses
FROM TBRDP_DW_DEV.IM_RPT.V_MERCH_NO_ANALYSIS_SIMPLE
GROUP BY season, reason_category
ORDER BY season DESC, responses DESC;

-- Check total records by year
SELECT 
  season,
  COUNT(*) AS total_feedback_responses
FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
GROUP BY season
ORDER BY season DESC;

-- =====================================================
-- SUMMARY ANALYSIS QUERIES
-- =====================================================

-- Year-over-year sentiment trends
SELECT 
  season,
  sentiment_category,
  COUNT(*) AS responses,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY season), 1) AS pct_of_year
FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
GROUP BY season, sentiment_category
ORDER BY season DESC, responses DESC;

-- Top feedback categories across all years
SELECT 
  ai_category,
  sentiment_category,
  COUNT(*) AS total_responses,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_all,
  COUNT(DISTINCT season) AS seasons_present
FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
GROUP BY ai_category, sentiment_category
ORDER BY total_responses DESC;

-- =====================================================
-- VERIFICATION QUERIES
-- =====================================================

-- Verify stage contents
LIST @TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS;

-- Verify base view access
USE ROLE TBRDP_DW_PROD_CORTEX_USER;
USE WAREHOUSE TBRDP_DW_CORTEX_XS_WH;

SELECT COUNT(*) as total_rows
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI;

-- Check data structure
SELECT 
    OVERALL_NUMRAT as satisfaction_score,
    GAME_DATE,
    RESPONSE_DATE,
    SEASON
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE GAME_DATE >= DATEADD(month, -6, CURRENT_DATE())
LIMIT 10;
-- =====================================================

