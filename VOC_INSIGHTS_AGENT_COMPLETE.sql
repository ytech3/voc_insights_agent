-- =====================================================
-- VOC INSIGHTS AGENT - OPTIMIZED DEPLOYMENT SCRIPT (FINAL)
-- Tampa Bay Rays - Voice of Customer Analysis
-- =====================================================
-- Version: 2.0 (Optimized - Yuki Preferences)
-- Last Updated: December 2025
-- Key Notes:
--   • NO AI_FILTER pre-filter (Optimization #1 skipped)
--   • Category taxonomy aligned with YAML (incl. "stadium departure")
--   • Sentence-level analysis uses single AI_COMPLETE call (snowflake-llama3.3-70b)
--   • AI_AGG + AI_SUMMARIZE_AGG views for category + exec summaries
--   • Exec summary includes POSITIVE + NEGATIVE summaries
--   • Unified qualitative view + sentence-level qualitative view (2023–2025)
--   • Cost monitoring + query-level cost tracking
-- =====================================================

-- =====================================================
-- ENVIRONMENT SETUP
-- =====================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE TBRDP_DW_CORTEX_XS_WH;

-- =====================================================
-- CATEGORY TAXONOMY (MUST MATCH YAML)
-- =====================================================
-- PRE-ARRIVAL & ARRIVAL:
--   "Parking & Arrival"
--
-- ENTRY & NAVIGATION:
--   "Gate Entry & Security"
--   "Wayfinding & Accessibility"
--
-- IN-SEAT EXPERIENCE:
--   "Seating & Venue Comfort"
--   "Crowd & Atmosphere"
--
-- CONCESSIONS & AMENITIES:
--   "Food & Beverage Quality"
--   "Concession Service & Speed"
--   "Merchandise & Team Store"
--
-- ENTERTAINMENT & ENGAGEMENT:
--   "Game Entertainment & Presentation"
--   "Promotions & Special Events"
--   "Team Performance & Game Quality"
--
-- SERVICE & OPERATIONS:
--   "Staff Interactions & Service"
--   "Facilities & Cleanliness"
--   "Weather"
--   "Technology & Digital Experience"
--
-- VALUE & OVERALL:
--   "Pricing & Value Perception"
--   "Overall Experience & Loyalty"
--   "Ticketing & Purchase Experience"
--
-- EGRESS & DEPARTURE:
--   "Egress"
--   "stadium departure"
--
-- OTHER:
--   "Other"


-- =====================================================
-- 2) OVERALL FEEDBACK ANALYSIS VIEW
-- =====================================================
-- Aligned with YAML taxonomy (incl. "stadium departure")
-- Adds parent_category rollup; seasons 2023–2025
-- =====================================================

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
    AND season BETWEEN 2023 AND 2025
),
with_ai_analysis AS (
  SELECT
    *,
    -- Topic classification - ALIGNED WITH YAML TAXONOMY
    AI_CLASSIFY(
      feedback_text,
      ARRAY_CONSTRUCT(
        'Parking & Arrival',
        'Gate Entry & Security',
        'Wayfinding & Accessibility',
        'Seating & Venue Comfort',
        'Crowd & Atmosphere',
        'Food & Beverage Quality',
        'Concession Service & Speed',
        'Merchandise & Team Store',
        'Game Entertainment & Presentation',
        'Promotions & Special Events',
        'Team Performance & Game Quality',
        'Staff Interactions & Service',
        'Facilities & Cleanliness',
        'Weather',
        'Technology & Digital Experience',
        'Pricing & Value Perception',
        'Overall Experience & Loyalty',
        'Ticketing & Purchase Experience',
        'Egress',
        'stadium departure',
        'Other'
      )
    )['labels'][0]::VARCHAR AS ai_category,
    
    -- Sentiment classification (categorical)
    AI_CLASSIFY(
      feedback_text,
      ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative')
    )['labels'][0]::VARCHAR AS sentiment_category,
    
    -- Numeric sentiment score (newer syntax)
    AI_SENTIMENT(feedback_text) AS sentiment_score,
    
    -- NPS segment based on satisfaction rating
    CASE 
      WHEN satisfaction_rating >= 9 THEN 'Promoter'
      WHEN satisfaction_rating BETWEEN 7 AND 8 THEN 'Passive'
      WHEN satisfaction_rating <= 6 THEN 'Detractor'
      ELSE 'Unknown'
    END AS nps_segment
  FROM base_data
),
with_parent_category AS (
  SELECT
    *,
    CASE 
      WHEN ai_category = 'Parking & Arrival' THEN 'PRE-ARRIVAL & ARRIVAL'
      WHEN ai_category IN ('Gate Entry & Security', 'Wayfinding & Accessibility') THEN 'ENTRY & NAVIGATION'
      WHEN ai_category IN ('Seating & Venue Comfort', 'Crowd & Atmosphere') THEN 'IN-SEAT EXPERIENCE'
      WHEN ai_category IN ('Food & Beverage Quality', 'Concession Service & Speed', 'Merchandise & Team Store') THEN 'CONCESSIONS & AMENITIES'
      WHEN ai_category IN ('Game Entertainment & Presentation', 'Promotions & Special Events', 'Team Performance & Game Quality') THEN 'ENTERTAINMENT & ENGAGEMENT'
      WHEN ai_category IN ('Staff Interactions & Service', 'Facilities & Cleanliness', 'Weather', 'Technology & Digital Experience') THEN 'SERVICE & OPERATIONS'
      WHEN ai_category IN ('Pricing & Value Perception', 'Overall Experience & Loyalty', 'Ticketing & Purchase Experience') THEN 'VALUE & OVERALL'
      WHEN ai_category IN ('Egress', 'stadium departure') THEN 'EGRESS & DEPARTURE'
      ELSE 'OTHER'
    END AS parent_category
  FROM with_ai_analysis
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
  parent_category,
  sentiment_category,
  sentiment_score,
  nps_segment,
  CONCAT(ai_category, ' - ', sentiment_category) AS detailed_category
FROM with_parent_category;

GRANT SELECT ON VIEW TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS 
    TO ROLE TBRDP_DW_PROD_CORTEX_USER;

COMMENT ON VIEW TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS IS 
'AI-powered analysis of fan feedback with categories aligned to YAML taxonomy.
Includes parent category rollups for reporting. Covers seasons 2023–2025.';


-- =====================================================
-- 3) SENTENCE-LEVEL ANALYSIS (SINGLE AI CALL)
-- =====================================================
-- Uses AI_COMPLETE (snowflake-llama3.3-70b) and YAML taxonomy
-- Seasons 2023–2025; replaces older 3-call version
-- =====================================================

CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_SENTENCE_LEVEL AS
WITH feedback_data AS (
  SELECT 
    QUALTRICS_ID,
    SEASON,
    GAME_DATE,
    BUYER_TYPE,
    OVERALL_NUMRAT_OT AS feedback_text,
    OVERALL_NUMRAT AS satisfaction_rating
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE OVERALL_NUMRAT_OT IS NOT NULL
    AND LENGTH(TRIM(OVERALL_NUMRAT_OT)) > 10
    AND season BETWEEN 2023 AND 2025
),

combined_analysis AS (
  SELECT
    QUALTRICS_ID,
    SEASON,
    GAME_DATE,
    BUYER_TYPE,
    feedback_text,
    satisfaction_rating,
    AI_COMPLETE(
      'snowflake-llama3.3-70b',
      'Analyze this fan feedback from a baseball stadium. Split into sentences and classify each.

FEEDBACK: ' || feedback_text || '

Return ONLY a valid JSON array. Each element must have:
- "sentence": the exact sentence text
- "sentiment": exactly one of "Positive", "Neutral", or "Negative"
- "category": exactly one of these categories:
  "Parking & Arrival", "Gate Entry & Security", "Wayfinding & Accessibility",
  "Seating & Venue Comfort", "Crowd & Atmosphere", "Food & Beverage Quality",
  "Concession Service & Speed", "Merchandise & Team Store",
  "Game Entertainment & Presentation", "Promotions & Special Events",
  "Team Performance & Game Quality", "Staff Interactions & Service",
  "Facilities & Cleanliness", "Weather", "Technology & Digital Experience",
  "Pricing & Value Perception", "Overall Experience & Loyalty",
  "Ticketing & Purchase Experience", "Egress", "stadium departure", "Other"

CLASSIFICATION RULES:
- Be SPECIFIC with categories. Do not overuse "Overall Experience & Loyalty"
- Food quality vs service speed are DIFFERENT categories
- Staff comments go to "Staff Interactions & Service"
- Positive atmosphere comments go to "Crowd & Atmosphere", NOT "Overall Experience"
- Team/game action comments go to "Team Performance & Game Quality"
- Comments about leaving or exiting the stadium go to "Egress" or "stadium departure" as appropriate
- Return ONLY the JSON array, nothing else.

Example output:
[{"sentence":"The food was great","sentiment":"Positive","category":"Food & Beverage Quality"},{"sentence":"Parking was terrible","sentiment":"Negative","category":"Parking & Arrival"}]',
      {
        'temperature': 0.1,
        'max_tokens': 2000
      }
    ) AS analysis_json
  FROM feedback_data
),

parsed_analysis AS (
  SELECT
    QUALTRICS_ID,
    SEASON,
    GAME_DATE,
    BUYER_TYPE,
    feedback_text AS original_feedback,
    satisfaction_rating,
    TRY_PARSE_JSON(analysis_json) AS sentences_array
  FROM combined_analysis
  WHERE analysis_json IS NOT NULL
),

flattened AS (
  SELECT
    QUALTRICS_ID,
    SEASON,
    GAME_DATE,
    BUYER_TYPE,
    original_feedback,
    satisfaction_rating,
    sentence.INDEX + 1 AS sentence_number,
    TRIM(sentence.VALUE:sentence::STRING) AS sentence_text,
    TRIM(sentence.VALUE:sentiment::STRING) AS sentiment_category,
    TRIM(sentence.VALUE:category::STRING) AS ai_category
  FROM parsed_analysis,
  LATERAL FLATTEN(input => sentences_array) sentence
  WHERE sentence.VALUE:sentence IS NOT NULL
    AND LENGTH(TRIM(sentence.VALUE:sentence::STRING)) > 5
)

SELECT
  QUALTRICS_ID,
  SEASON,
  GAME_DATE,
  BUYER_TYPE,
  original_feedback,
  satisfaction_rating,
  sentence_number,
  sentence_text,
  sentiment_category,
  ai_category,
  CASE 
    WHEN ai_category = 'Parking & Arrival' THEN 'PRE-ARRIVAL & ARRIVAL'
    WHEN ai_category IN ('Gate Entry & Security', 'Wayfinding & Accessibility') THEN 'ENTRY & NAVIGATION'
    WHEN ai_category IN ('Seating & Venue Comfort', 'Crowd & Atmosphere') THEN 'IN-SEAT EXPERIENCE'
    WHEN ai_category IN ('Food & Beverage Quality', 'Concession Service & Speed', 'Merchandise & Team Store') THEN 'CONCESSIONS & AMENITIES'
    WHEN ai_category IN ('Game Entertainment & Presentation', 'Promotions & Special Events', 'Team Performance & Game Quality') THEN 'ENTERTAINMENT & ENGAGEMENT'
    WHEN ai_category IN ('Staff Interactions & Service', 'Facilities & Cleanliness', 'Weather', 'Technology & Digital Experience') THEN 'SERVICE & OPERATIONS'
    WHEN ai_category IN ('Pricing & Value Perception', 'Overall Experience & Loyalty', 'Ticketing & Purchase Experience') THEN 'VALUE & OVERALL'
    WHEN ai_category IN ('Egress', 'stadium departure') THEN 'EGRESS & DEPARTURE'
    ELSE 'OTHER'
  END AS parent_category,
  CONCAT(ai_category, ' - ', sentiment_category) AS detailed_category,
  LENGTH(sentence_text) AS sentence_length,
  CASE 
    WHEN satisfaction_rating >= 9 THEN 'Promoter'
    WHEN satisfaction_rating >= 7 THEN 'Passive'
    ELSE 'Detractor'
  END AS nps_segment
FROM flattened
ORDER BY QUALTRICS_ID, sentence_number;

GRANT SELECT ON VIEW TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_SENTENCE_LEVEL 
    TO ROLE TBRDP_DW_PROD_CORTEX_USER;

COMMENT ON VIEW TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_SENTENCE_LEVEL IS 
'Sentence-level analysis of OVERALL_NUMRAT_OT using a single AI call (snowflake-llama3.3-70b).
Categories aligned with YAML taxonomy (incl. "stadium departure"). Covers 2023–2025.';


-- =====================================================
-- 4) MERCHANDISE NON-PURCHASE ANALYSIS
-- =====================================================

CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_MERCH_NO_ANALYSIS_SIMPLE AS
SELECT
  qualtrics_id,
  game_date,
  season,
  buyer_type,
  merch_no_otherspecify AS feedback_text,
  
  AI_CLASSIFY(
    merch_no_otherspecify,
    ARRAY_CONSTRUCT(
      'Budget/Cost',
      'No Time',
      'Product Selection',
      'Sizing Issues',
      'Not Interested',
      'Already Own Items',
      'Forgot',
      'Lines Too Long',
      'Location Inconvenient',
      'Other'
    )
  )['labels'][0]::VARCHAR AS reason_category,
  
  AI_CLASSIFY(
    merch_no_otherspecify,
    ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative')
  )['labels'][0]::VARCHAR AS sentiment_category,
  
  AI_SENTIMENT(merch_no_otherspecify) AS sentiment_score
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE merch_no_otherspecify IS NOT NULL
  AND LENGTH(TRIM(merch_no_otherspecify)) > 10
  AND season BETWEEN 2023 AND 2025;

GRANT SELECT ON VIEW TBRDP_DW_DEV.IM_RPT.V_MERCH_NO_ANALYSIS_SIMPLE 
    TO ROLE TBRDP_DW_PROD_CORTEX_USER;

COMMENT ON VIEW TBRDP_DW_DEV.IM_RPT.V_MERCH_NO_ANALYSIS_SIMPLE IS 
'AI-powered analysis of merchandise non-purchase reasons (2023–2025).';


-- =====================================================
-- 5) CATEGORY INSIGHTS (AI_AGG)
-- =====================================================

CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_CATEGORY_INSIGHTS AS
WITH category_feedback AS (
  SELECT
    season,
    ai_category,
    parent_category,
    sentiment_category,
    feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
  WHERE season >= 2024
)
SELECT
  season,
  ai_category,
  parent_category,
  COUNT(*) AS feedback_count,
  COUNT(CASE WHEN sentiment_category = 'Positive' THEN 1 END) AS positive_count,
  COUNT(CASE WHEN sentiment_category = 'Negative' THEN 1 END) AS negative_count,
  ROUND(100.0 * COUNT(CASE WHEN sentiment_category = 'Positive' THEN 1 END) / NULLIF(COUNT(*), 0), 1) AS positive_pct,
  ROUND(100.0 * COUNT(CASE WHEN sentiment_category = 'Negative' THEN 1 END) / NULLIF(COUNT(*), 0), 1) AS negative_pct,
  AI_AGG(
    feedback_text,
    'Summarize the top 3 most common themes in this fan feedback. Be specific and actionable. Focus on what fans are saying, not just that they said something.'
  ) AS category_insights
FROM category_feedback
GROUP BY season, ai_category, parent_category
HAVING COUNT(*) >= 5
ORDER BY season DESC, feedback_count DESC;

GRANT SELECT ON VIEW TBRDP_DW_DEV.IM_RPT.V_CATEGORY_INSIGHTS 
    TO ROLE TBRDP_DW_PROD_CORTEX_USER;

COMMENT ON VIEW TBRDP_DW_DEV.IM_RPT.V_CATEGORY_INSIGHTS IS 
'Category-level insights using AI_AGG. Summarizes themes per category/season.';


-- =====================================================
-- 6) EXECUTIVE SUMMARY (POSITIVE + NEGATIVE)
-- =====================================================
-- Changed to include BOTH positive and negative summaries
-- =====================================================

CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_EXECUTIVE_SUMMARY AS
WITH sentiment_feedback AS (
  SELECT
    season,
    parent_category,
    sentiment_category,
    feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
  WHERE season = YEAR(CURRENT_DATE())
    AND sentiment_category IN ('Positive', 'Negative')
)
SELECT
  season,
  parent_category,
  sentiment_category,
  COUNT(*) AS feedback_count,
  AI_SUMMARIZE_AGG(feedback_text) AS executive_summary
FROM sentiment_feedback
GROUP BY season, parent_category, sentiment_category
HAVING COUNT(*) >= 3
ORDER BY feedback_count DESC;

GRANT SELECT ON VIEW TBRDP_DW_DEV.IM_RPT.V_EXECUTIVE_SUMMARY 
    TO ROLE TBRDP_DW_PROD_CORTEX_USER;

COMMENT ON VIEW TBRDP_DW_DEV.IM_RPT.V_EXECUTIVE_SUMMARY IS 
'Executive-level summaries of POSITIVE and NEGATIVE feedback by parent category for current season.';


-- =====================================================
-- 7) QUALITATIVE FEEDBACK - UNIFIED VIEW (TEXT-LEVEL)
-- =====================================================

CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_QUALITATIVE_FEEDBACK_ALL AS

-- Overall experience feedback (PRIMARY)
SELECT
  qualtrics_id,
  game_date,
  season,
  buyer_type,
  'Overall Experience' AS feedback_source,
  'OVERALL_NUMRAT_OT' AS source_field,
  OVERALL_NUMRAT_OT AS feedback_text,
  AI_CLASSIFY(
    OVERALL_NUMRAT_OT,
    ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative')
  )['labels'][0]::VARCHAR AS sentiment,
  AI_SENTIMENT(OVERALL_NUMRAT_OT) AS sentiment_score
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE OVERALL_NUMRAT_OT IS NOT NULL 
  AND LENGTH(TRIM(OVERALL_NUMRAT_OT)) > 5
  AND season BETWEEN 2023 AND 2025

UNION ALL

-- TB_ADDON_8_1: Tickets/Seats Issues
SELECT qualtrics_id, game_date, season, buyer_type,
  'Tickets/Seats Issues' AS feedback_source,
  'TB_ADDON_8_1' AS source_field,
  TB_ADDON_8_1 AS feedback_text,
  AI_CLASSIFY(TB_ADDON_8_1, ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative'))['labels'][0]::VARCHAR,
  AI_SENTIMENT(TB_ADDON_8_1)
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE TB_ADDON_8_1 IS NOT NULL AND LENGTH(TRIM(TB_ADDON_8_1)) > 5 AND season BETWEEN 2023 AND 2025

UNION ALL

-- TB_ADDON_8_2: Staff/Service Issues
SELECT qualtrics_id, game_date, season, buyer_type,
  'Staff/Service Issues' AS feedback_source,
  'TB_ADDON_8_2' AS source_field,
  TB_ADDON_8_2 AS feedback_text,
  AI_CLASSIFY(TB_ADDON_8_2, ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative'))['labels'][0]::VARCHAR,
  AI_SENTIMENT(TB_ADDON_8_2)
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE TB_ADDON_8_2 IS NOT NULL AND LENGTH(TRIM(TB_ADDON_8_2)) > 5 AND season BETWEEN 2023 AND 2025

UNION ALL

-- TB_ADDON_8_3: Entertainment Issues
SELECT qualtrics_id, game_date, season, buyer_type,
  'Entertainment Issues' AS feedback_source,
  'TB_ADDON_8_3' AS source_field,
  TB_ADDON_8_3 AS feedback_text,
  AI_CLASSIFY(TB_ADDON_8_3, ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative'))['labels'][0]::VARCHAR,
  AI_SENTIMENT(TB_ADDON_8_3)
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE TB_ADDON_8_3 IS NOT NULL AND LENGTH(TRIM(TB_ADDON_8_3)) > 5 AND season BETWEEN 2023 AND 2025

UNION ALL

-- TB_ADDON_8_4: Concessions/Food Issues
SELECT qualtrics_id, game_date, season, buyer_type,
  'Concessions/Food Issues' AS feedback_source,
  'TB_ADDON_8_4' AS source_field,
  TB_ADDON_8_4 AS feedback_text,
  AI_CLASSIFY(TB_ADDON_8_4, ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative'))['labels'][0]::VARCHAR,
  AI_SENTIMENT(TB_ADDON_8_4)
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE TB_ADDON_8_4 IS NOT NULL AND LENGTH(TRIM(TB_ADDON_8_4)) > 5 AND season BETWEEN 2023 AND 2025

UNION ALL

-- TB_ADDON_8_5: Cleanliness Issues
SELECT qualtrics_id, game_date, season, buyer_type,
  'Cleanliness Issues' AS feedback_source,
  'TB_ADDON_8_5' AS source_field,
  TB_ADDON_8_5 AS feedback_text,
  AI_CLASSIFY(TB_ADDON_8_5, ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative'))['labels'][0]::VARCHAR,
  AI_SENTIMENT(TB_ADDON_8_5)
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE TB_ADDON_8_5 IS NOT NULL AND LENGTH(TRIM(TB_ADDON_8_5)) > 5 AND season BETWEEN 2023 AND 2025

UNION ALL

-- TB_ADDON_8_6: Parking Issues
SELECT qualtrics_id, game_date, season, buyer_type,
  'Parking Issues' AS feedback_source,
  'TB_ADDON_8_6' AS source_field,
  TB_ADDON_8_6 AS feedback_text,
  AI_CLASSIFY(TB_ADDON_8_6, ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative'))['labels'][0]::VARCHAR,
  AI_SENTIMENT(TB_ADDON_8_6)
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE TB_ADDON_8_6 IS NOT NULL AND LENGTH(TRIM(TB_ADDON_8_6)) > 5 AND season BETWEEN 2023 AND 2025

UNION ALL

-- TB_ADDON_8_7: Retail/Merchandise Issues
SELECT qualtrics_id, game_date, season, buyer_type,
  'Retail/Merchandise Issues' AS feedback_source,
  'TB_ADDON_8_7' AS source_field,
  TB_ADDON_8_7 AS feedback_text,
  AI_CLASSIFY(TB_ADDON_8_7, ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative'))['labels'][0]::VARCHAR,
  AI_SENTIMENT(TB_ADDON_8_7)
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE TB_ADDON_8_7 IS NOT NULL AND LENGTH(TRIM(TB_ADDON_8_7)) > 5 AND season BETWEEN 2023 AND 2025

UNION ALL

-- TB_ADDON_8_8: Safety/Security Issues
SELECT qualtrics_id, game_date, season, buyer_type,
  'Safety/Security Issues' AS feedback_source,
  'TB_ADDON_8_8' AS source_field,
  TB_ADDON_8_8 AS feedback_text,
  AI_CLASSIFY(TB_ADDON_8_8, ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative'))['labels'][0]::VARCHAR,
  AI_SENTIMENT(TB_ADDON_8_8)
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE TB_ADDON_8_8 IS NOT NULL AND LENGTH(TRIM(TB_ADDON_8_8)) > 5 AND season BETWEEN 2023 AND 2025

UNION ALL

-- TB_ADDON_8_9: App Issues
SELECT qualtrics_id, game_date, season, buyer_type,
  'App Issues' AS feedback_source,
  'TB_ADDON_8_9' AS source_field,
  TB_ADDON_8_9 AS feedback_text,
  AI_CLASSIFY(TB_ADDON_8_9, ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative'))['labels'][0]::VARCHAR,
  AI_SENTIMENT(TB_ADDON_8_9)
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE TB_ADDON_8_9 IS NOT NULL AND LENGTH(TRIM(TB_ADDON_8_9)) > 5 AND season BETWEEN 2023 AND 2025

UNION ALL

-- TB_ADDON_8_10: Other Fan Behavior Issues
SELECT qualtrics_id, game_date, season, buyer_type,
  'Other Fan Behavior Issues' AS feedback_source,
  'TB_ADDON_8_10' AS source_field,
  TB_ADDON_8_10 AS feedback_text,
  AI_CLASSIFY(TB_ADDON_8_10, ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative'))['labels'][0]::VARCHAR,
  AI_SENTIMENT(TB_ADDON_8_10)
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE TB_ADDON_8_10 IS NOT NULL AND LENGTH(TRIM(TB_ADDON_8_10)) > 5 AND season BETWEEN 2023 AND 2025

UNION ALL

-- TB_ADDON_8_11: Other Miscellaneous Issues
SELECT qualtrics_id, game_date, season, buyer_type,
  'Other Issues' AS feedback_source,
  'TB_ADDON_8_11' AS source_field,
  TB_ADDON_8_11 AS feedback_text,
  AI_CLASSIFY(TB_ADDON_8_11, ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative'))['labels'][0]::VARCHAR,
  AI_SENTIMENT(TB_ADDON_8_11)
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE TB_ADDON_8_11 IS NOT NULL AND LENGTH(TRIM(TB_ADDON_8_11)) > 5 AND season BETWEEN 2023 AND 2025

UNION ALL

-- INCENTIVES_OT: Ticket Purchase Decision Factors
SELECT qualtrics_id, game_date, season, buyer_type,
  'Ticket Purchase Incentives' AS feedback_source,
  'INCENTIVES_OT' AS source_field,
  INCENTIVES_OT AS feedback_text,
  AI_CLASSIFY(INCENTIVES_OT, ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative'))['labels'][0]::VARCHAR,
  AI_SENTIMENT(INCENTIVES_OT)
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE INCENTIVES_OT IS NOT NULL AND LENGTH(TRIM(INCENTIVES_OT)) > 5 AND season BETWEEN 2023 AND 2025;

GRANT SELECT ON VIEW TBRDP_DW_DEV.IM_RPT.V_QUALITATIVE_FEEDBACK_ALL 
    TO ROLE TBRDP_DW_PROD_CORTEX_USER;

COMMENT ON VIEW TBRDP_DW_DEV.IM_RPT.V_QUALITATIVE_FEEDBACK_ALL IS 
'Unified view of ALL qualitative feedback fields (2023–2025) with sentiment analysis.';


-- =====================================================
-- 7B) QUALITATIVE FEEDBACK - SENTENCE/GROUPING LEVEL
-- =====================================================
-- Applies sentence-level analysis to ALL qualitative fields (2023–2025)
-- Uses "common sense" grouping via feedback_source + sentence_number
-- =====================================================

CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_QUALITATIVE_FEEDBACK_SENTENCE_LEVEL AS
- Step 1: Gather all qualitative feedback directly from base table
WITH raw_feedback AS (
  -- Overall Experience (PRIMARY)
  SELECT
    qualtrics_id,
    game_date,
    season,
    buyer_type,
    'Overall Experience' AS feedback_source,
    'OVERALL_NUMRAT_OT' AS source_field,
    OVERALL_NUMRAT_OT AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE OVERALL_NUMRAT_OT IS NOT NULL 
    AND LENGTH(TRIM(OVERALL_NUMRAT_OT)) > 5
    AND season BETWEEN 2023 AND 2025

  UNION ALL

  -- TB_ADDON_8_1: Tickets/Seats Issues
  SELECT qualtrics_id, game_date, season, buyer_type,
    'Tickets/Seats Issues' AS feedback_source,
    'TB_ADDON_8_1' AS source_field,
    TB_ADDON_8_1 AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE TB_ADDON_8_1 IS NOT NULL 
    AND LENGTH(TRIM(TB_ADDON_8_1)) > 5 
    AND season BETWEEN 2023 AND 2025

  UNION ALL

  -- TB_ADDON_8_2: Staff/Service Issues
  SELECT qualtrics_id, game_date, season, buyer_type,
    'Staff/Service Issues' AS feedback_source,
    'TB_ADDON_8_2' AS source_field,
    TB_ADDON_8_2 AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE TB_ADDON_8_2 IS NOT NULL 
    AND LENGTH(TRIM(TB_ADDON_8_2)) > 5 
    AND season BETWEEN 2023 AND 2025

  UNION ALL

  -- TB_ADDON_8_3: Entertainment Issues
  SELECT qualtrics_id, game_date, season, buyer_type,
    'Entertainment Issues' AS feedback_source,
    'TB_ADDON_8_3' AS source_field,
    TB_ADDON_8_3 AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE TB_ADDON_8_3 IS NOT NULL 
    AND LENGTH(TRIM(TB_ADDON_8_3)) > 5 
    AND season BETWEEN 2023 AND 2025

  UNION ALL

  -- TB_ADDON_8_4: Concessions/Food Issues
  SELECT qualtrics_id, game_date, season, buyer_type,
    'Concessions/Food Issues' AS feedback_source,
    'TB_ADDON_8_4' AS source_field,
    TB_ADDON_8_4 AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE TB_ADDON_8_4 IS NOT NULL 
    AND LENGTH(TRIM(TB_ADDON_8_4)) > 5 
    AND season BETWEEN 2023 AND 2025

  UNION ALL

  -- TB_ADDON_8_5: Cleanliness Issues
  SELECT qualtrics_id, game_date, season, buyer_type,
    'Cleanliness Issues' AS feedback_source,
    'TB_ADDON_8_5' AS source_field,
    TB_ADDON_8_5 AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE TB_ADDON_8_5 IS NOT NULL 
    AND LENGTH(TRIM(TB_ADDON_8_5)) > 5 
    AND season BETWEEN 2023 AND 2025

  UNION ALL

  -- TB_ADDON_8_6: Parking Issues
  SELECT qualtrics_id, game_date, season, buyer_type,
    'Parking Issues' AS feedback_source,
    'TB_ADDON_8_6' AS source_field,
    TB_ADDON_8_6 AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE TB_ADDON_8_6 IS NOT NULL 
    AND LENGTH(TRIM(TB_ADDON_8_6)) > 5 
    AND season BETWEEN 2023 AND 2025

  UNION ALL

  -- TB_ADDON_8_7: Retail/Merchandise Issues
  SELECT qualtrics_id, game_date, season, buyer_type,
    'Retail/Merchandise Issues' AS feedback_source,
    'TB_ADDON_8_7' AS source_field,
    TB_ADDON_8_7 AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE TB_ADDON_8_7 IS NOT NULL 
    AND LENGTH(TRIM(TB_ADDON_8_7)) > 5 
    AND season BETWEEN 2023 AND 2025

  UNION ALL

  -- TB_ADDON_8_8: Safety/Security Issues
  SELECT qualtrics_id, game_date, season, buyer_type,
    'Safety/Security Issues' AS feedback_source,
    'TB_ADDON_8_8' AS source_field,
    TB_ADDON_8_8 AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE TB_ADDON_8_8 IS NOT NULL 
    AND LENGTH(TRIM(TB_ADDON_8_8)) > 5 
    AND season BETWEEN 2023 AND 2025

  UNION ALL

  -- TB_ADDON_8_9: App Issues
  SELECT qualtrics_id, game_date, season, buyer_type,
    'App Issues' AS feedback_source,
    'TB_ADDON_8_9' AS source_field,
    TB_ADDON_8_9 AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE TB_ADDON_8_9 IS NOT NULL 
    AND LENGTH(TRIM(TB_ADDON_8_9)) > 5 
    AND season BETWEEN 2023 AND 2025

  UNION ALL

  -- TB_ADDON_8_10: Other Fan Behavior Issues
  SELECT qualtrics_id, game_date, season, buyer_type,
    'Other Fan Behavior Issues' AS feedback_source,
    'TB_ADDON_8_10' AS source_field,
    TB_ADDON_8_10 AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE TB_ADDON_8_10 IS NOT NULL 
    AND LENGTH(TRIM(TB_ADDON_8_10)) > 5 
    AND season BETWEEN 2023 AND 2025

  UNION ALL

  -- TB_ADDON_8_11: Other Miscellaneous Issues
  SELECT qualtrics_id, game_date, season, buyer_type,
    'Other Issues' AS feedback_source,
    'TB_ADDON_8_11' AS source_field,
    TB_ADDON_8_11 AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE TB_ADDON_8_11 IS NOT NULL 
    AND LENGTH(TRIM(TB_ADDON_8_11)) > 5 
    AND season BETWEEN 2023 AND 2025

  UNION ALL

  -- INCENTIVES_OT: Ticket Purchase Decision Factors
  SELECT qualtrics_id, game_date, season, buyer_type,
    'Ticket Purchase Incentives' AS feedback_source,
    'INCENTIVES_OT' AS source_field,
    INCENTIVES_OT AS feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE INCENTIVES_OT IS NOT NULL 
    AND LENGTH(TRIM(INCENTIVES_OT)) > 5 
    AND season BETWEEN 2023 AND 2025
),

-- Step 2: Single AI call for sentence splitting + sentiment + category classification
combined_analysis AS (
  SELECT
    qualtrics_id,
    game_date,
    season,
    buyer_type,
    feedback_source,
    source_field,
    feedback_text,
    AI_COMPLETE(
      'snowflake-llama3.3-70b',
      'Analyze this fan feedback from a baseball stadium. Split into sentences and classify each.

FEEDBACK: ' || feedback_text || '

Return ONLY a valid JSON array. Each element must have:
- "sentence": the exact sentence text
- "sentiment": exactly one of "Positive", "Neutral", or "Negative"
- "category": exactly one of these categories:
  "Parking & Arrival", "Gate Entry & Security", "Wayfinding & Accessibility",
  "Seating & Venue Comfort", "Crowd & Atmosphere", "Food & Beverage Quality",
  "Concession Service & Speed", "Merchandise & Team Store",
  "Game Entertainment & Presentation", "Promotions & Special Events",
  "Team Performance & Game Quality", "Staff Interactions & Service",
  "Facilities & Cleanliness", "Weather", "Technology & Digital Experience",
  "Pricing & Value Perception", "Overall Experience & Loyalty",
  "Ticketing & Purchase Experience", "Egress", "stadium departure", "Other"

CLASSIFICATION RULES:
- Be SPECIFIC with categories. Do not overuse "Overall Experience & Loyalty"
- Food quality vs service speed are DIFFERENT categories
- Staff comments go to "Staff Interactions & Service"
- Positive atmosphere comments go to "Crowd & Atmosphere", NOT "Overall Experience"
- Team/game action comments go to "Team Performance & Game Quality"
- Comments about leaving or exiting the stadium go to "Egress" or "stadium departure"
- Return ONLY the JSON array, nothing else.

Example output:
[{"sentence":"The food was great","sentiment":"Positive","category":"Food & Beverage Quality"},{"sentence":"Parking was terrible","sentiment":"Negative","category":"Parking & Arrival"}]',
      {
        'temperature': 0.1,
        'max_tokens': 2000
      }
    ) AS analysis_json
  FROM raw_feedback
),

-- Step 3: Parse the JSON response
parsed_analysis AS (
  SELECT
    qualtrics_id,
    game_date,
    season,
    buyer_type,
    feedback_source,
    source_field,
    feedback_text AS original_feedback,
    TRY_PARSE_JSON(analysis_json) AS sentences_array
  FROM combined_analysis
  WHERE analysis_json IS NOT NULL
),

-- Step 4: Flatten to individual sentences
flattened AS (
  SELECT
    qualtrics_id,
    game_date,
    season,
    buyer_type,
    feedback_source,
    source_field,
    original_feedback,
    sentence.INDEX + 1 AS sentence_number,
    TRIM(sentence.VALUE:sentence::STRING) AS sentence_text,
    TRIM(sentence.VALUE:sentiment::STRING) AS sentiment_category,
    TRIM(sentence.VALUE:category::STRING) AS ai_category
  FROM parsed_analysis,
  LATERAL FLATTEN(input => sentences_array) sentence
  WHERE sentence.VALUE:sentence IS NOT NULL
    AND LENGTH(TRIM(sentence.VALUE:sentence::STRING)) > 5
)

-- Step 5: Final output with parent category mapping
SELECT
  qualtrics_id,
  game_date,
  season,
  buyer_type,
  feedback_source,
  source_field,
  original_feedback,
  sentence_number,
  sentence_text,
  sentiment_category,
  ai_category,
  -- Parent category mapping (matches YAML taxonomy)
  CASE 
    WHEN ai_category = 'Parking & Arrival' THEN 'PRE-ARRIVAL & ARRIVAL'
    WHEN ai_category IN ('Gate Entry & Security', 'Wayfinding & Accessibility') THEN 'ENTRY & NAVIGATION'
    WHEN ai_category IN ('Seating & Venue Comfort', 'Crowd & Atmosphere') THEN 'IN-SEAT EXPERIENCE'
    WHEN ai_category IN ('Food & Beverage Quality', 'Concession Service & Speed', 'Merchandise & Team Store') THEN 'CONCESSIONS & AMENITIES'
    WHEN ai_category IN ('Game Entertainment & Presentation', 'Promotions & Special Events', 'Team Performance & Game Quality') THEN 'ENTERTAINMENT & ENGAGEMENT'
    WHEN ai_category IN ('Staff Interactions & Service', 'Facilities & Cleanliness', 'Weather', 'Technology & Digital Experience') THEN 'SERVICE & OPERATIONS'
    WHEN ai_category IN ('Pricing & Value Perception', 'Overall Experience & Loyalty', 'Ticketing & Purchase Experience') THEN 'VALUE & OVERALL'
    WHEN ai_category IN ('Egress', 'stadium departure') THEN 'EGRESS & DEPARTURE'
    ELSE 'OTHER'
  END AS parent_category,
  CONCAT(ai_category, ' - ', sentiment_category) AS detailed_category,
  LENGTH(sentence_text) AS sentence_length
FROM flattened
ORDER BY season DESC, game_date DESC, qualtrics_id, feedback_source, sentence_number;

GRANT SELECT ON VIEW TBRDP_DW_DEV.IM_RPT.V_QUALITATIVE_FEEDBACK_SENTENCE_LEVEL
    TO ROLE TBRDP_DW_PROD_CORTEX_USER;

COMMENT ON VIEW TBRDP_DW_DEV.IM_RPT.V_QUALITATIVE_FEEDBACK_SENTENCE_LEVEL IS 
'OPTIMIZED: Sentence-level analysis of ALL qualitative feedback fields (2023-2025).
Reads directly from base table (not nested view) for cost efficiency.
Uses single AI_COMPLETE call per feedback for sentence splitting, sentiment, AND category classification.
Categories aligned with YAML taxonomy (21 categories incl. "stadium departure").';
-- =====================================================
-- 8) CORTEX AI COST MONITORING VIEW
-- =====================================================

CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_CORTEX_AI_COSTS AS
SELECT
  DATE_TRUNC('day', START_TIME) AS usage_date,
  FUNCTION_NAME,
  MODEL_NAME,
  COUNT(*) AS total_calls,
  SUM(INPUT_TOKENS) AS total_input_tokens,
  SUM(OUTPUT_TOKENS) AS total_output_tokens,
  SUM(TOTAL_CREDITS) AS total_credits,
  ROUND(SUM(TOTAL_CREDITS) * 3, 2) AS estimated_cost_usd  -- adjust multiplier to your contract
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD(day, -30, CURRENT_DATE())
GROUP BY 1, 2, 3
ORDER BY usage_date DESC, total_credits DESC;

COMMENT ON VIEW TBRDP_DW_DEV.IM_RPT.V_CORTEX_AI_COSTS IS 
'Cortex AI cost monitoring view by day/function/model (last 30 days).';


-- =====================================================
-- 9) QUERY-LEVEL COST TRACKING
-- =====================================================

CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_CORTEX_QUERY_COSTS AS
SELECT
  QUERY_ID,
  DATE_TRUNC('hour', START_TIME) AS query_hour,
  MODEL_NAME,
  SUM(INPUT_TOKENS) AS input_tokens,
  SUM(OUTPUT_TOKENS) AS output_tokens,
  SUM(TOTAL_CREDITS) AS credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY
WHERE START_TIME >= DATEADD(day, -7, CURRENT_DATE())
GROUP BY 1, 2, 3
ORDER BY credits_used DESC
LIMIT 100;

COMMENT ON VIEW TBRDP_DW_DEV.IM_RPT.V_CORTEX_QUERY_COSTS IS 
'Top 100 most expensive Cortex AI queries in the last 7 days.';


-- =====================================================
-- VERIFICATION QUERIES (OPTIONAL)
-- =====================================================

-- Category distribution alignment with YAML
-- SELECT 
--   ai_category,
--   parent_category,
--   sentiment_category,
--   COUNT(*) AS count,
--   ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS pct
-- FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
-- WHERE season = 2025
-- GROUP BY 1, 2, 3
-- ORDER BY count DESC;

-- Verify all categories are in use
-- SELECT DISTINCT ai_category
-- FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
-- WHERE season >= 2024
-- ORDER BY 1;

-- Sentence-level performance sanity check
-- SELECT 
--   season,
--   COUNT(DISTINCT qualtrics_id) AS unique_responses,
--   COUNT(*) AS total_sentences,
--   ROUND(AVG(sentence_number), 1) AS avg_sentences_per_response
-- FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_SENTENCE_LEVEL
-- GROUP BY season
-- ORDER BY season DESC;

-- Qualitative feedback sources summary
-- SELECT 
--   feedback_source,
--   COUNT(*) AS feedback_count,
--   COUNT(CASE WHEN sentiment = 'Negative' THEN 1 END) AS negative_count,
--   ROUND(100.0 * COUNT(CASE WHEN sentiment = 'Negative' THEN 1 END) / NULLIF(COUNT(*), 0), 1) AS negative_pct
-- FROM TBRDP_DW_DEV.IM_RPT.V_QUALITATIVE_FEEDBACK_ALL
-- WHERE season = 2025
-- GROUP BY 1
-- ORDER BY feedback_count DESC;

-- Check cost monitoring
-- SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_CORTEX_AI_COSTS
-- WHERE usage_date >= CURRENT_DATE() - 7;

-- =====================================================
-- END OF SCRIPT
-- =====================================================
