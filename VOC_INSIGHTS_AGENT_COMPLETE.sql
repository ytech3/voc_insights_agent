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

