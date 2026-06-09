-- =====================================================
-- VOC REPORT CARD - TEST / LOCAL PREVIEW VARIANT
-- Procedure: SP_VOC_DAILY_REPORT_CARD_TEST
-- Same as Step 2, with two differences:
--   1. Adds a pie chart (overall rating 9-10 vs 8-and-below)
--      as a middle column between OVERALL and QUALITATIVE.
--   2. RETURNS the HTML instead of emailing it, so a past
--      game can be previewed locally without sending mail.
-- Deploy + preview via: preview_report_card.py
-- Production proc (SP_VOC_DAILY_REPORT_CARD) is untouched.
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
-- IMPORTANT SNOWFLAKE SQL PROCEDURE PATTERNS:
--   - GET_PRESIGNED_URL does NOT accept bind variables directly.
--     Workaround: wrap in a subquery: FROM (SELECT :var AS fname)
--   - LET c CURSOR FOR SELECT... does NOT see LET-declared variables.
--     Workaround: LET rs RESULTSET := (SELECT ...); LET c CURSOR FOR rs;
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

    -- Section 2: Sentence-level qualitative variables
    LET v_positive_total NUMBER DEFAULT 0;
    LET v_negative_total NUMBER DEFAULT 0;
    LET v_feedback_total NUMBER DEFAULT 0;
    LET v_positive_pct VARCHAR DEFAULT '0';
    LET v_negative_pct VARCHAR DEFAULT '0';
    LET v_pos_topic_1 VARCHAR DEFAULT 'N/A'; LET v_pos_topic_1_pct VARCHAR DEFAULT '0';
    LET v_pos_topic_2 VARCHAR DEFAULT 'N/A'; LET v_pos_topic_2_pct VARCHAR DEFAULT '0';
    LET v_pos_topic_3 VARCHAR DEFAULT 'N/A'; LET v_pos_topic_3_pct VARCHAR DEFAULT '0';
    LET v_neg_topic_1 VARCHAR DEFAULT 'N/A'; LET v_neg_topic_1_pct VARCHAR DEFAULT '0';
    LET v_neg_topic_2 VARCHAR DEFAULT 'N/A'; LET v_neg_topic_2_pct VARCHAR DEFAULT '0';
    LET v_neg_topic_3 VARCHAR DEFAULT 'N/A'; LET v_neg_topic_3_pct VARCHAR DEFAULT '0';

    -- Section 3: Metric comparison variables (game vs season, 3 best + 3 worst)
    LET v_best1_label VARCHAR DEFAULT 'N/A'; LET v_best1_dept VARCHAR DEFAULT ''; LET v_best1_delta VARCHAR DEFAULT '0'; LET v_best1_unit VARCHAR DEFAULT '';
    LET v_best2_label VARCHAR DEFAULT 'N/A'; LET v_best2_dept VARCHAR DEFAULT ''; LET v_best2_delta VARCHAR DEFAULT '0'; LET v_best2_unit VARCHAR DEFAULT '';
    LET v_best3_label VARCHAR DEFAULT 'N/A'; LET v_best3_dept VARCHAR DEFAULT ''; LET v_best3_delta VARCHAR DEFAULT '0'; LET v_best3_unit VARCHAR DEFAULT '';
    LET v_worst1_label VARCHAR DEFAULT 'N/A'; LET v_worst1_dept VARCHAR DEFAULT ''; LET v_worst1_delta VARCHAR DEFAULT '0'; LET v_worst1_unit VARCHAR DEFAULT '';
    LET v_worst2_label VARCHAR DEFAULT 'N/A'; LET v_worst2_dept VARCHAR DEFAULT ''; LET v_worst2_delta VARCHAR DEFAULT '0'; LET v_worst2_unit VARCHAR DEFAULT '';
    LET v_worst3_label VARCHAR DEFAULT 'N/A'; LET v_worst3_dept VARCHAR DEFAULT ''; LET v_worst3_delta VARCHAR DEFAULT '0'; LET v_worst3_unit VARCHAR DEFAULT '';

    -- Natural language suffix: always "% higher" or "% lower"
    LET v_best1_suffix VARCHAR DEFAULT '% higher';
    LET v_best2_suffix VARCHAR DEFAULT '% higher';
    LET v_best3_suffix VARCHAR DEFAULT '% higher';
    LET v_worst1_suffix VARCHAR DEFAULT '% higher';
    LET v_worst2_suffix VARCHAR DEFAULT '% higher';
    LET v_worst3_suffix VARCHAR DEFAULT '% higher';

    -- Logo variables
    LET v_opponent_logo_url VARCHAR DEFAULT '';
    LET v_rays_logo_url VARCHAR DEFAULT '';

    -- CSV deep dive variables
    LET v_csv_filename VARCHAR DEFAULT '';
    LET v_csv_url VARCHAR DEFAULT '';
    LET v_csv_sql VARCHAR DEFAULT '';

    -- AI & email variables
    LET v_action_items VARCHAR DEFAULT '';
    LET v_html_body VARCHAR;
    LET v_email_subject VARCHAR;

    -- =============================================
    -- SECTION 3 CONTEXT: Game identity
    -- =============================================
    LET v_theme_names VARCHAR DEFAULT 'None';
    LET v_giveaway_name VARCHAR DEFAULT 'None';
    LET v_giveaway_type VARCHAR DEFAULT 'None';
    LET v_holiday_flag NUMBER DEFAULT 0;

    -- SECTION 3 CONTEXT: Audience composition (game-day)
    LET v_pct_left_early FLOAT DEFAULT 0;
    LET v_pct_exit_7th_or_earlier FLOAT DEFAULT 0;
    LET v_pct_with_young_kids FLOAT DEFAULT 0;
    LET v_pct_with_friends FLOAT DEFAULT 0;
    LET v_pct_with_spouse FLOAT DEFAULT 0;
    LET v_pct_alone FLOAT DEFAULT 0;
    LET v_pct_first_time_buyer FLOAT DEFAULT 0;
    LET v_pct_repurchase_intent FLOAT DEFAULT 0;
    LET v_avg_group_size FLOAT DEFAULT 0;
    LET v_pct_rays_fans FLOAT DEFAULT 0;
    LET v_pct_opposing_fans FLOAT DEFAULT 0;
    LET v_pct_passionate_fans FLOAT DEFAULT 0;
    LET v_avg_age FLOAT DEFAULT 0;
    LET v_avg_home_dist FLOAT DEFAULT 0;
    LET v_pct_drove FLOAT DEFAULT 0;
    LET v_pct_no_prev_season_games FLOAT DEFAULT 0;

    -- SECTION 3 CONTEXT: Operational metrics (game-day)
    LET v_pct_concess_wait_long FLOAT DEFAULT 0;
    LET v_pct_parking_arrival_long FLOAT DEFAULT 0;
    LET v_pct_parking_exit_long FLOAT DEFAULT 0;
    LET v_pct_travel_longer FLOAT DEFAULT 0;
    LET v_pct_gate_entry_long FLOAT DEFAULT 0;
    LET v_pct_bought_concessions FLOAT DEFAULT 0;
    LET v_pct_bought_merch FLOAT DEFAULT 0;
    LET v_pct_mobile_order FLOAT DEFAULT 0;
    LET v_pct_concess_spend_high FLOAT DEFAULT 0;

    -- SECTION 3 CONTEXT: Promo/theme performance (game-day)
    LET v_pct_giveaway_satisfied FLOAT DEFAULT 0;
    LET v_pct_arrived_early_for_giveaway FLOAT DEFAULT 0;
    LET v_pct_cared_giveaway FLOAT DEFAULT 0;
    LET v_pct_cared_theme FLOAT DEFAULT 0;
    LET v_pct_theme_drove_attendance FLOAT DEFAULT 0;
    LET v_pct_theme_satisfied FLOAT DEFAULT 0;

    -- SECTION 3 CONTEXT: Buyer segment summary
    LET v_buyer_seg_summary VARCHAR DEFAULT 'N/A';

    -- SECTION 3 BENCHMARKS: Game Tier (same-tier avg from 2023+2024)
    LET v_game_tier NUMBER DEFAULT 0;
    LET v_tier_avg_overall FLOAT DEFAULT 0;
    LET v_tier_num_games NUMBER DEFAULT 0;
    LET v_tier_total_responses NUMBER DEFAULT 0;
    LET v_tier_pct_left_early FLOAT DEFAULT 0;
    LET v_tier_pct_exit_7th_or_earlier FLOAT DEFAULT 0;
    LET v_tier_pct_with_young_kids FLOAT DEFAULT 0;
    LET v_tier_pct_with_friends FLOAT DEFAULT 0;
    LET v_tier_pct_with_spouse FLOAT DEFAULT 0;
    LET v_tier_pct_alone FLOAT DEFAULT 0;
    LET v_tier_pct_first_time_buyer FLOAT DEFAULT 0;
    LET v_tier_pct_repurchase_intent FLOAT DEFAULT 0;
    LET v_tier_avg_group_size FLOAT DEFAULT 0;
    LET v_tier_pct_rays_fans FLOAT DEFAULT 0;
    LET v_tier_pct_passionate_fans FLOAT DEFAULT 0;
    LET v_tier_avg_age FLOAT DEFAULT 0;
    LET v_tier_avg_home_dist FLOAT DEFAULT 0;
    LET v_tier_pct_drove FLOAT DEFAULT 0;
    LET v_tier_pct_no_prev_season_games FLOAT DEFAULT 0;
    LET v_tier_pct_concess_wait_long FLOAT DEFAULT 0;
    LET v_tier_pct_parking_arrival_long FLOAT DEFAULT 0;
    LET v_tier_pct_parking_exit_long FLOAT DEFAULT 0;
    LET v_tier_pct_travel_longer FLOAT DEFAULT 0;
    LET v_tier_pct_gate_entry_long FLOAT DEFAULT 0;
    LET v_tier_pct_bought_concessions FLOAT DEFAULT 0;
    LET v_tier_pct_bought_merch FLOAT DEFAULT 0;
    LET v_tier_pct_mobile_order FLOAT DEFAULT 0;
    LET v_tier_pct_concess_spend_high FLOAT DEFAULT 0;

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
        RETURN 'No game data found.';
    END IF;

    -- =============================================
    -- HEADER: Game date, opponent, day of week, opponent logo (base64)
    -- =============================================
    -- The opponent logo base64 is generated inline to avoid passing a bind variable
    -- through BUILD_SCOPED_FILE_URL, which can fail in procedure context.
    SELECT
        DECODE(DAYNAME(GAME_DATE::DATE),
            'Mon','Monday','Tue','Tuesday','Wed','Wednesday',
            'Thu','Thursday','Fri','Friday','Sat','Saturday','Sun','Sunday'),
        AWAYTRI,
        TO_VARCHAR(GAME_DATE::DATE, 'MMMM DD'),
        SEASON,
        TBRDP_DW_DEV.IM_RPT.READ_STAGE_FILE_BASE64(
            BUILD_SCOPED_FILE_URL(@TBRDP_DW_DEV.IM_RPT.MLB_LOGOS_STAGE,
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
                    ELSE 'TB_Full_Color_WHITE_RGB (1).png'
                END
            )
        )
    INTO :v_day_of_week, :v_opponent, :v_game_date_display, :v_season, :v_opponent_logo_url
    FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
    WHERE GAME_DATE::DATE = :v_target_game_date
      AND AWAYTRI IS NOT NULL
    LIMIT 1;

    v_header_line := v_day_of_week || ', ' || v_game_date_display || ' vs ' || v_opponent;

    -- Embed Rays logo as base64 data URI
    SELECT TBRDP_DW_DEV.IM_RPT.READ_STAGE_FILE_BASE64(
        BUILD_SCOPED_FILE_URL(@TBRDP_DW_DEV.IM_RPT.MLB_LOGOS_STAGE, 'TB_White.png')
    )
    INTO :v_rays_logo_url;

    -- =============================================
    -- SECTION 1: OVERALL — Game score vs season
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
      AND OVERALL_NUMRAT IS NOT NULL
      AND GAME_DATE::DATE != :v_target_game_date;

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
    -- Sentence-level: each response split into sentences,
    -- classified into 61 fine-grained categories.
    -- Source: T_OVERALL_FEEDBACK_SENTENCE_LEVEL
    -- No department names displayed in output.
    -- =============================================
    -- IMPORTANT: Cursors use RESULTSET pattern because
    -- LET c CURSOR FOR SELECT... cannot see LET-declared variables.
    -- Pattern: LET rs RESULTSET := (SELECT ...); LET c CURSOR FOR rs;

    SELECT
        COUNT(CASE WHEN sentiment_category = 'Positive' THEN 1 END),
        COUNT(CASE WHEN sentiment_category = 'Negative' THEN 1 END)
    INTO :v_positive_total, :v_negative_total
    FROM TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL
    WHERE GAME_DATE::DATE = :v_target_game_date
      AND ai_category IS NOT NULL
      AND ai_category != 'Unclassifiable'
      AND sentiment_category IN ('Positive', 'Negative');

    v_feedback_total := v_positive_total + v_negative_total;
    v_positive_pct := CASE WHEN v_feedback_total > 0
        THEN ROUND(100.0 * v_positive_total / v_feedback_total, 0)::VARCHAR
        ELSE '0' END;
    v_negative_pct := CASE WHEN v_feedback_total > 0
        THEN ROUND(100.0 * v_negative_total / v_feedback_total, 0)::VARCHAR
        ELSE '0' END;

    -- Top 3 Positive topics (exclude General Positive/Negative — non-actionable catch-all categories)
    LET rs_pos RESULTSET := (
        SELECT ai_category,
            ROUND(100.0 * COUNT(*) / NULLIF(
                (SELECT COUNT(*) FROM TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL
                 WHERE GAME_DATE::DATE = :v_target_game_date
                   AND sentiment_category = 'Positive'
                   AND ai_category IS NOT NULL
                   AND ai_category NOT IN ('General Positive', 'General Negative', 'Team Performance', 'Unclassifiable')),
            0), 1) AS pct
        FROM TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL
        WHERE GAME_DATE::DATE = :v_target_game_date
          AND sentiment_category = 'Positive'
          AND ai_category IS NOT NULL
          AND ai_category NOT IN ('General Positive', 'General Negative', 'Team Performance', 'Unclassifiable')
        GROUP BY ai_category
        ORDER BY COUNT(*) DESC
        LIMIT 3
    );
    LET c_pos CURSOR FOR rs_pos;
    LET v_rank NUMBER := 0;
    FOR rec IN c_pos DO
        v_rank := v_rank + 1;
        IF (v_rank = 1) THEN v_pos_topic_1 := rec.ai_category; v_pos_topic_1_pct := rec.pct::VARCHAR;
        ELSEIF (v_rank = 2) THEN v_pos_topic_2 := rec.ai_category; v_pos_topic_2_pct := rec.pct::VARCHAR;
        ELSEIF (v_rank = 3) THEN v_pos_topic_3 := rec.ai_category; v_pos_topic_3_pct := rec.pct::VARCHAR;
        END IF;
    END FOR;

    -- Top 3 Negative topics (exclude General Positive/Negative — non-actionable catch-all categories)
    LET rs_neg RESULTSET := (
        SELECT ai_category,
            ROUND(100.0 * COUNT(*) / NULLIF(
                (SELECT COUNT(*) FROM TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL
                 WHERE GAME_DATE::DATE = :v_target_game_date
                   AND sentiment_category = 'Negative'
                   AND ai_category IS NOT NULL
                   AND ai_category NOT IN ('General Positive', 'General Negative', 'Team Performance', 'Unclassifiable')),
            0), 1) AS pct
        FROM TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL
        WHERE GAME_DATE::DATE = :v_target_game_date
          AND sentiment_category = 'Negative'
          AND ai_category IS NOT NULL
          AND ai_category NOT IN ('General Positive', 'General Negative', 'Team Performance', 'Unclassifiable')
        GROUP BY ai_category
        ORDER BY COUNT(*) DESC
        LIMIT 3
    );
    LET c_neg CURSOR FOR rs_neg;
    v_rank := 0;
    FOR rec IN c_neg DO
        v_rank := v_rank + 1;
        IF (v_rank = 1) THEN v_neg_topic_1 := rec.ai_category; v_neg_topic_1_pct := rec.pct::VARCHAR;
        ELSEIF (v_rank = 2) THEN v_neg_topic_2 := rec.ai_category; v_neg_topic_2_pct := rec.pct::VARCHAR;
        ELSEIF (v_rank = 3) THEN v_neg_topic_3 := rec.ai_category; v_neg_topic_3_pct := rec.pct::VARCHAR;
        END IF;
    END FOR;

    -- =============================================
    -- SECTION 2B: QUALITATIVE DEEP DIVE CSV EXPORT
    -- Export sentence-level comments to CSV on stage for email download link
    -- =============================================
    v_csv_filename := 'qualitative_deep_dive_' || REPLACE(:v_target_game_date::VARCHAR, '-', '') || '.csv';

    v_csv_sql := '
        COPY INTO @TBRDP_DW_DEV.IM_RPT.VOC_REPORT_CSV_STAGE/' || :v_csv_filename || '
        FROM (
            SELECT
                SENTENCE_TEXT AS "Comment",
                DETAILED_CATEGORY AS "Category",
                SENTIMENT_CATEGORY AS "Sentiment",
                BUYER_TYPE AS "Buyer Type",
                SATISFACTION_RATING AS "Rating (1-10)"
            FROM TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL
            WHERE GAME_DATE::DATE = ''' || :v_target_game_date::VARCHAR || '''
            ORDER BY DETAILED_CATEGORY, SENTIMENT_CATEGORY
        )
        FILE_FORMAT = (TYPE = ''CSV'' FIELD_OPTIONALLY_ENCLOSED_BY = ''"'' COMPRESSION = ''NONE'')
        HEADER = TRUE
        OVERWRITE = TRUE
        SINGLE = TRUE;
    ';
    EXECUTE IMMEDIATE :v_csv_sql;

    v_csv_sql := 'SELECT GET_PRESIGNED_URL(@TBRDP_DW_DEV.IM_RPT.VOC_REPORT_CSV_STAGE, ''' || :v_csv_filename || ''', 604800) AS url';
    LET rs_csv RESULTSET := (EXECUTE IMMEDIATE :v_csv_sql);
    LET c_csv CURSOR FOR rs_csv;
    FOR rec_csv IN c_csv DO
        v_csv_url := rec_csv.url;
    END FOR;

    -- =============================================
    -- SECTION 3: QUANTITATIVE SUMMARY
    -- Game vs Season metric comparison (~30 metrics, satisfaction extremes)
    -- Top 3 best improvements, Top 3 worst regressions
    -- Positive: "Fans highly satisfied with X was Y% higher"
    -- Negative: "Fans highly dissatisfied with X was Y% higher"
    -- Improvement calc: game_val - season_val (all metrics are percentages)
    -- =============================================

    -- Top 3 BEST improvements (% highly satisfied / % 9-10 scores, game vs season)
    LET rs_best RESULTSET := (
        WITH game AS (
            SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
            WHERE GAME_DATE::DATE = :v_target_game_date
        ),
        season AS (
            SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
            WHERE SEASON = :v_season AND OVERALL_NUMRAT IS NOT NULL
              AND GAME_DATE::DATE != :v_target_game_date
        ),
        metrics AS (
            -- 0-10 Numeric Ratings: % of 9-10 responses (top scores)
            SELECT 'Overall Rating' AS metric_label, 'General' AS dept, '% Top Scores' AS unit,
                ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT >= 9 AND OVERALL_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT IS NOT NULL AND OVERALL_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) AS game_val,
                (SELECT ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT >= 9 AND OVERALL_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT IS NOT NULL AND OVERALL_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season) AS season_val,
                SUM(CASE WHEN OVERALL_NUMRAT IS NOT NULL AND OVERALL_NUMRAT < 80 THEN 1 ELSE 0 END) AS n
            FROM game
            UNION ALL
            SELECT 'Concession Rating', 'Concessions', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN CONCESS_NUMRAT >= 9 AND CONCESS_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_NUMRAT IS NOT NULL AND CONCESS_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_NUMRAT >= 9 AND CONCESS_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_NUMRAT IS NOT NULL AND CONCESS_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_NUMRAT IS NOT NULL AND CONCESS_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Parking Rating', 'Parking', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN PARKING_NUMRAT >= 9 AND PARKING_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PARKING_NUMRAT IS NOT NULL AND PARKING_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN PARKING_NUMRAT >= 9 AND PARKING_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PARKING_NUMRAT IS NOT NULL AND PARKING_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN PARKING_NUMRAT IS NOT NULL AND PARKING_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Entertainment Rating', 'Game Entertainment', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_NUMRAT >= 9 AND ENTERTAIN_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_NUMRAT IS NOT NULL AND ENTERTAIN_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_NUMRAT >= 9 AND ENTERTAIN_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_NUMRAT IS NOT NULL AND ENTERTAIN_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_NUMRAT IS NOT NULL AND ENTERTAIN_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Rating', 'Retail', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN MERCH_NUMRAT >= 9 AND MERCH_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_NUMRAT IS NOT NULL AND MERCH_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_NUMRAT >= 9 AND MERCH_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_NUMRAT IS NOT NULL AND MERCH_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_NUMRAT IS NOT NULL AND MERCH_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff Rating', 'Operations', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN STAFF_NUMRAT >= 9 AND STAFF_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN STAFF_NUMRAT IS NOT NULL AND STAFF_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN STAFF_NUMRAT >= 9 AND STAFF_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN STAFF_NUMRAT IS NOT NULL AND STAFF_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN STAFF_NUMRAT IS NOT NULL AND STAFF_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Seat View Rating', 'General', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN SEATVIEW_NUMRAT >= 9 AND SEATVIEW_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN SEATVIEW_NUMRAT IS NOT NULL AND SEATVIEW_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN SEATVIEW_NUMRAT >= 9 AND SEATVIEW_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN SEATVIEW_NUMRAT IS NOT NULL AND SEATVIEW_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN SEATVIEW_NUMRAT IS NOT NULL AND SEATVIEW_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Concession Grid: % Highly satisfied
            SELECT 'Concession Value', 'Concessions', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_VALUE_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_VALUE_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Concession Service', 'Concessions', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Concession Selection', 'Concessions', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Concession Cleanliness', 'Concessions', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Merchandise Grid: % Highly satisfied
            SELECT 'Merch Pricing', 'Retail', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_PRICE_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_PRICE_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Selection', 'Retail', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_SELECTION_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_SELECTION_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Quality', 'Retail', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Wait Time', 'Retail', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_WAIT_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_WAIT_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Customer Service', 'Retail', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Entertainment Grid: % Highly satisfied
            SELECT 'In-Game Music', 'Game Entertainment', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'In-Game Activities', 'Game Entertainment', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Scoreboard', 'Game Entertainment', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Game Theme', 'Game Entertainment', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Kids Activities', 'Game Entertainment', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IS NOT NULL AND ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IS NOT NULL AND ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IS NOT NULL AND ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Pregame Content', 'Game Entertainment', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IS NOT NULL AND ENTERTAIN_GRID_PREGAME_CONTENT_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IS NOT NULL AND ENTERTAIN_GRID_PREGAME_CONTENT_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IS NOT NULL AND ENTERTAIN_GRID_PREGAME_CONTENT_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Food Quality Grid: % Highly satisfied
            SELECT 'FQ: Alcoholic Beverages', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_ALCOHOL_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_ALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_ALCOHOL_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_ALCOHOL_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_ALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_ALCOHOL_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_ALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_ALCOHOL_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Non-Alcoholic Beverages', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_NONALCOHOL_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_NONALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_NONALCOHOL_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_NONALCOHOL_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_NONALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_NONALCOHOL_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_NONALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_NONALCOHOL_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Hot Dogs', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_HOTDOG_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_HOTDOG_DESC IS NOT NULL AND CONCESS_QUALITY_HOTDOG_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_HOTDOG_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_HOTDOG_DESC IS NOT NULL AND CONCESS_QUALITY_HOTDOG_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_HOTDOG_DESC IS NOT NULL AND CONCESS_QUALITY_HOTDOG_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Chicken Tenders', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_CHICKEN_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_CHICKEN_DESC IS NOT NULL AND CONCESS_QUALITY_CHICKEN_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_CHICKEN_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_CHICKEN_DESC IS NOT NULL AND CONCESS_QUALITY_CHICKEN_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_CHICKEN_DESC IS NOT NULL AND CONCESS_QUALITY_CHICKEN_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Fries', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_FRIES_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_FRIES_DESC IS NOT NULL AND CONCESS_QUALITY_FRIES_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_FRIES_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_FRIES_DESC IS NOT NULL AND CONCESS_QUALITY_FRIES_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_FRIES_DESC IS NOT NULL AND CONCESS_QUALITY_FRIES_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Nachos', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_NACHOS_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_NACHOS_DESC IS NOT NULL AND CONCESS_QUALITY_NACHOS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_NACHOS_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_NACHOS_DESC IS NOT NULL AND CONCESS_QUALITY_NACHOS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_NACHOS_DESC IS NOT NULL AND CONCESS_QUALITY_NACHOS_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Pizza', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_PIZZA_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_PIZZA_DESC IS NOT NULL AND CONCESS_QUALITY_PIZZA_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_PIZZA_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_PIZZA_DESC IS NOT NULL AND CONCESS_QUALITY_PIZZA_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_PIZZA_DESC IS NOT NULL AND CONCESS_QUALITY_PIZZA_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Popcorn', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_POPCORN_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_POPCORN_DESC IS NOT NULL AND CONCESS_QUALITY_POPCORN_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_POPCORN_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_POPCORN_DESC IS NOT NULL AND CONCESS_QUALITY_POPCORN_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_POPCORN_DESC IS NOT NULL AND CONCESS_QUALITY_POPCORN_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Pretzels', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_PRETZELS_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_PRETZELS_DESC IS NOT NULL AND CONCESS_QUALITY_PRETZELS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_PRETZELS_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_PRETZELS_DESC IS NOT NULL AND CONCESS_QUALITY_PRETZELS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_PRETZELS_DESC IS NOT NULL AND CONCESS_QUALITY_PRETZELS_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Sausage', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_SAUSAGE_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_SAUSAGE_DESC IS NOT NULL AND CONCESS_QUALITY_SAUSAGE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_SAUSAGE_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_SAUSAGE_DESC IS NOT NULL AND CONCESS_QUALITY_SAUSAGE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_SAUSAGE_DESC IS NOT NULL AND CONCESS_QUALITY_SAUSAGE_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Peanuts/Nuts', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_NUTS_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_NUTS_DESC IS NOT NULL AND CONCESS_QUALITY_NUTS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_NUTS_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_NUTS_DESC IS NOT NULL AND CONCESS_QUALITY_NUTS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_NUTS_DESC IS NOT NULL AND CONCESS_QUALITY_NUTS_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Ice Cream', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_ICECREAM_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_ICECREAM_DESC IS NOT NULL AND CONCESS_QUALITY_ICECREAM_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_ICECREAM_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_ICECREAM_DESC IS NOT NULL AND CONCESS_QUALITY_ICECREAM_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_ICECREAM_DESC IS NOT NULL AND CONCESS_QUALITY_ICECREAM_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Sandwiches', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_SANDWICH_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_SANDWICH_DESC IS NOT NULL AND CONCESS_QUALITY_SANDWICH_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_SANDWICH_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_SANDWICH_DESC IS NOT NULL AND CONCESS_QUALITY_SANDWICH_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_SANDWICH_DESC IS NOT NULL AND CONCESS_QUALITY_SANDWICH_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Burgers', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_BURGERS_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_BURGERS_DESC IS NOT NULL AND CONCESS_QUALITY_BURGERS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_BURGERS_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_BURGERS_DESC IS NOT NULL AND CONCESS_QUALITY_BURGERS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_BURGERS_DESC IS NOT NULL AND CONCESS_QUALITY_BURGERS_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Salad', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_SALAD_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_SALAD_DESC IS NOT NULL AND CONCESS_QUALITY_SALAD_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_SALAD_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_SALAD_DESC IS NOT NULL AND CONCESS_QUALITY_SALAD_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_SALAD_DESC IS NOT NULL AND CONCESS_QUALITY_SALAD_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Other Entrees', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_OTHER_ENTREE_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_OTHER_ENTREE_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_ENTREE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_OTHER_ENTREE_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_OTHER_ENTREE_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_ENTREE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_OTHER_ENTREE_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_ENTREE_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Other Desserts', 'Food Quality', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_OTHER_DESSERT_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_OTHER_DESSERT_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_DESSERT_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_OTHER_DESSERT_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_OTHER_DESSERT_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_DESSERT_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_OTHER_DESSERT_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_DESSERT_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Staff Ratings (0-10 scale, TB_ADDON_23_*): % Top Scores (>=9)
            SELECT 'Staff: Parking (0-10)', 'Staff', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_1 >= 9 AND TB_ADDON_23_1 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_1 IS NOT NULL AND TB_ADDON_23_1 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_1 >= 9 AND TB_ADDON_23_1 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_1 IS NOT NULL AND TB_ADDON_23_1 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_1 IS NOT NULL AND TB_ADDON_23_1 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Fan Host/Usher (0-10)', 'Staff', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_3 >= 9 AND TB_ADDON_23_3 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_3 IS NOT NULL AND TB_ADDON_23_3 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_3 >= 9 AND TB_ADDON_23_3 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_3 IS NOT NULL AND TB_ADDON_23_3 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_3 IS NOT NULL AND TB_ADDON_23_3 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Concessions (0-10)', 'Staff', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_5 >= 9 AND TB_ADDON_23_5 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_5 IS NOT NULL AND TB_ADDON_23_5 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_5 >= 9 AND TB_ADDON_23_5 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_5 IS NOT NULL AND TB_ADDON_23_5 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_5 IS NOT NULL AND TB_ADDON_23_5 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Retail/Team Store (0-10)', 'Staff', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_6 >= 9 AND TB_ADDON_23_6 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_6 IS NOT NULL AND TB_ADDON_23_6 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_6 >= 9 AND TB_ADDON_23_6 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_6 IS NOT NULL AND TB_ADDON_23_6 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_6 IS NOT NULL AND TB_ADDON_23_6 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Wheelchair Team (0-10)', 'Staff', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_24 >= 9 AND TB_ADDON_23_24 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_24 IS NOT NULL AND TB_ADDON_23_24 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_24 >= 9 AND TB_ADDON_23_24 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_24 IS NOT NULL AND TB_ADDON_23_24 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_24 IS NOT NULL AND TB_ADDON_23_24 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Tech Team (0-10)', 'Staff', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_38 >= 9 AND TB_ADDON_23_38 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_38 IS NOT NULL AND TB_ADDON_23_38 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_38 >= 9 AND TB_ADDON_23_38 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_38 IS NOT NULL AND TB_ADDON_23_38 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_38 IS NOT NULL AND TB_ADDON_23_38 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Security (0-10)', 'Staff', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_60 >= 9 AND TB_ADDON_23_60 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_60 IS NOT NULL AND TB_ADDON_23_60 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_60 >= 9 AND TB_ADDON_23_60 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_60 IS NOT NULL AND TB_ADDON_23_60 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_60 IS NOT NULL AND TB_ADDON_23_60 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Ticket Scanner (0-10)', 'Staff', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_61 >= 9 AND TB_ADDON_23_61 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_61 IS NOT NULL AND TB_ADDON_23_61 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_61 >= 9 AND TB_ADDON_23_61 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_61 IS NOT NULL AND TB_ADDON_23_61 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_61 IS NOT NULL AND TB_ADDON_23_61 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Go-Ahead Entry (0-10)', 'Staff', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_67 >= 9 AND TB_ADDON_23_67 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_67 IS NOT NULL AND TB_ADDON_23_67 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_67 >= 9 AND TB_ADDON_23_67 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_67 IS NOT NULL AND TB_ADDON_23_67 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_67 IS NOT NULL AND TB_ADDON_23_67 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Concession Speed (coded 1-4 satisfaction): % Highly Satisfied (=1)
            SELECT 'Concession Speed', 'Concessions', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_SPEED = 1 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_SPEED IS NOT NULL AND CONCESS_GRID_SPEED <= 4 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_SPEED = 1 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_SPEED IS NOT NULL AND CONCESS_GRID_SPEED <= 4 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_SPEED IS NOT NULL AND CONCESS_GRID_SPEED <= 4 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Preparedness Satisfaction (coded 1-4): % Highly Satisfied (=1)
            SELECT 'Preparedness Info', 'Operations', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN PREPARED_SAT = 1 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PREPARED_SAT IS NOT NULL AND PREPARED_SAT <= 4 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN PREPARED_SAT = 1 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PREPARED_SAT IS NOT NULL AND PREPARED_SAT <= 4 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN PREPARED_SAT IS NOT NULL AND PREPARED_SAT <= 4 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Gate Entry Score (0-10 scale): % Top Scores (>=9)
            SELECT 'Gate Entry Score', 'Operations', '% Top Scores',
                ROUND(100.0*SUM(CASE WHEN GE_NUMRAT >= 9 AND GE_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN GE_NUMRAT IS NOT NULL AND GE_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN GE_NUMRAT >= 9 AND GE_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN GE_NUMRAT IS NOT NULL AND GE_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN GE_NUMRAT IS NOT NULL AND GE_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Purchase Intent: % Yes I Do
            SELECT 'Purchase Intent', 'General', '% Yes I Do',
                ROUND(100.0*SUM(CASE WHEN PURCHASE_INTENT_DESC = 'Yes, I do' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PURCHASE_INTENT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN PURCHASE_INTENT_DESC = 'Yes, I do' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PURCHASE_INTENT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN PURCHASE_INTENT_DESC IS NOT NULL THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Gate Entry Wait vs Expectations: % Less Than Expected
            SELECT 'Gate Entry Wait', 'Operations', '% Less Than Expected',
                ROUND(100.0*SUM(CASE WHEN GE_TIME_EXPECT_DESC = 'Less than what I expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN GE_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN GE_TIME_EXPECT_DESC = 'Less than what I expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN GE_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN GE_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Concession Wait vs Expectations: % Much Less Than Expected
            SELECT 'Concession Wait Expect', 'Concessions', '% Much Less Than Expected',
                ROUND(100.0*SUM(CASE WHEN CONCESS_WAIT_EXPECT_DESC = 'Much less than what I expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_WAIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_WAIT_EXPECT_DESC = 'Much less than what I expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_WAIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_WAIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Giveaway Satisfaction: % Highly Satisfied
            SELECT 'Giveaway Satisfaction', 'Promotions', '% Highly Satisfied',
                ROUND(100.0*SUM(CASE WHEN GIVEAWAY_SAT_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN GIVEAWAY_SAT_DESC IS NOT NULL AND GIVEAWAY_SAT_DESC NOT IN ('N/A', '5') THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN GIVEAWAY_SAT_DESC = 'Highly satisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN GIVEAWAY_SAT_DESC IS NOT NULL AND GIVEAWAY_SAT_DESC NOT IN ('N/A', '5') THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN GIVEAWAY_SAT_DESC IS NOT NULL AND GIVEAWAY_SAT_DESC NOT IN ('N/A', '5') THEN 1 ELSE 0 END)
            FROM game
        ),
        scored AS (
            SELECT metric_label, dept, unit, game_val, season_val, n,
                ROUND(game_val - season_val, 2) AS improvement
            FROM metrics
            WHERE game_val IS NOT NULL AND season_val IS NOT NULL AND n >= 20
              AND game_val != 0 AND season_val != 0
              AND ROUND(game_val - season_val, 2) > 0
        )
        SELECT metric_label, dept, unit, improvement
        FROM scored ORDER BY improvement DESC LIMIT 3
    );
    LET c_best CURSOR FOR rs_best;
    v_rank := 0;
    FOR rec IN c_best DO
        v_rank := v_rank + 1;
        IF (v_rank = 1) THEN
            v_best1_label := rec.metric_label; v_best1_dept := rec.dept;
            v_best1_delta := ABS(rec.improvement)::VARCHAR; v_best1_unit := rec.unit;
            v_best1_suffix := '% higher';
        ELSEIF (v_rank = 2) THEN
            v_best2_label := rec.metric_label; v_best2_dept := rec.dept;
            v_best2_delta := ABS(rec.improvement)::VARCHAR; v_best2_unit := rec.unit;
            v_best2_suffix := '% higher';
        ELSEIF (v_rank = 3) THEN
            v_best3_label := rec.metric_label; v_best3_dept := rec.dept;
            v_best3_delta := ABS(rec.improvement)::VARCHAR; v_best3_unit := rec.unit;
            v_best3_suffix := '% higher';
        END IF;
    END FOR;

    -- Top 3 WORST regressions (% highly dissatisfied / % 0-7 scores, game vs season)
    LET rs_worst RESULTSET := (
        WITH game AS (
            SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
            WHERE GAME_DATE::DATE = :v_target_game_date
        ),
        season AS (
            SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
            WHERE SEASON = :v_season AND OVERALL_NUMRAT IS NOT NULL
              AND GAME_DATE::DATE != :v_target_game_date
        ),
        metrics AS (
            -- 0-10 Numeric Ratings: % of 0-7 responses (low scores)
            SELECT 'Overall Rating' AS metric_label, 'General' AS dept, '% Low Scores' AS unit,
                ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT <= 7 AND OVERALL_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT IS NOT NULL AND OVERALL_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) AS game_val,
                (SELECT ROUND(100.0*SUM(CASE WHEN OVERALL_NUMRAT <= 7 AND OVERALL_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN OVERALL_NUMRAT IS NOT NULL AND OVERALL_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season) AS season_val,
                SUM(CASE WHEN OVERALL_NUMRAT IS NOT NULL AND OVERALL_NUMRAT < 80 THEN 1 ELSE 0 END) AS n
            FROM game
            UNION ALL
            SELECT 'Concession Rating', 'Concessions', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN CONCESS_NUMRAT <= 7 AND CONCESS_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_NUMRAT IS NOT NULL AND CONCESS_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_NUMRAT <= 7 AND CONCESS_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_NUMRAT IS NOT NULL AND CONCESS_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_NUMRAT IS NOT NULL AND CONCESS_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Parking Rating', 'Parking', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN PARKING_NUMRAT <= 7 AND PARKING_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PARKING_NUMRAT IS NOT NULL AND PARKING_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN PARKING_NUMRAT <= 7 AND PARKING_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PARKING_NUMRAT IS NOT NULL AND PARKING_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN PARKING_NUMRAT IS NOT NULL AND PARKING_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Entertainment Rating', 'Game Entertainment', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_NUMRAT <= 7 AND ENTERTAIN_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_NUMRAT IS NOT NULL AND ENTERTAIN_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_NUMRAT <= 7 AND ENTERTAIN_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_NUMRAT IS NOT NULL AND ENTERTAIN_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_NUMRAT IS NOT NULL AND ENTERTAIN_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Rating', 'Retail', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN MERCH_NUMRAT <= 7 AND MERCH_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_NUMRAT IS NOT NULL AND MERCH_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_NUMRAT <= 7 AND MERCH_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_NUMRAT IS NOT NULL AND MERCH_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_NUMRAT IS NOT NULL AND MERCH_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff Rating', 'Operations', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN STAFF_NUMRAT <= 7 AND STAFF_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN STAFF_NUMRAT IS NOT NULL AND STAFF_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN STAFF_NUMRAT <= 7 AND STAFF_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN STAFF_NUMRAT IS NOT NULL AND STAFF_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN STAFF_NUMRAT IS NOT NULL AND STAFF_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Seat View Rating', 'General', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN SEATVIEW_NUMRAT <= 7 AND SEATVIEW_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN SEATVIEW_NUMRAT IS NOT NULL AND SEATVIEW_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN SEATVIEW_NUMRAT <= 7 AND SEATVIEW_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN SEATVIEW_NUMRAT IS NOT NULL AND SEATVIEW_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN SEATVIEW_NUMRAT IS NOT NULL AND SEATVIEW_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Concession Grid: % Highly dissatisfied
            SELECT 'Concession Value', 'Concessions', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_VALUE_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_VALUE_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_VALUE_DESC IS NOT NULL AND CONCESS_GRID_VALUE_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Concession Service', 'Concessions', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_CUSTSERV_DESC IS NOT NULL AND CONCESS_GRID_CUSTSERV_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Concession Selection', 'Concessions', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_SELECTION_DESC IS NOT NULL AND CONCESS_GRID_SELECTION_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Concession Cleanliness', 'Concessions', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_CLEAN_DESC IS NOT NULL AND CONCESS_GRID_CLEAN_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Merchandise Grid: % Highly dissatisfied
            SELECT 'Merch Pricing', 'Retail', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_PRICE_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_PRICE_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_PRICE_DESC IS NOT NULL AND MERCH_GRID_PRICE_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Selection', 'Retail', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_SELECTION_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_SELECTION_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_SELECTION_DESC IS NOT NULL AND MERCH_GRID_SELECTION_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Quality', 'Retail', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_MERCHQUALITY_DESC IS NOT NULL AND MERCH_GRID_MERCHQUALITY_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Wait Time', 'Retail', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_WAIT_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_WAIT_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_WAIT_DESC IS NOT NULL AND MERCH_GRID_WAIT_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Merch Customer Service', 'Retail', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN MERCH_GRID_CUSTSERV_DESC IS NOT NULL AND MERCH_GRID_CUSTSERV_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Entertainment Grid: % Highly dissatisfied
            SELECT 'In-Game Music', 'Game Entertainment', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_MUSIC_DESC IS NOT NULL AND ENTERTAIN_GRID_MUSIC_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'In-Game Activities', 'Game Entertainment', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_GAMES_DESC IS NOT NULL AND ENTERTAIN_GRID_GAMES_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Scoreboard', 'Game Entertainment', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_SCOREBOARD_DESC IS NOT NULL AND ENTERTAIN_GRID_SCOREBOARD_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Game Theme', 'Game Entertainment', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_THEME_DESC IS NOT NULL AND ENTERTAIN_GRID_THEME_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Kids Activities', 'Game Entertainment', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IS NOT NULL AND ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IS NOT NULL AND ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC IS NOT NULL AND ENTERTAIN_GRID_KIDS_ACTIVITIES_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Pregame Content', 'Game Entertainment', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IS NOT NULL AND ENTERTAIN_GRID_PREGAME_CONTENT_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IS NOT NULL AND ENTERTAIN_GRID_PREGAME_CONTENT_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN ENTERTAIN_GRID_PREGAME_CONTENT_DESC IS NOT NULL AND ENTERTAIN_GRID_PREGAME_CONTENT_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Food Quality Grid: % Highly dissatisfied
            SELECT 'FQ: Alcoholic Beverages', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_ALCOHOL_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_ALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_ALCOHOL_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_ALCOHOL_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_ALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_ALCOHOL_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_ALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_ALCOHOL_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Non-Alcoholic Beverages', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_NONALCOHOL_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_NONALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_NONALCOHOL_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_NONALCOHOL_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_NONALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_NONALCOHOL_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_NONALCOHOL_DESC IS NOT NULL AND CONCESS_QUALITY_NONALCOHOL_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Hot Dogs', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_HOTDOG_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_HOTDOG_DESC IS NOT NULL AND CONCESS_QUALITY_HOTDOG_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_HOTDOG_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_HOTDOG_DESC IS NOT NULL AND CONCESS_QUALITY_HOTDOG_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_HOTDOG_DESC IS NOT NULL AND CONCESS_QUALITY_HOTDOG_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Chicken Tenders', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_CHICKEN_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_CHICKEN_DESC IS NOT NULL AND CONCESS_QUALITY_CHICKEN_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_CHICKEN_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_CHICKEN_DESC IS NOT NULL AND CONCESS_QUALITY_CHICKEN_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_CHICKEN_DESC IS NOT NULL AND CONCESS_QUALITY_CHICKEN_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Fries', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_FRIES_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_FRIES_DESC IS NOT NULL AND CONCESS_QUALITY_FRIES_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_FRIES_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_FRIES_DESC IS NOT NULL AND CONCESS_QUALITY_FRIES_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_FRIES_DESC IS NOT NULL AND CONCESS_QUALITY_FRIES_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Nachos', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_NACHOS_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_NACHOS_DESC IS NOT NULL AND CONCESS_QUALITY_NACHOS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_NACHOS_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_NACHOS_DESC IS NOT NULL AND CONCESS_QUALITY_NACHOS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_NACHOS_DESC IS NOT NULL AND CONCESS_QUALITY_NACHOS_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Pizza', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_PIZZA_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_PIZZA_DESC IS NOT NULL AND CONCESS_QUALITY_PIZZA_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_PIZZA_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_PIZZA_DESC IS NOT NULL AND CONCESS_QUALITY_PIZZA_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_PIZZA_DESC IS NOT NULL AND CONCESS_QUALITY_PIZZA_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Popcorn', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_POPCORN_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_POPCORN_DESC IS NOT NULL AND CONCESS_QUALITY_POPCORN_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_POPCORN_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_POPCORN_DESC IS NOT NULL AND CONCESS_QUALITY_POPCORN_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_POPCORN_DESC IS NOT NULL AND CONCESS_QUALITY_POPCORN_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Pretzels', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_PRETZELS_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_PRETZELS_DESC IS NOT NULL AND CONCESS_QUALITY_PRETZELS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_PRETZELS_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_PRETZELS_DESC IS NOT NULL AND CONCESS_QUALITY_PRETZELS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_PRETZELS_DESC IS NOT NULL AND CONCESS_QUALITY_PRETZELS_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Sausage', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_SAUSAGE_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_SAUSAGE_DESC IS NOT NULL AND CONCESS_QUALITY_SAUSAGE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_SAUSAGE_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_SAUSAGE_DESC IS NOT NULL AND CONCESS_QUALITY_SAUSAGE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_SAUSAGE_DESC IS NOT NULL AND CONCESS_QUALITY_SAUSAGE_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Peanuts/Nuts', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_NUTS_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_NUTS_DESC IS NOT NULL AND CONCESS_QUALITY_NUTS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_NUTS_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_NUTS_DESC IS NOT NULL AND CONCESS_QUALITY_NUTS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_NUTS_DESC IS NOT NULL AND CONCESS_QUALITY_NUTS_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Ice Cream', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_ICECREAM_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_ICECREAM_DESC IS NOT NULL AND CONCESS_QUALITY_ICECREAM_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_ICECREAM_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_ICECREAM_DESC IS NOT NULL AND CONCESS_QUALITY_ICECREAM_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_ICECREAM_DESC IS NOT NULL AND CONCESS_QUALITY_ICECREAM_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Sandwiches', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_SANDWICH_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_SANDWICH_DESC IS NOT NULL AND CONCESS_QUALITY_SANDWICH_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_SANDWICH_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_SANDWICH_DESC IS NOT NULL AND CONCESS_QUALITY_SANDWICH_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_SANDWICH_DESC IS NOT NULL AND CONCESS_QUALITY_SANDWICH_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Burgers', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_BURGERS_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_BURGERS_DESC IS NOT NULL AND CONCESS_QUALITY_BURGERS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_BURGERS_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_BURGERS_DESC IS NOT NULL AND CONCESS_QUALITY_BURGERS_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_BURGERS_DESC IS NOT NULL AND CONCESS_QUALITY_BURGERS_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Salad', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_SALAD_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_SALAD_DESC IS NOT NULL AND CONCESS_QUALITY_SALAD_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_SALAD_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_SALAD_DESC IS NOT NULL AND CONCESS_QUALITY_SALAD_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_SALAD_DESC IS NOT NULL AND CONCESS_QUALITY_SALAD_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Other Entrees', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_OTHER_ENTREE_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_OTHER_ENTREE_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_ENTREE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_OTHER_ENTREE_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_OTHER_ENTREE_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_ENTREE_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_OTHER_ENTREE_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_ENTREE_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'FQ: Other Desserts', 'Food Quality', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_OTHER_DESSERT_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_OTHER_DESSERT_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_DESSERT_DESC != 'N/A' THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_QUALITY_OTHER_DESSERT_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_QUALITY_OTHER_DESSERT_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_DESSERT_DESC != 'N/A' THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_QUALITY_OTHER_DESSERT_DESC IS NOT NULL AND CONCESS_QUALITY_OTHER_DESSERT_DESC != 'N/A' THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Staff Ratings (0-10 scale, TB_ADDON_23_*): % Low Scores (<=7)
            SELECT 'Staff: Parking (0-10)', 'Staff', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_1 <= 7 AND TB_ADDON_23_1 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_1 IS NOT NULL AND TB_ADDON_23_1 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_1 <= 7 AND TB_ADDON_23_1 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_1 IS NOT NULL AND TB_ADDON_23_1 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_1 IS NOT NULL AND TB_ADDON_23_1 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Fan Host/Usher (0-10)', 'Staff', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_3 <= 7 AND TB_ADDON_23_3 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_3 IS NOT NULL AND TB_ADDON_23_3 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_3 <= 7 AND TB_ADDON_23_3 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_3 IS NOT NULL AND TB_ADDON_23_3 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_3 IS NOT NULL AND TB_ADDON_23_3 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Concessions (0-10)', 'Staff', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_5 <= 7 AND TB_ADDON_23_5 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_5 IS NOT NULL AND TB_ADDON_23_5 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_5 <= 7 AND TB_ADDON_23_5 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_5 IS NOT NULL AND TB_ADDON_23_5 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_5 IS NOT NULL AND TB_ADDON_23_5 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Retail/Team Store (0-10)', 'Staff', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_6 <= 7 AND TB_ADDON_23_6 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_6 IS NOT NULL AND TB_ADDON_23_6 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_6 <= 7 AND TB_ADDON_23_6 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_6 IS NOT NULL AND TB_ADDON_23_6 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_6 IS NOT NULL AND TB_ADDON_23_6 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Wheelchair Team (0-10)', 'Staff', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_24 <= 7 AND TB_ADDON_23_24 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_24 IS NOT NULL AND TB_ADDON_23_24 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_24 <= 7 AND TB_ADDON_23_24 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_24 IS NOT NULL AND TB_ADDON_23_24 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_24 IS NOT NULL AND TB_ADDON_23_24 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Tech Team (0-10)', 'Staff', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_38 <= 7 AND TB_ADDON_23_38 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_38 IS NOT NULL AND TB_ADDON_23_38 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_38 <= 7 AND TB_ADDON_23_38 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_38 IS NOT NULL AND TB_ADDON_23_38 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_38 IS NOT NULL AND TB_ADDON_23_38 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Security (0-10)', 'Staff', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_60 <= 7 AND TB_ADDON_23_60 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_60 IS NOT NULL AND TB_ADDON_23_60 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_60 <= 7 AND TB_ADDON_23_60 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_60 IS NOT NULL AND TB_ADDON_23_60 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_60 IS NOT NULL AND TB_ADDON_23_60 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Ticket Scanner (0-10)', 'Staff', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_61 <= 7 AND TB_ADDON_23_61 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_61 IS NOT NULL AND TB_ADDON_23_61 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_61 <= 7 AND TB_ADDON_23_61 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_61 IS NOT NULL AND TB_ADDON_23_61 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_61 IS NOT NULL AND TB_ADDON_23_61 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            SELECT 'Staff: Go-Ahead Entry (0-10)', 'Staff', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_67 <= 7 AND TB_ADDON_23_67 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_67 IS NOT NULL AND TB_ADDON_23_67 < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN TB_ADDON_23_67 <= 7 AND TB_ADDON_23_67 < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN TB_ADDON_23_67 IS NOT NULL AND TB_ADDON_23_67 < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN TB_ADDON_23_67 IS NOT NULL AND TB_ADDON_23_67 < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Concession Speed (coded 1-4 satisfaction): % Highly Dissatisfied (=4)
            SELECT 'Concession Speed', 'Concessions', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_SPEED = 4 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_SPEED IS NOT NULL AND CONCESS_GRID_SPEED <= 4 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_GRID_SPEED = 4 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_GRID_SPEED IS NOT NULL AND CONCESS_GRID_SPEED <= 4 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_GRID_SPEED IS NOT NULL AND CONCESS_GRID_SPEED <= 4 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Preparedness Satisfaction (coded 1-4): % Highly Dissatisfied (=4)
            SELECT 'Preparedness Info', 'Operations', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN PREPARED_SAT = 4 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PREPARED_SAT IS NOT NULL AND PREPARED_SAT <= 4 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN PREPARED_SAT = 4 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PREPARED_SAT IS NOT NULL AND PREPARED_SAT <= 4 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN PREPARED_SAT IS NOT NULL AND PREPARED_SAT <= 4 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Gate Entry Score (0-10 scale): % Low Scores (<=7)
            SELECT 'Gate Entry Score', 'Operations', '% Low Scores',
                ROUND(100.0*SUM(CASE WHEN GE_NUMRAT <= 7 AND GE_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN GE_NUMRAT IS NOT NULL AND GE_NUMRAT < 80 THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN GE_NUMRAT <= 7 AND GE_NUMRAT < 80 THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN GE_NUMRAT IS NOT NULL AND GE_NUMRAT < 80 THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN GE_NUMRAT IS NOT NULL AND GE_NUMRAT < 80 THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Purchase Intent: % No I Do Not
            SELECT 'Purchase Intent', 'General', '% No I Do Not',
                ROUND(100.0*SUM(CASE WHEN PURCHASE_INTENT_DESC = 'No, I do not' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PURCHASE_INTENT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN PURCHASE_INTENT_DESC = 'No, I do not' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN PURCHASE_INTENT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN PURCHASE_INTENT_DESC IS NOT NULL THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Gate Entry Wait vs Expectations: % More Than Expected
            SELECT 'Gate Entry Wait', 'Operations', '% More Than Expected',
                ROUND(100.0*SUM(CASE WHEN GE_TIME_EXPECT_DESC = 'More than what I expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN GE_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN GE_TIME_EXPECT_DESC = 'More than what I expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN GE_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN GE_TIME_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Concession Wait vs Expectations: % Much More Than Expected
            SELECT 'Concession Wait Expect', 'Concessions', '% Much More Than Expected',
                ROUND(100.0*SUM(CASE WHEN CONCESS_WAIT_EXPECT_DESC = 'Much more than what I expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_WAIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN CONCESS_WAIT_EXPECT_DESC = 'Much more than what I expected' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN CONCESS_WAIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN CONCESS_WAIT_EXPECT_DESC IS NOT NULL THEN 1 ELSE 0 END)
            FROM game
            UNION ALL
            -- Giveaway Satisfaction: % Highly Dissatisfied
            SELECT 'Giveaway Satisfaction', 'Promotions', '% Highly Dissatisfied',
                ROUND(100.0*SUM(CASE WHEN GIVEAWAY_SAT_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN GIVEAWAY_SAT_DESC IS NOT NULL AND GIVEAWAY_SAT_DESC NOT IN ('N/A', '5') THEN 1 ELSE 0 END),0),2),
                (SELECT ROUND(100.0*SUM(CASE WHEN GIVEAWAY_SAT_DESC = 'Highly dissatisfied' THEN 1 ELSE 0 END)/NULLIF(SUM(CASE WHEN GIVEAWAY_SAT_DESC IS NOT NULL AND GIVEAWAY_SAT_DESC NOT IN ('N/A', '5') THEN 1 ELSE 0 END),0),2) FROM season),
                SUM(CASE WHEN GIVEAWAY_SAT_DESC IS NOT NULL AND GIVEAWAY_SAT_DESC NOT IN ('N/A', '5') THEN 1 ELSE 0 END)
            FROM game
        ),
        scored AS (
            SELECT metric_label, dept, unit, game_val, season_val, n,
                ROUND(game_val - season_val, 2) AS regression
            FROM metrics
            WHERE game_val IS NOT NULL AND season_val IS NOT NULL AND n >= 20
              AND game_val != 0 AND season_val != 0
              AND ROUND(game_val - season_val, 2) >= 1
        )
        SELECT metric_label, dept, unit, regression
        FROM scored ORDER BY regression DESC LIMIT 3
    );
    LET c_worst CURSOR FOR rs_worst;
    v_rank := 0;
    FOR rec IN c_worst DO
        v_rank := v_rank + 1;
        IF (v_rank = 1) THEN
            v_worst1_label := rec.metric_label; v_worst1_dept := rec.dept;
            v_worst1_delta := ABS(rec.regression)::VARCHAR; v_worst1_unit := rec.unit;
            v_worst1_suffix := '% higher';
        ELSEIF (v_rank = 2) THEN
            v_worst2_label := rec.metric_label; v_worst2_dept := rec.dept;
            v_worst2_delta := ABS(rec.regression)::VARCHAR; v_worst2_unit := rec.unit;
            v_worst2_suffix := '% higher';
        ELSEIF (v_rank = 3) THEN
            v_worst3_label := rec.metric_label; v_worst3_dept := rec.dept;
            v_worst3_delta := ABS(rec.regression)::VARCHAR; v_worst3_unit := rec.unit;
            v_worst3_suffix := '% higher';
        END IF;
    END FOR;

    -- =============================================
    -- SECTION 3 CONTEXT: Query A — Game-day comprehensive aggregates
    -- =============================================
    SELECT
        -- Theme / Giveaway / Holiday
        COALESCE(MAX(t.theme_list), 'None'),
        COALESCE(MAX(g.giveaway_nm), 'None'),
        COALESCE(MAX(g.giveaway_tp), 'None'),
        COALESCE(MAX(v.HOLIDAY), 0),
        -- Audience composition
        ROUND(100.0 * SUM(CASE WHEN v.EXIT_STAGE_DESC IS NOT NULL AND v.EXIT_STAGE_DESC != 'After the final pitch' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.EXIT_STAGE_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.EXIT_STAGE_DESC IN ('7th inning','6th inning','5th inning','4th inning','3rd inning','2nd inning','1st inning') THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.EXIT_STAGE_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.ATTEND_WITH_CATEGORY_YOUNG_KIDS > 0 THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.ATTEND_WITH_CATEGORY_YOUNG_KIDS IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.ATTEND_WITH_CATEGORY_FRIENDS > 0 THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.ATTEND_WITH_CATEGORY_FRIENDS IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.ATTEND_WITH_CATEGORY_SPOUSE > 0 THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.ATTEND_WITH_CATEGORY_SPOUSE IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.ATTEND_WITH_CATEGORY_ALONE > 0 THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.ATTEND_WITH_CATEGORY_ALONE IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.PREVIOUS_PURCHASE_DESC = 'No' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.PREVIOUS_PURCHASE_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.PURCHASE_INTENT_DESC = 'Yes, I do' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.PURCHASE_INTENT_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(AVG(TRY_TO_NUMBER(REGEXP_SUBSTR(v.GROUP_SIZE_DESC, '\\d+'))), 1),
        ROUND(100.0 * SUM(CASE WHEN v.FAVORITE_TEAM_CLEAN ILIKE '%rays%' OR v.FAVORITE_TEAM_CLEAN ILIKE '%tampa bay%' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.FAVORITE_TEAM_CLEAN IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.FAVORITE_TEAM_CLEAN ILIKE '%' || v.TEAM_NICKNAME || '%' AND NOT (v.FAVORITE_TEAM_CLEAN ILIKE '%rays%' OR v.FAVORITE_TEAM_CLEAN ILIKE '%tampa bay%') THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.FAVORITE_TEAM_CLEAN IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.TEAM_AVIDITY_DESC = '5 (passionate fan)' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.TEAM_AVIDITY_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(AVG(v.AGE), 1),
        ROUND(MEDIAN(v.HOME_DIST), 1),
        ROUND(100.0 * SUM(CASE WHEN v.TRAVELTO_METHOD_DESC ILIKE '%car%' OR v.TRAVELTO_METHOD_DESC ILIKE '%vehicle%' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.TRAVELTO_METHOD_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.GAMES_PREV_SEASON_DESC = 'I did not attend any games' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.GAMES_PREV_SEASON_DESC IS NOT NULL THEN 1 END), 0), 1),
        -- Operational metrics
        ROUND(100.0 * SUM(CASE WHEN v.CONCESS_WAIT_EXPECT_DESC IN ('Much more than what I expected','Slightly more than what I expected') THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.CONCESS_WAIT_EXPECT_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.PARKING_TIME_EXPECT_DESC = 'More than what I expected' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.PARKING_TIME_EXPECT_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.PARKING_EXIT_EXPECT_DESC = 'More than what I expected' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.PARKING_EXIT_EXPECT_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.TRAVELTO_TIME_EXPECT_DESC = 'More than what I expected' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.TRAVELTO_TIME_EXPECT_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.GE_TIME_EXPECT_DESC = 'More than what I expected' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.GE_TIME_EXPECT_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.CONCESS_SCREENER_DESC = 'Yes, I did' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.CONCESS_SCREENER_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.MERCH_SCREENER_DESC = 'Yes, I did' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.MERCH_SCREENER_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.CONCESS_ORDER_METHOD_MOBILE > 0 THEN 1 ELSE 0 END)
              / NULLIF(SUM(CASE WHEN v.CONCESS_SCREENER_DESC = 'Yes, I did' THEN 1 ELSE 0 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.CONCESS_SPEND_DESC IN ('Between $41 and $50','More than $50') THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.CONCESS_SPEND_DESC IS NOT NULL THEN 1 END), 0), 1),
        -- Promo/theme metrics
        ROUND(100.0 * SUM(CASE WHEN v.GIVEAWAY_SAT_DESC IN ('Highly satisfied','Somewhat satisfied') THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.GIVEAWAY_SAT_DESC IS NOT NULL AND v.GIVEAWAY_SAT_DESC != 'N/A' THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.GIVEAWAY_ARRIVAL_DESC IS NOT NULL AND v.GIVEAWAY_ARRIVAL_DESC != 'It had no impact / I arrived when I usualy would' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.GIVEAWAY_ARRIVAL_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.PA_PROMO_GRID_GIVEAWAY_DESC = 'I cared about this' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.PA_PROMO_GRID_GIVEAWAY_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.PA_PROMO_GRID_THEME_DESC = 'I cared about this' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.PA_PROMO_GRID_THEME_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.PA_THEME_INTENT_DESC = 'I would not have purchased / attended at this time' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.PA_THEME_INTENT_DESC IS NOT NULL THEN 1 END), 0), 1),
        ROUND(100.0 * SUM(CASE WHEN v.THEME_SAT_DESC IN ('Highly satisfied','Somewhat satisfied') THEN 1 ELSE 0 END)
              / NULLIF(COUNT(CASE WHEN v.THEME_SAT_DESC IS NOT NULL AND v.THEME_SAT_DESC != 'N/A' THEN 1 END), 0), 1)
    INTO
        :v_theme_names, :v_giveaway_name, :v_giveaway_type, :v_holiday_flag,
        :v_pct_left_early, :v_pct_exit_7th_or_earlier,
        :v_pct_with_young_kids, :v_pct_with_friends, :v_pct_with_spouse, :v_pct_alone,
        :v_pct_first_time_buyer, :v_pct_repurchase_intent, :v_avg_group_size,
        :v_pct_rays_fans, :v_pct_opposing_fans, :v_pct_passionate_fans,
        :v_avg_age, :v_avg_home_dist, :v_pct_drove, :v_pct_no_prev_season_games,
        :v_pct_concess_wait_long, :v_pct_parking_arrival_long, :v_pct_parking_exit_long,
        :v_pct_travel_longer, :v_pct_gate_entry_long,
        :v_pct_bought_concessions, :v_pct_bought_merch, :v_pct_mobile_order, :v_pct_concess_spend_high,
        :v_pct_giveaway_satisfied, :v_pct_arrived_early_for_giveaway,
        :v_pct_cared_giveaway, :v_pct_cared_theme, :v_pct_theme_drove_attendance, :v_pct_theme_satisfied
    FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI v
    LEFT JOIN (
        SELECT GAME_DATE::DATE AS gd, LISTAGG(DISTINCT THEME_NAME, ', ') WITHIN GROUP (ORDER BY THEME_NAME) AS theme_list
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
        WHERE GAME_DATE::DATE = :v_target_game_date AND THEME_NAME IS NOT NULL
        GROUP BY gd
    ) t ON v.GAME_DATE::DATE = t.gd
    LEFT JOIN (
        SELECT GAME_DATE::DATE AS gd, MAX(GIVEAWAY_NAME) AS giveaway_nm, MAX(GIVEAWAY_TYPE) AS giveaway_tp
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
        WHERE GAME_DATE::DATE = :v_target_game_date AND GIVEAWAY_NAME IS NOT NULL
        GROUP BY gd
    ) g ON v.GAME_DATE::DATE = g.gd
    WHERE v.GAME_DATE::DATE = :v_target_game_date
      AND v.OVERALL_NUMRAT IS NOT NULL;

    -- =============================================
    -- SECTION 3 CONTEXT: Query E — Top 5 buyer segments with avg ratings
    -- =============================================
    SELECT LISTAGG(seg_line, ' | ') WITHIN GROUP (ORDER BY rn)
    INTO :v_buyer_seg_summary
    FROM (
        SELECT
            ROW_NUMBER() OVER (ORDER BY cnt DESC) AS rn,
            buyer_segment || ': ' || ROUND(100.0 * cnt / total_n, 0)::VARCHAR || '% (avg ' || avg_ovr::VARCHAR || '/10)' AS seg_line
        FROM (
            SELECT
                CASE
                    WHEN BUYER_TYPE ILIKE '%plan%' OR BUYER_TYPE ILIKE '%season%' OR BUYER_TYPE ILIKE '%162%' THEN 'Season/Plan'
                    WHEN BUYER_TYPE ILIKE '%single game ticket' THEN 'Single Game'
                    WHEN BUYER_TYPE ILIKE '%complimentary%' OR BUYER_TYPE ILIKE '%comp%' THEN 'Complimentary'
                    WHEN BUYER_TYPE ILIKE '%group%' THEN 'Group'
                    WHEN BUYER_TYPE ILIKE '%suite%' THEN 'Suite/Premium'
                    WHEN BUYER_TYPE ILIKE '%fevo%' OR BUYER_TYPE ILIKE '%offer%' OR BUYER_TYPE ILIKE '%pack%' OR BUYER_TYPE ILIKE '%ten-dollar%' THEN 'Promotional/Offer'
                    ELSE 'Other'
                END AS buyer_segment,
                COUNT(*) AS cnt,
                ROUND(AVG(OVERALL_NUMRAT), 2) AS avg_ovr,
                SUM(COUNT(*)) OVER () AS total_n
            FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
            WHERE GAME_DATE::DATE = :v_target_game_date AND BUYER_TYPE IS NOT NULL AND OVERALL_NUMRAT IS NOT NULL
            GROUP BY buyer_segment
        )
        WHERE cnt > 0
    )
    WHERE rn <= 5;

    -- =============================================
    -- SECTION 3 CONTEXT: Game Tier lookup
    -- =============================================
    SELECT GAME_TIER
    INTO :v_game_tier
    FROM TBRDP_DW_DEV.IM_RPT.T_GAME_TIERS
    WHERE GAME_DATE = :v_target_game_date;

    -- =============================================
    -- SECTION 3 CONTEXT: Tier Benchmark — same-tier avg from 2023+2024
    -- Computes all Query A metrics for historical games of the same tier
    -- =============================================
    LET v_tier_rs RESULTSET;
    v_tier_rs := (
        SELECT
            ROUND(AVG(v.OVERALL_NUMRAT), 2),
            COUNT(DISTINCT v.GAME_DATE::DATE),
            COUNT(*),
            ROUND(100.0 * SUM(CASE WHEN v.EXIT_STAGE_DESC IS NOT NULL AND v.EXIT_STAGE_DESC != 'After the final pitch' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.EXIT_STAGE_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.EXIT_STAGE_DESC IN ('7th inning','6th inning','5th inning','4th inning','3rd inning','2nd inning','1st inning') THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.EXIT_STAGE_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.ATTEND_WITH_CATEGORY_YOUNG_KIDS > 0 THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.ATTEND_WITH_CATEGORY_YOUNG_KIDS IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.ATTEND_WITH_CATEGORY_FRIENDS > 0 THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.ATTEND_WITH_CATEGORY_FRIENDS IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.ATTEND_WITH_CATEGORY_SPOUSE > 0 THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.ATTEND_WITH_CATEGORY_SPOUSE IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.ATTEND_WITH_CATEGORY_ALONE > 0 THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.ATTEND_WITH_CATEGORY_ALONE IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.PREVIOUS_PURCHASE_DESC = 'No' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.PREVIOUS_PURCHASE_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.PURCHASE_INTENT_DESC = 'Yes, I do' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.PURCHASE_INTENT_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(AVG(TRY_TO_NUMBER(REGEXP_SUBSTR(v.GROUP_SIZE_DESC, '\\d+'))), 1),
            ROUND(100.0 * SUM(CASE WHEN v.FAVORITE_TEAM_CLEAN ILIKE '%rays%' OR v.FAVORITE_TEAM_CLEAN ILIKE '%tampa bay%' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.FAVORITE_TEAM_CLEAN IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.TEAM_AVIDITY_DESC = '5 (passionate fan)' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.TEAM_AVIDITY_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(AVG(v.AGE), 1),
            ROUND(MEDIAN(v.HOME_DIST), 1),
            ROUND(100.0 * SUM(CASE WHEN v.TRAVELTO_METHOD_DESC ILIKE '%car%' OR v.TRAVELTO_METHOD_DESC ILIKE '%vehicle%' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.TRAVELTO_METHOD_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.GAMES_PREV_SEASON_DESC = 'I did not attend any games' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.GAMES_PREV_SEASON_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.CONCESS_WAIT_EXPECT_DESC IN ('Much more than what I expected','Slightly more than what I expected') THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.CONCESS_WAIT_EXPECT_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.PARKING_TIME_EXPECT_DESC = 'More than what I expected' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.PARKING_TIME_EXPECT_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.PARKING_EXIT_EXPECT_DESC = 'More than what I expected' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.PARKING_EXIT_EXPECT_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.TRAVELTO_TIME_EXPECT_DESC = 'More than what I expected' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.TRAVELTO_TIME_EXPECT_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.GE_TIME_EXPECT_DESC = 'More than what I expected' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.GE_TIME_EXPECT_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.CONCESS_SCREENER_DESC = 'Yes, I did' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.CONCESS_SCREENER_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.MERCH_SCREENER_DESC = 'Yes, I did' THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.MERCH_SCREENER_DESC IS NOT NULL THEN 1 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.CONCESS_ORDER_METHOD_MOBILE > 0 THEN 1 ELSE 0 END)
                  / NULLIF(SUM(CASE WHEN v.CONCESS_SCREENER_DESC = 'Yes, I did' THEN 1 ELSE 0 END), 0), 1),
            ROUND(100.0 * SUM(CASE WHEN v.CONCESS_SPEND_DESC IN ('Between $41 and $50','More than $50') THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(CASE WHEN v.CONCESS_SPEND_DESC IS NOT NULL THEN 1 END), 0), 1)
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI v
        INNER JOIN TBRDP_DW_DEV.IM_RPT.T_GAME_TIERS gt
            ON v.GAME_DATE::DATE = gt.GAME_DATE
        WHERE gt.GAME_TIER = :v_game_tier
          AND gt.SEASON IN (2023, 2024)
          AND v.OVERALL_NUMRAT IS NOT NULL
    );
    LET v_tier_cur CURSOR FOR v_tier_rs;
    OPEN v_tier_cur;
    FETCH v_tier_cur INTO
        v_tier_avg_overall, v_tier_num_games, v_tier_total_responses,
        v_tier_pct_left_early, v_tier_pct_exit_7th_or_earlier,
        v_tier_pct_with_young_kids, v_tier_pct_with_friends, v_tier_pct_with_spouse, v_tier_pct_alone,
        v_tier_pct_first_time_buyer, v_tier_pct_repurchase_intent, v_tier_avg_group_size,
        v_tier_pct_rays_fans, v_tier_pct_passionate_fans, v_tier_avg_age, v_tier_avg_home_dist,
        v_tier_pct_drove, v_tier_pct_no_prev_season_games,
        v_tier_pct_concess_wait_long, v_tier_pct_parking_arrival_long, v_tier_pct_parking_exit_long,
        v_tier_pct_travel_longer, v_tier_pct_gate_entry_long,
        v_tier_pct_bought_concessions, v_tier_pct_bought_merch, v_tier_pct_mobile_order, v_tier_pct_concess_spend_high;
    CLOSE v_tier_cur;

    -- =============================================
    -- AI-GENERATED ACTION ITEMS (enriched with full context)
    -- =============================================

    -- Fetch last 3 games' insights to prevent repetitive recommendations
    -- Uses MAX(ACTION_ITEMS) per GAME_DATE to guarantee 3 distinct game dates
    -- even if duplicate rows exist in the log table.
    LET v_previous_insights VARCHAR DEFAULT 'None available';
    LET v_prev_rs RESULTSET := (
        SELECT LISTAGG('Game ' || GAME_DATE::VARCHAR || ': ' || LEFT(ACTION_ITEMS, 300), ' ||| ')
            WITHIN GROUP (ORDER BY GAME_DATE DESC) AS prev
        FROM (
            SELECT GAME_DATE, MAX(ACTION_ITEMS) AS ACTION_ITEMS
            FROM TBRDP_DW_DEV.IM_RPT.T_VOC_REPORT_CARD_LOG
            WHERE GAME_DATE != :v_target_game_date
            GROUP BY GAME_DATE
            ORDER BY GAME_DATE DESC
            LIMIT 3
        )
    );
    LET v_prev_cur CURSOR FOR v_prev_rs;
    OPEN v_prev_cur;
    FETCH v_prev_cur INTO v_previous_insights;
    CLOSE v_prev_cur;

    -- Format game_avg to always show 2 decimal places (e.g., 9.06, not 9)
    LET v_game_avg_display VARCHAR := TO_VARCHAR(v_game_avg, '99.00');
    LET v_season_avg_display VARCHAR := TO_VARCHAR(v_season_avg, '99.00');

    LET v_action_prompt VARCHAR;
    v_action_prompt := 'You are a sports business analyst for the Tampa Bay Rays reviewing post-game survey data. Generate exactly 2 insights as HTML.' ||
        ' RULES:' ||
        ' - Insight 1 (checkmark): A positive finding worth replicating — an anomaly, trend, or standout result backed by data.' ||
        ' - Insight 2 (rocket): An area where satisfaction scores lagged relative to benchmarks, with a suggestion for how trying a different approach could potentially lead to higher satisfaction.' ||
        ' - Ground every insight in specific numbers and comparisons from the data below.' ||
        ' - Look across ALL data to find meaningful patterns — connect audience composition, behavior, operations, qualitative feedback, promos, and benchmarks to surface non-obvious insights.' ||
        ' - Do NOT recommend pricing adjustments to tickets, concessions, or retail — these are fixed and not adjustable.' ||
        ' - Do NOT assume the organization lacks existing programming, activations, or processes. The team already programs between-innings entertainment, has fan engagement elements, and runs operational procedures. Frame recommendations as trying different or additional approaches rather than introducing something new from scratch.' ||
        ' - Keep language constructive and professional — avoid harsh or judgmental words like "underdelivered", "failed", or "lacking". Use forward-looking language such as "trying different X could potentially lead to higher satisfaction" rather than implying current efforts are insufficient.' ||
        ' GAME: ' || v_day_of_week || ', ' || v_game_date_display || ' vs ' || v_opponent ||
        ' | ' || v_response_count::VARCHAR || ' responses | Overall: ' || v_game_avg_display || '/10 (Season avg: ' || v_season_avg_display || '/10)' ||
        ' | Game Tier: ' || v_game_tier::VARCHAR || ' (1=premium, 5=lower draw) — Tier benchmark: ' || v_tier_num_games::VARCHAR || ' games, ' || v_tier_total_responses::VARCHAR || ' responses, avg ' || v_tier_avg_overall::VARCHAR || '/10' ||
        ' | Theme(s): ' || v_theme_names || ' | Giveaway: ' || v_giveaway_name || ' (' || v_giveaway_type || ')' ||
        ' | Holiday: ' || IFF(v_holiday_flag > 0, 'Yes', 'No') ||
        CASE WHEN v_game_avg >= v_season_avg THEN
            ' PERFORMANCE CONTEXT: This was a HIGH-PERFORMING game (' || v_game_avg_display || '/10 vs ' || v_season_avg_display || '/10 season avg). The improvement insight (rocket) MUST remain positive in tone — lead by acknowledging the strong overall performance, then frame the opportunity as a minor area to push even higher rather than a criticism or deficiency.'
        ELSE '' END ||
        ' AUDIENCE (game value | Tier ' || v_game_tier::VARCHAR || ' avg):' ||
        CASE WHEN COALESCE(v_pct_first_time_buyer, 0) != 0 THEN ' - First-time buyers: ' || v_pct_first_time_buyer::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_first_time_buyer, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_with_young_kids, 0) != 0 THEN ' - Young kids: ' || v_pct_with_young_kids::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_with_young_kids, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_with_friends, 0) != 0 THEN ' - Friends: ' || v_pct_with_friends::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_with_friends, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_with_spouse, 0) != 0 THEN ' - Spouse: ' || v_pct_with_spouse::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_with_spouse, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_alone, 0) != 0 THEN ' - Alone: ' || v_pct_alone::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_alone, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_avg_group_size, 0) != 0 THEN ' - Avg group: ' || v_avg_group_size::VARCHAR || ' (Tier: ' || COALESCE(v_tier_avg_group_size, 0)::VARCHAR || ')' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_passionate_fans, 0) != 0 THEN ' - Passionate fans (Die-hard/Avid): ' || v_pct_passionate_fans::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_passionate_fans, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_rays_fans, 0) != 0 THEN ' - Rays fans: ' || v_pct_rays_fans::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_rays_fans, 0)::VARCHAR || '%) | ' || v_opponent || ' fans: ' || COALESCE(v_pct_opposing_fans, 0)::VARCHAR || '%' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_no_prev_season_games, 0) != 0 THEN ' - No games last season: ' || v_pct_no_prev_season_games::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_no_prev_season_games, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_avg_age, 0) != 0 THEN ' - Avg age: ' || v_avg_age::VARCHAR || ' (Tier: ' || COALESCE(v_tier_avg_age, 0)::VARCHAR || ')' ELSE '' END ||
        CASE WHEN COALESCE(v_avg_home_dist, 0) != 0 THEN ' - Avg distance: ' || v_avg_home_dist::VARCHAR || 'mi (Tier: ' || COALESCE(v_tier_avg_home_dist, 0)::VARCHAR || 'mi)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_drove, 0) != 0 THEN ' - Drove: ' || v_pct_drove::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_drove, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_repurchase_intent, 0) != 0 THEN ' - Repurchase intent: ' || v_pct_repurchase_intent::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_repurchase_intent, 0)::VARCHAR || '%)' ELSE '' END ||
        ' BUYER MIX (top 5): ' || COALESCE(v_buyer_seg_summary, 'N/A') ||
        ' OPERATIONS (game | Tier ' || v_game_tier::VARCHAR || ' avg):' ||
        CASE WHEN COALESCE(v_pct_left_early, 0) != 0 THEN ' - Left early: ' || v_pct_left_early::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_left_early, 0)::VARCHAR || '%) — 7th or earlier: ' || COALESCE(v_pct_exit_7th_or_earlier, 0)::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_exit_7th_or_earlier, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_concess_wait_long, 0) != 0 THEN ' - Concession wait long: ' || v_pct_concess_wait_long::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_concess_wait_long, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_parking_arrival_long, 0) != 0 THEN ' - Parking arrival long: ' || v_pct_parking_arrival_long::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_parking_arrival_long, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_parking_exit_long, 0) != 0 THEN ' - Parking exit long: ' || v_pct_parking_exit_long::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_parking_exit_long, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_travel_longer, 0) != 0 THEN ' - Travel longer: ' || v_pct_travel_longer::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_travel_longer, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_gate_entry_long, 0) != 0 THEN ' - Gate entry longer: ' || v_pct_gate_entry_long::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_gate_entry_long, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_bought_concessions, 0) != 0 THEN ' - Bought concessions: ' || v_pct_bought_concessions::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_bought_concessions, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_bought_merch, 0) != 0 THEN ' - Bought merch: ' || v_pct_bought_merch::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_bought_merch, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_mobile_order, 0) != 0 THEN ' - Mobile ordering: ' || v_pct_mobile_order::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_mobile_order, 0)::VARCHAR || '%)' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_concess_spend_high, 0) != 0 THEN ' - Concession spend $41+: ' || v_pct_concess_spend_high::VARCHAR || '% (Tier: ' || COALESCE(v_tier_pct_concess_spend_high, 0)::VARCHAR || '%)' ELSE '' END ||
        ' PROMO/THEME:' ||
        CASE WHEN COALESCE(v_pct_giveaway_satisfied, 0) != 0 OR COALESCE(v_pct_arrived_early_for_giveaway, 0) != 0 THEN ' - Giveaway satisfaction: ' || COALESCE(v_pct_giveaway_satisfied, 0)::VARCHAR || '% | Arrived early for giveaway: ' || COALESCE(v_pct_arrived_early_for_giveaway, 0)::VARCHAR || '%' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_cared_giveaway, 0) != 0 OR COALESCE(v_pct_cared_theme, 0) != 0 THEN ' - Cared about giveaway: ' || COALESCE(v_pct_cared_giveaway, 0)::VARCHAR || '% | Cared about theme: ' || COALESCE(v_pct_cared_theme, 0)::VARCHAR || '%' ELSE '' END ||
        CASE WHEN COALESCE(v_pct_theme_drove_attendance, 0) != 0 OR COALESCE(v_pct_theme_satisfied, 0) != 0 THEN ' - Theme drove attendance: ' || COALESCE(v_pct_theme_drove_attendance, 0)::VARCHAR || '% | Theme satisfaction: ' || COALESCE(v_pct_theme_satisfied, 0)::VARCHAR || '%' ELSE '' END ||
        ' QUANTITATIVE (game vs season, ~30 metrics, satisfaction extremes):' ||
        ' - Best: ' || v_best1_label || ' (' || v_best1_delta || v_best1_suffix || '), ' || v_best2_label || ' (' || v_best2_delta || v_best2_suffix || '), ' || v_best3_label || ' (' || v_best3_delta || v_best3_suffix || ')' ||
        ' - Worst: ' || CASE WHEN v_worst1_label != 'N/A' THEN v_worst1_label || ' (' || v_worst1_delta || v_worst1_suffix || ')' ELSE 'None — all metrics at or above season average' END || CASE WHEN v_worst2_label != 'N/A' THEN ', ' || v_worst2_label || ' (' || v_worst2_delta || v_worst2_suffix || ')' ELSE '' END || CASE WHEN v_worst3_label != 'N/A' THEN ', ' || v_worst3_label || ' (' || v_worst3_delta || v_worst3_suffix || ')' ELSE '' END ||
        ' QUALITATIVE (top sentence-level topics):' ||
        ' - Positive: ' || v_pos_topic_1 || ' (' || v_pos_topic_1_pct::VARCHAR || '%), ' || v_pos_topic_2 || ' (' || v_pos_topic_2_pct::VARCHAR || '%), ' || v_pos_topic_3 || ' (' || v_pos_topic_3_pct::VARCHAR || '%)' ||
        ' - Negative: ' || v_neg_topic_1 || ' (' || v_neg_topic_1_pct::VARCHAR || '%), ' || v_neg_topic_2 || ' (' || v_neg_topic_2_pct::VARCHAR || '%), ' || v_neg_topic_3 || ' (' || v_neg_topic_3_pct::VARCHAR || '%)' ||
        ' RULES:' ||
        ' - Each insight must be exactly 2-3 sentences. Be concise and efficient — every word should add value.' ||
        ' - IMPORTANT: Every sentence must be complete. Never leave a thought unfinished.' ||
        ' - CRITICAL ZERO RULE: Before writing each sentence, verify that every number you reference is greater than 0%. If ANY metric in your draft has a game value of 0% OR a benchmark value of 0%, DELETE that entire sentence and replace it with a different data point. The characters "0%" must NEVER appear anywhere in your output — not as a comparison target, not parenthetically, not in any context. Any sentence containing "0%" is invalid and must be rewritten with a different insight.' ||
        ' - FRESHNESS RULE: Review the PREVIOUS INSIGHTS section below. Do NOT repeat the same themes, metrics, or recommendations that appeared in recent games. Find new angles, different data points, or alternative recommendations each time.' ||
        ' PREVIOUS INSIGHTS (these were already sent — do NOT repeat these themes):' ||
        ' ' || COALESCE(:v_previous_insights, 'None available') ||
        ' FORMAT (output ONLY these two divs, nothing else): <div>&#9989; [positive insight with specific data]</div> <div>&#128640; [improvement insight with specific data]</div>';

    SELECT AI_COMPLETE('claude-sonnet-4-6', :v_action_prompt, {'temperature': 0.3, 'max_tokens': 800})
    INTO :v_action_items;

    -- Strip literal \n characters that the AI model sometimes outputs
    v_action_items := REPLACE(v_action_items, '\\n', '');

    -- Log this game's action items for freshness dedup in future runs
    -- MERGE upsert: keeps exactly 1 row per GAME_DATE, replacing on re-runs
    MERGE INTO TBRDP_DW_DEV.IM_RPT.T_VOC_REPORT_CARD_LOG tgt
    USING (SELECT :v_target_game_date AS GAME_DATE, :v_action_items AS ACTION_ITEMS) src
    ON tgt.GAME_DATE = src.GAME_DATE
    WHEN MATCHED THEN UPDATE SET ACTION_ITEMS = src.ACTION_ITEMS, SENT_AT = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (GAME_DATE, ACTION_ITEMS) VALUES (src.GAME_DATE, src.ACTION_ITEMS);

    -- =============================================
    -- PIE CHART: Overall rating distribution
    --   Green slice  = ratings 9 or 10 (top box)
    --   Light-red    = ratings 8 and below (everyone else)
    -- Rendered as inline SVG so it displays in a browser.
    -- Valid ratings only: OVERALL_NUMRAT < 80 excludes sentinel/N-A codes.
    -- =============================================
    LET v_pie_top NUMBER DEFAULT 0;       -- count of 9-10 ratings
    LET v_pie_total NUMBER DEFAULT 0;     -- count of all valid ratings
    LET v_pie_bottom NUMBER DEFAULT 0;    -- count of 8-and-below ratings

    SELECT
        SUM(CASE WHEN OVERALL_NUMRAT >= 9 THEN 1 ELSE 0 END),
        COUNT(*)
    INTO :v_pie_top, :v_pie_total
    FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
    WHERE GAME_DATE::DATE = :v_target_game_date
      AND OVERALL_NUMRAT IS NOT NULL
      AND OVERALL_NUMRAT < 80;

    v_pie_bottom := v_pie_total - v_pie_top;

    LET v_pie_top_pct NUMBER DEFAULT 0;
    LET v_pie_bottom_pct NUMBER DEFAULT 0;
    LET v_pie_frac FLOAT DEFAULT 0;
    IF (v_pie_total > 0) THEN
        v_pie_top_pct := ROUND(100.0 * v_pie_top / v_pie_total, 0);
        v_pie_bottom_pct := 100 - v_pie_top_pct;
        v_pie_frac := v_pie_top / v_pie_total;
    END IF;

    -- Pie geometry (cx=cy=75, r=60). Slice arc points + label points.
    -- Start at top of circle (-90 deg), green sweeps clockwise by 360*frac.
    LET v_gx1 NUMBER(8,2) DEFAULT 0; LET v_gy1 NUMBER(8,2) DEFAULT 0;
    LET v_gx2 NUMBER(8,2) DEFAULT 0; LET v_gy2 NUMBER(8,2) DEFAULT 0;
    LET v_g_large NUMBER DEFAULT 0;  LET v_r_large NUMBER DEFAULT 0;
    LET v_glx NUMBER(8,2) DEFAULT 0; LET v_gly NUMBER(8,2) DEFAULT 0;
    LET v_rlx NUMBER(8,2) DEFAULT 0; LET v_rly NUMBER(8,2) DEFAULT 0;

    SELECT
        ROUND(75 + 60*COS(RADIANS(-90)), 2),
        ROUND(75 + 60*SIN(RADIANS(-90)), 2),
        ROUND(75 + 60*COS(RADIANS(-90 + 360*:v_pie_frac)), 2),
        ROUND(75 + 60*SIN(RADIANS(-90 + 360*:v_pie_frac)), 2),
        IFF(360*:v_pie_frac > 180, 1, 0),
        IFF(360*(1-:v_pie_frac) > 180, 1, 0),
        ROUND(75 + 38*COS(RADIANS(-90 + 180*:v_pie_frac)), 2),
        ROUND(75 + 38*SIN(RADIANS(-90 + 180*:v_pie_frac)), 2),
        ROUND(75 + 38*COS(RADIANS(90 + 180*:v_pie_frac)), 2),
        ROUND(75 + 38*SIN(RADIANS(90 + 180*:v_pie_frac)), 2)
    INTO :v_gx1, :v_gy1, :v_gx2, :v_gy2, :v_g_large, :v_r_large, :v_glx, :v_gly, :v_rlx, :v_rly;

    LET v_svg VARCHAR DEFAULT '';
    IF (v_pie_total = 0) THEN
        v_svg := '<div style="font-size:11px;color:#888;padding:40px 0;">No rating data</div>';
    ELSEIF (v_pie_top = v_pie_total) THEN
        -- 100% green
        v_svg := '<svg width="150" height="150" viewBox="0 0 150 150" xmlns="http://www.w3.org/2000/svg">'
            || '<circle cx="75" cy="75" r="60" fill="#2ecc71" stroke="#ffffff" stroke-width="2"/>'
            || '<text x="75" y="70" text-anchor="middle" font-family="Arial,Helvetica,sans-serif" font-weight="700" fill="#ffffff"><tspan x="75" font-size="13">' || v_pie_top_pct::VARCHAR || '%</tspan><tspan x="75" dy="14" font-size="11">(' || v_pie_top::VARCHAR || ')</tspan></text>'
            || '</svg>';
    ELSEIF (v_pie_top = 0) THEN
        -- 100% red
        v_svg := '<svg width="150" height="150" viewBox="0 0 150 150" xmlns="http://www.w3.org/2000/svg">'
            || '<circle cx="75" cy="75" r="60" fill="#f5b7b1" stroke="#ffffff" stroke-width="2"/>'
            || '<text x="75" y="70" text-anchor="middle" font-family="Arial,Helvetica,sans-serif" font-weight="700" fill="#8e2b20"><tspan x="75" font-size="13">' || v_pie_bottom_pct::VARCHAR || '%</tspan><tspan x="75" dy="14" font-size="11">(' || v_pie_bottom::VARCHAR || ')</tspan></text>'
            || '</svg>';
    ELSE
        v_svg := '<svg width="150" height="150" viewBox="0 0 150 150" xmlns="http://www.w3.org/2000/svg">'
            || '<path d="M75 75 L' || v_gx1::VARCHAR || ' ' || v_gy1::VARCHAR || ' A60 60 0 ' || v_g_large::VARCHAR || ' 1 ' || v_gx2::VARCHAR || ' ' || v_gy2::VARCHAR || ' Z" fill="#2ecc71" stroke="#ffffff" stroke-width="2"/>'
            || '<path d="M75 75 L' || v_gx2::VARCHAR || ' ' || v_gy2::VARCHAR || ' A60 60 0 ' || v_r_large::VARCHAR || ' 1 ' || v_gx1::VARCHAR || ' ' || v_gy1::VARCHAR || ' Z" fill="#f5b7b1" stroke="#ffffff" stroke-width="2"/>'
            || '<text x="' || v_glx::VARCHAR || '" y="' || (v_gly-3)::VARCHAR || '" text-anchor="middle" font-family="Arial,Helvetica,sans-serif" font-weight="700" fill="#ffffff"><tspan x="' || v_glx::VARCHAR || '" font-size="13">' || v_pie_top_pct::VARCHAR || '%</tspan><tspan x="' || v_glx::VARCHAR || '" dy="14" font-size="11">(' || v_pie_top::VARCHAR || ')</tspan></text>'
            || '<text x="' || v_rlx::VARCHAR || '" y="' || (v_rly-3)::VARCHAR || '" text-anchor="middle" font-family="Arial,Helvetica,sans-serif" font-weight="700" fill="#8e2b20"><tspan x="' || v_rlx::VARCHAR || '" font-size="13">' || v_pie_bottom_pct::VARCHAR || '%</tspan><tspan x="' || v_rlx::VARCHAR || '" dy="14" font-size="11">(' || v_pie_bottom::VARCHAR || ')</tspan></text>'
            || '</svg>';
    END IF;

    -- =============================================
    -- BUILD EMAIL HTML — matches reference format
    -- Section labels: OVERALL, QUALITATIVE SUMMARY, QUANTITATIVE SUMMARY
    -- No department names displayed in qualitative or quantitative
    -- Natural language: "Fans highly satisfied with X was Y% higher"
    -- For negative: "Fans highly dissatisfied with X was Y% higher"
    -- MSO conditional comments for Outlook compatibility
    -- =============================================
    v_email_subject := 'Rays VOC Report Card - ' || v_game_date_display || ' VS ' || v_opponent;

    v_html_body := '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head><body style="margin:0;padding:0;background-color:#f4f4f4;font-family:Arial,Helvetica,sans-serif;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f4f4;"><tr><td align="center" style="padding:20px 10px;"><table role="presentation" width="640" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">';

    -- HEADER with logos
    -- bgcolor="#092C5C" is the critical fallback — email clients (Outlook, Gmail) often strip
    -- CSS background/background-color from style attributes but always honor the bgcolor HTML attribute.
    v_html_body := v_html_body || '<tr><td bgcolor="#092C5C" style="background-color:#092C5C;background:linear-gradient(135deg, #092C5C 0%, #1a4a8a 100%);padding:24px 20px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td width="60" style="text-align:left;vertical-align:middle;"><img src="' || v_opponent_logo_url || '" alt="' || v_opponent || '" width="50" height="50" style="display:block;border:0;outline:none;" /></td><td style="text-align:center;vertical-align:middle;padding:0 10px;"><div style="font-size:13px;letter-spacing:3px;color:#8FBCE6;font-weight:600;margin-bottom:6px;">TAMPA BAY RAYS</div><div style="font-size:26px;font-weight:700;color:#ffffff;margin-bottom:4px;">GAME DAY REPORT CARD</div><div style="font-size:14px;color:#8FBCE6;margin-top:10px;">' || v_header_line || ' &nbsp;|&nbsp; ' || v_response_count::VARCHAR || ' Survey Responses</div></td><td width="60" style="text-align:right;vertical-align:middle;"><img src="' || v_rays_logo_url || '" alt="Rays" width="50" height="50" style="display:block;border:0;outline:none;margin-left:auto;" /></td></tr></table></td></tr>';

    -- SECTIONS 1, PIE & 2 side by side with MSO conditional comments
    v_html_body := v_html_body || '<tr><td style="padding:20px 24px 0 24px;"><!--[if mso]><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td width="172" valign="top"><![endif]--><div style="display:inline-block;vertical-align:top;width:100%;max-width:172px;margin-right:12px;">';

    -- SECTION 1: OVERALL score card
    v_html_body := v_html_body || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:8px;"><tr><td style="padding:6px 0 4px 0;font-size:10px;letter-spacing:1.5px;color:#092C5C;font-weight:700;text-align:center;">&#128202; OVERALL</td></tr><tr><td style="background-color:#092C5C;border-radius:8px;padding:16px 18px;text-align:center;"><div style="font-size:36px;font-weight:800;color:#ffffff;line-height:1.1;">' || v_game_avg_display || '</div><div style="font-size:11px;color:#8FBCE6;margin-top:2px;">out of 10</div><div style="margin-top:8px;font-size:14px;font-weight:700;color:' || v_gap_color || ';">' || v_gap_icon || ' ' || ABS(v_gap_pct)::VARCHAR || '% vs 2026 avg</div></td></tr><tr><td style="padding:14px 0 0 0;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="padding:4px 0;font-size:11px;color:#555;">Season Avg</td><td style="padding:4px 0;font-size:11px;color:#092C5C;font-weight:700;text-align:right;">' || v_season_avg_display || '/10</td></tr><tr><td style="padding:4px 0;font-size:11px;color:#555;border-top:1px solid #e8eaed;">Game Responses</td><td style="padding:4px 0;font-size:11px;color:#092C5C;font-weight:700;text-align:right;border-top:1px solid #e8eaed;">' || v_response_count::VARCHAR || '</td></tr><tr><td style="padding:4px 0;font-size:11px;color:#555;border-top:1px solid #e8eaed;">Season Responses</td><td style="padding:4px 0;font-size:11px;color:#092C5C;font-weight:700;text-align:right;border-top:1px solid #e8eaed;">' || v_season_responses::VARCHAR || '</td></tr></table></td></tr></table></div>';

    -- MSO separator + PIE CHART column (between Overall and Qualitative)
    v_html_body := v_html_body || '<!--[if mso]></td><td width="152" valign="top"><![endif]--><div style="display:inline-block;vertical-align:top;width:100%;max-width:152px;margin-right:12px;text-align:center;">';
    v_html_body := v_html_body || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="padding:6px 0 4px 0;font-size:10px;letter-spacing:1.5px;color:#092C5C;font-weight:700;text-align:center;">&#128202; OVERALL SPLIT</td></tr>';
    v_html_body := v_html_body || '<tr><td style="text-align:center;padding:0;">' || v_svg || '</td></tr>';
    v_html_body := v_html_body || '<tr><td style="padding:6px 0 0 0;"><table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 auto;"><tr><td style="padding:2px 4px;"><span style="display:inline-block;width:11px;height:11px;background-color:#2ecc71;border-radius:2px;"></span></td><td style="padding:2px 4px;font-size:10px;color:#333;">9 &amp; above</td></tr><tr><td style="padding:2px 4px;"><span style="display:inline-block;width:11px;height:11px;background-color:#f5b7b1;border-radius:2px;"></span></td><td style="padding:2px 4px;font-size:10px;color:#333;">8 &amp; below</td></tr></table></td></tr></table></div>';

    -- MSO separator for Qualitative column
    v_html_body := v_html_body || '<!--[if mso]></td><td width="244" valign="top"><![endif]--><div style="display:inline-block;vertical-align:top;width:100%;max-width:244px;">';

    -- SECTION 2: QUALITATIVE SUMMARY (no departments shown)
    v_html_body := v_html_body || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="padding:6px 0 4px 0;font-size:10px;letter-spacing:1.5px;color:#092C5C;font-weight:700;text-align:center;">&#128172; QUALITATIVE &mdash; <a href="' || v_csv_url || '" style="color:#1a73e8;text-decoration:underline;font-weight:700;">DEEP DIVE</a></td></tr></table>';

    -- Positive topics (no department names)
    v_html_body := v_html_body || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:32px;"><tr><td style="padding:6px 10px;background-color:#f0fff4;border-left:3px solid #2ecc71;border-radius:0 6px 6px 0;"><div style="font-size:10px;font-weight:700;color:#1a7431;letter-spacing:0.5px;margin-bottom:4px;">&#9989; POSITIVE FEEDBACK &middot; ' || v_positive_total::VARCHAR || ' (' || v_positive_pct || '%)</div><div style="font-size:11px;color:#333;line-height:1.6;"><div><strong>' || v_pos_topic_1 || '</strong> <span style="color:#1a7431;font-weight:600;">' || v_pos_topic_1_pct || '%</span></div><div><strong>' || v_pos_topic_2 || '</strong> <span style="color:#1a7431;font-weight:600;">' || v_pos_topic_2_pct || '%</span></div><div><strong>' || v_pos_topic_3 || '</strong> <span style="color:#1a7431;font-weight:600;">' || v_pos_topic_3_pct || '%</span></div></div></td></tr></table>';

    -- Negative topics (no department names)
    v_html_body := v_html_body || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="padding:6px 10px;background-color:#fff5f5;border-left:3px solid #e74c3c;border-radius:0 6px 6px 0;"><div style="font-size:10px;font-weight:700;color:#c0392b;letter-spacing:0.5px;margin-bottom:4px;">&#9888;&#65039; NEGATIVE FEEDBACK &middot; ' || v_negative_total::VARCHAR || ' (' || v_negative_pct || '%)</div><div style="font-size:11px;color:#333;line-height:1.6;"><div><strong>' || v_neg_topic_1 || '</strong> <span style="color:#c0392b;font-weight:600;">' || v_neg_topic_1_pct || '%</span></div><div><strong>' || v_neg_topic_2 || '</strong> <span style="color:#c0392b;font-weight:600;">' || v_neg_topic_2_pct || '%</span></div><div><strong>' || v_neg_topic_3 || '</strong> <span style="color:#c0392b;font-weight:600;">' || v_neg_topic_3_pct || '%</span></div></div></td></tr></table></div><!--[if mso]></td></tr></table><![endif]--></td></tr>';

    -- DIVIDER
    v_html_body := v_html_body || '<tr><td style="padding:14px 24px;"><hr style="border:none;border-top:2px solid #e8eaed;margin:0;"></td></tr>';

    -- SECTION 3: QUANTITATIVE SUMMARY with natural language (conditional takeaways)
    -- Only include the section if there is at least one positive or negative takeaway
    IF (v_best1_label != 'N/A' OR v_worst1_label != 'N/A') THEN
        v_html_body := v_html_body || '<tr><td style="padding:0 24px 20px 24px;"><div style="font-size:10px;letter-spacing:1.5px;color:#092C5C;font-weight:700;margin-bottom:10px;">&#127919; QUANTITATIVE SUMMARY <span style="font-weight:400;color:#888;letter-spacing:0;">&mdash; Game vs 2026 avg (~30 metrics)</span></div>';

        -- Positive takeaways (only if at least one metric is above season avg)
        IF (v_best1_label != 'N/A') THEN
            v_html_body := v_html_body || '<div style="padding:10px 14px;background-color:#f0fff4;border-left:3px solid #2ecc71;border-radius:0 6px 6px 0;margin-bottom:8px;"><div style="font-size:10px;font-weight:700;color:#1a7431;letter-spacing:0.5px;margin-bottom:5px;">POSITIVE TAKEAWAYS</div><div style="font-size:12px;color:#333;line-height:1.8;">';
            v_html_body := v_html_body || '<div>&#9650; Fans highly satisfied with <strong>' || v_best1_label || '</strong> was <span style="color:#1a7431;font-weight:700;">' || v_best1_delta || v_best1_suffix || '</span> than the season average</div>';
            IF (v_best2_label != 'N/A') THEN
                v_html_body := v_html_body || '<div>&#9650; Fans highly satisfied with <strong>' || v_best2_label || '</strong> was <span style="color:#1a7431;font-weight:700;">' || v_best2_delta || v_best2_suffix || '</span> than the season average</div>';
            END IF;
            IF (v_best3_label != 'N/A') THEN
                v_html_body := v_html_body || '<div>&#9650; Fans highly satisfied with <strong>' || v_best3_label || '</strong> was <span style="color:#1a7431;font-weight:700;">' || v_best3_delta || v_best3_suffix || '</span> than the season average</div>';
            END IF;
            v_html_body := v_html_body || '</div></div>';
        END IF;

        -- Negative takeaways (only if at least one metric is below season avg)
        IF (v_worst1_label != 'N/A') THEN
            v_html_body := v_html_body || '<div style="padding:10px 14px;background-color:#fff5f5;border-left:3px solid #e74c3c;border-radius:0 6px 6px 0;margin-bottom:8px;"><div style="font-size:10px;font-weight:700;color:#c0392b;letter-spacing:0.5px;margin-bottom:5px;">NEGATIVE TAKEAWAYS</div><div style="font-size:12px;color:#333;line-height:1.8;">';
            v_html_body := v_html_body || '<div>&#9660; Fans highly dissatisfied with <strong>' || v_worst1_label || '</strong> was <span style="color:#c0392b;font-weight:700;">' || v_worst1_delta || v_worst1_suffix || '</span> than the season average</div>';
            IF (v_worst2_label != 'N/A') THEN
                v_html_body := v_html_body || '<div>&#9660; Fans highly dissatisfied with <strong>' || v_worst2_label || '</strong> was <span style="color:#c0392b;font-weight:700;">' || v_worst2_delta || v_worst2_suffix || '</span> than the season average</div>';
            END IF;
            IF (v_worst3_label != 'N/A') THEN
                v_html_body := v_html_body || '<div>&#9660; Fans highly dissatisfied with <strong>' || v_worst3_label || '</strong> was <span style="color:#c0392b;font-weight:700;">' || v_worst3_delta || v_worst3_suffix || '</span> than the season average</div>';
            END IF;
            v_html_body := v_html_body || '</div></div>';
        END IF;

        v_html_body := v_html_body || '</td></tr>';
    END IF;

    -- Actionable items (AI-generated) - always shown
    v_html_body := v_html_body || '<tr><td style="padding:0 24px 20px 24px;"><div style="padding:10px 14px;background-color:#f0f7ff;border-left:3px solid #3498db;border-radius:0 6px 6px 0;"><div style="font-size:10px;font-weight:700;color:#2471a3;letter-spacing:0.5px;margin-bottom:4px;">ACTIONABLE ITEMS</div><div style="font-size:12px;color:#333;line-height:1.5;">' || v_action_items || '</div></div></td></tr>';

    -- FOOTER
    v_html_body := v_html_body || '<tr><td bgcolor="#092C5C" style="background-color:#092C5C;padding:16px 40px;text-align:center;"><div style="font-size:10px;color:#8FBCE6;line-height:1.5;">Data sourced from post-game VOC survey &nbsp;|&nbsp; ' || v_response_count::VARCHAR || ' responses &nbsp;|&nbsp; ' || v_header_line || '<br>Powered by Snowflake Cortex AI &nbsp;|&nbsp; Tampa Bay Rays Strategy &amp; Analytics<br>Click <a href="https://prod-useast-b.online.tableau.com/#/site/tampabayrays/projects/2351593" style="color:#ffffff;">here</a> for further dashboard insights</div></td></tr>';

    v_html_body := v_html_body || '</table></td></tr></table></body></html>';

    -- =============================================
    -- SEND EMAIL
    -- =============================================
    CALL SYSTEM$SEND_EMAIL(
        'VOC_REPORT_CARD_EMAIL',
        'abuchner@raysbaseball.com,ytaketani@raysbaseball.com',
        :v_email_subject,
        :v_html_body,
        'text/html'
    );

    RETURN 'Report Card sent for ' || v_header_line
        || ' | Score: ' || v_game_avg_display || '/10'
        || ' | Gap: ' || v_gap_pct::VARCHAR || '%'
        || ' | Best: ' || v_best1_label || ' (' || v_best1_delta || v_best1_suffix || ')'
        || ' | Worst: ' || v_worst1_label || ' (' || v_worst1_delta || v_worst1_suffix || ')';
END;
$$;
