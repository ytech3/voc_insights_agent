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

-- =====================================================
-- ENVIRONMENT SETUP
-- =====================================================

USE ROLE TBRDP_DW_PROD_CORTEX_USER;
USE WAREHOUSE TBRDP_DW_CORTEX_XS_WH;

-- =====================================================
-- SECTION 1: INFRASTRUCTURE SETUP
-- =====================================================

-- Create stage for Cortex Analyst semantic model YAML files
CREATE OR REPLACE STAGE TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Stage for Cortex Analyst semantic model YAML files';

-- =====================================================
-- SECTION 2: BASE VIEW - V_VOC_ENHANCED_AI
-- =====================================================
-- Purpose: Core view that enriches VOC data with AI-powered insights
-- Features:
--   - AI Classification of feedback topics
--   - Sentiment analysis
--   - NPS segmentation
--   - Revenue indicators
--   - Family attendance flags
--   - Time dimensions

CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI AS
SELECT 
    v.*,
    
    -- AI-powered topic classification
    AI_CLASSIFY(
        v.OVERALL_NUMRAT_OT,
        ARRAY_CONSTRUCT(
            'Food & Beverage',
            'Parking & Transportation',
            'Ticketing & Seating',
            'Entertainment',
            'Staff/Service',
            'Facilities',
            'General'
        )
    )['labels'][0]::STRING AS primary_topic,
    
    -- Sentiment analysis (-1 to 1 scale)
    AI_SENTIMENT(v.OVERALL_NUMRAT_OT) AS sentiment_score,
    
    -- NPS segmentation
    CASE 
        WHEN v.OVERALL_NUMRAT >= 9 THEN 'Promoter'
        WHEN v.OVERALL_NUMRAT >= 7 THEN 'Passive'
        WHEN v.OVERALL_NUMRAT IS NOT NULL THEN 'Detractor'
        ELSE 'Unknown'
    END AS nps_segment,
    
    -- Revenue indicators
    v.AVERAGE_TIX_PRICE AS ticket_price_clean,
    v.CONCESS_SPEND_DESC AS concession_spend_description,
    NULL AS merch_spend_clean,
    
    -- Family attendance flag
    CASE 
        WHEN v.ATTEND_KIDS_AGES_BET_3_5 = 1 
          OR v.ATTEND_KIDS_AGES_BET_6_12 = 1 
          OR v.ATTEND_KIDS_AGES_BET_13_17 = 1 
        THEN TRUE 
        ELSE FALSE 
    END AS has_children,
    
    -- Time dimensions
    v.GAME_DATE AS game_date_clean,
    MONTH(v.GAME_DATE) AS game_month,
    DAYNAME(v.GAME_DATE) AS game_day_of_week,
    DAYOFWEEK(v.GAME_DATE) AS game_day_num,
    QUARTER(v.GAME_DATE) AS game_quarter
    
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI v
WHERE v.OVERALL_NUMRAT_OT IS NOT NULL
  AND v.OVERALL_NUMRAT_OT NOT IN ('88', '81')
  AND YEAR(v.GAME_DATE) >= 2024;

-- =====================================================
-- SECTION 3: ANALYTICAL VIEWS
-- =====================================================

-- Monthly Insights View
-- Purpose: Aggregate VOC metrics by month with AI-generated summaries
CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_VOC_MONTHLY_INSIGHTS AS
SELECT 
    DATE_TRUNC('month', game_date_clean) AS month,
    COUNT(*) AS total_responses,
    AVG(OVERALL_NUMRAT) AS avg_satisfaction,
    
    -- AI aggregation for unlimited row summarization
    AI_AGG(
        OVERALL_NUMRAT_OT,
        'Analyze all feedback and list the top 5 complaint themes with approximate frequency percentages. Include sentiment trends.'
    ) AS top_complaints_analysis,
    
    -- Executive summary
    AI_SUMMARIZE_AGG(OVERALL_NUMRAT_OT) AS executive_summary,
    
    -- NPS metrics
    SUM(CASE WHEN nps_segment = 'Promoter' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0) AS promoter_pct,
    SUM(CASE WHEN nps_segment = 'Detractor' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0) AS detractor_pct,
    
    -- Revenue metrics
    AVG(ticket_price_clean) AS avg_ticket_price,
    SUM(CASE WHEN CONCESS_SCREENER_DESC = 'Yes' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0) AS concession_purchase_rate
    
FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
GROUP BY 1
ORDER BY 1 DESC;

-- Buyer Type Insights View
-- Purpose: Analyze feedback patterns and revenue opportunities by buyer segment
CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_VOC_BUYER_TYPE_INSIGHTS AS
SELECT 
    BUYER_TYPE,
    COUNT(*) AS total_responses,
    ROUND(AVG(OVERALL_NUMRAT), 2) AS avg_satisfaction,
    ROUND(AVG(ticket_price_clean), 2) AS avg_ticket_price,
    
    -- Purchase behavior
    AVG(CASE WHEN CONCESS_SCREENER_DESC = 'Yes' THEN 1 ELSE 0 END) * 100 AS concession_purchase_pct,
    AVG(CASE WHEN MERCH_SCREENER_DESC = 'Yes' THEN 1 ELSE 0 END) * 100 AS merch_purchase_pct,
    
    -- AI-powered segment insights
    AI_AGG(
        OVERALL_NUMRAT_OT,
        'Summarize the key differences in feedback for this buyer segment compared to general fans. Highlight revenue opportunities.'
    ) AS segment_insights
    
FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
WHERE OVERALL_NUMRAT_OT IS NOT NULL
  AND OVERALL_NUMRAT_OT NOT IN ('88', '81')
GROUP BY BUYER_TYPE
ORDER BY avg_satisfaction DESC;

-- =====================================================
-- SECTION 4: MONITORING VIEWS
-- =====================================================

-- Cortex Function Cost Monitoring
CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_CORTEX_FUNCTION_COSTS AS
SELECT 
    DATE_TRUNC('day', start_time) AS usage_date,
    function_name,
    COUNT(*) AS total_calls
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
WHERE start_time >= DATEADD(day, -30, CURRENT_DATE())
GROUP BY DATE_TRUNC('day', start_time), function_name
ORDER BY usage_date DESC, total_calls DESC;

-- Cortex Query Cost Monitoring
CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_CORTEX_COST_MONITORING AS
SELECT 
    query_id,
    query_text,
    user_name,
    warehouse_name,
    start_time,
    end_time,
    credits_used_cloud_services AS credits_used,
    total_elapsed_time/1000 AS elapsed_seconds
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_text ILIKE '%AI_COMPLETE%'
   OR query_text ILIKE '%AI_CLASSIFY%'
   OR query_text ILIKE '%AI_SENTIMENT%'
   OR query_text ILIKE '%AI_AGG%'
   OR query_text ILIKE '%AI_SUMMARIZE%'
ORDER BY start_time DESC
LIMIT 1000;

-- =====================================================
-- SECTION 5: FUNCTIONS
-- =====================================================

-- Quick Stats Function
-- Purpose: Retrieve key VOC metrics for a specific year
CREATE OR REPLACE FUNCTION TBRDP_DW_DEV.IM_RPT.VOC_QUICK_STATS(target_year NUMBER)
RETURNS TABLE(
    metric_name VARCHAR,
    metric_value FLOAT,
    metric_context VARCHAR
)
AS
$$
    SELECT 'Average Overall Satisfaction' AS metric_name, 
           AVG(OVERALL_NUMRAT) AS metric_value,
           'Scale: 1-10, Year: ' || target_year AS metric_context
    FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
    WHERE YEAR(game_date_clean) = target_year
    
    UNION ALL
    
    SELECT 'Total Survey Responses', 
           COUNT(*)::FLOAT,
           'Complete responses in ' || target_year
    FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
    WHERE YEAR(game_date_clean) = target_year
    
    UNION ALL
    
    SELECT 'Average Ticket Price',
           AVG(ticket_price_clean),
           'USD, Year: ' || target_year
    FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
    WHERE YEAR(game_date_clean) = target_year
    
    UNION ALL
    
    SELECT 'Family Attendance Rate',
           AVG(CASE WHEN has_children THEN 100 ELSE 0 END),
           'Percentage with children, Year: ' || target_year
    FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
    WHERE YEAR(game_date_clean) = target_year
    
    UNION ALL
    
    SELECT 'NPS Score',
           (SUM(CASE WHEN nps_segment = 'Promoter' THEN 1 ELSE 0 END) - 
            SUM(CASE WHEN nps_segment = 'Detractor' THEN 1 ELSE 0 END)) * 100.0 / 
            NULLIF(COUNT(*), 0),
           'Net Promoter Score, Year: ' || target_year
    FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
    WHERE YEAR(game_date_clean) = target_year
    
    UNION ALL
    
    SELECT 'Concession Purchase Rate',
           AVG(CASE WHEN CONCESS_SCREENER_DESC = 'Yes' THEN 100 ELSE 0 END),
           'Percentage who purchased, Year: ' || target_year
    FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
    WHERE YEAR(game_date_clean) = target_year
$$;

-- Classification Function - Single Label
-- Purpose: Classify feedback into primary category
CREATE OR REPLACE FUNCTION TBRDP_DW_DEV.IM_RPT.classify_feedback_v2(feedback_text STRING)
RETURNS OBJECT
LANGUAGE SQL
AS
$$
    SELECT AI_CLASSIFY(
        feedback_text,
        ARRAY_CONSTRUCT(
            'Food & Beverage - Quality',
            'Food & Beverage - Price', 
            'Food & Beverage - Variety',
            'Parking & Transportation - Price',
            'Parking & Transportation - Location',
            'Parking & Transportation - Access',
            'Ticketing & Seating - View',
            'Ticketing & Seating - Price',
            'Non-Game Entertainment - Quality',
            'Staff/Service - Quality',
            'Facilities - Cleanliness',
            'General/Other'
        )
    ) AS classification_result
$$;

-- Classification Function - Multi-Label
-- Purpose: Classify feedback into multiple categories (up to 3)
CREATE OR REPLACE FUNCTION TBRDP_DW_DEV.IM_RPT.classify_feedback_multilabel(feedback_text STRING)
RETURNS OBJECT
LANGUAGE SQL
AS
$$
    SELECT AI_CLASSIFY(
        feedback_text,
        ARRAY_CONSTRUCT(
            'Food & Beverage - Quality',
            'Food & Beverage - Price',
            'Parking & Transportation',
            'Ticketing & Seating',
            'Non-Game Entertainment',
            'Staff/Service',
            'Facilities'
        ),
        {
            'multi_label': true,
            'max_labels': 3
        }
    ) AS classification_result
$$;

-- =====================================================
-- SECTION 6: CORTEX SEARCH SERVICE
-- =====================================================
-- Purpose: Enable semantic search across fan feedback

CREATE OR REPLACE CORTEX SEARCH SERVICE VOC_FEEDBACK_SEARCH
ON feedback_text
WAREHOUSE = TBRDP_DW_CORTEX_XS_WH
TARGET_LAG = '1 hour'
AS (
    SELECT 
        QUALTRICS_ID as qualtrics_id,
        GAME_DATE as game_date,
        SEASON as season,
        BUYER_TYPE as buyer_type,
        OVERALL_NUMRAT as satisfaction_score,
        OVERALL_NUMRAT_OT as feedback_text,
        CONCAT(
            'Game Date: ', TO_VARCHAR(GAME_DATE), 
            ' | Satisfaction: ', TO_VARCHAR(OVERALL_NUMRAT),
            ' | Buyer Type: ', COALESCE(BUYER_TYPE, 'Unknown'),
            ' | Feedback: ', OVERALL_NUMRAT_OT
        ) as search_context
    FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
    WHERE OVERALL_NUMRAT_OT IS NOT NULL
        AND OVERALL_NUMRAT_OT NOT IN ('88', '81')
        AND LENGTH(OVERALL_NUMRAT_OT) > 10
);

-- =====================================================
-- SECTION 7: USAGE EXAMPLES
-- =====================================================

-- Example 1: Get quick stats for 2024
-- SELECT * FROM TABLE(TBRDP_DW_DEV.IM_RPT.VOC_QUICK_STATS(2024));

-- Example 2: View monthly insights
-- SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_VOC_MONTHLY_INSIGHTS;

-- Example 3: Analyze buyer type insights
-- SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_VOC_BUYER_TYPE_INSIGHTS;

-- Example 4: Classify a single piece of feedback
-- SELECT TBRDP_DW_DEV.IM_RPT.classify_feedback_v2('The food was cold and overpriced');

-- Example 5: Multi-label classification
-- SELECT TBRDP_DW_DEV.IM_RPT.classify_feedback_multilabel('Great seats but parking was terrible and expensive');

-- Example 6: Search for specific feedback
-- SELECT * 
-- FROM TABLE(VOC_FEEDBACK_SEARCH!SEARCH('parking complaints'))
-- LIMIT 10;

-- Example 7: Monitor Cortex costs
-- SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_CORTEX_FUNCTION_COSTS
-- WHERE usage_date >= DATEADD(day, -7, CURRENT_DATE());

-- =====================================================
-- DEPLOYMENT NOTES
-- =====================================================
-- 1. Ensure the base view V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI exists
-- 2. Upload the semantic model YAML to CORTEX_SEMANTIC_MODELS stage
-- 3. Grant appropriate permissions to TBRDP_DW_PROD_CORTEX_USER role
-- 4. Monitor costs using the provided monitoring views
-- 5. Semantic model file: voc_semantic_model.yaml (stored separately)
-- =====================================================

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

-- Script Complete ✅
