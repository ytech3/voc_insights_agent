-- =====================================================
-- VOC REPORT CARD - STEP 2 OF 3
-- Create the Stored Procedure
-- =====================================================
-- INSTRUCTIONS:
--   1. Open this file in a NEW Snowsight SQL Worksheet
--   2. Set Role to ACCOUNTADMIN (top-left dropdown)
--   3. Set Warehouse to TBRDP_DW_CORTEX_XS_WH
--   4. Set Database to TBRDP_DW_DEV, Schema to IM_RPT
--   5. Select ALL text (Ctrl+A), then click "Run" (Ctrl+Enter)
--      This is a SINGLE statement — do NOT use "Run All"
-- =====================================================
-- NOTE: The $$ delimiters tell Snowsight to treat everything
--       between them as the procedure body. Internal semicolons
--       will NOT be misinterpreted as statement separators.
-- =====================================================

CREATE OR REPLACE PROCEDURE TBRDP_DW_DEV.IM_RPT.SP_VOC_DAILY_REPORT_CARD(P_GAME_DATE VARCHAR DEFAULT NULL)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
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
    LET v_gap_color VARCHAR;
    LET v_game_date_display VARCHAR;
    LET v_day_of_week VARCHAR;
    LET v_opponent VARCHAR;
    LET v_header_line VARCHAR;

    -- Section 2: Sentiment-based qualitative variables (all fans)
    LET v_positive_total NUMBER DEFAULT 0;
    LET v_negative_total NUMBER DEFAULT 0;
    LET v_pos_topic_1 VARCHAR DEFAULT 'N/A';
    LET v_pos_topic_1_dept VARCHAR DEFAULT '';
    LET v_pos_topic_1_pct VARCHAR DEFAULT '0';
    LET v_pos_topic_2 VARCHAR DEFAULT 'N/A';
    LET v_pos_topic_2_dept VARCHAR DEFAULT '';
    LET v_pos_topic_2_pct VARCHAR DEFAULT '0';
    LET v_pos_topic_3 VARCHAR DEFAULT 'N/A';
    LET v_pos_topic_3_dept VARCHAR DEFAULT '';
    LET v_pos_topic_3_pct VARCHAR DEFAULT '0';
    LET v_neg_topic_1 VARCHAR DEFAULT 'N/A';
    LET v_neg_topic_1_dept VARCHAR DEFAULT '';
    LET v_neg_topic_1_pct VARCHAR DEFAULT '0';
    LET v_neg_topic_2 VARCHAR DEFAULT 'N/A';
    LET v_neg_topic_2_dept VARCHAR DEFAULT '';
    LET v_neg_topic_2_pct VARCHAR DEFAULT '0';
    LET v_neg_topic_3 VARCHAR DEFAULT 'N/A';
    LET v_neg_topic_3_dept VARCHAR DEFAULT '';
    LET v_neg_topic_3_pct VARCHAR DEFAULT '0';

    -- Section 3: Metric comparison variables (game vs season)
    LET v_best1_label VARCHAR DEFAULT 'N/A';
    LET v_best1_dept VARCHAR DEFAULT '';
    LET v_best1_game VARCHAR DEFAULT '0';
    LET v_best1_season VARCHAR DEFAULT '0';
    LET v_best1_delta VARCHAR DEFAULT '0';
    LET v_best1_unit VARCHAR DEFAULT '';
    LET v_best2_label VARCHAR DEFAULT 'N/A';
    LET v_best2_dept VARCHAR DEFAULT '';
    LET v_best2_game VARCHAR DEFAULT '0';
    LET v_best2_season VARCHAR DEFAULT '0';
    LET v_best2_delta VARCHAR DEFAULT '0';
    LET v_best2_unit VARCHAR DEFAULT '';
    LET v_worst1_label VARCHAR DEFAULT 'N/A';
    LET v_worst1_dept VARCHAR DEFAULT '';
    LET v_worst1_game VARCHAR DEFAULT '0';
    LET v_worst1_season VARCHAR DEFAULT '0';
    LET v_worst1_delta VARCHAR DEFAULT '0';
    LET v_worst1_unit VARCHAR DEFAULT '';
    LET v_worst2_label VARCHAR DEFAULT 'N/A';
    LET v_worst2_dept VARCHAR DEFAULT '';
    LET v_worst2_game VARCHAR DEFAULT '0';
    LET v_worst2_season VARCHAR DEFAULT '0';
    LET v_worst2_delta VARCHAR DEFAULT '0';
    LET v_worst2_unit VARCHAR DEFAULT '';

    -- Logo variables
    LET v_opponent_logo_file VARCHAR;
    LET v_opponent_logo_url VARCHAR DEFAULT '';
    LET v_rays_logo_url VARCHAR DEFAULT '';

    -- AI & email variables
    LET v_action_items VARCHAR DEFAULT '';
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
    -- HEADER: Game date, opponent, day of week, logo filename
    -- =============================================
    SELECT
        DECODE(DAYNAME(GAME_DATE::DATE),
            'Mon','Monday','Tue','Tuesday','Wed','Wednesday',
            'Thu','Thursday','Fri','Friday','Sat','Saturday','Sun','Sunday'),
        AWAYTRI,
        TO_VARCHAR(GAME_DATE::DATE, 'MMMM DD'),
        SEASON,
        CASE AWAYTRI
            WHEN 'ATH' THEN 'Oakland_Athletics.png'
            WHEN 'ATL' THEN 'Atlanta_Braves.png'
            WHEN 'AZ'  THEN 'Arizona_Diamondbacks.png'
            WHEN 'BAL' THEN 'Baltimore_Orioles.png'
            WHEN 'BOS' THEN 'Boston_Redsox.png'
            WHEN 'CHC' THEN 'Chicago_Cubs.png'
            WHEN 'CIN' THEN 'Cincinnati_Reds.png'
            WHEN 'CLE' THEN 'Cleveland_Guardians.png'
            WHEN 'COL' THEN 'Colorado_Rockies.png'
            WHEN 'CWS' THEN 'Chicago_Whitesox.png'
            WHEN 'DET' THEN 'Detroit_Tigers.png'
            WHEN 'HOU' THEN 'Houston_Astros.png'
            WHEN 'KC'  THEN 'KansasCity_Royals.png'
            WHEN 'LAA' THEN 'LosAngeles_Angels.png'
            WHEN 'LAD' THEN 'LosAngeles_Dodgers.png'
            WHEN 'MIA' THEN 'Miami_Marlins.png'
            WHEN 'MIL' THEN 'Milwaukee_Brewers.png'
            WHEN 'MIN' THEN 'Minnesota_Twins.png'
            WHEN 'NYM' THEN 'NewYork_Mets.png'
            WHEN 'NYY' THEN 'NewYork_Yankees.png'
            WHEN 'PHI' THEN 'Philadelphia_Phillies.png'
            WHEN 'PIT' THEN 'Pittsburgh_Pirates.png'
            WHEN 'SD'  THEN 'SanDiego_Padres.png'
            WHEN 'SEA' THEN 'Seattle_Mariners.png'
            WHEN 'SF'  THEN 'SanFrancisco_Giants.png'
            WHEN 'STL' THEN 'StLouis_Cardinals.png'
            WHEN 'TEX' THEN 'Texas_Rangers.png'
            WHEN 'TOR' THEN 'Toronto_BlueJays.png'
            WHEN 'WSH' THEN 'Washington_Nationals.png'
            ELSE 'TampaBay_Rays.png'
        END
    INTO :v_day_of_week, :v_opponent, :v_game_date_display, :v_season, :v_opponent_logo_file
    FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
    WHERE GAME_DATE::DATE = :v_target_game_date
      AND AWAYTRI IS NOT NULL
    LIMIT 1;

    v_header_line := v_day_of_week || ', ' || v_game_date_display || ' vs ' || v_opponent;

    -- Generate presigned URLs (valid 1 hour — sufficient for email send)
    SELECT GET_PRESIGNED_URL(@TBRDP_DW_DEV.IM_RPT.MLB_LOGOS_STAGE, :v_opponent_logo_file, 3600)
    INTO :v_opponent_logo_url;

    SELECT GET_PRESIGNED_URL(@TBRDP_DW_DEV.IM_RPT.MLB_LOGOS_STAGE, 'TampaBay_Rays.png', 3600)
    INTO :v_rays_logo_url;

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

    v_gap_pct := ROUND(((v_game_avg - v_season_avg) / v_season_avg) * 100, 2);
    IF (v_gap_pct >= 0) THEN
        v_gap_icon := '&#9650;';
        v_gap_color := '#2ecc71';
    ELSE
        v_gap_icon := '&#9660;';
        v_gap_color := '#ff6b6b';
    END IF;

    -- =============================================
    -- SECTION 2: QUALITATIVE SUMMARY (by Sentiment)
    -- All fans, positive vs negative, with department
    -- =============================================
    SELECT
        COUNT(CASE WHEN sentiment_category = 'Positive' THEN 1 END),
        COUNT(CASE WHEN sentiment_category = 'Negative' THEN 1 END)
    INTO :v_positive_total, :v_negative_total
    FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
    WHERE GAME_DATE::DATE = :v_target_game_date
      AND ai_category IS NOT NULL
      AND sentiment_category IN ('Positive', 'Negative');

    -- Top 3 Positive topics (all fans)
    LET c_pos_topics CURSOR FOR
        SELECT ai_category, parent_category,
            ROUND(100.0 * COUNT(*) / NULLIF(:v_positive_total, 0), 1) AS pct
        FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
        WHERE GAME_DATE::DATE = :v_target_game_date
          AND sentiment_category = 'Positive'
          AND ai_category IS NOT NULL
        GROUP BY ai_category, parent_category
        ORDER BY COUNT(*) DESC
        LIMIT 3;

    LET v_rank NUMBER := 0;
    FOR rec IN c_pos_topics DO
        v_rank := v_rank + 1;
        IF (v_rank = 1) THEN v_pos_topic_1 := rec.ai_category; v_pos_topic_1_dept := rec.parent_category; v_pos_topic_1_pct := rec.pct::VARCHAR;
        ELSEIF (v_rank = 2) THEN v_pos_topic_2 := rec.ai_category; v_pos_topic_2_dept := rec.parent_category; v_pos_topic_2_pct := rec.pct::VARCHAR;
        ELSEIF (v_rank = 3) THEN v_pos_topic_3 := rec.ai_category; v_pos_topic_3_dept := rec.parent_category; v_pos_topic_3_pct := rec.pct::VARCHAR;
        END IF;
    END FOR;

    -- Top 3 Negative topics (all fans)
    LET c_neg_topics CURSOR FOR
        SELECT ai_category, parent_category,
            ROUND(100.0 * COUNT(*) / NULLIF(:v_negative_total, 0), 1) AS pct
        FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
        WHERE GAME_DATE::DATE = :v_target_game_date
          AND sentiment_category = 'Negative'
          AND ai_category IS NOT NULL
        GROUP BY ai_category, parent_category
        ORDER BY COUNT(*) DESC
        LIMIT 3;

    v_rank := 0;
    FOR rec IN c_neg_topics DO
        v_rank := v_rank + 1;
        IF (v_rank = 1) THEN v_neg_topic_1 := rec.ai_category; v_neg_topic_1_dept := rec.parent_category; v_neg_topic_1_pct := rec.pct::VARCHAR;
        ELSEIF (v_rank = 2) THEN v_neg_topic_2 := rec.ai_category; v_neg_topic_2_dept := rec.parent_category; v_neg_topic_2_pct := rec.pct::VARCHAR;
        ELSEIF (v_rank = 3) THEN v_neg_topic_3 := rec.ai_category; v_neg_topic_3_dept := rec.parent_category; v_neg_topic_3_pct := rec.pct::VARCHAR;
        END IF;
    END FOR;

    -- =============================================
    -- SECTION 3: OVERALL SUMMARY
    -- Game vs Season metric comparison (35 metrics)
    -- =============================================
    LET c_best CURSOR FOR
        WITH game AS (
            SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
            WHERE GAME_DATE::DATE = :v_target_game_date
        ),
        season AS (
            SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
            WHERE SEASON = :v_season AND OVERALL_NUMRAT IS NOT NULL
        ),
        metrics AS (
            -- NUMRAT avg metrics (higher = better)
            SELECT 'Overall Rating' AS metric_label, 'General' AS dept, '/10' AS unit,
                ROUND(AVG(OVERALL_NUMRAT),2) AS game_val,
                (SELECT ROUND(AVG(OVERALL_NUMRAT),2) FROM season) AS season_val,
                COUNT(CASE WHEN OVERALL_NUMRAT IS NOT NULL THEN 1 END) AS n
            FROM game
            UNION ALL
            SELECT 'Concession Rating', 'Concessions', '/10',
                ROUND(AVG(CONCESS_NUMRAT),2),
                (SELECT ROUND(AVG(CONCESS_NUMRAT),2) FROM season WHERE CONCESS_NUMRAT IS NOT NULL),
                COUNT(CASE WHEN CONCESS_NUMRAT IS NOT NULL THEN 1 END)
            FROM game WHERE CONCESS_NUMRAT IS NOT NULL
            UNION ALL
            SELECT 'Parking Rating', 'Parking', '/10',
                ROUND(AVG(PARKING_NUMRAT),2),
                (SELECT ROUND(AVG(PARKING_NUMRAT),2) FROM season WHERE PARKING_NUMRAT IS NOT NULL),
                COUNT(CASE WHEN PARKING_NUMRAT IS NOT NULL THEN 1 END)
            FROM game WHERE PARKING_NUMRAT IS NOT NULL
            UNION ALL
            -- Concession grid dissatisfaction (lower = better, so improvement = season - game)
            SELECT 'Concession Value', 'Concessions', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Concession Service', 'Concessions', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Concession Selection', 'Concessions', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Concession Cleanliness', 'Concessions', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Merchandise grid dissatisfaction
            SELECT 'Merch Pricing', 'Retail', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_PRICE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_PRICE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Selection', 'Retail', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Quality', 'Retail', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Wait Time', 'Retail', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_WAIT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_WAIT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Customer Service', 'Retail', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Entertainment grid dissatisfaction
            SELECT 'In-Game Music', 'Game Entertainment', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'In-Game Activities', 'Game Entertainment', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Scoreboard Experience', 'Game Entertainment', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Game Theme', 'Game Entertainment', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Kids Activities', 'Game Entertainment', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IS NOT NULL AND ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IS NOT NULL AND ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IS NOT NULL AND ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Pregame Content', 'Game Entertainment', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IS NOT NULL AND ENTERTAIN_GRID_PREGAME_CONTENT_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IS NOT NULL AND ENTERTAIN_GRID_PREGAME_CONTENT_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IS NOT NULL AND ENTERTAIN_GRID_PREGAME_CONTENT_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Parking (wait expectations)
            SELECT 'Parking Arrival Wait', 'Parking', '% Longer Than Expected',
                ROUND(100.0*SUM(CASE WHEN PARKING_TIME_EXPECT_DESC = 'Longer than expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PARKING_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN PARKING_TIME_EXPECT_DESC = 'Longer than expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PARKING_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN PARKING_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Parking Exit Wait', 'Parking', '% Longer Than Expected',
                ROUND(100.0*SUM(CASE WHEN PARKING_EXIT_EXPECT_DESC = 'Longer than expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PARKING_EXIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN PARKING_EXIT_EXPECT_DESC = 'Longer than expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PARKING_EXIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN PARKING_EXIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Brand Health (disagree = negative, lower = better)
            SELECT 'Brand: Accessible', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_ACCESSIBLE_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_ACCESSIBLE_DESC IS NOT NULL AND BRANDHEALTH_GRID_ACCESSIBLE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_ACCESSIBLE_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_ACCESSIBLE_DESC IS NOT NULL AND BRANDHEALTH_GRID_ACCESSIBLE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_ACCESSIBLE_DESC IS NOT NULL AND BRANDHEALTH_GRID_ACCESSIBLE_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Champion', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_CHAMPION_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_CHAMPION_DESC IS NOT NULL AND BRANDHEALTH_GRID_CHAMPION_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_CHAMPION_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_CHAMPION_DESC IS NOT NULL AND BRANDHEALTH_GRID_CHAMPION_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_CHAMPION_DESC IS NOT NULL AND BRANDHEALTH_GRID_CHAMPION_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Diversity', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_DIVERSITY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_DIVERSITY_DESC IS NOT NULL AND BRANDHEALTH_GRID_DIVERSITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_DIVERSITY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_DIVERSITY_DESC IS NOT NULL AND BRANDHEALTH_GRID_DIVERSITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_DIVERSITY_DESC IS NOT NULL AND BRANDHEALTH_GRID_DIVERSITY_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Emotional', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_EMOTIONAL_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_EMOTIONAL_DESC IS NOT NULL AND BRANDHEALTH_GRID_EMOTIONAL_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_EMOTIONAL_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_EMOTIONAL_DESC IS NOT NULL AND BRANDHEALTH_GRID_EMOTIONAL_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_EMOTIONAL_DESC IS NOT NULL AND BRANDHEALTH_GRID_EMOTIONAL_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Exciting', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_EXCITING_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_EXCITING_DESC IS NOT NULL AND BRANDHEALTH_GRID_EXCITING_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_EXCITING_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_EXCITING_DESC IS NOT NULL AND BRANDHEALTH_GRID_EXCITING_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_EXCITING_DESC IS NOT NULL AND BRANDHEALTH_GRID_EXCITING_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Family Friendly', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_FAMFRIENDLY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_FAMFRIENDLY_DESC IS NOT NULL AND BRANDHEALTH_GRID_FAMFRIENDLY_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_FAMFRIENDLY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_FAMFRIENDLY_DESC IS NOT NULL AND BRANDHEALTH_GRID_FAMFRIENDLY_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_FAMFRIENDLY_DESC IS NOT NULL AND BRANDHEALTH_GRID_FAMFRIENDLY_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Positive Influence', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_POSINFLUENCE_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_POSINFLUENCE_DESC IS NOT NULL AND BRANDHEALTH_GRID_POSINFLUENCE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_POSINFLUENCE_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_POSINFLUENCE_DESC IS NOT NULL AND BRANDHEALTH_GRID_POSINFLUENCE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_POSINFLUENCE_DESC IS NOT NULL AND BRANDHEALTH_GRID_POSINFLUENCE_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Right Direction', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_RIGHTDIRECTION_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_RIGHTDIRECTION_DESC IS NOT NULL AND BRANDHEALTH_GRID_RIGHTDIRECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_RIGHTDIRECTION_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_RIGHTDIRECTION_DESC IS NOT NULL AND BRANDHEALTH_GRID_RIGHTDIRECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_RIGHTDIRECTION_DESC IS NOT NULL AND BRANDHEALTH_GRID_RIGHTDIRECTION_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Safe', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_SAFE_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_SAFE_DESC IS NOT NULL AND BRANDHEALTH_GRID_SAFE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_SAFE_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_SAFE_DESC IS NOT NULL AND BRANDHEALTH_GRID_SAFE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_SAFE_DESC IS NOT NULL AND BRANDHEALTH_GRID_SAFE_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Sustainability', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_SUSTAINABILITY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_SUSTAINABILITY_DESC IS NOT NULL AND BRANDHEALTH_GRID_SUSTAINABILITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_SUSTAINABILITY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_SUSTAINABILITY_DESC IS NOT NULL AND BRANDHEALTH_GRID_SUSTAINABILITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_SUSTAINABILITY_DESC IS NOT NULL AND BRANDHEALTH_GRID_SUSTAINABILITY_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Trendy', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_TRENDY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_TRENDY_DESC IS NOT NULL AND BRANDHEALTH_GRID_TRENDY_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_TRENDY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_TRENDY_DESC IS NOT NULL AND BRANDHEALTH_GRID_TRENDY_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_TRENDY_DESC IS NOT NULL AND BRANDHEALTH_GRID_TRENDY_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Welcoming', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_WELCOME_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_WELCOME_DESC IS NOT NULL AND BRANDHEALTH_GRID_WELCOME_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_WELCOME_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_WELCOME_DESC IS NOT NULL AND BRANDHEALTH_GRID_WELCOME_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_WELCOME_DESC IS NOT NULL AND BRANDHEALTH_GRID_WELCOME_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
        ),
        scored AS (
            SELECT metric_label, dept, unit, game_val, season_val, n,
                CASE
                    WHEN unit = '/10' THEN ROUND(game_val - season_val, 2)
                    ELSE ROUND(season_val - game_val, 2)
                END AS improvement
            FROM metrics
            WHERE game_val IS NOT NULL AND season_val IS NOT NULL AND n >= 20
        )
        SELECT metric_label, dept, unit, game_val, season_val, improvement
        FROM scored
        ORDER BY improvement DESC
        LIMIT 2;

    v_rank := 0;
    FOR rec IN c_best DO
        v_rank := v_rank + 1;
        IF (v_rank = 1) THEN
            v_best1_label := rec.metric_label; v_best1_dept := rec.dept; v_best1_unit := rec.unit;
            v_best1_game := rec.game_val::VARCHAR; v_best1_season := rec.season_val::VARCHAR;
            v_best1_delta := rec.improvement::VARCHAR;
        ELSEIF (v_rank = 2) THEN
            v_best2_label := rec.metric_label; v_best2_dept := rec.dept; v_best2_unit := rec.unit;
            v_best2_game := rec.game_val::VARCHAR; v_best2_season := rec.season_val::VARCHAR;
            v_best2_delta := rec.improvement::VARCHAR;
        END IF;
    END FOR;

    -- Top 2 worst performing metrics (same query, ORDER BY ASC)
    LET c_worst CURSOR FOR
        WITH game AS (
            SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
            WHERE GAME_DATE::DATE = :v_target_game_date
        ),
        season AS (
            SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
            WHERE SEASON = :v_season AND OVERALL_NUMRAT IS NOT NULL
        ),
        metrics AS (
            SELECT 'Overall Rating' AS metric_label, 'General' AS dept, '/10' AS unit,
                ROUND(AVG(OVERALL_NUMRAT),2) AS game_val,
                (SELECT ROUND(AVG(OVERALL_NUMRAT),2) FROM season) AS season_val,
                COUNT(CASE WHEN OVERALL_NUMRAT IS NOT NULL THEN 1 END) AS n
            FROM game
            UNION ALL
            SELECT 'Concession Rating', 'Concessions', '/10', ROUND(AVG(CONCESS_NUMRAT),2),
                (SELECT ROUND(AVG(CONCESS_NUMRAT),2) FROM season WHERE CONCESS_NUMRAT IS NOT NULL),
                COUNT(CASE WHEN CONCESS_NUMRAT IS NOT NULL THEN 1 END)
            FROM game WHERE CONCESS_NUMRAT IS NOT NULL
            UNION ALL
            SELECT 'Parking Rating', 'Parking', '/10', ROUND(AVG(PARKING_NUMRAT),2),
                (SELECT ROUND(AVG(PARKING_NUMRAT),2) FROM season WHERE PARKING_NUMRAT IS NOT NULL),
                COUNT(CASE WHEN PARKING_NUMRAT IS NOT NULL THEN 1 END)
            FROM game WHERE PARKING_NUMRAT IS NOT NULL
            UNION ALL
            SELECT 'Concession Value', 'Concessions', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Concession Service', 'Concessions', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Concession Selection', 'Concessions', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Concession Cleanliness', 'Concessions', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Pricing', 'Retail', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_PRICE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_PRICE_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Selection', 'Retail', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Quality', 'Retail', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Wait Time', 'Retail', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_WAIT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_WAIT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Customer Service', 'Retail', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'In-Game Music', 'Game Entertainment', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'In-Game Activities', 'Game Entertainment', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Scoreboard Experience', 'Game Entertainment', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Kids Activities', 'Game Entertainment', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IS NOT NULL AND ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IS NOT NULL AND ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IS NOT NULL AND ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Pregame Content', 'Game Entertainment', '% Dissatisfaction',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IS NOT NULL AND ENTERTAIN_GRID_PREGAME_CONTENT_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IN ('Somewhat dissatisfied','Highly dissatisfied') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IS NOT NULL AND ENTERTAIN_GRID_PREGAME_CONTENT_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IS NOT NULL AND ENTERTAIN_GRID_PREGAME_CONTENT_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Parking Arrival Wait', 'Parking', '% Longer Than Expected',
                ROUND(100.0*SUM(CASE WHEN PARKING_TIME_EXPECT_DESC = 'Longer than expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PARKING_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN PARKING_TIME_EXPECT_DESC = 'Longer than expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PARKING_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN PARKING_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Parking Exit Wait', 'Parking', '% Longer Than Expected',
                ROUND(100.0*SUM(CASE WHEN PARKING_EXIT_EXPECT_DESC = 'Longer than expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PARKING_EXIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN PARKING_EXIT_EXPECT_DESC = 'Longer than expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PARKING_EXIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN PARKING_EXIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Accessible', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_ACCESSIBLE_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_ACCESSIBLE_DESC IS NOT NULL AND BRANDHEALTH_GRID_ACCESSIBLE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_ACCESSIBLE_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_ACCESSIBLE_DESC IS NOT NULL AND BRANDHEALTH_GRID_ACCESSIBLE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_ACCESSIBLE_DESC IS NOT NULL AND BRANDHEALTH_GRID_ACCESSIBLE_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Exciting', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_EXCITING_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_EXCITING_DESC IS NOT NULL AND BRANDHEALTH_GRID_EXCITING_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_EXCITING_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_EXCITING_DESC IS NOT NULL AND BRANDHEALTH_GRID_EXCITING_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_EXCITING_DESC IS NOT NULL AND BRANDHEALTH_GRID_EXCITING_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Family Friendly', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_FAMFRIENDLY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_FAMFRIENDLY_DESC IS NOT NULL AND BRANDHEALTH_GRID_FAMFRIENDLY_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_FAMFRIENDLY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_FAMFRIENDLY_DESC IS NOT NULL AND BRANDHEALTH_GRID_FAMFRIENDLY_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_FAMFRIENDLY_DESC IS NOT NULL AND BRANDHEALTH_GRID_FAMFRIENDLY_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Welcoming', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_WELCOME_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_WELCOME_DESC IS NOT NULL AND BRANDHEALTH_GRID_WELCOME_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_WELCOME_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_WELCOME_DESC IS NOT NULL AND BRANDHEALTH_GRID_WELCOME_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_WELCOME_DESC IS NOT NULL AND BRANDHEALTH_GRID_WELCOME_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Trendy', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_TRENDY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_TRENDY_DESC IS NOT NULL AND BRANDHEALTH_GRID_TRENDY_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_TRENDY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_TRENDY_DESC IS NOT NULL AND BRANDHEALTH_GRID_TRENDY_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_TRENDY_DESC IS NOT NULL AND BRANDHEALTH_GRID_TRENDY_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Safe', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_SAFE_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_SAFE_DESC IS NOT NULL AND BRANDHEALTH_GRID_SAFE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_SAFE_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_SAFE_DESC IS NOT NULL AND BRANDHEALTH_GRID_SAFE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_SAFE_DESC IS NOT NULL AND BRANDHEALTH_GRID_SAFE_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Sustainability', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_SUSTAINABILITY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_SUSTAINABILITY_DESC IS NOT NULL AND BRANDHEALTH_GRID_SUSTAINABILITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_SUSTAINABILITY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_SUSTAINABILITY_DESC IS NOT NULL AND BRANDHEALTH_GRID_SUSTAINABILITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_SUSTAINABILITY_DESC IS NOT NULL AND BRANDHEALTH_GRID_SUSTAINABILITY_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Emotional', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_EMOTIONAL_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_EMOTIONAL_DESC IS NOT NULL AND BRANDHEALTH_GRID_EMOTIONAL_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_EMOTIONAL_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_EMOTIONAL_DESC IS NOT NULL AND BRANDHEALTH_GRID_EMOTIONAL_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_EMOTIONAL_DESC IS NOT NULL AND BRANDHEALTH_GRID_EMOTIONAL_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Champion', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_CHAMPION_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_CHAMPION_DESC IS NOT NULL AND BRANDHEALTH_GRID_CHAMPION_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_CHAMPION_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_CHAMPION_DESC IS NOT NULL AND BRANDHEALTH_GRID_CHAMPION_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_CHAMPION_DESC IS NOT NULL AND BRANDHEALTH_GRID_CHAMPION_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Diversity', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_DIVERSITY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_DIVERSITY_DESC IS NOT NULL AND BRANDHEALTH_GRID_DIVERSITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_DIVERSITY_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_DIVERSITY_DESC IS NOT NULL AND BRANDHEALTH_GRID_DIVERSITY_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_DIVERSITY_DESC IS NOT NULL AND BRANDHEALTH_GRID_DIVERSITY_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Positive Influence', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_POSINFLUENCE_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_POSINFLUENCE_DESC IS NOT NULL AND BRANDHEALTH_GRID_POSINFLUENCE_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_POSINFLUENCE_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_POSINFLUENCE_DESC IS NOT NULL AND BRANDHEALTH_GRID_POSINFLUENCE_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_POSINFLUENCE_DESC IS NOT NULL AND BRANDHEALTH_GRID_POSINFLUENCE_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Brand: Right Direction', 'Marketing', '% Disagreement',
                ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_RIGHTDIRECTION_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_RIGHTDIRECTION_DESC IS NOT NULL AND BRANDHEALTH_GRID_RIGHTDIRECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN BRANDHEALTH_GRID_RIGHTDIRECTION_DESC IN ('Somewhat disagree','Strongly disagree') THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN BRANDHEALTH_GRID_RIGHTDIRECTION_DESC IS NOT NULL AND BRANDHEALTH_GRID_RIGHTDIRECTION_DESC!='N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN BRANDHEALTH_GRID_RIGHTDIRECTION_DESC IS NOT NULL AND BRANDHEALTH_GRID_RIGHTDIRECTION_DESC!='N/A' THEN 1 ELSE 0 END)
            FROM game
        ),
        scored AS (
            SELECT metric_label, dept, unit, game_val, season_val, n,
                CASE
                    WHEN unit = '/10' THEN ROUND(game_val - season_val, 2)
                    ELSE ROUND(season_val - game_val, 2)
                END AS improvement
            FROM metrics
            WHERE game_val IS NOT NULL AND season_val IS NOT NULL AND n >= 20
        )
        SELECT metric_label, dept, unit, game_val, season_val, improvement
        FROM scored
        ORDER BY improvement ASC
        LIMIT 2;

    v_rank := 0;
    FOR rec IN c_worst DO
        v_rank := v_rank + 1;
        IF (v_rank = 1) THEN
            v_worst1_label := rec.metric_label; v_worst1_dept := rec.dept; v_worst1_unit := rec.unit;
            v_worst1_game := rec.game_val::VARCHAR; v_worst1_season := rec.season_val::VARCHAR;
            v_worst1_delta := rec.improvement::VARCHAR;
        ELSEIF (v_rank = 2) THEN
            v_worst2_label := rec.metric_label; v_worst2_dept := rec.dept; v_worst2_unit := rec.unit;
            v_worst2_game := rec.game_val::VARCHAR; v_worst2_season := rec.season_val::VARCHAR;
            v_worst2_delta := rec.improvement::VARCHAR;
        END IF;
    END FOR;

    -- =============================================
    -- AI: ACTIONABLE ITEMS (only AI call)
    -- 1 positive reinforcement + 1 corrective action
    -- =============================================
    LET v_action_prompt VARCHAR;
    v_action_prompt := 'You are a senior sports business analyst for the Tampa Bay Rays. Generate exactly 2 action items based on the game-day performance data below. The FIRST action must reinforce/amplify the top positive performing area. The SECOND action must address the top negative performing area with a specific corrective recommendation. Each is one sentence referencing the department and data. Use HTML <div> tags with icons. Do not use markdown.

GAME: ' || v_header_line || ' | ' || v_response_count::VARCHAR || ' responses | ' || v_game_avg::VARCHAR || '/10 vs ' || v_season_avg::VARCHAR || '/10 season

BEST PERFORMING METRIC: ' || v_best1_label || ' (' || v_best1_dept || ') — Game: ' || v_best1_game || ' ' || v_best1_unit || ' vs Season: ' || v_best1_season || ' ' || v_best1_unit || ' (improved by ' || v_best1_delta || ')
WORST PERFORMING METRIC: ' || v_worst1_label || ' (' || v_worst1_dept || ') — Game: ' || v_worst1_game || ' ' || v_worst1_unit || ' vs Season: ' || v_worst1_season || ' ' || v_worst1_unit || ' (declined by ' || ABS(v_worst1_delta::FLOAT)::VARCHAR || ')

FORMAT: Return exactly 2 lines.
<div>&#9989; [Positive reinforcement action referencing the best metric, department, and data]</div>
<div>&#128640; [Corrective action referencing the worst metric, department, and specific fix]</div>';

    SELECT AI_COMPLETE('claude-sonnet-4-6', :v_action_prompt, {'temperature': 0.3, 'max_tokens': 300})
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
<tr><td style="background:linear-gradient(135deg, #092C5C 0%, #1a4a8a 100%);padding:24px 20px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
    <tr>
      <td width="60" style="text-align:left;vertical-align:middle;">
        <img src="' || v_opponent_logo_url || '" alt="' || v_opponent || '" width="50" height="50" style="display:block;border:0;outline:none;" />
      </td>
      <td style="text-align:center;vertical-align:middle;padding:0 10px;">
        <div style="font-size:13px;letter-spacing:3px;color:#8FBCE6;font-weight:600;margin-bottom:6px;">TAMPA BAY RAYS</div>
        <div style="font-size:26px;font-weight:700;color:#ffffff;margin-bottom:4px;">GAME DAY REPORT CARD</div>
        <div style="font-size:14px;color:#8FBCE6;margin-top:10px;">' || v_header_line || ' &nbsp;|&nbsp; ' || v_response_count::VARCHAR || ' Survey Responses</div>
      </td>
      <td width="60" style="text-align:right;vertical-align:middle;">
        <img src="' || v_rays_logo_url || '" alt="Rays" width="50" height="50" style="display:block;border:0;outline:none;margin-left:auto;" />
      </td>
    </tr>
  </table>
</td></tr>

<!-- ========== SECTIONS 1 & 2: SCORE + QUALITATIVE (side by side) ========== -->
<tr><td style="padding:20px 24px 0 24px;">
  <!--[if mso]><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td width="220" valign="top"><![endif]-->
  <div style="display:inline-block;vertical-align:top;width:100%;max-width:210px;margin-right:12px;">
    <!-- QUANTITATIVE SCORE CARD -->
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:8px;">
      <tr><td style="padding:6px 0 4px 0;font-size:10px;letter-spacing:1.5px;color:#092C5C;font-weight:700;">&#128202; QUANTITATIVE</td></tr>
      <tr><td style="background-color:#092C5C;border-radius:8px;padding:16px 18px;text-align:center;">
        <div style="font-size:36px;font-weight:800;color:#ffffff;line-height:1.1;">' || v_game_avg::VARCHAR || '</div>
        <div style="font-size:11px;color:#8FBCE6;margin-top:2px;">out of 10</div>
        <div style="margin-top:8px;font-size:14px;font-weight:700;color:' || v_gap_color || ';">' || v_gap_icon || ' ' || ABS(v_gap_pct)::VARCHAR || '% vs season</div>
      </td></tr>
      <tr><td style="padding:6px 0 0 0;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
          <tr>
            <td style="padding:4px 0;font-size:11px;color:#555;">Season Avg</td>
            <td style="padding:4px 0;font-size:11px;color:#092C5C;font-weight:700;text-align:right;">' || v_season_avg::VARCHAR || '/10</td>
          </tr>
          <tr>
            <td style="padding:4px 0;font-size:11px;color:#555;border-top:1px solid #e8eaed;">Game Responses</td>
            <td style="padding:4px 0;font-size:11px;color:#092C5C;font-weight:700;text-align:right;border-top:1px solid #e8eaed;">' || v_response_count::VARCHAR || '</td>
          </tr>
          <tr>
            <td style="padding:4px 0;font-size:11px;color:#555;border-top:1px solid #e8eaed;">Season Responses</td>
            <td style="padding:4px 0;font-size:11px;color:#092C5C;font-weight:700;text-align:right;border-top:1px solid #e8eaed;">' || v_season_responses::VARCHAR || '</td>
          </tr>
        </table>
      </td></tr>
    </table>
  </div>
  <!--[if mso]></td><td width="370" valign="top"><![endif]-->
  <div style="display:inline-block;vertical-align:top;width:100%;max-width:365px;">
    <!-- QUALITATIVE SUMMARY -->
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      <tr><td style="padding:6px 0 4px 0;font-size:10px;letter-spacing:1.5px;color:#092C5C;font-weight:700;">&#128172; QUALITATIVE</td></tr>
    </table>
    <!-- Positive Topics -->
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:6px;">
      <tr><td style="padding:6px 10px;background-color:#f0fff4;border-left:3px solid #2ecc71;border-radius:0 6px 6px 0;">
        <div style="font-size:10px;font-weight:700;color:#1a7431;letter-spacing:0.5px;margin-bottom:4px;">&#9989; POSITIVE FEEDBACK &middot; ' || v_positive_total::VARCHAR || '</div>
        <div style="font-size:11px;color:#333;line-height:1.6;">
          <div><strong>' || v_pos_topic_1 || '</strong> <span style="color:#888;">(' || v_pos_topic_1_dept || ')</span> <span style="color:#1a7431;font-weight:600;">' || v_pos_topic_1_pct || '%</span></div>
          <div><strong>' || v_pos_topic_2 || '</strong> <span style="color:#888;">(' || v_pos_topic_2_dept || ')</span> <span style="color:#1a7431;font-weight:600;">' || v_pos_topic_2_pct || '%</span></div>
          <div><strong>' || v_pos_topic_3 || '</strong> <span style="color:#888;">(' || v_pos_topic_3_dept || ')</span> <span style="color:#1a7431;font-weight:600;">' || v_pos_topic_3_pct || '%</span></div>
        </div>
      </td></tr>
    </table>
    <!-- Negative Topics -->
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      <tr><td style="padding:6px 10px;background-color:#fff5f5;border-left:3px solid #e74c3c;border-radius:0 6px 6px 0;">
        <div style="font-size:10px;font-weight:700;color:#c0392b;letter-spacing:0.5px;margin-bottom:4px;">&#9888;&#65039; NEGATIVE FEEDBACK &middot; ' || v_negative_total::VARCHAR || '</div>
        <div style="font-size:11px;color:#333;line-height:1.6;">
          <div><strong>' || v_neg_topic_1 || '</strong> <span style="color:#888;">(' || v_neg_topic_1_dept || ')</span> <span style="color:#c0392b;font-weight:600;">' || v_neg_topic_1_pct || '%</span></div>
          <div><strong>' || v_neg_topic_2 || '</strong> <span style="color:#888;">(' || v_neg_topic_2_dept || ')</span> <span style="color:#c0392b;font-weight:600;">' || v_neg_topic_2_pct || '%</span></div>
          <div><strong>' || v_neg_topic_3 || '</strong> <span style="color:#888;">(' || v_neg_topic_3_dept || ')</span> <span style="color:#c0392b;font-weight:600;">' || v_neg_topic_3_pct || '%</span></div>
        </div>
      </td></tr>
    </table>
  </div>
  <!--[if mso]></td></tr></table><![endif]-->
</td></tr>

<!-- DIVIDER -->
<tr><td style="padding:14px 24px;"><hr style="border:none;border-top:2px solid #e8eaed;margin:0;"></td></tr>

<!-- ========== SECTION 3: OVERALL SUMMARY ========== -->
<tr><td style="padding:0 24px 20px 24px;">
  <div style="font-size:10px;letter-spacing:1.5px;color:#092C5C;font-weight:700;margin-bottom:10px;">&#127919; OVERALL SUMMARY <span style="font-weight:400;color:#888;letter-spacing:0;">&mdash; Game vs season average (35 metrics)</span></div>

  <!-- Positive Takeaways -->
  <div style="padding:10px 14px;background-color:#f0fff4;border-left:3px solid #2ecc71;border-radius:0 6px 6px 0;margin-bottom:8px;">
    <div style="font-size:10px;font-weight:700;color:#1a7431;letter-spacing:0.5px;margin-bottom:5px;">POSITIVE TAKEAWAYS</div>
    <div style="font-size:12px;color:#333;line-height:1.6;">
      <div>&#9650; <strong>' || v_best1_label || '</strong> <span style="color:#888;">(' || v_best1_dept || ')</span> &mdash; Game: ' || v_best1_game || v_best1_unit || ' vs Season: ' || v_best1_season || v_best1_unit || ' <span style="color:#1a7431;font-weight:700;">+' || v_best1_delta || '% better</span></div>
      <div>&#9650; <strong>' || v_best2_label || '</strong> <span style="color:#888;">(' || v_best2_dept || ')</span> &mdash; Game: ' || v_best2_game || v_best2_unit || ' vs Season: ' || v_best2_season || v_best2_unit || ' <span style="color:#1a7431;font-weight:700;">+' || v_best2_delta || '% better</span></div>
    </div>
  </div>

  <!-- Negative Takeaways -->
  <div style="padding:10px 14px;background-color:#fff5f5;border-left:3px solid #e74c3c;border-radius:0 6px 6px 0;margin-bottom:8px;">
    <div style="font-size:10px;font-weight:700;color:#c0392b;letter-spacing:0.5px;margin-bottom:5px;">NEGATIVE TAKEAWAYS</div>
    <div style="font-size:12px;color:#333;line-height:1.6;">
      <div>&#9660; <strong>' || v_worst1_label || '</strong> <span style="color:#888;">(' || v_worst1_dept || ')</span> &mdash; Game: ' || v_worst1_game || v_worst1_unit || ' vs Season: ' || v_worst1_season || v_worst1_unit || ' <span style="color:#c0392b;font-weight:700;">' || v_worst1_delta || '% worse</span></div>
      <div>&#9660; <strong>' || v_worst2_label || '</strong> <span style="color:#888;">(' || v_worst2_dept || ')</span> &mdash; Game: ' || v_worst2_game || v_worst2_unit || ' vs Season: ' || v_worst2_season || v_worst2_unit || ' <span style="color:#c0392b;font-weight:700;">' || v_worst2_delta || '% worse</span></div>
    </div>
  </div>

  <!-- Actionable Items -->
  <div style="padding:10px 14px;background-color:#f0f7ff;border-left:3px solid #3498db;border-radius:0 6px 6px 0;">
    <div style="font-size:10px;font-weight:700;color:#2471a3;letter-spacing:0.5px;margin-bottom:4px;">ACTIONABLE ITEMS</div>
    <div style="font-size:12px;color:#333;line-height:1.5;">' || v_action_items || '</div>
  </div>
</td></tr>

<!-- ========== FOOTER ========== -->
<tr><td style="background-color:#092C5C;padding:16px 40px;text-align:center;">
  <div style="font-size:10px;color:#8FBCE6;line-height:1.5;">
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

    RETURN 'Report Card sent for ' || v_header_line || ' | Score: ' || v_game_avg::VARCHAR || '/10 | Gap: ' || v_gap_pct::VARCHAR || '% | Best: ' || v_best1_label || ' | Worst: ' || v_worst1_label;
END;
$$;
