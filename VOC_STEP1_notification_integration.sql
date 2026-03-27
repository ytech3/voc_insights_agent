-- =====================================================
-- VOC REPORT CARD - STEP 1 OF 3
-- Create Email Notification Integration (one-time setup)
-- =====================================================
-- INSTRUCTIONS:
--   1. Open this file in a Snowsight SQL Worksheet
--   2. Set Role to ACCOUNTADMIN (top-left dropdown)
--   3. Set Warehouse to TBRDP_DW_CORTEX_XS_WH
--   4. Click "Run All" (Ctrl+Shift+Enter)
-- =====================================================

USE ROLE ACCOUNTADMIN;

USE WAREHOUSE TBRDP_DW_CORTEX_XS_WH;

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS VOC_REPORT_CARD_EMAIL
    TYPE = EMAIL
    ENABLED = TRUE
    ALLOWED_RECIPIENTS = ('ytaketani@raysbaseball.com')
    COMMENT = 'Email integration for daily VOC Game Day Report Card';

GRANT USAGE ON INTEGRATION VOC_REPORT_CARD_EMAIL TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- =====================================================
-- Create Internal Stage for MLB Team Logos
-- =====================================================
CREATE STAGE IF NOT EXISTS TBRDP_DW_DEV.IM_RPT.MLB_LOGOS_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'MLB team logos for VOC Game Day Report Card email headers';

GRANT READ ON STAGE TBRDP_DW_DEV.IM_RPT.MLB_LOGOS_STAGE TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- =====================================================
-- UPLOAD LOGOS (run from SnowSQL CLI, not Snowsight):
-- =====================================================
-- PUT 'file://C:\Users\ytaketani\voc_insights_agent\MLB Logos\*.png'
--     @TBRDP_DW_DEV.IM_RPT.MLB_LOGOS_STAGE
--     AUTO_COMPRESS = FALSE
--     OVERWRITE = TRUE;
--
-- Then refresh the directory table:
-- ALTER STAGE TBRDP_DW_DEV.IM_RPT.MLB_LOGOS_STAGE REFRESH;
-- =====================================================
