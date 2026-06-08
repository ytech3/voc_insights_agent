-- =====================================================
-- VOC DAILY REPORT CARD V2 - AUTOMATED EMAIL SYSTEM
-- Tampa Bay Rays - Voice of Customer Analysis
-- =====================================================
-- Description: Automated daily Report Card with dynamic
--              deep dive that changes based on data:
--   1. Quantitative Summary (bar chart, % gap to goal)
--   2. Qualitative Summary (AI-classified topic ranking)
--   Key Insight: Dynamic Gap Finder across 36+ metrics
--   Deep Dive: Routes to biggest gap area automatically (Concessions, Parking, Merchandise, Entertainment, Staff, Food Quality)
--   3. AI-Generated Action Items (claude-sonnet-4-6)
-- Version: 2.0
-- Created: March 2026
-- Author: Tampa Bay Rays Strategy & Analytics Team
-- =====================================================
-- PREREQUISITES:
--   - ACCOUNTADMIN role (for notification integration)
--   - TBRDP_DW_CORTEX_XS_WH warehouse
--   - V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI base view
--   - V_OVERALL_FEEDBACK_ANALYSIS AI-enriched feedback view
--   - Cortex AI functions (AI_COMPLETE with claude-sonnet-4-6)
-- =====================================================

-- =====================================================
-- STEP 1: CREATE EMAIL NOTIFICATION INTEGRATION
-- =====================================================
-- Run as ACCOUNTADMIN (one-time setup)

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE TBRDP_DW_CORTEX_XS_WH;

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS VOC_REPORT_CARD_EMAIL
    TYPE = EMAIL
    ENABLED = TRUE
    ALLOWED_RECIPIENTS = ('ytaketani@raysbaseball.com')
    COMMENT = 'Email integration for daily VOC Game Day Report Card';

GRANT USAGE ON INTEGRATION VOC_REPORT_CARD_EMAIL TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- =====================================================
-- STEP 2: CREATE THE REPORT CARD STORED PROCEDURE
-- =====================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE TBRDP_DW_DEV;
USE SCHEMA IM_RPT;

CREATE OR REPLACE PROCEDURE TBRDP_DW_DEV.IM_RPT.SP_VOC_DAILY_REPORT_CARD(P_GAME_DATE VARCHAR DEFAULT NULL)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
BEGIN
    -- =============================================
    -- VARIABLE DECLARATIONS
    -- =============================================
    LET v_target_game_date DATE;
    LET v_season NUMBER;
    LET v_response_count NUMBER;
    LET v_game_avg FLOAT;
    LET v_season_avg FLOAT;
    LET v_season_responses NUMBER;
    LET v_gap_pct FLOAT;
    LET v_gap_icon VARCHAR;
    LET v_game_date_display VARCHAR;
    LET v_day_of_week VARCHAR;
    LET v_opponent VARCHAR;
    LET v_header_line VARCHAR;

    -- Bar chart width variables
    LET v_benchmark_bar_width VARCHAR;
    LET v_benchmark_bar_remainder VARCHAR;
    LET v_game_bar_width VARCHAR;
    LET v_game_bar_remainder VARCHAR;

    -- Qualitative variables
    LET v_promoter_count NUMBER;
    LET v_opportunity_count NUMBER;
    LET v_promoter_topic_1 VARCHAR DEFAULT 'N/A';
    LET v_promoter_topic_1_pct VARCHAR DEFAULT '0';
    LET v_promoter_topic_2 VARCHAR DEFAULT 'N/A';
    LET v_promoter_topic_2_pct VARCHAR DEFAULT '0';
    LET v_promoter_topic_3 VARCHAR DEFAULT 'N/A';
    LET v_promoter_topic_3_pct VARCHAR DEFAULT '0';
    LET v_opp_topic_1 VARCHAR DEFAULT 'N/A';
    LET v_opp_topic_1_pct VARCHAR DEFAULT '0';
    LET v_opp_topic_2 VARCHAR DEFAULT 'N/A';
    LET v_opp_topic_2_pct VARCHAR DEFAULT '0';
    LET v_opp_topic_3 VARCHAR DEFAULT 'N/A';
    LET v_opp_topic_3_pct VARCHAR DEFAULT '0';

    -- Gap Finder variables
    LET v_gap_metric VARCHAR DEFAULT '';
    LET v_gap_area VARCHAR DEFAULT '';
    LET v_gap_metric_type VARCHAR DEFAULT '';
    LET v_gap_value FLOAT DEFAULT 0;
    LET v_gap_promoter_val FLOAT DEFAULT 0;
    LET v_gap_opp_val FLOAT DEFAULT 0;

    -- Deep dive variables (generic for any area)
    LET v_dd_title VARCHAR DEFAULT '';
    LET v_dd_icon VARCHAR DEFAULT '';
    LET v_dd_numrat_label VARCHAR DEFAULT '';
    LET v_dd_promoter_numrat VARCHAR DEFAULT 'N/A';
    LET v_dd_opp_numrat VARCHAR DEFAULT 'N/A';
    LET v_dd_numrat_gap VARCHAR DEFAULT 'N/A';
    LET v_dd_row1_label VARCHAR DEFAULT '';
    LET v_dd_row1_p VARCHAR DEFAULT 'N/A';
    LET v_dd_row1_o VARCHAR DEFAULT 'N/A';
    LET v_dd_row1_gap VARCHAR DEFAULT 'N/A';
    LET v_dd_row2_label VARCHAR DEFAULT '';
    LET v_dd_row2_p VARCHAR DEFAULT 'N/A';
    LET v_dd_row2_o VARCHAR DEFAULT 'N/A';
    LET v_dd_row2_gap VARCHAR DEFAULT 'N/A';
    LET v_dd_row3_label VARCHAR DEFAULT '';
    LET v_dd_row3_p VARCHAR DEFAULT 'N/A';
    LET v_dd_row3_o VARCHAR DEFAULT 'N/A';
    LET v_dd_row3_gap VARCHAR DEFAULT 'N/A';
    LET v_dd_has_numrat BOOLEAN DEFAULT FALSE;

    -- Staff deep dive variables
    LET v_staff_promoter_avg FLOAT DEFAULT NULL;
    LET v_staff_opp_avg FLOAT DEFAULT NULL;
    LET v_staff_cat_label VARCHAR DEFAULT '';
    LET v_staff_cat_p FLOAT DEFAULT 0;
    LET v_staff_cat_o FLOAT DEFAULT 0;
    LET v_staff_cat_gap FLOAT DEFAULT 0;
    LET v_staff_rank NUMBER DEFAULT 0;

    -- Food quality deep dive variables
    LET v_fq_cat_label VARCHAR DEFAULT '';
    LET v_fq_cat_p FLOAT DEFAULT 0;
    LET v_fq_cat_o FLOAT DEFAULT 0;
    LET v_fq_cat_gap FLOAT DEFAULT 0;
    LET v_fq_rank NUMBER DEFAULT 0;

    -- AI context variables for staff + food quality
    LET v_staff_context VARCHAR DEFAULT '';
    LET v_food_quality_context VARCHAR DEFAULT '';

    -- AI & email variables
    LET v_action_items VARCHAR DEFAULT '';
    LET v_key_insight VARCHAR DEFAULT '';
    LET v_deep_dive_narrative VARCHAR DEFAULT '';
    LET v_html_body VARCHAR;
    LET v_email_subject VARCHAR;

    -- =============================================
    -- DETERMINE TARGET GAME DATE
    -- =============================================
    IF (P_GAME_DATE IS NOT NULL) THEN
        v_target_game_date := P_GAME_DATE::DATE;
    ELSE
        SELECT MAX(GAME_DATE)::DATE
        INTO :v_target_game_date
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
        WHERE GAME_DATE IS NOT NULL
          AND GAME_DATE::DATE < CURRENT_DATE()
          AND OVERALL_NUMRAT IS NOT NULL;
    END IF;

    IF (v_target_game_date IS NULL) THEN
        RETURN 'No game data found for report card generation.';
    END IF;

    -- =============================================
    -- HEADER: Game date, opponent, day of week
    -- =============================================
    SELECT
        DECODE(DAYNAME(GAME_DATE::DATE),
            'Mon','Monday','Tue','Tuesday','Wed','Wednesday',
            'Thu','Thursday','Fri','Friday','Sat','Saturday','Sun','Sunday'),
        AWAYTRI,
        TO_VARCHAR(GAME_DATE::DATE, 'MMMM DD'),
        SEASON
    INTO :v_day_of_week, :v_opponent, :v_game_date_display, :v_season
    FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
    WHERE GAME_DATE::DATE = :v_target_game_date
      AND AWAYTRI IS NOT NULL
    LIMIT 1;

    -- Format: "Thursday, March 28 vs TOR"
    v_header_line := v_day_of_week || ', ' || v_game_date_display || ' vs ' || v_opponent;

    -- =============================================
    -- SECTION 1: QUANTITATIVE SUMMARY
    -- =============================================
    SELECT COUNT(*), ROUND(AVG(OVERALL_NUMRAT), 2)
    INTO :v_response_count, :v_game_avg
    FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
    WHERE GAME_DATE::DATE = :v_target_game_date
      AND OVERALL_NUMRAT IS NOT NULL;

    SELECT COUNT(*), ROUND(AVG(OVERALL_NUMRAT), 2)
    INTO :v_season_responses, :v_season_avg
    FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
    WHERE SEASON = :v_season
      AND OVERALL_NUMRAT IS NOT NULL;

    -- Gap as percentage
    v_gap_pct := ROUND(((v_game_avg - v_season_avg) / v_season_avg) * 100, 2);
    IF (v_gap_pct >= 0) THEN
        v_gap_icon := '&#9650;';
    ELSE
        v_gap_icon := '&#9660;';
    END IF;

    -- Bar chart widths (score / 10 * 100 = % width)
    v_benchmark_bar_width := ROUND(v_season_avg * 10, 1)::VARCHAR || '%';
    v_benchmark_bar_remainder := ROUND((10 - v_season_avg) * 10, 1)::VARCHAR || '%';
    v_game_bar_width := ROUND(v_game_avg * 10, 1)::VARCHAR || '%';
    v_game_bar_remainder := ROUND((10 - v_game_avg) * 10, 1)::VARCHAR || '%';

    -- =============================================
    -- SECTION 2: QUALITATIVE SUMMARY
    -- =============================================
    SELECT
        COUNT(CASE WHEN nps_segment = 'Promoter' THEN 1 END),
        COUNT(CASE WHEN nps_segment IN ('Passive', 'Detractor') THEN 1 END)
    INTO :v_promoter_count, :v_opportunity_count
    FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
    WHERE GAME_DATE::DATE = :v_target_game_date;

    -- Top 3 Promoter topics
    LET v_rank NUMBER := 0;
    LET res_promoter RESULTSET := (
        SELECT ai_category,
            ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS pct
        FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
        WHERE GAME_DATE::DATE = :v_target_game_date
          AND nps_segment = 'Promoter'
          AND ai_category IS NOT NULL
        GROUP BY ai_category
        ORDER BY COUNT(*) DESC
        LIMIT 3
    );
    LET c_promoter_topics CURSOR FOR res_promoter;
    FOR rec IN c_promoter_topics DO
        v_rank := v_rank + 1;
        IF (v_rank = 1) THEN v_promoter_topic_1 := rec.ai_category; v_promoter_topic_1_pct := rec.pct::VARCHAR;
        ELSEIF (v_rank = 2) THEN v_promoter_topic_2 := rec.ai_category; v_promoter_topic_2_pct := rec.pct::VARCHAR;
        ELSEIF (v_rank = 3) THEN v_promoter_topic_3 := rec.ai_category; v_promoter_topic_3_pct := rec.pct::VARCHAR;
        END IF;
    END FOR;

    -- Top 3 Opportunity topics
    LET res_opp RESULTSET := (
        SELECT ai_category,
            ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS pct
        FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
        WHERE GAME_DATE::DATE = :v_target_game_date
          AND nps_segment IN ('Passive', 'Detractor')
          AND ai_category IS NOT NULL
        GROUP BY ai_category
        ORDER BY COUNT(*) DESC
        LIMIT 3
    );
    LET c_opp_topics CURSOR FOR res_opp;
    v_rank := 0;
    FOR rec IN c_opp_topics DO
        v_rank := v_rank + 1;
        IF (v_rank = 1) THEN v_opp_topic_1 := rec.ai_category; v_opp_topic_1_pct := rec.pct::VARCHAR;
        ELSEIF (v_rank = 2) THEN v_opp_topic_2 := rec.ai_category; v_opp_topic_2_pct := rec.pct::VARCHAR;
        ELSEIF (v_rank = 3) THEN v_opp_topic_3 := rec.ai_category; v_opp_topic_3_pct := rec.pct::VARCHAR;
        END IF;
    END FOR;

    -- =============================================
    -- GAP FINDER: Find largest Promoter vs Opp gap
    -- =============================================
    LET res_gap RESULTSET := (
        WITH base AS (
            SELECT *,
                CASE WHEN OVERALL_NUMRAT >= 9 THEN 'Promoter' ELSE 'Opportunity' END AS nps_seg
            FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
            WHERE GAME_DATE::DATE = :v_target_game_date
        ),
        numrat_gaps AS (
            SELECT 'CONCESS_NUMRAT' AS metric, 'Concessions' AS area, 'numrat' AS metric_type,
                ROUND(100.0 * (AVG(CASE WHEN nps_seg='Promoter' THEN CONCESS_NUMRAT END) - AVG(CASE WHEN nps_seg='Opportunity' THEN CONCESS_NUMRAT END))
                    / NULLIF(AVG(CASE WHEN nps_seg='Promoter' THEN CONCESS_NUMRAT END), 0), 2) AS gap_pct,
                ROUND(AVG(CASE WHEN nps_seg='Promoter' THEN CONCESS_NUMRAT END), 2) AS promoter_val,
                ROUND(AVG(CASE WHEN nps_seg='Opportunity' THEN CONCESS_NUMRAT END), 2) AS opp_val
            FROM base WHERE CONCESS_NUMRAT IS NOT NULL
            UNION ALL
            SELECT 'PARKING_NUMRAT', 'Parking', 'numrat',
                ROUND(100.0 * (AVG(CASE WHEN nps_seg='Promoter' THEN PARKING_NUMRAT END) - AVG(CASE WHEN nps_seg='Opportunity' THEN PARKING_NUMRAT END))
                    / NULLIF(AVG(CASE WHEN nps_seg='Promoter' THEN PARKING_NUMRAT END), 0), 2),
                ROUND(AVG(CASE WHEN nps_seg='Promoter' THEN PARKING_NUMRAT END), 2),
                ROUND(AVG(CASE WHEN nps_seg='Opportunity' THEN PARKING_NUMRAT END), 2)
            FROM base WHERE PARKING_NUMRAT IS NOT NULL
            UNION ALL
            SELECT 'STAFF_OVERALL', 'Staff', 'numrat',
                ROUND(100.0 * (p_avg - o_avg) / NULLIF(p_avg, 0), 2),
                ROUND(p_avg, 2),
                ROUND(o_avg, 2)
            FROM (
                SELECT
                    AVG(CASE WHEN nps_seg='Promoter' THEN staff_norm END) AS p_avg,
                    AVG(CASE WHEN nps_seg='Opportunity' THEN staff_norm END) AS o_avg
                FROM (
                    SELECT nps_seg,
                        CASE WHEN SEASON >= 2026 THEN
                            (COALESCE(CASE WHEN TB_ADDON_23_1 < 80 THEN TB_ADDON_23_1 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_23_3 < 80 THEN TB_ADDON_23_3 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_23_5 < 80 THEN TB_ADDON_23_5 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_23_6 < 80 THEN TB_ADDON_23_6 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_23_24 < 80 THEN TB_ADDON_23_24 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_23_38 < 80 THEN TB_ADDON_23_38 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_23_60 < 80 THEN TB_ADDON_23_60 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_23_61 < 80 THEN TB_ADDON_23_61 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_23_67 < 80 THEN TB_ADDON_23_67 END, 0))
                            / NULLIF(
                                IFF(TB_ADDON_23_1 IS NOT NULL AND TB_ADDON_23_1 < 80, 1, 0)
                                + IFF(TB_ADDON_23_3 IS NOT NULL AND TB_ADDON_23_3 < 80, 1, 0)
                                + IFF(TB_ADDON_23_5 IS NOT NULL AND TB_ADDON_23_5 < 80, 1, 0)
                                + IFF(TB_ADDON_23_6 IS NOT NULL AND TB_ADDON_23_6 < 80, 1, 0)
                                + IFF(TB_ADDON_23_24 IS NOT NULL AND TB_ADDON_23_24 < 80, 1, 0)
                                + IFF(TB_ADDON_23_38 IS NOT NULL AND TB_ADDON_23_38 < 80, 1, 0)
                                + IFF(TB_ADDON_23_60 IS NOT NULL AND TB_ADDON_23_60 < 80, 1, 0)
                                + IFF(TB_ADDON_23_61 IS NOT NULL AND TB_ADDON_23_61 < 80, 1, 0)
                                + IFF(TB_ADDON_23_67 IS NOT NULL AND TB_ADDON_23_67 < 80, 1, 0), 0)
                        ELSE
                            (COALESCE(CASE WHEN TB_ADDON_4_1 IS NOT NULL THEN (TB_ADDON_4_1 - 1) * 2.5 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_4_3 IS NOT NULL THEN (TB_ADDON_4_3 - 1) * 2.5 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_4_5 IS NOT NULL THEN (TB_ADDON_4_5 - 1) * 2.5 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_4_6 IS NOT NULL THEN (TB_ADDON_4_6 - 1) * 2.5 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_4_10 IS NOT NULL THEN (TB_ADDON_4_10 - 1) * 2.5 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_4_11 IS NOT NULL THEN (TB_ADDON_4_11 - 1) * 2.5 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_4_24 IS NOT NULL THEN (TB_ADDON_4_24 - 1) * 2.5 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_4_38 IS NOT NULL THEN (TB_ADDON_4_38 - 1) * 2.5 END, 0)
                             + COALESCE(CASE WHEN TB_ADDON_4_39 IS NOT NULL THEN (TB_ADDON_4_39 - 1) * 2.5 END, 0))
                            / NULLIF(
                                IFF(TB_ADDON_4_1 IS NOT NULL, 1, 0)
                                + IFF(TB_ADDON_4_3 IS NOT NULL, 1, 0)
                                + IFF(TB_ADDON_4_5 IS NOT NULL, 1, 0)
                                + IFF(TB_ADDON_4_6 IS NOT NULL, 1, 0)
                                + IFF(TB_ADDON_4_10 IS NOT NULL, 1, 0)
                                + IFF(TB_ADDON_4_11 IS NOT NULL, 1, 0)
                                + IFF(TB_ADDON_4_24 IS NOT NULL, 1, 0)
                                + IFF(TB_ADDON_4_38 IS NOT NULL, 1, 0)
                                + IFF(TB_ADDON_4_39 IS NOT NULL, 1, 0), 0)
                        END AS staff_norm
                    FROM base
                    WHERE (SEASON >= 2026 AND (TB_ADDON_23_1 IS NOT NULL OR TB_ADDON_23_3 IS NOT NULL OR TB_ADDON_23_5 IS NOT NULL OR TB_ADDON_23_6 IS NOT NULL OR TB_ADDON_23_24 IS NOT NULL OR TB_ADDON_23_38 IS NOT NULL OR TB_ADDON_23_60 IS NOT NULL OR TB_ADDON_23_61 IS NOT NULL OR TB_ADDON_23_67 IS NOT NULL))
                       OR (SEASON < 2026 AND (TB_ADDON_4_1 IS NOT NULL OR TB_ADDON_4_3 IS NOT NULL OR TB_ADDON_4_5 IS NOT NULL OR TB_ADDON_4_6 IS NOT NULL OR TB_ADDON_4_10 IS NOT NULL OR TB_ADDON_4_11 IS NOT NULL OR TB_ADDON_4_24 IS NOT NULL OR TB_ADDON_4_38 IS NOT NULL OR TB_ADDON_4_39 IS NOT NULL))
                )
            ) WHERE p_avg IS NOT NULL AND o_avg IS NOT NULL
            UNION ALL
            SELECT 'CONCESS_SPEED', 'Concessions', 'numrat',
                ROUND(100.0 * (AVG(CASE WHEN nps_seg='Promoter' THEN CONCESS_GRID_SPEED END) - AVG(CASE WHEN nps_seg='Opportunity' THEN CONCESS_GRID_SPEED END))
                    / NULLIF(AVG(CASE WHEN nps_seg='Promoter' THEN CONCESS_GRID_SPEED END), 0), 2),
                ROUND(AVG(CASE WHEN nps_seg='Promoter' THEN CONCESS_GRID_SPEED END), 2),
                ROUND(AVG(CASE WHEN nps_seg='Opportunity' THEN CONCESS_GRID_SPEED END), 2)
            FROM base WHERE CONCESS_GRID_SPEED IS NOT NULL AND SEASON >= 2026
        ),
        grid_helper AS (
            SELECT nps_seg,
                CONCESS_GRID_VALUE_DESC, CONCESS_GRID_CUSTSERV_DESC, CONCESS_GRID_SELECTION_DESC, CONCESS_GRID_CLEAN_DESC,
                MERCH_GRID_PRICE_DESC, MERCH_GRID_SELECTION_DESC, MERCH_GRID_MERCHQUALITY_DESC, MERCH_GRID_CUSTSERV_DESC, MERCH_GRID_WAIT_DESC,
                ENTERTAIN_GRID_MUSIC_DESC, ENTERTAIN_GRID_GAMES_DESC, ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC, ENTERTAIN_GRID_SCOREBOARD_DESC, ENTERTAIN_GRID_THEME_DESC,
                CONCESS_QUALITY_ALCOHOL_DESC, CONCESS_QUALITY_NONALCOHOL_DESC, CONCESS_QUALITY_HOTDOG_DESC,
                CONCESS_QUALITY_CHICKEN_DESC, CONCESS_QUALITY_FRIES_DESC, CONCESS_QUALITY_NACHOS_DESC,
                CONCESS_QUALITY_PIZZA_DESC, CONCESS_QUALITY_POPCORN_DESC, CONCESS_QUALITY_PRETZELS_DESC,
                CONCESS_QUALITY_SAUSAGE_DESC, CONCESS_QUALITY_NUTS_DESC, CONCESS_QUALITY_ICECREAM_DESC,
                CONCESS_QUALITY_SANDWICH_DESC, CONCESS_QUALITY_BURGERS_DESC, CONCESS_QUALITY_SALAD_DESC,
                CONCESS_QUALITY_OTHER_ENTREE_DESC, CONCESS_QUALITY_OTHER_DESSERT_DESC
            FROM base
        ),
        grid_gaps AS (
            SELECT 'CONCESS_VALUE' AS metric, 'Concessions' AS area, 'grid' AS metric_type,
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_VALUE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_VALUE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) AS gap_pct,
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_VALUE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) AS promoter_val,
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_VALUE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) AS opp_val
            FROM grid_helper
            UNION ALL
            SELECT 'CONCESS_SERVICE', 'Concessions', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'CONCESS_SELECTION', 'Concessions', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'CONCESS_CLEAN', 'Concessions', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_CLEAN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_CLEAN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_CLEAN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_CLEAN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'MERCH_PRICE', 'Merchandise', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_PRICE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_PRICE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_PRICE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_PRICE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'MERCH_SELECTION', 'Merchandise', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'MERCH_QUALITY', 'Merchandise', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_MERCHQUALITY_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_MERCHQUALITY_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_MERCHQUALITY_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_MERCHQUALITY_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'MERCH_CUSTSERV', 'Merchandise', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'MERCH_WAIT', 'Merchandise', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_WAIT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_WAIT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_WAIT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_WAIT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'ENTERTAIN_MUSIC', 'Entertainment', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_MUSIC_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_MUSIC_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_MUSIC_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_MUSIC_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'ENTERTAIN_GAMES', 'Entertainment', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_GAMES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_GAMES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_GAMES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_GAMES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'ENTERTAIN_SCOREBOARD', 'Entertainment', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_SCOREBOARD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_SCOREBOARD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_SCOREBOARD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_SCOREBOARD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'ENTERTAIN_THEME', 'Entertainment', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_THEME_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_THEME_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_THEME_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_THEME_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_ALCOHOL', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_ALCOHOL_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_ALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_ALCOHOL_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_ALCOHOL_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_ALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_ALCOHOL_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_ALCOHOL_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_ALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_ALCOHOL_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_ALCOHOL_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_ALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_ALCOHOL_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_NONALCOHOL', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_NONALCOHOL_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_NONALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_NONALCOHOL_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_NONALCOHOL_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_NONALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_NONALCOHOL_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_NONALCOHOL_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_NONALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_NONALCOHOL_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_NONALCOHOL_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_NONALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_NONALCOHOL_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_HOTDOG', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_HOTDOG_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_HOTDOG_DESC IS NOT NULL AND CONCESS_QUALITY_HOTDOG_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_HOTDOG_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_HOTDOG_DESC IS NOT NULL AND CONCESS_QUALITY_HOTDOG_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_HOTDOG_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_HOTDOG_DESC IS NOT NULL AND CONCESS_QUALITY_HOTDOG_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_HOTDOG_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_HOTDOG_DESC IS NOT NULL AND CONCESS_QUALITY_HOTDOG_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_CHICKEN', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_CHICKEN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_CHICKEN_DESC IS NOT NULL AND CONCESS_QUALITY_CHICKEN_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_CHICKEN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_CHICKEN_DESC IS NOT NULL AND CONCESS_QUALITY_CHICKEN_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_CHICKEN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_CHICKEN_DESC IS NOT NULL AND CONCESS_QUALITY_CHICKEN_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_CHICKEN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_CHICKEN_DESC IS NOT NULL AND CONCESS_QUALITY_CHICKEN_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_FRIES', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_FRIES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_FRIES_DESC IS NOT NULL AND CONCESS_QUALITY_FRIES_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_FRIES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_FRIES_DESC IS NOT NULL AND CONCESS_QUALITY_FRIES_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_FRIES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_FRIES_DESC IS NOT NULL AND CONCESS_QUALITY_FRIES_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_FRIES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_FRIES_DESC IS NOT NULL AND CONCESS_QUALITY_FRIES_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_NACHOS', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_NACHOS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_NACHOS_DESC IS NOT NULL AND CONCESS_QUALITY_NACHOS_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_NACHOS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_NACHOS_DESC IS NOT NULL AND CONCESS_QUALITY_NACHOS_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_NACHOS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_NACHOS_DESC IS NOT NULL AND CONCESS_QUALITY_NACHOS_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_NACHOS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_NACHOS_DESC IS NOT NULL AND CONCESS_QUALITY_NACHOS_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_PIZZA', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_PIZZA_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_PIZZA_DESC IS NOT NULL AND CONCESS_QUALITY_PIZZA_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_PIZZA_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_PIZZA_DESC IS NOT NULL AND CONCESS_QUALITY_PIZZA_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_PIZZA_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_PIZZA_DESC IS NOT NULL AND CONCESS_QUALITY_PIZZA_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_PIZZA_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_PIZZA_DESC IS NOT NULL AND CONCESS_QUALITY_PIZZA_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_POPCORN', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_POPCORN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_POPCORN_DESC IS NOT NULL AND CONCESS_QUALITY_POPCORN_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_POPCORN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_POPCORN_DESC IS NOT NULL AND CONCESS_QUALITY_POPCORN_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_POPCORN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_POPCORN_DESC IS NOT NULL AND CONCESS_QUALITY_POPCORN_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_POPCORN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_POPCORN_DESC IS NOT NULL AND CONCESS_QUALITY_POPCORN_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_PRETZELS', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_PRETZELS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_PRETZELS_DESC IS NOT NULL AND CONCESS_QUALITY_PRETZELS_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_PRETZELS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_PRETZELS_DESC IS NOT NULL AND CONCESS_QUALITY_PRETZELS_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_PRETZELS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_PRETZELS_DESC IS NOT NULL AND CONCESS_QUALITY_PRETZELS_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_PRETZELS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_PRETZELS_DESC IS NOT NULL AND CONCESS_QUALITY_PRETZELS_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_SAUSAGE', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_SAUSAGE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_SAUSAGE_DESC IS NOT NULL AND CONCESS_QUALITY_SAUSAGE_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_SAUSAGE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_SAUSAGE_DESC IS NOT NULL AND CONCESS_QUALITY_SAUSAGE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_SAUSAGE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_SAUSAGE_DESC IS NOT NULL AND CONCESS_QUALITY_SAUSAGE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_SAUSAGE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_SAUSAGE_DESC IS NOT NULL AND CONCESS_QUALITY_SAUSAGE_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_NUTS', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_NUTS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_NUTS_DESC IS NOT NULL AND CONCESS_QUALITY_NUTS_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_NUTS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_NUTS_DESC IS NOT NULL AND CONCESS_QUALITY_NUTS_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_NUTS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_NUTS_DESC IS NOT NULL AND CONCESS_QUALITY_NUTS_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_NUTS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_NUTS_DESC IS NOT NULL AND CONCESS_QUALITY_NUTS_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_ICECREAM', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_ICECREAM_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_ICECREAM_DESC IS NOT NULL AND CONCESS_QUALITY_ICECREAM_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_ICECREAM_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_ICECREAM_DESC IS NOT NULL AND CONCESS_QUALITY_ICECREAM_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_ICECREAM_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_ICECREAM_DESC IS NOT NULL AND CONCESS_QUALITY_ICECREAM_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_ICECREAM_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_ICECREAM_DESC IS NOT NULL AND CONCESS_QUALITY_ICECREAM_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_SANDWICH', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_SANDWICH_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_SANDWICH_DESC IS NOT NULL AND CONCESS_QUALITY_SANDWICH_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_SANDWICH_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_SANDWICH_DESC IS NOT NULL AND CONCESS_QUALITY_SANDWICH_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_SANDWICH_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_SANDWICH_DESC IS NOT NULL AND CONCESS_QUALITY_SANDWICH_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_SANDWICH_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_SANDWICH_DESC IS NOT NULL AND CONCESS_QUALITY_SANDWICH_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_BURGERS', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_BURGERS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_BURGERS_DESC IS NOT NULL AND CONCESS_QUALITY_BURGERS_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_BURGERS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_BURGERS_DESC IS NOT NULL AND CONCESS_QUALITY_BURGERS_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_BURGERS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_BURGERS_DESC IS NOT NULL AND CONCESS_QUALITY_BURGERS_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_BURGERS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_BURGERS_DESC IS NOT NULL AND CONCESS_QUALITY_BURGERS_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_SALAD', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_SALAD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_SALAD_DESC IS NOT NULL AND CONCESS_QUALITY_SALAD_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_SALAD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_SALAD_DESC IS NOT NULL AND CONCESS_QUALITY_SALAD_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_SALAD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_SALAD_DESC IS NOT NULL AND CONCESS_QUALITY_SALAD_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_SALAD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_SALAD_DESC IS NOT NULL AND CONCESS_QUALITY_SALAD_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_OTHER_ENTREE', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_OTHER_ENTREE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_OTHER_ENTREE_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_ENTREE_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_OTHER_ENTREE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_OTHER_ENTREE_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_ENTREE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_OTHER_ENTREE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_OTHER_ENTREE_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_ENTREE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_OTHER_ENTREE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_OTHER_ENTREE_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_ENTREE_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
            UNION ALL
            SELECT 'FQ_OTHER_DESSERT', 'Food Quality', 'grid',
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_OTHER_DESSERT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_OTHER_DESSERT_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_DESSERT_DESC!='N/A' THEN 1 ELSE 0 END),0)
                -100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_OTHER_DESSERT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_OTHER_DESSERT_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_DESSERT_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_OTHER_DESSERT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Promoter' AND CONCESS_QUALITY_OTHER_DESSERT_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_DESSERT_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                ROUND(100.0*SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_OTHER_DESSERT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN nps_seg='Opportunity' AND CONCESS_QUALITY_OTHER_DESSERT_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_DESSERT_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
            FROM grid_helper
        ),
        all_gaps AS (
            SELECT * FROM numrat_gaps UNION ALL SELECT * FROM grid_gaps
        )
        SELECT metric, area, metric_type, gap_pct, promoter_val, opp_val
        FROM all_gaps
        WHERE gap_pct IS NOT NULL
        ORDER BY ABS(gap_pct) DESC
        LIMIT 1;

    FOR rec IN c_gap DO
        v_gap_metric := rec.metric;
        v_gap_area := rec.area;
        v_gap_metric_type := rec.metric_type;
        v_gap_value := rec.gap_pct;
        v_gap_promoter_val := rec.promoter_val;
        v_gap_opp_val := rec.opp_val;
    END FOR;

    -- =============================================
    -- DYNAMIC DEEP DIVE: Route to correct area
    -- =============================================
    -- Set deep dive title and icon based on area
    IF (v_gap_area = 'Concessions') THEN
        v_dd_title := 'CONCESSION DEEP DIVE';
        v_dd_icon := '&#127828;';
        v_dd_has_numrat := TRUE;
        v_dd_numrat_label := 'Avg Concession Rating';
        -- Get CONCESS_NUMRAT Promoter vs Opp
        SELECT
            COALESCE(ROUND(AVG(CASE WHEN OVERALL_NUMRAT >= 9 THEN CONCESS_NUMRAT END), 2)::VARCHAR, 'N/A'),
            COALESCE(ROUND(AVG(CASE WHEN OVERALL_NUMRAT < 9 THEN CONCESS_NUMRAT END), 2)::VARCHAR, 'N/A')
        INTO :v_dd_promoter_numrat, :v_dd_opp_numrat
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
        WHERE GAME_DATE::DATE = :v_target_game_date AND CONCESS_NUMRAT IS NOT NULL;

        v_dd_numrat_gap := CASE WHEN v_dd_promoter_numrat != 'N/A' AND v_dd_opp_numrat != 'N/A'
            THEN ROUND(100.0 * (v_dd_promoter_numrat::FLOAT - v_dd_opp_numrat::FLOAT) / NULLIF(v_dd_promoter_numrat::FLOAT, 0), 2)::VARCHAR ELSE 'N/A' END;

        -- Grid rows: Value, Service, Selection
        v_dd_row1_label := '&#128176; Value for Money';
        v_dd_row2_label := '&#129309; Customer Service';
        v_dd_row3_label := '&#127829; Food/Bev Selection';

        SELECT
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_GRID_VALUE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_GRID_VALUE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A')
        INTO :v_dd_row1_p, :v_dd_row1_o, :v_dd_row2_p, :v_dd_row2_o, :v_dd_row3_p, :v_dd_row3_o
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
        WHERE GAME_DATE::DATE = :v_target_game_date;

    ELSEIF (v_gap_area = 'Merchandise') THEN
        v_dd_title := 'MERCHANDISE DEEP DIVE';
        v_dd_icon := '&#128085;';
        v_dd_has_numrat := FALSE;
        v_dd_row1_label := '&#128176; Price Satisfaction';
        v_dd_row2_label := '&#127917; Product Selection';
        v_dd_row3_label := '&#11088; Merchandise Quality';

        SELECT
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND MERCH_GRID_PRICE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND MERCH_GRID_PRICE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND MERCH_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND MERCH_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND MERCH_GRID_MERCHQUALITY_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND MERCH_GRID_MERCHQUALITY_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A')
        INTO :v_dd_row1_p, :v_dd_row1_o, :v_dd_row2_p, :v_dd_row2_o, :v_dd_row3_p, :v_dd_row3_o
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
        WHERE GAME_DATE::DATE = :v_target_game_date;

    ELSEIF (v_gap_area = 'Entertainment') THEN
        v_dd_title := 'ENTERTAINMENT DEEP DIVE';
        v_dd_icon := '&#127926;';
        v_dd_has_numrat := FALSE;
        v_dd_row1_label := '&#127925; Music Selection';
        v_dd_row2_label := '&#127918; In-Game Activities';
        v_dd_row3_label := '&#128250; Scoreboard Experience';

        SELECT
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND ENTERTAIN_GRID_MUSIC_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND ENTERTAIN_GRID_MUSIC_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND ENTERTAIN_GRID_GAMES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND ENTERTAIN_GRID_GAMES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND ENTERTAIN_GRID_SCOREBOARD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND ENTERTAIN_GRID_SCOREBOARD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC!='N/A' THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A')
        INTO :v_dd_row1_p, :v_dd_row1_o, :v_dd_row2_p, :v_dd_row2_o, :v_dd_row3_p, :v_dd_row3_o
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
        WHERE GAME_DATE::DATE = :v_target_game_date;

    ELSEIF (v_gap_area = 'Parking') THEN
        v_dd_title := 'PARKING DEEP DIVE';
        v_dd_icon := '&#128663;';
        v_dd_has_numrat := TRUE;
        v_dd_numrat_label := 'Avg Parking Rating';

        SELECT
            COALESCE(ROUND(AVG(CASE WHEN OVERALL_NUMRAT >= 9 THEN PARKING_NUMRAT END), 2)::VARCHAR, 'N/A'),
            COALESCE(ROUND(AVG(CASE WHEN OVERALL_NUMRAT < 9 THEN PARKING_NUMRAT END), 2)::VARCHAR, 'N/A')
        INTO :v_dd_promoter_numrat, :v_dd_opp_numrat
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
        WHERE GAME_DATE::DATE = :v_target_game_date AND PARKING_NUMRAT IS NOT NULL;

        v_dd_numrat_gap := CASE WHEN v_dd_promoter_numrat != 'N/A' AND v_dd_opp_numrat != 'N/A'
            THEN ROUND(100.0 * (v_dd_promoter_numrat::FLOAT - v_dd_opp_numrat::FLOAT) / NULLIF(v_dd_promoter_numrat::FLOAT, 0), 2)::VARCHAR ELSE 'N/A' END;

        -- Parking sub-metrics: arrival time, exit time expectations
        v_dd_row1_label := '&#9200; Arrival Wait Expectations';
        v_dd_row2_label := '&#128337; Exit Time Expectations';
        v_dd_row3_label := '';

        SELECT
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND PARKING_TIME_EXPECT_DESC IN ('Longer than expected') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND PARKING_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND PARKING_TIME_EXPECT_DESC IN ('Longer than expected') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND PARKING_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND PARKING_EXIT_EXPECT_DESC IN ('Longer than expected') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND PARKING_EXIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A'),
            COALESCE(ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND PARKING_EXIT_EXPECT_DESC IN ('Longer than expected') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND PARKING_EXIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2)::VARCHAR,'N/A')
        INTO :v_dd_row1_p, :v_dd_row1_o, :v_dd_row2_p, :v_dd_row2_o
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
        WHERE GAME_DATE::DATE = :v_target_game_date;

    ELSEIF (v_gap_area = 'Staff') THEN
        v_dd_title := 'STAFF SATISFACTION DEEP DIVE';
        v_dd_icon := '&#129489;';
        v_dd_has_numrat := TRUE;
        v_dd_numrat_label := 'Avg Staff Rating (composite)';

        -- Composite staff avg: average across all available TB_ADDON_23_* (2026) or normalized TB_ADDON_4_* (pre-2026)
        SELECT
            COALESCE(ROUND(AVG(CASE WHEN OVERALL_NUMRAT >= 9 THEN staff_norm END), 2)::VARCHAR, 'N/A'),
            COALESCE(ROUND(AVG(CASE WHEN OVERALL_NUMRAT < 9 THEN staff_norm END), 2)::VARCHAR, 'N/A')
        INTO :v_dd_promoter_numrat, :v_dd_opp_numrat
        FROM (
            SELECT OVERALL_NUMRAT,
                CASE WHEN SEASON >= 2026 THEN
                    (COALESCE(CASE WHEN TB_ADDON_23_1 < 80 THEN TB_ADDON_23_1 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_23_3 < 80 THEN TB_ADDON_23_3 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_23_5 < 80 THEN TB_ADDON_23_5 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_23_6 < 80 THEN TB_ADDON_23_6 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_23_24 < 80 THEN TB_ADDON_23_24 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_23_38 < 80 THEN TB_ADDON_23_38 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_23_60 < 80 THEN TB_ADDON_23_60 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_23_61 < 80 THEN TB_ADDON_23_61 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_23_67 < 80 THEN TB_ADDON_23_67 END, 0))
                    / NULLIF(
                        IFF(TB_ADDON_23_1 IS NOT NULL AND TB_ADDON_23_1 < 80, 1, 0)
                        + IFF(TB_ADDON_23_3 IS NOT NULL AND TB_ADDON_23_3 < 80, 1, 0)
                        + IFF(TB_ADDON_23_5 IS NOT NULL AND TB_ADDON_23_5 < 80, 1, 0)
                        + IFF(TB_ADDON_23_6 IS NOT NULL AND TB_ADDON_23_6 < 80, 1, 0)
                        + IFF(TB_ADDON_23_24 IS NOT NULL AND TB_ADDON_23_24 < 80, 1, 0)
                        + IFF(TB_ADDON_23_38 IS NOT NULL AND TB_ADDON_23_38 < 80, 1, 0)
                        + IFF(TB_ADDON_23_60 IS NOT NULL AND TB_ADDON_23_60 < 80, 1, 0)
                        + IFF(TB_ADDON_23_61 IS NOT NULL AND TB_ADDON_23_61 < 80, 1, 0)
                        + IFF(TB_ADDON_23_67 IS NOT NULL AND TB_ADDON_23_67 < 80, 1, 0), 0)
                ELSE
                    (COALESCE(CASE WHEN TB_ADDON_4_1 IS NOT NULL THEN (TB_ADDON_4_1 - 1) * 2.5 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_4_3 IS NOT NULL THEN (TB_ADDON_4_3 - 1) * 2.5 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_4_5 IS NOT NULL THEN (TB_ADDON_4_5 - 1) * 2.5 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_4_6 IS NOT NULL THEN (TB_ADDON_4_6 - 1) * 2.5 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_4_10 IS NOT NULL THEN (TB_ADDON_4_10 - 1) * 2.5 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_4_11 IS NOT NULL THEN (TB_ADDON_4_11 - 1) * 2.5 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_4_24 IS NOT NULL THEN (TB_ADDON_4_24 - 1) * 2.5 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_4_38 IS NOT NULL THEN (TB_ADDON_4_38 - 1) * 2.5 END, 0)
                     + COALESCE(CASE WHEN TB_ADDON_4_39 IS NOT NULL THEN (TB_ADDON_4_39 - 1) * 2.5 END, 0))
                    / NULLIF(
                        IFF(TB_ADDON_4_1 IS NOT NULL, 1, 0) + IFF(TB_ADDON_4_3 IS NOT NULL, 1, 0)
                        + IFF(TB_ADDON_4_5 IS NOT NULL, 1, 0) + IFF(TB_ADDON_4_6 IS NOT NULL, 1, 0)
                        + IFF(TB_ADDON_4_10 IS NOT NULL, 1, 0) + IFF(TB_ADDON_4_11 IS NOT NULL, 1, 0)
                        + IFF(TB_ADDON_4_24 IS NOT NULL, 1, 0) + IFF(TB_ADDON_4_38 IS NOT NULL, 1, 0)
                        + IFF(TB_ADDON_4_39 IS NOT NULL, 1, 0), 0)
                END AS staff_norm
            FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
            WHERE GAME_DATE::DATE = :v_target_game_date
              AND ((SEASON >= 2026 AND (TB_ADDON_23_1 IS NOT NULL OR TB_ADDON_23_3 IS NOT NULL OR TB_ADDON_23_5 IS NOT NULL OR TB_ADDON_23_6 IS NOT NULL OR TB_ADDON_23_24 IS NOT NULL OR TB_ADDON_23_38 IS NOT NULL OR TB_ADDON_23_60 IS NOT NULL OR TB_ADDON_23_61 IS NOT NULL OR TB_ADDON_23_67 IS NOT NULL))
                OR (SEASON < 2026 AND (TB_ADDON_4_1 IS NOT NULL OR TB_ADDON_4_3 IS NOT NULL OR TB_ADDON_4_5 IS NOT NULL OR TB_ADDON_4_6 IS NOT NULL OR TB_ADDON_4_10 IS NOT NULL OR TB_ADDON_4_11 IS NOT NULL OR TB_ADDON_4_24 IS NOT NULL OR TB_ADDON_4_38 IS NOT NULL OR TB_ADDON_4_39 IS NOT NULL)))
        );

        v_dd_numrat_gap := CASE WHEN v_dd_promoter_numrat != 'N/A' AND v_dd_opp_numrat != 'N/A'
            THEN ROUND(100.0 * (v_dd_promoter_numrat::FLOAT - v_dd_opp_numrat::FLOAT) / NULLIF(v_dd_promoter_numrat::FLOAT, 0), 2)::VARCHAR ELSE 'N/A' END;

        -- Dynamic top 3 staff categories by largest avg score gap (Promoter vs Opportunity)
        -- Uses TB_ADDON_23_* (0-10 scale, 2026 only since that's where data exists)
        LET c_staff_gaps CURSOR FOR
            SELECT cat_label, p_avg, o_avg, ABS(p_avg - o_avg) AS gap_val
            FROM (
                SELECT 'Parking Staff' AS cat_label,
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT>=9 AND TB_ADDON_23_1 < 80 THEN TB_ADDON_23_1 END),2) AS p_avg,
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT<9 AND TB_ADDON_23_1 < 80 THEN TB_ADDON_23_1 END),2) AS o_avg
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
                WHERE GAME_DATE::DATE = :v_target_game_date AND SEASON >= 2026 AND TB_ADDON_23_1 IS NOT NULL AND TB_ADDON_23_1 < 80
                UNION ALL
                SELECT 'Fan Host/Usher',
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT>=9 AND TB_ADDON_23_3 < 80 THEN TB_ADDON_23_3 END),2),
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT<9 AND TB_ADDON_23_3 < 80 THEN TB_ADDON_23_3 END),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
                WHERE GAME_DATE::DATE = :v_target_game_date AND SEASON >= 2026 AND TB_ADDON_23_3 IS NOT NULL AND TB_ADDON_23_3 < 80
                UNION ALL
                SELECT 'Concessions Staff',
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT>=9 AND TB_ADDON_23_5 < 80 THEN TB_ADDON_23_5 END),2),
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT<9 AND TB_ADDON_23_5 < 80 THEN TB_ADDON_23_5 END),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
                WHERE GAME_DATE::DATE = :v_target_game_date AND SEASON >= 2026 AND TB_ADDON_23_5 IS NOT NULL AND TB_ADDON_23_5 < 80
                UNION ALL
                SELECT 'Retail/Team Store',
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT>=9 AND TB_ADDON_23_6 < 80 THEN TB_ADDON_23_6 END),2),
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT<9 AND TB_ADDON_23_6 < 80 THEN TB_ADDON_23_6 END),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
                WHERE GAME_DATE::DATE = :v_target_game_date AND SEASON >= 2026 AND TB_ADDON_23_6 IS NOT NULL AND TB_ADDON_23_6 < 80
                UNION ALL
                SELECT 'Wheelchair Team',
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT>=9 AND TB_ADDON_23_24 < 80 THEN TB_ADDON_23_24 END),2),
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT<9 AND TB_ADDON_23_24 < 80 THEN TB_ADDON_23_24 END),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
                WHERE GAME_DATE::DATE = :v_target_game_date AND SEASON >= 2026 AND TB_ADDON_23_24 IS NOT NULL AND TB_ADDON_23_24 < 80
                UNION ALL
                SELECT 'Tech Team',
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT>=9 AND TB_ADDON_23_38 < 80 THEN TB_ADDON_23_38 END),2),
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT<9 AND TB_ADDON_23_38 < 80 THEN TB_ADDON_23_38 END),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
                WHERE GAME_DATE::DATE = :v_target_game_date AND SEASON >= 2026 AND TB_ADDON_23_38 IS NOT NULL AND TB_ADDON_23_38 < 80
                UNION ALL
                SELECT 'Security',
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT>=9 AND TB_ADDON_23_60 < 80 THEN TB_ADDON_23_60 END),2),
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT<9 AND TB_ADDON_23_60 < 80 THEN TB_ADDON_23_60 END),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
                WHERE GAME_DATE::DATE = :v_target_game_date AND SEASON >= 2026 AND TB_ADDON_23_60 IS NOT NULL AND TB_ADDON_23_60 < 80
                UNION ALL
                SELECT 'Ticket Scanner',
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT>=9 AND TB_ADDON_23_61 < 80 THEN TB_ADDON_23_61 END),2),
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT<9 AND TB_ADDON_23_61 < 80 THEN TB_ADDON_23_61 END),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
                WHERE GAME_DATE::DATE = :v_target_game_date AND SEASON >= 2026 AND TB_ADDON_23_61 IS NOT NULL AND TB_ADDON_23_61 < 80
                UNION ALL
                SELECT 'Go-Ahead Entry',
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT>=9 AND TB_ADDON_23_67 < 80 THEN TB_ADDON_23_67 END),2),
                    ROUND(AVG(CASE WHEN OVERALL_NUMRAT<9 AND TB_ADDON_23_67 < 80 THEN TB_ADDON_23_67 END),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
                WHERE GAME_DATE::DATE = :v_target_game_date AND SEASON >= 2026 AND TB_ADDON_23_67 IS NOT NULL AND TB_ADDON_23_67 < 80
            )
            WHERE p_avg IS NOT NULL AND o_avg IS NOT NULL
            ORDER BY gap_val DESC
            LIMIT 3;

        v_staff_rank := 0;
        FOR rec IN c_staff_gaps DO
            v_staff_rank := v_staff_rank + 1;
            IF (v_staff_rank = 1) THEN
                v_dd_row1_label := '&#129489; ' || rec.cat_label;
                v_dd_row1_p := rec.p_avg::VARCHAR;
                v_dd_row1_o := rec.o_avg::VARCHAR;
            ELSEIF (v_staff_rank = 2) THEN
                v_dd_row2_label := '&#129489; ' || rec.cat_label;
                v_dd_row2_p := rec.p_avg::VARCHAR;
                v_dd_row2_o := rec.o_avg::VARCHAR;
            ELSEIF (v_staff_rank = 3) THEN
                v_dd_row3_label := '&#129489; ' || rec.cat_label;
                v_dd_row3_p := rec.p_avg::VARCHAR;
                v_dd_row3_o := rec.o_avg::VARCHAR;
            END IF;
        END FOR;

    ELSEIF (v_gap_area = 'Food Quality') THEN
        v_dd_title := 'FOOD QUALITY DEEP DIVE';
        v_dd_icon := '&#127869;';
        v_dd_has_numrat := FALSE;

        -- Dynamic top 3 food quality items by largest % dissatisfied gap (Promoter vs Opportunity)
        LET c_fq_gaps CURSOR FOR
            SELECT cat_label, p_dissat, o_dissat, ABS(o_dissat - p_dissat) AS gap_val
            FROM (
                SELECT 'Alcoholic Beverages' AS cat_label,
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_ALCOHOL_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_ALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_ALCOHOL_DESC!='N/A' THEN 1 ELSE 0 END),0),2) AS p_dissat,
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_ALCOHOL_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_ALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_ALCOHOL_DESC!='N/A' THEN 1 ELSE 0 END),0),2) AS o_dissat
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Non-Alcoholic Beverages',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_NONALCOHOL_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_NONALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_NONALCOHOL_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_NONALCOHOL_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_NONALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_NONALCOHOL_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Hot Dogs',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_HOTDOG_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_HOTDOG_DESC IS NOT NULL AND CONCESS_QUALITY_HOTDOG_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_HOTDOG_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_HOTDOG_DESC IS NOT NULL AND CONCESS_QUALITY_HOTDOG_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Chicken Tenders',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_CHICKEN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_CHICKEN_DESC IS NOT NULL AND CONCESS_QUALITY_CHICKEN_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_CHICKEN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_CHICKEN_DESC IS NOT NULL AND CONCESS_QUALITY_CHICKEN_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Fries',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_FRIES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_FRIES_DESC IS NOT NULL AND CONCESS_QUALITY_FRIES_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_FRIES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_FRIES_DESC IS NOT NULL AND CONCESS_QUALITY_FRIES_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Nachos',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_NACHOS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_NACHOS_DESC IS NOT NULL AND CONCESS_QUALITY_NACHOS_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_NACHOS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_NACHOS_DESC IS NOT NULL AND CONCESS_QUALITY_NACHOS_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Pizza',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_PIZZA_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_PIZZA_DESC IS NOT NULL AND CONCESS_QUALITY_PIZZA_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_PIZZA_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_PIZZA_DESC IS NOT NULL AND CONCESS_QUALITY_PIZZA_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Popcorn',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_POPCORN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_POPCORN_DESC IS NOT NULL AND CONCESS_QUALITY_POPCORN_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_POPCORN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_POPCORN_DESC IS NOT NULL AND CONCESS_QUALITY_POPCORN_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Pretzels',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_PRETZELS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_PRETZELS_DESC IS NOT NULL AND CONCESS_QUALITY_PRETZELS_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_PRETZELS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_PRETZELS_DESC IS NOT NULL AND CONCESS_QUALITY_PRETZELS_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Sausage',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_SAUSAGE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_SAUSAGE_DESC IS NOT NULL AND CONCESS_QUALITY_SAUSAGE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_SAUSAGE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_SAUSAGE_DESC IS NOT NULL AND CONCESS_QUALITY_SAUSAGE_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Peanuts/Nuts',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_NUTS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_NUTS_DESC IS NOT NULL AND CONCESS_QUALITY_NUTS_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_NUTS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_NUTS_DESC IS NOT NULL AND CONCESS_QUALITY_NUTS_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Ice Cream',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_ICECREAM_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_ICECREAM_DESC IS NOT NULL AND CONCESS_QUALITY_ICECREAM_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_ICECREAM_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_ICECREAM_DESC IS NOT NULL AND CONCESS_QUALITY_ICECREAM_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Sandwiches',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_SANDWICH_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_SANDWICH_DESC IS NOT NULL AND CONCESS_QUALITY_SANDWICH_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_SANDWICH_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_SANDWICH_DESC IS NOT NULL AND CONCESS_QUALITY_SANDWICH_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Burgers',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_BURGERS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_BURGERS_DESC IS NOT NULL AND CONCESS_QUALITY_BURGERS_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_BURGERS_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_BURGERS_DESC IS NOT NULL AND CONCESS_QUALITY_BURGERS_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Salad',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_SALAD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_SALAD_DESC IS NOT NULL AND CONCESS_QUALITY_SALAD_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_SALAD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_SALAD_DESC IS NOT NULL AND CONCESS_QUALITY_SALAD_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Other Entrees',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_OTHER_ENTREE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_OTHER_ENTREE_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_ENTREE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_OTHER_ENTREE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_OTHER_ENTREE_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_ENTREE_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
                UNION ALL
                SELECT 'Other Desserts',
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_OTHER_DESSERT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT>=9 AND CONCESS_QUALITY_OTHER_DESSERT_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_DESSERT_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                    ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_OTHER_DESSERT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT<9 AND CONCESS_QUALITY_OTHER_DESSERT_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_DESSERT_DESC!='N/A' THEN 1 ELSE 0 END),0),2)
                FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI WHERE GAME_DATE::DATE = :v_target_game_date
            )
            WHERE p_dissat IS NOT NULL AND o_dissat IS NOT NULL
            ORDER BY gap_val DESC
            LIMIT 3;

        v_fq_rank := 0;
        FOR rec IN c_fq_gaps DO
            v_fq_rank := v_fq_rank + 1;
            IF (v_fq_rank = 1) THEN
                v_dd_row1_label := '&#127869; ' || rec.cat_label;
                v_dd_row1_p := rec.p_dissat::VARCHAR;
                v_dd_row1_o := rec.o_dissat::VARCHAR;
            ELSEIF (v_fq_rank = 2) THEN
                v_dd_row2_label := '&#127869; ' || rec.cat_label;
                v_dd_row2_p := rec.p_dissat::VARCHAR;
                v_dd_row2_o := rec.o_dissat::VARCHAR;
            ELSEIF (v_fq_rank = 3) THEN
                v_dd_row3_label := '&#127869; ' || rec.cat_label;
                v_dd_row3_p := rec.p_dissat::VARCHAR;
                v_dd_row3_o := rec.o_dissat::VARCHAR;
            END IF;
        END FOR;

    ELSE
        -- Fallback: use the gap metric info directly
        v_dd_title := UPPER(v_gap_area) || ' DEEP DIVE';
        v_dd_icon := '&#128270;';
        v_dd_has_numrat := FALSE;
        v_dd_row1_label := v_gap_metric;
        v_dd_row1_p := v_gap_promoter_val::VARCHAR;
        v_dd_row1_o := v_gap_opp_val::VARCHAR;
    END IF;

    -- Compute gap strings for deep dive rows
    v_dd_row1_gap := CASE WHEN v_dd_row1_p != 'N/A' AND v_dd_row1_o != 'N/A'
        THEN ROUND(ABS(v_dd_row1_o::FLOAT - v_dd_row1_p::FLOAT), 2)::VARCHAR ELSE 'N/A' END;
    v_dd_row2_gap := CASE WHEN v_dd_row2_p != 'N/A' AND v_dd_row2_o != 'N/A'
        THEN ROUND(ABS(v_dd_row2_o::FLOAT - v_dd_row2_p::FLOAT), 2)::VARCHAR ELSE 'N/A' END;
    v_dd_row3_gap := CASE WHEN v_dd_row3_p != 'N/A' AND v_dd_row3_o != 'N/A'
        THEN ROUND(ABS(v_dd_row3_o::FLOAT - v_dd_row3_p::FLOAT), 2)::VARCHAR ELSE 'N/A' END;

    -- =============================================
    -- BUILD AI CONTEXT FOR STAFF + FOOD QUALITY
    -- =============================================
    IF (v_dd_promoter_numrat != 'N/A' AND v_gap_area = 'Staff') THEN
        v_staff_context := '
STAFF DATA: Composite avg rating — Promoters ' || v_dd_promoter_numrat || '/10 vs Opportunity ' || v_dd_opp_numrat || '/10 (gap: ' || v_dd_numrat_gap || '%)
Top staff gap: ' || v_dd_row1_label || ' — Promoters ' || v_dd_row1_p || ' vs Opp ' || v_dd_row1_o;
    ELSEIF (v_gap_area != 'Staff') THEN
        -- Even if Staff didn't win the gap finder, provide context if data exists
        SELECT
            COALESCE(ROUND(AVG(CASE WHEN OVERALL_NUMRAT >= 9 AND TB_ADDON_23_1 < 80 THEN TB_ADDON_23_1 END), 2)::VARCHAR, 'N/A'),
            COALESCE(ROUND(AVG(CASE WHEN OVERALL_NUMRAT < 9 AND TB_ADDON_23_1 < 80 THEN TB_ADDON_23_1 END), 2)::VARCHAR, 'N/A')
        INTO :v_dd_promoter_numrat, :v_dd_opp_numrat
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
        WHERE GAME_DATE::DATE = :v_target_game_date AND SEASON >= 2026 AND TB_ADDON_23_1 IS NOT NULL;
        IF (v_dd_promoter_numrat != 'N/A') THEN
            v_staff_context := '
STAFF DATA (background): Sample staff rating (Parking Staff) — Promoters ' || v_dd_promoter_numrat || '/10 vs Opportunity ' || v_dd_opp_numrat || '/10';
        END IF;
    END IF;

    IF (v_gap_area = 'Food Quality') THEN
        v_food_quality_context := '
FOOD QUALITY DATA: Top food quality gaps —
- ' || v_dd_row1_label || ': Promoters ' || v_dd_row1_p || '% vs Opp ' || v_dd_row1_o || '% dissatisfied
- ' || v_dd_row2_label || ': Promoters ' || v_dd_row2_p || '% vs Opp ' || v_dd_row2_o || '% dissatisfied';
    END IF;

    -- =============================================
    -- AI: KEY INSIGHT (claude-sonnet-4-6)
    -- =============================================
    LET v_insight_prompt VARCHAR;
    v_insight_prompt := 'You are a sports business analyst for the Tampa Bay Rays. In exactly ONE sentence, provide the single most important finding from this game data. Be specific with numbers and percentages. Do not use markdown formatting.

Game: ' || v_header_line || ' | Score: ' || v_game_avg::VARCHAR || '/10 vs ' || v_season_avg::VARCHAR || '/10 benchmark
Gap to goal: ' || ABS(v_gap_pct)::VARCHAR || '% ' || CASE WHEN v_gap_pct >= 0 THEN 'above' ELSE 'below' END || ' benchmark
Biggest gap area: ' || v_gap_area || ' (' || v_gap_metric || ') — ' || v_gap_value::VARCHAR || '% gap between Promoters and Opportunity
Promoter top topic: ' || v_promoter_topic_1 || ' (' || v_promoter_topic_1_pct || '%)
Opportunity top topic: ' || v_opp_topic_1 || ' (' || v_opp_topic_1_pct || '%)
Deep dive: ' || v_dd_row1_label || ' — Promoters ' || v_dd_row1_p || '% vs Opportunity ' || v_dd_row1_o || '%'
    || v_staff_context || v_food_quality_context;

    SELECT AI_COMPLETE('claude-sonnet-4-6', :v_insight_prompt, {'temperature': 0.2, 'max_tokens': 200})
    INTO :v_key_insight;

    -- =============================================
    -- AI: ACTION ITEMS (claude-sonnet-4-6)
    -- =============================================
    LET v_ai_prompt VARCHAR;
    v_ai_prompt := 'You are a senior sports business analyst for the Tampa Bay Rays. Based on this game day survey data, generate 1-3 immediate, specific, data-backed action items. Each should be 1-2 sentences with a concrete action, specific data point, and a creative suggestion. Do not use markdown formatting — return plain text with numbered items.

GAME: ' || v_header_line || '
Responses: ' || v_response_count::VARCHAR || ' | Score: ' || v_game_avg::VARCHAR || '/10 vs ' || v_season_avg::VARCHAR || '/10 benchmark (' || ABS(v_gap_pct)::VARCHAR || '% ' || CASE WHEN v_gap_pct >= 0 THEN 'above' ELSE 'below' END || ')

PROMOTER TOPICS (9-10 score):
1. ' || v_promoter_topic_1 || ' (' || v_promoter_topic_1_pct || '%)
2. ' || v_promoter_topic_2 || ' (' || v_promoter_topic_2_pct || '%)
3. ' || v_promoter_topic_3 || ' (' || v_promoter_topic_3_pct || '%)

OPPORTUNITY TOPICS (0-8 score):
1. ' || v_opp_topic_1 || ' (' || v_opp_topic_1_pct || '%)
2. ' || v_opp_topic_2 || ' (' || v_opp_topic_2_pct || '%)
3. ' || v_opp_topic_3 || ' (' || v_opp_topic_3_pct || '%)

BIGGEST GAP: ' || v_gap_area || ' — ' || v_gap_metric || ' (' || v_gap_value::VARCHAR || '% gap)
' || v_dd_title || ':
- ' || v_dd_row1_label || ': Promoters ' || v_dd_row1_p || '% vs Opportunity ' || v_dd_row1_o || '% (gap: ' || v_dd_row1_gap || '%)
- ' || v_dd_row2_label || ': Promoters ' || v_dd_row2_p || '% vs Opportunity ' || v_dd_row2_o || '% (gap: ' || v_dd_row2_gap || '%)
- ' || v_dd_row3_label || ': Promoters ' || v_dd_row3_p || '% vs Opportunity ' || v_dd_row3_o || '% (gap: ' || v_dd_row3_gap || '%)

FORMAT: Return 1-3 numbered items. Each starts with a bold topic (use HTML <strong> tags). Be specific with numbers. Example:
1. <strong>Concession Value</strong> — Introduce visible combo deals to address the X% dissatisfaction gap.
2. <strong>Seating Comfort</strong> — Deploy seat cushion rentals at high-traffic sections, addressing Y% of Opportunity feedback.'
    || v_staff_context || v_food_quality_context;

    SELECT AI_COMPLETE('claude-sonnet-4-6', :v_ai_prompt, {'temperature': 0.3, 'max_tokens': 600})
    INTO :v_action_items;

    -- =============================================
    -- ASSEMBLE HTML EMAIL
    -- =============================================
    v_email_subject := '&#9918; Rays Game Day Report Card — ' || v_header_line || ' | ' || v_game_avg::VARCHAR || '/10';

    v_html_body := '<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="margin:0;padding:0;background-color:#f4f4f4;font-family:Arial,Helvetica,sans-serif;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f4f4;">
<tr><td align="center" style="padding:20px 10px;">
<table role="presentation" width="640" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">

<!-- ========== HEADER ========== -->
<tr><td style="background:linear-gradient(135deg, #092C5C 0%, #1a4a8a 100%);padding:32px 40px;text-align:center;">
  <div style="font-size:14px;letter-spacing:3px;color:#8FBCE6;font-weight:600;margin-bottom:8px;">TAMPA BAY RAYS</div>
  <div style="font-size:28px;font-weight:700;color:#ffffff;margin-bottom:4px;">&#9918; GAME DAY REPORT CARD</div>
  <div style="font-size:15px;color:#8FBCE6;margin-top:12px;">' || v_header_line || ' &nbsp;|&nbsp; ' || v_response_count::VARCHAR || ' Survey Responses</div>
</td></tr>

<!-- ========== SECTION 1: QUANTITATIVE SUMMARY (BAR CHART) ========== -->
<tr><td style="padding:32px 40px 0 40px;">
  <div style="font-size:13px;letter-spacing:2px;color:#092C5C;font-weight:700;margin-bottom:20px;">&#128202; SECTION 1: QUANTITATIVE SUMMARY</div>

  <!-- Bar 1: Season Benchmark -->
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:14px;">
    <tr><td style="padding:0 0 4px 0;font-size:12px;color:#666;font-weight:600;letter-spacing:0.5px;">' || v_season::VARCHAR || ' SEASON BENCHMARK &nbsp;<span style="color:#999;font-weight:400;">(' || v_season_responses::VARCHAR || ' responses)</span></td></tr>
    <tr><td style="padding:0;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
        <td width="' || v_benchmark_bar_width || '" style="background-color:#8FBCE6;height:36px;border-radius:6px 0 0 6px;padding-left:14px;vertical-align:middle;">
          <span style="color:#092C5C;font-size:16px;font-weight:800;">' || v_season_avg::VARCHAR || '</span><span style="color:#092C5C;font-size:12px;font-weight:400;"> / 10</span>
        </td>
        <td width="' || v_benchmark_bar_remainder || '" style="height:36px;background-color:#e8edf2;border-radius:0 6px 6px 0;"></td>
      </tr></table>
    </td></tr>
  </table>

  <!-- Bar 2: Game Score -->
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:14px;">
    <tr><td style="padding:0 0 4px 0;font-size:12px;color:#666;font-weight:600;letter-spacing:0.5px;">' || v_header_line || ' &nbsp;<span style="color:#999;font-weight:400;">(' || v_response_count::VARCHAR || ' responses)</span></td></tr>
    <tr><td style="padding:0;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
        <td width="' || v_game_bar_width || '" style="background-color:#092C5C;height:36px;border-radius:6px 0 0 6px;padding-left:14px;vertical-align:middle;">
          <span style="color:#ffffff;font-size:16px;font-weight:800;">' || v_game_avg::VARCHAR || '</span><span style="color:#8FBCE6;font-size:12px;font-weight:400;"> / 10</span>
        </td>
        <td width="' || v_game_bar_remainder || '" style="height:36px;background-color:#e8edf2;border-radius:0 6px 6px 0;"></td>
      </tr></table>
    </td></tr>
  </table>

  <!-- Gap to Goal -->
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
    <td style="padding:12px 16px;background-color:' || CASE WHEN v_gap_pct >= 0 THEN '#f0fff4;border:1px solid #c6f6d5' ELSE '#fff5f5;border:1px solid #fce4e4' END || ';border-radius:6px;text-align:center;">
      <span style="font-size:12px;color:#666;font-weight:600;letter-spacing:0.5px;">GAP TO GOAL</span><br>
      <span style="font-size:22px;font-weight:800;color:' || CASE WHEN v_gap_pct >= 0 THEN '#1a7431' ELSE '#c0392b' END || ';">' || v_gap_icon || ' ' || ABS(v_gap_pct)::VARCHAR || '%</span>
      <span style="font-size:13px;color:#888;"> ' || CASE WHEN v_gap_pct >= 0 THEN 'above' ELSE 'below' END || ' season benchmark</span>
    </td>
  </tr></table>
</td></tr>

<!-- DIVIDER -->
<tr><td style="padding:24px 40px;"><hr style="border:none;border-top:2px solid #e8eaed;margin:0;"></td></tr>

<!-- ========== SECTION 2: QUALITATIVE SUMMARY ========== -->
<tr><td style="padding:0 40px;">
  <div style="font-size:13px;letter-spacing:2px;color:#092C5C;font-weight:700;margin-bottom:16px;">&#128172; SECTION 2: QUALITATIVE SUMMARY</div>
  <div style="font-size:13px;color:#666;margin-bottom:12px;">Top 3 Topics by Group (% of fans who left open-text feedback mentioning this topic)</div>

  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;">
    <tr style="background-color:#092C5C;">
      <td style="padding:10px 12px;color:#ffffff;font-weight:600;font-size:12px;width:30px;border-radius:6px 0 0 0;">#</td>
      <td style="padding:10px 12px;color:#8FBCE6;font-weight:600;font-size:12px;">Promoters (9&ndash;10) &middot; ' || v_promoter_count::VARCHAR || ' responses</td>
      <td style="padding:10px 12px;color:#8FBCE6;font-weight:600;font-size:12px;border-radius:0 6px 0 0;">Opportunity (0&ndash;8) &middot; ' || v_opportunity_count::VARCHAR || ' responses</td>
    </tr>
    <tr style="background-color:#f0f7ff;">
      <td style="padding:10px 12px;font-weight:700;color:#092C5C;border-bottom:1px solid #e8eaed;">1</td>
      <td style="padding:10px 12px;font-size:13px;border-bottom:1px solid #e8eaed;"><strong>' || v_promoter_topic_1 || '</strong>&nbsp; <span style="color:#1a7431;font-weight:600;">' || v_promoter_topic_1_pct || '%</span></td>
      <td style="padding:10px 12px;font-size:13px;border-bottom:1px solid #e8eaed;"><strong>' || v_opp_topic_1 || '</strong>&nbsp; <span style="color:#c0392b;font-weight:600;">' || v_opp_topic_1_pct || '%</span></td>
    </tr>
    <tr>
      <td style="padding:10px 12px;font-weight:700;color:#092C5C;border-bottom:1px solid #e8eaed;">2</td>
      <td style="padding:10px 12px;font-size:13px;border-bottom:1px solid #e8eaed;"><strong>' || v_promoter_topic_2 || '</strong>&nbsp; <span style="color:#1a7431;font-weight:600;">' || v_promoter_topic_2_pct || '%</span></td>
      <td style="padding:10px 12px;font-size:13px;border-bottom:1px solid #e8eaed;"><strong>' || v_opp_topic_2 || '</strong>&nbsp; <span style="color:#c0392b;font-weight:600;">' || v_opp_topic_2_pct || '%</span></td>
    </tr>
    <tr style="background-color:#f0f7ff;">
      <td style="padding:10px 12px;font-weight:700;color:#092C5C;">3</td>
      <td style="padding:10px 12px;font-size:13px;"><strong>' || v_promoter_topic_3 || '</strong>&nbsp; <span style="color:#1a7431;font-weight:600;">' || v_promoter_topic_3_pct || '%</span></td>
      <td style="padding:10px 12px;font-size:13px;"><strong>' || v_opp_topic_3 || '</strong>&nbsp; <span style="color:#c0392b;font-weight:600;">' || v_opp_topic_3_pct || '%</span></td>
    </tr>
  </table>

  <!-- KEY INSIGHT -->
  <div style="margin-top:20px;padding:16px 20px;background-color:#fff8e1;border-left:4px solid #f9a825;border-radius:4px;">
    <div style="font-size:12px;font-weight:700;color:#f57f17;letter-spacing:1px;margin-bottom:6px;">&#128273; KEY INSIGHT</div>
    <div style="font-size:14px;color:#333;line-height:1.5;">' || REPLACE(REPLACE(v_key_insight, '<', '&lt;'), '>', '&gt;') || '</div>
  </div>
</td></tr>

<!-- DIVIDER -->
<tr><td style="padding:24px 40px;"><hr style="border:none;border-top:2px solid #e8eaed;margin:0;"></td></tr>

<!-- ========== DYNAMIC DEEP DIVE ========== -->
<tr><td style="padding:0 40px;">
  <div style="font-size:13px;letter-spacing:2px;color:#092C5C;font-weight:700;margin-bottom:16px;">' || v_dd_icon || ' ' || v_dd_title || '</div>';

    -- Add NUMRAT rating row if applicable
    IF (v_dd_has_numrat) THEN
        v_html_body := v_html_body || '
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin-bottom:16px;">
    <tr style="background-color:#092C5C;">
      <td style="padding:8px 12px;color:#ffffff;font-size:12px;font-weight:600;border-radius:6px 0 0 0;">Overall Rating (1&ndash;10)</td>
      <td style="padding:8px 12px;color:#8FBCE6;font-size:12px;font-weight:600;text-align:center;">Promoters</td>
      <td style="padding:8px 12px;color:#8FBCE6;font-size:12px;font-weight:600;text-align:center;">Opportunity</td>
      <td style="padding:8px 12px;color:#8FBCE6;font-size:12px;font-weight:600;text-align:center;border-radius:0 6px 0 0;">Gap</td>
    </tr>
    <tr style="background-color:#f8f9fb;">
      <td style="padding:10px 12px;font-size:13px;color:#333;">' || v_dd_numrat_label || '</td>
      <td style="padding:10px 12px;font-size:14px;font-weight:700;color:#1a7431;text-align:center;">' || v_dd_promoter_numrat || '</td>
      <td style="padding:10px 12px;font-size:14px;font-weight:700;color:#c0392b;text-align:center;">' || v_dd_opp_numrat || '</td>
      <td style="padding:10px 12px;font-size:14px;font-weight:700;color:#c0392b;text-align:center;">&#9660; ' || v_dd_numrat_gap || '%</td>
    </tr>
  </table>';
    END IF;

    -- Deep dive dissatisfaction grid
    v_html_body := v_html_body || '
  <div style="font-size:12px;color:#666;margin-bottom:8px;">% Dissatisfied (&ldquo;Somewhat&rdquo; + &ldquo;Highly&rdquo; Dissatisfied)</div>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;">
    <tr style="background-color:#092C5C;">
      <td style="padding:8px 12px;color:#ffffff;font-size:12px;font-weight:600;border-radius:6px 0 0 0;">Category</td>
      <td style="padding:8px 12px;color:#8FBCE6;font-size:12px;font-weight:600;text-align:center;">Promoters</td>
      <td style="padding:8px 12px;color:#8FBCE6;font-size:12px;font-weight:600;text-align:center;">Opportunity</td>
      <td style="padding:8px 12px;color:#8FBCE6;font-size:12px;font-weight:600;text-align:center;border-radius:0 6px 0 0;">Gap</td>
    </tr>
    <tr style="background-color:#fff5f5;">
      <td style="padding:10px 12px;font-size:13px;border-bottom:1px solid #e8eaed;">' || v_dd_row1_label || '</td>
      <td style="padding:10px 12px;font-size:13px;text-align:center;border-bottom:1px solid #e8eaed;">' || v_dd_row1_p || '%</td>
      <td style="padding:10px 12px;font-size:13px;text-align:center;font-weight:600;color:#c0392b;border-bottom:1px solid #e8eaed;">' || v_dd_row1_o || '%</td>
      <td style="padding:10px 12px;font-size:13px;text-align:center;color:#c0392b;font-weight:600;border-bottom:1px solid #e8eaed;">+' || v_dd_row1_gap || '%</td>
    </tr>
    <tr>
      <td style="padding:10px 12px;font-size:13px;border-bottom:1px solid #e8eaed;">' || v_dd_row2_label || '</td>
      <td style="padding:10px 12px;font-size:13px;text-align:center;border-bottom:1px solid #e8eaed;">' || v_dd_row2_p || '%</td>
      <td style="padding:10px 12px;font-size:13px;text-align:center;font-weight:600;color:#c0392b;border-bottom:1px solid #e8eaed;">' || v_dd_row2_o || '%</td>
      <td style="padding:10px 12px;font-size:13px;text-align:center;color:#c0392b;font-weight:600;border-bottom:1px solid #e8eaed;">+' || v_dd_row2_gap || '%</td>
    </tr>';

    -- Only add row 3 if the label is set
    IF (v_dd_row3_label != '') THEN
        v_html_body := v_html_body || '
    <tr style="background-color:#fff5f5;">
      <td style="padding:10px 12px;font-size:13px;">' || v_dd_row3_label || '</td>
      <td style="padding:10px 12px;font-size:13px;text-align:center;">' || v_dd_row3_p || '%</td>
      <td style="padding:10px 12px;font-size:13px;text-align:center;font-weight:600;color:#c0392b;">' || v_dd_row3_o || '%</td>
      <td style="padding:10px 12px;font-size:13px;text-align:center;color:#c0392b;font-weight:600;">+' || v_dd_row3_gap || '%</td>
    </tr>';
    END IF;

    v_html_body := v_html_body || '
  </table>
</td></tr>

<!-- DIVIDER -->
<tr><td style="padding:24px 40px;"><hr style="border:none;border-top:2px solid #e8eaed;margin:0;"></td></tr>

<!-- ========== SECTION 3: ACTION ITEMS ========== -->
<tr><td style="padding:0 40px 32px 40px;">
  <div style="font-size:13px;letter-spacing:2px;color:#092C5C;font-weight:700;margin-bottom:16px;">&#9989; SECTION 3: IMMEDIATE ACTION ITEMS</div>
  <div style="padding:16px 20px;background-color:#f0f7ff;border-radius:8px;border:1px solid #d0e3f7;">
    <div style="font-size:14px;color:#333;line-height:1.8;">' || v_action_items || '</div>
  </div>
</td></tr>

<!-- ========== FOOTER ========== -->
<tr><td style="background-color:#092C5C;padding:20px 40px;text-align:center;">
  <div style="font-size:11px;color:#8FBCE6;line-height:1.6;">
    Data sourced from post-game VOC survey &nbsp;|&nbsp; ' || v_response_count::VARCHAR || ' responses &nbsp;|&nbsp; ' || v_header_line || '<br>
    Powered by Snowflake Cortex AI (claude-sonnet-4-6) &nbsp;|&nbsp; Tampa Bay Rays Strategy &amp; Analytics
  </div>
</td></tr>

</table>
</td></tr>
</table>
</body>
</html>';

    -- =============================================
    -- SEND EMAIL
    -- =============================================
    CALL SYSTEM$SEND_EMAIL(
        'VOC_REPORT_CARD_EMAIL',
        'ytaketani@raysbaseball.com',
        :v_email_subject,
        :v_html_body,
        'text/html'
    );

    RETURN 'Report Card sent for ' || v_header_line || ' | Score: ' || v_game_avg::VARCHAR || '/10 | Deep Dive: ' || v_dd_title || ' (gap: ' || v_gap_value::VARCHAR || '%)';
END;

-- =====================================================
-- STEP 3: CREATE AUTOMATED TASK (7 AM ET daily)
-- =====================================================

USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE TASK TBRDP_DW_DEV.IM_RPT.TASK_VOC_DAILY_REPORT_CARD
    WAREHOUSE = TBRDP_DW_CORTEX_XS_WH
    SCHEDULE = 'USING CRON 0 7 * * * America/New_York'
    COMMENT = 'Sends daily VOC Game Day Report Card at 7 AM ET if a game was played yesterday'
AS
BEGIN
    -- Game-day guard: only run if there was a game yesterday with survey data
    LET v_game_exists NUMBER;
    SELECT COUNT(*)
    INTO :v_game_exists
    FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
    WHERE GAME_DATE::DATE = CURRENT_DATE() - 1
      AND OVERALL_NUMRAT IS NOT NULL;

    IF (v_game_exists > 0) THEN
        CALL TBRDP_DW_DEV.IM_RPT.SP_VOC_DAILY_REPORT_CARD();
    END IF;
END;

-- Resume the task (paused by default)
-- ALTER TASK TBRDP_DW_DEV.IM_RPT.TASK_VOC_DAILY_REPORT_CARD RESUME;
