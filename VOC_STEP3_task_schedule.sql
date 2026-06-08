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
-- PRE-REQUISITE: Update AI Views to use claude-sonnet-4-6
-- (replaces deprecated mistral-large2 and broken snowflake-llama3.3-70b)
-- =====================================================

-- VIEW 1: Overall Feedback Sentence-Level Analysis (used by the task INSERT)
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
) COMMENT='Sentence-level analysis of OVERALL_NUMRAT_OT using AI_COMPLETE (claude-sonnet-4-6).
Uses fine-grained categories aligned with Rays departments. Covers seasons 2023+.
Updated June 2026: Migrated from mistral-large2 to claude-sonnet-4-6. Added SECTION_CODE passthrough. Added Unclassifiable category for ambiguous fragments.
Tightened sentence filter to 3+ words and 11+ characters.'
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
      'claude-sonnet-4-6',
      'Analyze this fan feedback from a baseball stadium. Split into sentences and classify each.

FEEDBACK: ' || feedback_text || '

Return ONLY a valid JSON array. Each element must have:
- "sentence": the exact sentence text
- "sentiment": exactly one of "Positive", "Neutral", or "Negative"
- "category": exactly one of these categories:
  "Food Quality", "Beverage Quality", "Concession Wait Times", "Concession Staff Service",
  "Food Cost", "Beverage Cost", "Menu Variety", "Hot Dogs", "Pizza", "Burger", "Fries",
  "Vegan Options", "Alcohol", "Alcohol Pricing", "Concessions Ordering Process",
  "Merchandise Selection", "Merchandise Cost", "Team Store Experience", "Team Store Line",
  "In Game Entertainment", "Game Production",
  "Promotions", "Music", "Scoreboard", "Lights", "Stadium Atmosphere", "Pregame", "Postgame",
  "Fan Host and Ushers", "Concessions Staff", "Retail Staff", "Parking Staff",
  "Ticket Takers", "Security Staff", "ADA Staff", "Tech Team", "General Staff Service",
  "ADA Accessibility", "Venue Cleanliness", "Wayfinding",
  "Restroom Experience",
  "Run the Bases", "Autographs", "Giveaway",
  "Parking Availability", "Departure Traffic", "Parking Cost",
  "Facility Maintenance", "Gate Entry Speed", "Air Conditioning", "Bathroom Cleanliness",
  "Mobile App", "In-Venue Wi-Fi", "Mobile Ordering", "Seat Upgrade", "Go Ahead Entry",
  "Ticket Purchase Process", "Mobile Ticketing", "Ticketing Value Perception", "Ticket Pricing",
  "Seating Locations", "Premium Experience", "Baldwin Group Club", "Suites",
  "Skydeck", "All Inclusive F&B", "Seat View", "Seating Comfort",
  "Raymond the Mascot", "Theme/Heritage Night", "Concert Experience", "Concert Artist", "Kids Club",
  "Team Performance",
  "General Positive", "General Negative",
  "Unclassifiable"

CLASSIFICATION RULES:
- You must ONLY use categories from the list above. Do NOT invent new categories. If none fits precisely, use "General Positive" or "General Negative" based on sentiment.
- "Unclassifiable" is for sentence fragments, single words, or phrases that are too vague or ambiguous to meaningfully classify into any specific category. If a sentence does not contain enough context to determine what aspect of the experience is being referenced, classify it as "Unclassifiable" with "Neutral" sentiment. Examples: "Almost Unintelligible", "Meh", "Whatever", "idk", "N/A", "See above", "Not sure". A sentence does NOT need perfect grammar or punctuation to be classifiable — partial sentences that clearly reference a topic (e.g., "food was cold") should still be classified normally. Only use "Unclassifiable" when the MEANING is genuinely unclear.
- Be SPECIFIC with categories. Pick the most precise category that fits.
- Food quality vs service speed are DIFFERENT categories (Food Quality vs Concession Wait Times).
- Comments about ordering food or the ordering process go to "Concessions Ordering Process".
- Comments about food/beverage service staff behavior, in-seat service staff, or concession worker attitude go to "Concession Staff Service" (NOT "Concessions Staff Service" — use the exact spelling).
- "Fan Host and Ushers" is ONLY for comments that explicitly mention ushers, fan hosts, or greeters by name or role. Examples: "the usher was amazing", "Fan Hosts are always welcoming", "Marshall the usher was great". Do NOT use this category for generic staff praise.
- "General Staff Service" is for generic or non-specific mentions of staff, employees, or personnel where no specific department or role is named. Examples: "friendly staff", "great employees", "everyone was so polite", "helpful personnel", "the workers were nice". If the fan does not specify WHICH staff (usher, concession worker, security, parking, etc.), use "General Staff Service".
- "Concessions Staff" is for general mentions of concession workers without specific service complaints. For specific service quality issues, use "Concession Staff Service".
- "Retail Staff" is for comments about team store or merchandise staff.
- "Parking Staff" is for comments about parking lot or garage staff behavior. Examples: "parking attendants were helpful".
- "Ticket Takers" is for comments about staff at entry gates scanning tickets or checking credentials. Examples: "the ticket taker was rude", "gate staff was unfriendly". Gate wait time or line speed goes to "Gate Entry Speed", NOT "Ticket Takers".
- "Security Staff" is for comments about security personnel behavior or interactions. Examples: "security was overly aggressive", "bag check staff were polite".
- "ADA Staff" is for comments about staff assisting with ADA/accessibility needs.
- "Tech Team" is for comments about technology support staff.
- "Team Performance" is for comments about how the team played, wins, losses, player performance, lineup, or game results. Examples: "We lost", "Great game by the Rays", "Love the team", "Terrible lineup", "The team played like garbage". Do NOT confuse with "In Game Entertainment".
- "Stadium Atmosphere" is for comments about the atmosphere, energy, vibe, or overall ambiance of the stadium, including references to the crowd, other fans, or the feeling in the building. Examples: "the atmosphere was electric", "great crowd tonight", "fans were loud", "great vibe", "amazing energy in the building". Do NOT use Stadium Atmosphere for generic praise — use "General Positive" instead.
- "General Positive" is for vague or generic positive statements that do not reference a specific topic. Examples: "Great time", "Had a blast", "Awesome experience", "We loved it", "Good time at the game". If a sentence is broadly positive but does not mention any specific aspect (food, staff, crowd, parking, etc.), classify it as "General Positive".
- "General Negative" is for vague or generic negative statements that do not reference a specific topic. Examples: "Not a great experience", "Would not recommend", "Disappointing visit". If a sentence is broadly negative but does not mention any specific aspect, classify it as "General Negative".
- On-field entertainment, player interactions with fans, between-innings activities go to "In Game Entertainment".
- Scoreboard/video board comments go to "Scoreboard". Lighting comments go to "Lights".
- Parking-related comments go to "Parking Availability", "Departure Traffic", "Parking Cost", or "Parking Staff" as appropriate.
- Comments about leaving or exiting go to "Departure Traffic".
- Seat view comments go to "Seat View". Seat comfort comments go to "Seating Comfort".
- Skydeck area comments go to "Skydeck". All-inclusive food/beverage comments go to "All Inclusive F&B".
- Go Ahead Entry or early entry comments go to "Go Ahead Entry".
- Kids club or kids activities go to "Kids Club".
- Theme nights or heritage nights go to "Theme/Heritage Night".
- Air conditioning or temperature inside the stadium go to "Air Conditioning". Outdoor weather not relevant to the venue goes to "General Positive" or "General Negative".
- Return ONLY the JSON array, nothing else.

Example output:
[{"sentence":"The food was great","sentiment":"Positive","category":"Food Quality"},{"sentence":"Parking was terrible","sentiment":"Negative","category":"Parking Availability"},{"sentence":"Had a great time","sentiment":"Positive","category":"General Positive"},{"sentence":"The atmosphere was electric","sentiment":"Positive","category":"Stadium Atmosphere"},{"sentence":"The usher was very friendly","sentiment":"Positive","category":"Fan Host and Ushers"},{"sentence":"We lost but still had fun","sentiment":"Neutral","category":"Team Performance"},{"sentence":"The in-seat server was slow","sentiment":"Negative","category":"Concession Staff Service"},{"sentence":"Friendly staff","sentiment":"Positive","category":"General Staff Service"},{"sentence":"Almost Unintelligible","sentiment":"Neutral","category":"Unclassifiable"}]',
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
Updated June 2026: Migrated from snowflake-llama3.3-70b to claude-sonnet-4-6.'
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
      'claude-sonnet-4-6',
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
    COMMENT = 'Processes sentence-level AI analysis for YESTERDAY''s game only. Runs daily at 10:15 AM ET. Batches of 10 responses. Must complete before report card is sent.'
AS
BEGIN
    LET v_remaining NUMBER := 1;
    LET v_yesterday DATE := CURRENT_DATE() - 1;

    WHILE (v_remaining > 0) DO
        -- Create a temp table with the next 10 unprocessed IDs from yesterday's game
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
        LIMIT 10;

        -- Process this batch through the AI view
        INSERT INTO TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL
            (QUALTRICS_ID, SEASON, GAME_DATE, BUYER_TYPE, SECTION_CODE, ORIGINAL_FEEDBACK, SATISFACTION_RATING,
             SENTENCE_NUMBER, SENTENCE_TEXT, SENTIMENT_CATEGORY, AI_CATEGORY, PARENT_CATEGORY,
             DETAILED_CATEGORY, SENTENCE_LENGTH, NPS_SEGMENT)
        SELECT
            v.QUALTRICS_ID, v.SEASON, v.GAME_DATE, v.BUYER_TYPE, v.SECTION_CODE, v.ORIGINAL_FEEDBACK, v.SATISFACTION_RATING,
            v.SENTENCE_NUMBER, v.SENTENCE_TEXT, v.SENTIMENT_CATEGORY, v.AI_CATEGORY, v.PARENT_CATEGORY,
            v.DETAILED_CATEGORY, v.SENTENCE_LENGTH, v.NPS_SEGMENT
        FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_SENTENCE_LEVEL v
        INNER JOIN TBRDP_DW_DEV.IM_RPT.TMP_SENTENCE_BATCH b
            ON v.QUALTRICS_ID = b.QUALTRICS_ID;

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
    COMMENT = 'Backfills sentence-level AI analysis for any prior 2026+ games not yet processed. Runs AFTER report card is sent. Batches of 10 responses, newest games first.'
    AFTER TBRDP_DW_DEV.IM_RPT.TASK_VOC_DAILY_REPORT_CARD
AS
BEGIN
    LET v_remaining NUMBER := 1;
    LET v_yesterday DATE := CURRENT_DATE() - 1;

    WHILE (v_remaining > 0) DO
        -- Create a temp table with the next 10 unprocessed IDs from PRIOR games (not yesterday)
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
        LIMIT 10;

        -- Process this batch through the AI view
        INSERT INTO TBRDP_DW_DEV.IM_RPT.T_OVERALL_FEEDBACK_SENTENCE_LEVEL
            (QUALTRICS_ID, SEASON, GAME_DATE, BUYER_TYPE, SECTION_CODE, ORIGINAL_FEEDBACK, SATISFACTION_RATING,
             SENTENCE_NUMBER, SENTENCE_TEXT, SENTIMENT_CATEGORY, AI_CATEGORY, PARENT_CATEGORY,
             DETAILED_CATEGORY, SENTENCE_LENGTH, NPS_SEGMENT)
        SELECT
            v.QUALTRICS_ID, v.SEASON, v.GAME_DATE, v.BUYER_TYPE, v.SECTION_CODE, v.ORIGINAL_FEEDBACK, v.SATISFACTION_RATING,
            v.SENTENCE_NUMBER, v.SENTENCE_TEXT, v.SENTIMENT_CATEGORY, v.AI_CATEGORY, v.PARENT_CATEGORY,
            v.DETAILED_CATEGORY, v.SENTENCE_LENGTH, v.NPS_SEGMENT
        FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_SENTENCE_LEVEL v
        INNER JOIN TBRDP_DW_DEV.IM_RPT.TMP_SENTENCE_BATCH b
            ON v.QUALTRICS_ID = b.QUALTRICS_ID;

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
-- CLEANUP: Remove old task that is no longer needed
-- =====================================================
-- DROP TASK IF EXISTS TBRDP_DW_DEV.IM_RPT.TSK_REFRESH_SENTENCE_LEVEL_FEEDBACK;
