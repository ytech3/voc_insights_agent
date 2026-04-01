-- =====================================================
-- VOC FEEDBACK VIEW UPDATE
-- Adds 7 new AI categories + new department mapping
-- =====================================================
-- INSTRUCTIONS:
--   1. Open this file in a NEW Snowsight SQL Worksheet
--   2. Set Role to ACCOUNTADMIN (top-left dropdown)
--   3. Set Warehouse to TBRDP_DW_CORTEX_XS_WH
--   4. Set Database to TBRDP_DW_DEV, Schema to IM_RPT
--   5. Select ALL text (Ctrl+A), then click "Run" (Ctrl+Enter)
-- =====================================================

CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS(
    QUALTRICS_ID,
    GAME_DATE,
    SEASON,
    BUYER_TYPE,
    SATISFACTION_RATING,
    FEEDBACK_TEXT,
    FEEDBACK_LENGTH,
    EXISTING_PARENT_TOPIC,
    EXISTING_TOPIC,
    AI_CATEGORY,
    PARENT_CATEGORY,
    SENTIMENT_CATEGORY,
    SENTIMENT_SCORE,
    NPS_SEGMENT,
    DETAILED_CATEGORY
) COMMENT='AI-powered analysis of fan feedback with categories aligned to department taxonomy.
Includes parent category rollups mapped to Rays departments. Covers seasons 2023+.'
AS
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
      AND season >= 2023
),
with_ai_analysis AS (
    SELECT
        *,
        -- Topic classification (64 categories)
        AI_CLASSIFY(
            feedback_text,
            ARRAY_CONSTRUCT(
                -- Concessions (15)
                'Food Quality',
                'Beverage Quality',
                'Concession Wait Times',
                'Concession Staff Service',
                'Concessions Staff',
                'Food Cost',
                'Beverage Cost',
                'Menu Variety',
                'Hot Dogs',
                'Pizza',
                'Burger',
                'Fries',
                'Vegan Options',
                'Alcohol',
                'Alcohol Pricing',
                -- Retail (5)
                'Merchandise Selection',
                'Merchandise Cost',
                'Team Store Experience',
                'Team Store Line',
                'Retail Staff',
                -- Game Entertainment (10)
                'Team Performance',
                'Game Competitiveness',
                'On-Field Entertainment',
                'Game Production',
                'Promotions',
                'Music',
                'Giveaway',
                'Kids Club',
                'Pregame',
                'Postgame',
                -- Fan Experience (11)
                'Fan Experience',
                'Crowd Energy',
                'Seating Comfort',
                'Venue Cleanliness',
                'Wayfinding',
                'Staff Support',
                'ADA Accessibility',
                'Restroom Experience',
                'Seat View',
                'Run the Bases',
                'Autographs',
                -- Parking (3)
                'Parking Availability',
                'Departure Traffic',
                'Parking Cost',
                -- Stadium Operations (4)
                'Facility Maintenance',
                'Gate Entry Speed',
                'Weather Impact',
                'Bathroom Cleanliness',
                -- Digital Experience (4)
                'Mobile App',
                'In-Venue Wi-Fi',
                'Mobile Ordering',
                'Seat Upgrade',
                -- Ticketing (8)
                'Ticket Purchase Process',
                'Mobile Ticketing',
                'Ticketing Value Perception',
                'Ticket Pricing',
                'Seating Locations',
                'Premium Experience',
                'Baldwin Group Club',
                'Suites',
                -- Marketing (4)
                'Raymond the Mascot',
                'Theme Night',
                'Concert Experience',
                'Concert Artist'
            )
        )['labels'][0]::VARCHAR AS ai_category,

        -- Sentiment classification
        AI_CLASSIFY(
            feedback_text,
            ARRAY_CONSTRUCT('Positive', 'Neutral', 'Negative')
        )['labels'][0]::VARCHAR AS sentiment_category,

        -- Numeric sentiment score
        AI_SENTIMENT(feedback_text) AS sentiment_score,

        -- NPS segment
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
            -- Concessions (15)
            WHEN ai_category IN ('Food Quality', 'Beverage Quality', 'Concession Wait Times', 'Concession Staff Service',
                                 'Concessions Staff', 'Food Cost', 'Beverage Cost', 'Menu Variety',
                                 'Hot Dogs', 'Pizza', 'Burger', 'Fries', 'Vegan Options',
                                 'Alcohol', 'Alcohol Pricing') THEN 'Concessions'
            -- Retail (5)
            WHEN ai_category IN ('Merchandise Selection', 'Merchandise Cost', 'Team Store Experience', 'Team Store Line',
                                 'Retail Staff') THEN 'Retail'
            -- Game Entertainment (10)
            WHEN ai_category IN ('Team Performance', 'Game Competitiveness', 'On-Field Entertainment', 'Game Production',
                                 'Promotions', 'Music', 'Giveaway', 'Kids Club', 'Pregame', 'Postgame') THEN 'Game Entertainment'
            -- Fan Experience (11)
            WHEN ai_category IN ('Fan Experience', 'Crowd Energy', 'Seating Comfort', 'Venue Cleanliness', 'Wayfinding',
                                 'Staff Support', 'ADA Accessibility', 'Restroom Experience', 'Seat View',
                                 'Run the Bases', 'Autographs') THEN 'Fan Experience'
            -- Parking (3)
            WHEN ai_category IN ('Parking Availability', 'Departure Traffic', 'Parking Cost') THEN 'Parking'
            -- Stadium Operations (4)
            WHEN ai_category IN ('Facility Maintenance', 'Gate Entry Speed', 'Weather Impact', 'Bathroom Cleanliness') THEN 'Stadium Operations'
            -- Digital Experience (4)
            WHEN ai_category IN ('Mobile App', 'In-Venue Wi-Fi', 'Mobile Ordering', 'Seat Upgrade') THEN 'Digital Experience'
            -- Ticketing (8)
            WHEN ai_category IN ('Ticket Purchase Process', 'Mobile Ticketing', 'Ticketing Value Perception', 'Ticket Pricing',
                                 'Seating Locations', 'Premium Experience', 'Baldwin Group Club', 'Suites') THEN 'Ticketing'
            -- Marketing (4)
            WHEN ai_category IN ('Raymond the Mascot', 'Theme Night', 'Concert Experience', 'Concert Artist') THEN 'Marketing'
            ELSE 'Uncategorized'
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
FROM with_parent_category
