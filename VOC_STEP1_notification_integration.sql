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

-- =====================================================
-- Create Game Tiers Reference Table
-- =====================================================
-- Tier 1 = Premium/highest draw (e.g., Yankees weekend)
-- Tier 5 = Lower draw (e.g., Athletics weekday)
-- Used to benchmark each 2026 game against same-tier
-- historical games from 2023 + 2024 seasons.
-- =====================================================

CREATE OR REPLACE TABLE TBRDP_DW_DEV.IM_RPT.T_GAME_TIERS (
    GAME_DATE   DATE,
    OPPONENT    VARCHAR,
    GAME_TIER   NUMBER,
    SEASON      NUMBER
);

INSERT INTO TBRDP_DW_DEV.IM_RPT.T_GAME_TIERS (GAME_DATE, OPPONENT, GAME_TIER, SEASON)
VALUES
    -- 2023 Season (81 games)
    ('2023-03-30', 'Tigers', 3, 2023),
    ('2023-04-01', 'Tigers', 3, 2023),
    ('2023-04-02', 'Tigers', 3, 2023),
    ('2023-04-07', 'Athletics', 5, 2023),
    ('2023-04-08', 'Athletics', 3, 2023),
    ('2023-04-09', 'Athletics', 3, 2023),
    ('2023-04-10', 'Red Sox', 3, 2023),
    ('2023-04-11', 'Red Sox', 3, 2023),
    ('2023-04-12', 'Red Sox', 3, 2023),
    ('2023-04-13', 'Red Sox', 3, 2023),
    ('2023-04-21', 'White Sox', 4, 2023),
    ('2023-04-22', 'White Sox', 3, 2023),
    ('2023-04-23', 'White Sox', 4, 2023),
    ('2023-04-24', 'Astros', 5, 2023),
    ('2023-04-25', 'Astros', 5, 2023),
    ('2023-04-26', 'Astros', 5, 2023),
    ('2023-05-02', 'Pirates', 5, 2023),
    ('2023-05-03', 'Pirates', 5, 2023),
    ('2023-05-04', 'Pirates', 5, 2023),
    ('2023-05-05', 'Yankees', 2, 2023),
    ('2023-05-06', 'Yankees', 1, 2023),
    ('2023-05-07', 'Yankees', 1, 2023),
    ('2023-05-19', 'Brewers', 4, 2023),
    ('2023-05-20', 'Brewers', 3, 2023),
    ('2023-05-21', 'Brewers', 4, 2023),
    ('2023-05-22', 'Blue Jays', 5, 2023),
    ('2023-05-23', 'Blue Jays', 5, 2023),
    ('2023-05-24', 'Blue Jays', 5, 2023),
    ('2023-05-25', 'Blue Jays', 5, 2023),
    ('2023-05-26', 'Dodgers', 3, 2023),
    ('2023-05-27', 'Dodgers', 2, 2023),
    ('2023-05-28', 'Dodgers', 2, 2023),
    ('2023-06-06', 'Twins', 5, 2023),
    ('2023-06-07', 'Twins', 5, 2023),
    ('2023-06-08', 'Twins', 5, 2023),
    ('2023-06-09', 'Rangers', 4, 2023),
    ('2023-06-10', 'Rangers', 3, 2023),
    ('2023-06-11', 'Rangers', 4, 2023),
    ('2023-06-20', 'Orioles', 5, 2023),
    ('2023-06-21', 'Orioles', 5, 2023),
    ('2023-06-22', 'Royals', 5, 2023),
    ('2023-06-23', 'Royals', 4, 2023),
    ('2023-06-24', 'Royals', 3, 2023),
    ('2023-06-25', 'Royals', 4, 2023),
    ('2023-07-04', 'Phillies', 3, 2023),
    ('2023-07-05', 'Phillies', 4, 2023),
    ('2023-07-06', 'Phillies', 4, 2023),
    ('2023-07-07', 'Braves', 3, 2023),
    ('2023-07-08', 'Braves', 2, 2023),
    ('2023-07-09', 'Braves', 2, 2023),
    ('2023-07-20', 'Orioles', 5, 2023),
    ('2023-07-21', 'Orioles', 4, 2023),
    ('2023-07-22', 'Orioles', 3, 2023),
    ('2023-07-23', 'Orioles', 4, 2023),
    ('2023-07-25', 'Marlins', 5, 2023),
    ('2023-07-26', 'Marlins', 5, 2023),
    ('2023-08-08', 'Cardinals', 4, 2023),
    ('2023-08-09', 'Cardinals', 4, 2023),
    ('2023-08-10', 'Cardinals', 4, 2023),
    ('2023-08-11', 'Guardians', 4, 2023),
    ('2023-08-12', 'Guardians', 3, 2023),
    ('2023-08-13', 'Guardians', 4, 2023),
    ('2023-08-22', 'Rockies', 5, 2023),
    ('2023-08-23', 'Rockies', 5, 2023),
    ('2023-08-24', 'Rockies', 5, 2023),
    ('2023-08-25', 'Yankees', 2, 2023),
    ('2023-08-26', 'Yankees', 1, 2023),
    ('2023-08-27', 'Yankees', 1, 2023),
    ('2023-09-04', 'Red Sox', 3, 2023),
    ('2023-09-05', 'Red Sox', 3, 2023),
    ('2023-09-06', 'Red Sox', 3, 2023),
    ('2023-09-07', 'Mariners', 5, 2023),
    ('2023-09-08', 'Mariners', 4, 2023),
    ('2023-09-09', 'Mariners', 3, 2023),
    ('2023-09-10', 'Mariners', 4, 2023),
    ('2023-09-19', 'Angels', 5, 2023),
    ('2023-09-20', 'Angels', 5, 2023),
    ('2023-09-21', 'Angels', 5, 2023),
    ('2023-09-22', 'Blue Jays', 4, 2023),
    ('2023-09-23', 'Blue Jays', 3, 2023),
    ('2023-09-24', 'Blue Jays', 4, 2023),

    -- 2024 Season (81 games)
    ('2024-03-28', 'Blue Jays', 1, 2024),
    ('2024-03-29', 'Blue Jays', 3, 2024),
    ('2024-03-30', 'Blue Jays', 2, 2024),
    ('2024-03-31', 'Blue Jays', 2, 2024),
    ('2024-04-01', 'Rangers', 5, 2024),
    ('2024-04-02', 'Rangers', 5, 2024),
    ('2024-04-03', 'Rangers', 5, 2024),
    ('2024-04-12', 'Giants', 3, 2024),
    ('2024-04-13', 'Giants', 2, 2024),
    ('2024-04-14', 'Giants', 2, 2024),
    ('2024-04-15', 'Angels', 5, 2024),
    ('2024-04-16', 'Angels', 5, 2024),
    ('2024-04-17', 'Angels', 5, 2024),
    ('2024-04-18', 'Angels', 4, 2024),
    ('2024-04-22', 'Tigers', 5, 2024),
    ('2024-04-23', 'Tigers', 5, 2024),
    ('2024-04-24', 'Tigers', 5, 2024),
    ('2024-05-03', 'Mets', 2, 2024),
    ('2024-05-04', 'Mets', 1, 2024),
    ('2024-05-05', 'Mets', 1, 2024),
    ('2024-05-06', 'White Sox', 5, 2024),
    ('2024-05-07', 'White Sox', 5, 2024),
    ('2024-05-08', 'White Sox', 5, 2024),
    ('2024-05-10', 'Yankees', 1, 2024),
    ('2024-05-11', 'Yankees', 1, 2024),
    ('2024-05-12', 'Yankees', 1, 2024),
    ('2024-05-20', 'Red Sox', 3, 2024),
    ('2024-05-21', 'Red Sox', 3, 2024),
    ('2024-05-22', 'Red Sox', 3, 2024),
    ('2024-05-24', 'Royals', 5, 2024),
    ('2024-05-25', 'Royals', 2, 2024),
    ('2024-05-26', 'Royals', 3, 2024),
    ('2024-05-28', 'Athletics', 5, 2024),
    ('2024-05-29', 'Athletics', 5, 2024),
    ('2024-05-30', 'Athletics', 5, 2024),
    ('2024-06-07', 'Orioles', 3, 2024),
    ('2024-06-08', 'Orioles', 2, 2024),
    ('2024-06-09', 'Orioles', 2, 2024),
    ('2024-06-10', 'Orioles', 4, 2024),
    ('2024-06-11', 'Cubs', 1, 2024),
    ('2024-06-12', 'Cubs', 1, 2024),
    ('2024-06-13', 'Cubs', 1, 2024),
    ('2024-06-24', 'Mariners', 5, 2024),
    ('2024-06-25', 'Mariners', 5, 2024),
    ('2024-06-26', 'Mariners', 4, 2024),
    ('2024-06-28', 'Nationals', 3, 2024),
    ('2024-06-29', 'Nationals', 2, 2024),
    ('2024-06-30', 'Nationals', 2, 2024),
    ('2024-07-09', 'Yankees', 2, 2024),
    ('2024-07-10', 'Yankees', 2, 2024),
    ('2024-07-11', 'Yankees', 2, 2024),
    ('2024-07-12', 'Guardians', 3, 2024),
    ('2024-07-13', 'Guardians', 2, 2024),
    ('2024-07-14', 'Guardians', 2, 2024),
    ('2024-07-26', 'Reds', 3, 2024),
    ('2024-07-27', 'Reds', 2, 2024),
    ('2024-07-28', 'Reds', 2, 2024),
    ('2024-07-30', 'Marlins', 4, 2024),
    ('2024-07-31', 'Marlins', 4, 2024),
    ('2024-08-09', 'Orioles', 3, 2024),
    ('2024-08-10', 'Orioles', 2, 2024),
    ('2024-08-11', 'Orioles', 2, 2024),
    ('2024-08-12', 'Astros', 4, 2024),
    ('2024-08-13', 'Astros', 4, 2024),
    ('2024-08-14', 'Astros', 4, 2024),
    ('2024-08-16', 'Diamondbacks', 3, 2024),
    ('2024-08-17', 'Diamondbacks', 2, 2024),
    ('2024-08-18', 'Diamondbacks', 2, 2024),
    ('2024-08-30', 'Padres', 4, 2024),
    ('2024-08-31', 'Padres', 2, 2024),
    ('2024-09-01', 'Padres', 2, 2024),
    ('2024-09-02', 'Twins', 5, 2024),
    ('2024-09-03', 'Twins', 5, 2024),
    ('2024-09-04', 'Twins', 5, 2024),
    ('2024-09-05', 'Twins', 4, 2024),
    ('2024-09-17', 'Red Sox', 3, 2024),
    ('2024-09-18', 'Red Sox', 3, 2024),
    ('2024-09-19', 'Red Sox', 3, 2024),
    ('2024-09-20', 'Blue Jays', 3, 2024),
    ('2024-09-21', 'Blue Jays', 2, 2024),
    ('2024-09-22', 'Blue Jays', 2, 2024),

    -- 2026 Season (81 games)
    ('2026-04-06', 'Cubs', 1, 2026),
    ('2026-04-07', 'Cubs', 2, 2026),
    ('2026-04-08', 'Cubs', 2, 2026),
    ('2026-04-10', 'Yankees', 1, 2026),
    ('2026-04-11', 'Yankees', 1, 2026),
    ('2026-04-12', 'Yankees', 1, 2026),
    ('2026-04-20', 'Reds', 5, 2026),
    ('2026-04-21', 'Reds', 5, 2026),
    ('2026-04-22', 'Reds', 5, 2026),
    ('2026-04-24', 'Twins', 3, 2026),
    ('2026-04-25', 'Twins', 2, 2026),
    ('2026-04-26', 'Twins', 3, 2026),
    ('2026-05-01', 'Giants', 3, 2026),
    ('2026-05-02', 'Giants', 2, 2026),
    ('2026-05-03', 'Giants', 3, 2026),
    ('2026-05-04', 'Blue Jays', 5, 2026),
    ('2026-05-05', 'Blue Jays', 5, 2026),
    ('2026-05-06', 'Blue Jays', 5, 2026),
    ('2026-05-15', 'Marlins', 4, 2026),
    ('2026-05-16', 'Marlins', 3, 2026),
    ('2026-05-17', 'Marlins', 3, 2026),
    ('2026-05-18', 'Orioles', 5, 2026),
    ('2026-05-19', 'Orioles', 5, 2026),
    ('2026-05-20', 'Orioles', 5, 2026),
    ('2026-05-29', 'Angels', 4, 2026),
    ('2026-05-30', 'Angels', 3, 2026),
    ('2026-05-31', 'Angels', 3, 2026),
    ('2026-06-01', 'Tigers', 5, 2026),
    ('2026-06-02', 'Tigers', 4, 2026),
    ('2026-06-03', 'Tigers', 4, 2026),
    ('2026-06-08', 'Red Sox', 4, 2026),
    ('2026-06-09', 'Red Sox', 4, 2026),
    ('2026-06-10', 'Red Sox', 4, 2026),
    ('2026-06-19', 'Nationals', 3, 2026),
    ('2026-06-20', 'Nationals', 3, 2026),
    ('2026-06-21', 'Nationals', 3, 2026),
    ('2026-06-22', 'Royals', 5, 2026),
    ('2026-06-23', 'Royals', 5, 2026),
    ('2026-06-24', 'Royals', 5, 2026),
    ('2026-06-25', 'Royals', 5, 2026),
    ('2026-06-26', 'Diamondbacks', 3, 2026),
    ('2026-06-27', 'Diamondbacks', 3, 2026),
    ('2026-06-28', 'Diamondbacks', 3, 2026),
    ('2026-07-06', 'Yankees', 2, 2026),
    ('2026-07-07', 'Yankees', 2, 2026),
    ('2026-07-08', 'Yankees', 2, 2026),
    ('2026-07-09', 'Yankees', 2, 2026),
    ('2026-07-10', 'Mariners', 4, 2026),
    ('2026-07-11', 'Mariners', 3, 2026),
    ('2026-07-12', 'Mariners', 3, 2026),
    ('2026-07-24', 'Guardians', 4, 2026),
    ('2026-07-25', 'Guardians', 3, 2026),
    ('2026-07-26', 'Guardians', 3, 2026),
    ('2026-07-28', 'Rangers', 5, 2026),
    ('2026-07-29', 'Rangers', 5, 2026),
    ('2026-07-30', 'Rangers', 5, 2026),
    ('2026-07-31', 'White Sox', 4, 2026),
    ('2026-08-01', 'White Sox', 3, 2026),
    ('2026-08-02', 'White Sox', 3, 2026),
    ('2026-08-14', 'Orioles', 4, 2026),
    ('2026-08-15', 'Orioles', 3, 2026),
    ('2026-08-16', 'Orioles', 3, 2026),
    ('2026-08-17', 'Orioles', 5, 2026),
    ('2026-08-18', 'Blue Jays', 5, 2026),
    ('2026-08-19', 'Blue Jays', 5, 2026),
    ('2026-08-20', 'Blue Jays', 5, 2026),
    ('2026-08-28', 'Padres', 4, 2026),
    ('2026-08-29', 'Padres', 3, 2026),
    ('2026-08-30', 'Padres', 3, 2026),
    ('2026-08-31', 'Mets', 3, 2026),
    ('2026-09-01', 'Mets', 3, 2026),
    ('2026-09-02', 'Mets', 3, 2026),
    ('2026-09-11', 'Astros', 4, 2026),
    ('2026-09-12', 'Astros', 3, 2026),
    ('2026-09-13', 'Astros', 3, 2026),
    ('2026-09-15', 'Athletics', 5, 2026),
    ('2026-09-16', 'Athletics', 5, 2026),
    ('2026-09-17', 'Athletics', 5, 2026),
    ('2026-09-18', 'Red Sox', 3, 2026),
    ('2026-09-19', 'Red Sox', 2, 2026),
    ('2026-09-20', 'Red Sox', 3, 2026)
;

GRANT SELECT ON TABLE TBRDP_DW_DEV.IM_RPT.T_GAME_TIERS TO ROLE TBRDP_DW_PROD_CORTEX_USER;
