-- =====================================================
-- VOC REPORT CARD - STEP 3 OF 3
-- Create the Automated Task (daily 7 AM ET schedule)
-- =====================================================
-- INSTRUCTIONS:
--   1. Open this file in a NEW Snowsight SQL Worksheet
--   2. Set Role to ACCOUNTADMIN (top-left dropdown)
--   3. Set Warehouse to TBRDP_DW_CORTEX_XS_WH
--   4. Select ALL text (Ctrl+A), then click "Run" (Ctrl+Enter)
-- =====================================================
-- NOTE: The task is created in a PAUSED state by default.
--       After verifying the procedure works correctly with:
--         CALL TBRDP_DW_DEV.IM_RPT.SP_VOC_DAILY_REPORT_CARD('2024-03-28');
--       Uncomment and run the ALTER TASK RESUME line below.
-- =====================================================

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

-- =====================================================
-- ACTIVATE THE TASK (run this AFTER testing the procedure)
-- =====================================================
-- ALTER TASK TBRDP_DW_DEV.IM_RPT.TASK_VOC_DAILY_REPORT_CARD RESUME;
