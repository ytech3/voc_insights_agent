-- =====================================================
-- VOC REPORT CARD - STEP 3 OF 3
-- Create the Automated Tasks (daily schedule)
-- =====================================================
-- INSTRUCTIONS:
--   1. Open this file in a NEW Snowsight SQL Worksheet
--   2. Set Role to ACCOUNTADMIN (top-left dropdown)
--   3. Set Warehouse to TBRDP_DW_CORTEX_XS_WH
--   4. Select ALL text (Ctrl+A), then click "Run All" (Ctrl+Shift+Enter)
-- =====================================================
-- NOTE: All tasks are created in a PAUSED state by default.
--       After verifying the procedure works correctly with:
--         CALL TBRDP_DW_DEV.IM_RPT.SP_VOC_DAILY_REPORT_CARD('2024-03-28');
--       Uncomment and run the ALTER TASK RESUME lines below.
-- =====================================================
-- PIPELINE ORDER (DAG):
--   10:15 AM ET — TSK_REFRESH_SENTENCE_LEVEL_YESTERDAY (yesterday's game only)   [root]
--       AFTER  — TASK_VOC_DAILY_REPORT_CARD (report card email)                   [child 1]
--           AFTER  — TSK_REFRESH_SENTENCE_LEVEL_BACKFILL (prior games backfill)   [child 2]
-- =====================================================

-- =====================================================
-- PRE-REQUISITE: Update AI Views to use llama3.1-70b
-- (cost-efficient model: 1.21 credits/M tokens, native to Azure East US 2)
-- =====================================================

-- VIEW 1: Overall Feedback Sentence-Level Analysis (used by the task MERGE)
CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_SENTENCE_LEVEL(
    QUALTRICS_ID,
    SEASON,
    GAME_DATE,
    BUYER_TYPE,
    SECTION_CODE,
    ORIGINAL_FEEDBACK,
    SATISFACTION_RATING,
    SENTENCE_NUMBER,
    SENTENCE_TEXT,
    SENTIMENT_CATEGORY,
    AI_CATEGORY,
    PARENT_CATEGORY,
    DETAILED_CATEGORY,
    SENTENCE_LENGTH,
    NPS_SEGMENT
) COMMENT='Sentence-level analysis of OVERALL_NUMRAT_OT using AI_COMPLETE (llama3.1-70b).
Uses fine-grained categories aligned with Rays departments. Covers seasons 2023+.
Updated June 2026: Migrated to llama3.1-70b with condensed prompt for cost efficiency.
Sentence filter: 3+ words and 11+ characters.'
AS
WITH feedback_data AS (
  SELECT QUALTRICS_ID, SEASON, GAME_DATE, BUYER_TYPE, SECTION_CODE,
    OVERALL_NUMRAT_OT AS feedback_text, OVERALL_NUMRAT AS satisfaction_rating
  FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
  WHERE OVERALL_NUMRAT_OT IS NOT NULL AND LENGTH(TRIM(OVERALL_NUMRAT_OT)) > 10 AND season >= 2023
),
combined_analysis AS (
  SELECT QUALTRICS_ID, SEASON, GAME_DATE, BUYER_TYPE, SECTION_CODE, feedback_text, satisfaction_rating,
    AI_COMPLETE(
      'llama3.1-70b',
      'Split this baseball stadium fan feedback into sentences. Classify each sentence.

FEEDBACK: ' || feedback_text || '

Return ONLY a JSON array. Each element: {"sentence":"...","sentiment":"Positive|Neutral|Negative","category":"..."}

CATEGORIES (use exactly one):
Food Quality, Beverage Quality, Concession Wait Times, Concession Staff Service, Food Cost, Beverage Cost, Menu Variety, Hot Dogs, Pizza, Burger, Fries, Vegan Options, Alcohol, Alcohol Pricing, Concessions Ordering Process, Merchandise Selection, Merchandise Cost, Team Store Experience, Team Store Line, In Game Entertainment, Game Production, Promotions, Music, Scoreboard, Lights, Stadium Atmosphere, Pregame, Postgame, Fan Host and Ushers, Concessions Staff, Retail Staff, Parking Staff, Ticket Takers, Security Staff, ADA Staff, Tech Team, General Staff Service, ADA Accessibility, Venue Cleanliness, Wayfinding, Restroom Experience, Run the Bases, Autographs, Giveaway, Parking Availability, Departure Traffic, Parking Cost, Facility Maintenance, Gate Entry Speed, Air Conditioning, Bathroom Cleanliness, Mobile App, In-Venue Wi-Fi, Mobile Ordering, Seat Upgrade, Go Ahead Entry, Ticket Purchase Process, Mobile Ticketing, Ticketing Value Perception, Ticket Pricing, Seating Locations, Premium Experience, Baldwin Group Club, Suites, Skydeck, All Inclusive F&B, Seat View, Seating Comfort, Raymond the Mascot, Theme/Heritage Night, Concert Experience, Concert Artist, Kids Club, Team Performance, General Positive, General Negative, Unclassifiable

KEY RULES:
- Pick the MOST SPECIFIC category. Do NOT invent categories.
- "Fan Host and Ushers" ONLY if usher/fan host/greeter explicitly named. Generic staff praise = "General Staff Service".
- "Stadium Atmosphere" for crowd/energy/vibe. Generic praise ("great time") = "General Positive".
- "Team Performance" for wins/losses/players. NOT "In Game Entertainment".
- "Ticket Takers" for gate staff behavior. Gate wait time = "Gate Entry Speed".
- "Concession Staff Service" for food/bev service complaints. Exact spelling required.
- "Unclassifiable" ONLY when meaning is genuinely unclear (fragments like "meh", "N/A", "idk").
- Return ONLY the JSON array.',
      {'temperature': 0.1, 'max_tokens': 2000}
    ) AS analysis_json
  FROM feedback_data
),
cleaned_analysis AS (
  SELECT QUALTRICS_ID, SEASON, GAME_DATE, BUYER_TYPE, SECTION_CODE, feedback_text, satisfaction_rating,
    TRIM(REGEXP_REPLACE(REGEXP_REPLACE(analysis_json, '```json', ''), '```', '')) AS cleaned_json
  FROM combined_analysis WHERE analysis_json IS NOT NULL
),
parsed_analysis AS (
  SELECT QUALTRICS_ID, SEASON, GAME_DATE, BUYER_TYPE, SECTION_CODE,
    feedback_text AS original_feedback, satisfaction_rating,
    TRY_PARSE_JSON(cleaned_json) AS sentences_array
  FROM cleaned_analysis
),
flattened AS (
  SELECT QUALTRICS_ID, SEASON, GAME_DATE, BUYER_TYPE, SECTION_CODE, original_feedback, satisfaction_rating,
    sentence.INDEX + 1 AS sentence_number,
    TRIM(sentence.VALUE:sentence::STRING) AS sentence_text,
    TRIM(sentence.VALUE:sentiment::STRING) AS sentiment_category,
    TRIM(sentence.VALUE:category::STRING) AS ai_category
  FROM parsed_analysis, LATERAL FLATTEN(input => sentences_array) sentence
  WHERE sentence.VALUE:sentence IS NOT NULL 
    AND LENGTH(TRIM(sentence.VALUE:sentence::STRING)) > 10
    AND ARRAY_SIZE(SPLIT(TRIM(sentence.VALUE:sentence::STRING), ' ')) >= 3
)
SELECT QUALTRICS_ID, SEASON, GAME_DATE, BUYER_TYPE, SECTION_CODE, original_feedback, satisfaction_rating,
  sentence_number, sentence_text, sentiment_category, ai_category,
  CASE 
    WHEN ai_category IN ('Food Quality','Beverage Quality','Concession Wait Times','Concession Staff Service',
      'Concessions Staff Service',
      'Food Cost','Beverage Cost','Menu Variety','Hot Dogs','Pizza','Burger','Fries','Vegan Options',
      'Alcohol','Alcohol Pricing','Concessions Ordering Process') THEN 'Concessions'
    WHEN ai_category IN ('Merchandise Selection','Merchandise Cost','Team Store Experience','Team Store Line') THEN 'Retail'
    WHEN ai_category IN ('In Game Entertainment','Game Production','Promotions','Music','Scoreboard','Lights',
      'Stadium Atmosphere','Pregame','Postgame') THEN 'Game Entertainment'
    WHEN ai_category IN ('Fan Host and Ushers','Concessions Staff','Retail Staff','Parking Staff',
      'Ticket Takers','Security Staff','ADA Staff','Tech Team','General Staff Service') THEN 'Staff Service'
    WHEN ai_category IN ('ADA Accessibility','Venue Cleanliness','Wayfinding','Restroom Experience',
      'Run the Bases','Autographs','Giveaway','Parking Availability','Departure Traffic','Parking Cost',
      'General Positive','General Negative') THEN 'Fan Experience'
    WHEN ai_category IN ('Facility Maintenance','Gate Entry Speed','Air Conditioning','Bathroom Cleanliness') THEN 'Stadium Operations'
    WHEN ai_category IN ('Mobile App','In-Venue Wi-Fi','Mobile Ordering','Seat Upgrade',
      'Go Ahead Entry') THEN 'Digital Experience'
    WHEN ai_category IN ('Ticket Purchase Process','Mobile Ticketing','Ticketing Value Perception','Ticket Pricing',
      'Seating Locations','Premium Experience','Baldwin Group Club','Suites',
      'Skydeck','All Inclusive F&B','Seat View','Seating Comfort') THEN 'Ticketing'
    WHEN ai_category IN ('Raymond the Mascot','Theme/Heritage Night','Concert Experience','Concert Artist',
      'Kids Club') THEN 'Marketing'
    WHEN ai_category = 'Team Performance' THEN 'Team Performance'
    WHEN ai_category = 'Unclassifiable' THEN 'Unclassifiable'
    ELSE 'Uncategorized'
  END AS parent_category,
  CONCAT(ai_category, ' - ', sentiment_category) AS detailed_category,
  LENGTH(sentence_text) AS sentence_length,
  CASE WHEN satisfaction_rating >= 9 THEN 'Promoter' WHEN satisfaction_rating >= 7 THEN 'Passive' ELSE 'Detractor' END AS nps_segment
FROM flattened;

-- VIEW 2: Qualitative Feedback Sentence-Level (fixes broken snowflake-llama3.3-70b)
CREATE OR REPLACE VIEW TBRDP_DW_DEV.IM_RPT.V_QUALITATIVE_FEEDBACK_SENTENCE_LEVEL(
    QUALTRICS_ID,
    GAME_DATE,
    SEASON,
    BUYER_TYPE,
    FEEDBACK_SOURCE,
    SOURCE_FIELD,
    ORIGINAL_FEEDBACK,
    SENTENCE_NUMBER,
    SENTENCE_TEXT,
    SENTIMENT_CATEGORY,
    SENTENCE_LENGTH
) COMMENT='Sentence-level analysis of ALL qualitative feedback fields (2023+).
Updated June 2026: Migrated to llama3.1-70b for cost efficiency.'
AS
WITH raw AS (
  SELECT
    qualtrics_id,
    game_date,
    season,
    buyer_type,
    feedback_source,
    source_field,
    feedback_text
  FROM TBRDP_DW_DEV.IM_RPT.V_QUALITATIVE_FEEDBACK_ALL
),

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
      'llama3.1-70b',
      'Split the following fan feedback into individual sentences. For each sentence, classify the sentiment.

FEEDBACK: ' || feedback_text || '

Return ONLY a valid JSON array. Each element must have:
- "sentence": the exact sentence text
- "sentiment": exactly one of "Positive", "Neutral", or "Negative"

Example:
[{"sentence":"The ushers were very friendly.","sentiment":"Positive"},
 {"sentence":"The bathrooms were dirty.","sentiment":"Negative"}]',
      {
        'temperature': 0.1,
        'max_tokens': 1500
      }
    ) AS analysis_json
  FROM raw
),

parsed AS (
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
    TRIM(sentence.VALUE:sentiment::STRING) AS sentiment_category
  FROM parsed,
  LATERAL FLATTEN(input => sentences_array) sentence
  WHERE sentence.VALUE:sentence IS NOT NULL
    AND LENGTH(TRIM(sentence.VALUE:sentence::STRING)) > 5
)

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
  LENGTH(sentence_text) AS sentence_length
FROM flattened
ORDER BY season DESC, game_date DESC, qualtrics_id, feedback_source, sentence_number;

-- =====================================================
-- TASK 1 (Root): Yesterday's Game Sentence-Level Refresh (10:00 AM ET)
-- Incrementally populates T_OVERALL_FEEDBACK_SENTENCE_LEVEL
-- with AI-generated sentence splits, sentiment, and categories
-- ONLY for yesterday's game date.
-- Processes 10 responses per loop iteration to stay within
-- the 1,200-second account-level statement timeout limit.
-- Compares at QUALTRICS_ID level (not GAME_DATE) so that
-- late-arriving survey responses are always captured.
-- =====================================================
CREATE OR REPLACE TASK TBRDP_DW_DEV.IM_RPT.TSK_REFRESH_SENTENCE_LEVEL_YESTERDAY
    WAREHOUSE = TBRDP_DW_CORTEX_XS_WH
    SCHEDULE = 'USING CRON 15 10 * * * America/New_York'
    USER_TASK_TIMEOUT_MS = 7200000
    COMMENT = 'Processes sentence-level AI analysis for YESTERDAY''s game only. Runs daily at 10:15 AM ET. Batches of 50 responses via MERGE (dedup-safe). Must complete before report card is sent.'
AS
BEGIN
    LET v_remaining NUMBER := 1;
    LET v_yesterday DATE := CURRENT_DATE() - 1;

    WHILE (v_remaining > 0) DO
        -- Create a temp table with the next 50 unprocessed IDs from yesterday's game
        -- Filter: 3+ words required to match the view's sentence-level output filter
        CREATE OR REPLACE TEMPORARY TABLE TBRDP_DW_DEV.IM_RPT.TMP_SENTENCE_BATCH AS
        SELECT q.QUALTRICS_ID
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI q
        WHERE q.OVERALL_NUMRAT_OT IS NOT NULL
          AND LENGTH(TRIM(q.OVERALL_NUMRAT_OT)) > 10
          AND ARRAY_SIZE(SPLIT(TRIM(q.OVERALL_NUMRAT_OT), ' ')) >= 3
          AND q.SEASON >= 2026
          AND q.GAME_DATE::DATE = :v_yesterday
          AND q.QUALTRICS_ID NOT IN (
              SELECT DISTINCT QUALTRICS_ID
              FROM TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL
          )
        ORDER BY q.GAME_DATE DESC
        LIMIT 50;

        -- Process this batch through the AI view and MERGE (prevents duplicates)
        MERGE INTO TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL tgt
        USING (
            SELECT
                v.QUALTRICS_ID, v.SEASON, v.GAME_DATE, v.BUYER_TYPE, v.SECTION_CODE, v.ORIGINAL_FEEDBACK, v.SATISFACTION_RATING,
                v.SENTENCE_NUMBER, v.SENTENCE_TEXT, v.SENTIMENT_CATEGORY, v.AI_CATEGORY, v.PARENT_CATEGORY,
                v.DETAILED_CATEGORY, v.SENTENCE_LENGTH, v.NPS_SEGMENT
            FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_SENTENCE_LEVEL v
            INNER JOIN TBRDP_DW_DEV.IM_RPT.TMP_SENTENCE_BATCH b
                ON v.QUALTRICS_ID = b.QUALTRICS_ID
        ) src
        ON tgt.QUALTRICS_ID = src.QUALTRICS_ID AND tgt.SENTENCE_NUMBER = src.SENTENCE_NUMBER
        WHEN NOT MATCHED THEN INSERT
            (QUALTRICS_ID, SEASON, GAME_DATE, BUYER_TYPE, SECTION_CODE, ORIGINAL_FEEDBACK, SATISFACTION_RATING,
             SENTENCE_NUMBER, SENTENCE_TEXT, SENTIMENT_CATEGORY, AI_CATEGORY, PARENT_CATEGORY,
             DETAILED_CATEGORY, SENTENCE_LENGTH, NPS_SEGMENT)
        VALUES
            (src.QUALTRICS_ID, src.SEASON, src.GAME_DATE, src.BUYER_TYPE, src.SECTION_CODE, src.ORIGINAL_FEEDBACK, src.SATISFACTION_RATING,
             src.SENTENCE_NUMBER, src.SENTENCE_TEXT, src.SENTIMENT_CATEGORY, src.AI_CATEGORY, src.PARENT_CATEGORY,
             src.DETAILED_CATEGORY, src.SENTENCE_LENGTH, src.NPS_SEGMENT);

        -- Drop temp table
        DROP TABLE IF EXISTS TBRDP_DW_DEV.IM_RPT.TMP_SENTENCE_BATCH;

        -- Check how many unprocessed responses remain for yesterday
        -- Must match the same 3+ word filter to avoid infinite loop on short comments
        SELECT COUNT(DISTINCT q.QUALTRICS_ID)
        INTO :v_remaining
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI q
        WHERE q.OVERALL_NUMRAT_OT IS NOT NULL
          AND LENGTH(TRIM(q.OVERALL_NUMRAT_OT)) > 10
          AND ARRAY_SIZE(SPLIT(TRIM(q.OVERALL_NUMRAT_OT), ' ')) >= 3
          AND q.SEASON >= 2026
          AND q.GAME_DATE::DATE = :v_yesterday
          AND q.QUALTRICS_ID NOT IN (
              SELECT DISTINCT QUALTRICS_ID
              FROM TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL
          );
    END WHILE;
END;

-- =====================================================
-- TASK 2 (Child of Task 1): VOC Report Card Email
-- Sends the daily report card if a game was played yesterday.
-- Uses AFTER clause to guarantee yesterday's sentence-level data is ready.
-- =====================================================
CREATE OR REPLACE TASK TBRDP_DW_DEV.IM_RPT.TASK_VOC_DAILY_REPORT_CARD
    WAREHOUSE = TBRDP_DW_CORTEX_XS_WH
    COMMENT = 'Sends daily VOC Game Day Report Card after yesterday''s sentence-level analysis completes'
    AFTER TBRDP_DW_DEV.IM_RPT.TSK_REFRESH_SENTENCE_LEVEL_YESTERDAY
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

-- =====================================================
-- TASK 3 (Child of Task 2): Backfill Prior Games
-- Processes any remaining unprocessed 2026+ sentence-level
-- analysis from games BEFORE yesterday.
-- Runs AFTER the report card is sent so backfill does not
-- block the daily delivery.
-- =====================================================
CREATE OR REPLACE TASK TBRDP_DW_DEV.IM_RPT.TSK_REFRESH_SENTENCE_LEVEL_BACKFILL
    WAREHOUSE = TBRDP_DW_CORTEX_XS_WH
    USER_TASK_TIMEOUT_MS = 25200000
    COMMENT = 'Backfills sentence-level AI analysis for any prior 2026+ games not yet processed. Runs AFTER report card is sent. Batches of 50 responses via MERGE (dedup-safe), newest games first.'
    AFTER TBRDP_DW_DEV.IM_RPT.TASK_VOC_DAILY_REPORT_CARD
AS
BEGIN
    LET v_remaining NUMBER := 1;
    LET v_yesterday DATE := CURRENT_DATE() - 1;

    WHILE (v_remaining > 0) DO
        -- Create a temp table with the next 50 unprocessed IDs from PRIOR games (not yesterday)
        -- Filter: 3+ words required to match the view's sentence-level output filter
        CREATE OR REPLACE TEMPORARY TABLE TBRDP_DW_DEV.IM_RPT.TMP_SENTENCE_BATCH AS
        SELECT q.QUALTRICS_ID
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI q
        WHERE q.OVERALL_NUMRAT_OT IS NOT NULL
          AND LENGTH(TRIM(q.OVERALL_NUMRAT_OT)) > 10
          AND ARRAY_SIZE(SPLIT(TRIM(q.OVERALL_NUMRAT_OT), ' ')) >= 3
          AND q.SEASON >= 2026
          AND q.GAME_DATE::DATE < :v_yesterday
          AND q.QUALTRICS_ID NOT IN (
              SELECT DISTINCT QUALTRICS_ID
              FROM TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL
          )
        ORDER BY q.GAME_DATE DESC
        LIMIT 50;

        -- Process this batch through the AI view and MERGE (prevents duplicates)
        MERGE INTO TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL tgt
        USING (
            SELECT
                v.QUALTRICS_ID, v.SEASON, v.GAME_DATE, v.BUYER_TYPE, v.SECTION_CODE, v.ORIGINAL_FEEDBACK, v.SATISFACTION_RATING,
                v.SENTENCE_NUMBER, v.SENTENCE_TEXT, v.SENTIMENT_CATEGORY, v.AI_CATEGORY, v.PARENT_CATEGORY,
                v.DETAILED_CATEGORY, v.SENTENCE_LENGTH, v.NPS_SEGMENT
            FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_SENTENCE_LEVEL v
            INNER JOIN TBRDP_DW_DEV.IM_RPT.TMP_SENTENCE_BATCH b
                ON v.QUALTRICS_ID = b.QUALTRICS_ID
        ) src
        ON tgt.QUALTRICS_ID = src.QUALTRICS_ID AND tgt.SENTENCE_NUMBER = src.SENTENCE_NUMBER
        WHEN NOT MATCHED THEN INSERT
            (QUALTRICS_ID, SEASON, GAME_DATE, BUYER_TYPE, SECTION_CODE, ORIGINAL_FEEDBACK, SATISFACTION_RATING,
             SENTENCE_NUMBER, SENTENCE_TEXT, SENTIMENT_CATEGORY, AI_CATEGORY, PARENT_CATEGORY,
             DETAILED_CATEGORY, SENTENCE_LENGTH, NPS_SEGMENT)
        VALUES
            (src.QUALTRICS_ID, src.SEASON, src.GAME_DATE, src.BUYER_TYPE, src.SECTION_CODE, src.ORIGINAL_FEEDBACK, src.SATISFACTION_RATING,
             src.SENTENCE_NUMBER, src.SENTENCE_TEXT, src.SENTIMENT_CATEGORY, src.AI_CATEGORY, src.PARENT_CATEGORY,
             src.DETAILED_CATEGORY, src.SENTENCE_LENGTH, src.NPS_SEGMENT);

        -- Drop temp table
        DROP TABLE IF EXISTS TBRDP_DW_DEV.IM_RPT.TMP_SENTENCE_BATCH;

        -- Check how many unprocessed responses remain from prior games
        -- Must match the same 3+ word filter to avoid infinite loop on short comments
        SELECT COUNT(DISTINCT q.QUALTRICS_ID)
        INTO :v_remaining
        FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI q
        WHERE q.OVERALL_NUMRAT_OT IS NOT NULL
          AND LENGTH(TRIM(q.OVERALL_NUMRAT_OT)) > 10
          AND ARRAY_SIZE(SPLIT(TRIM(q.OVERALL_NUMRAT_OT), ' ')) >= 3
          AND q.SEASON >= 2026
          AND q.GAME_DATE::DATE < :v_yesterday
          AND q.QUALTRICS_ID NOT IN (
              SELECT DISTINCT QUALTRICS_ID
              FROM TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL
          );
    END WHILE;
END;

-- =====================================================
-- ACTIVATE TASKS (run AFTER testing the procedure)
-- IMPORTANT: Resume child tasks FIRST (deepest first), then root task.
-- =====================================================
-- ALTER TASK TBRDP_DW_DEV.IM_RPT.TSK_REFRESH_SENTENCE_LEVEL_BACKFILL RESUME;
-- ALTER TASK TBRDP_DW_DEV.IM_RPT.TASK_VOC_DAILY_REPORT_CARD RESUME;
-- ALTER TASK TBRDP_DW_DEV.IM_RPT.TSK_REFRESH_SENTENCE_LEVEL_YESTERDAY RESUME;

-- =====================================================
-- CLEANUP: Suspend/remove old tasks that are no longer needed
-- =====================================================
-- ALTER TASK TBRDP_DW_DEV.IM_RPT.TSK_SENTENCE_LEVEL_CATCHUP SUSPEND;
-- DROP TASK IF EXISTS TBRDP_DW_DEV.IM_RPT.TSK_REFRESH_SENTENCE_LEVEL_FEEDBACK;
