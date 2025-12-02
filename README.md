# VOC Insights Agent - Tampa Bay Rays

## 📊 Overview

The **VOC (Voice of Customer) Insights Agent** is an AI-powered analytics platform built on Snowflake Cortex AI that transforms post-game fan survey data into actionable business intelligence. This system enables Tampa Bay Rays employees to query fan sentiment, satisfaction metrics, and experience insights using natural language — 24/7.

### Key Capabilities

| Feature | Description |
|---------|-------------|
| **Natural Language Queries** | Ask questions in plain English via Cortex Analyst |
| **AI-Powered Classification** | Automatically categorizes feedback into 21 topic categories |
| **Sentiment Analysis** | Measures emotional tone (-1 to +1 scale) |
| **Sentence-Level Analysis** | Breaks down multi-topic feedback into individual insights |
| **NPS Segmentation** | Segments fans into Promoters, Passives, and Detractors |
| **Executive Summaries** | AI-generated summaries of positive and negative feedback |
| **Cost Monitoring** | Tracks Snowflake Cortex AI usage and credits |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DATA SOURCES                                │
│         Qualtrics Post-Game Survey → Fivetran → Snowflake          │
│                    (~50,000 responses/season)                       │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│                    BASE TABLE (647 columns)                         │
│      V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI            │
│   • Survey responses  • Satisfaction ratings  • Demographics        │
│   • Open-text feedback  • Behavioral data  • Revenue indicators     │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│                    AI-ENRICHED VIEWS                                │
├─────────────────────────────────────────────────────────────────────┤
│  V_OVERALL_FEEDBACK_ANALYSIS          Response-level AI analysis    │
│  V_OVERALL_FEEDBACK_SENTENCE_LEVEL    Sentence-level breakdown      │
│  V_QUALITATIVE_FEEDBACK_ALL           All open-text fields unified  │
│  V_QUALITATIVE_FEEDBACK_SENTENCE_LEVEL Sentence-level (all fields)  │
│  V_MERCH_NO_ANALYSIS_SIMPLE           Merchandise non-purchase      │
│  V_CATEGORY_INSIGHTS                  AI_AGG category summaries     │
│  V_EXECUTIVE_SUMMARY                  Leadership-ready summaries    │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│                 CORTEX ANALYST + SEMANTIC MODEL                     │
│              tampa_bay_rays_voc_complete.yaml                       │
│     Natural language → SQL generation → Insights delivery           │
└─────────────────────────────────────────────────────────────────────┘
                                   ↓
┌─────────────────────────────────────────────────────────────────────┐
│                    END USER INTERFACES                              │
│     Snowflake Intelligence  •  Microsoft Teams (future)            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 📁 Repository Structure

```
voc-insights-agent/
├── VOC_INSIGHTS_AGENT_COMPLETE.sql     # Main deployment script (all views)
├── tampa_bay_rays_voc_complete.yaml    # Cortex Analyst semantic model
├── README.md                            # This file
├── data/
│   ├── VOC_Meta_Updated_3.xlsx         # Survey metadata reference
│   ├── 2023_VOC_Results_Sample.xlsx    # Sample data - 2023
│   ├── 2024_VOC_Results_Sample.xlsx    # Sample data - 2024
│   └── 2025_VOC_Results_Sample.xlsx    # Sample data - 2025
└── docs/
    └── category_taxonomy.md            # Category definitions
```

---

## 🗂️ Category Taxonomy (21 Categories)

All AI classification is aligned with this taxonomy across the YAML semantic model and SQL views:

| Parent Category | Child Categories |
|-----------------|------------------|
| **PRE-ARRIVAL & ARRIVAL** | Parking & Arrival |
| **ENTRY & NAVIGATION** | Gate Entry & Security, Wayfinding & Accessibility |
| **IN-SEAT EXPERIENCE** | Seating & Venue Comfort, Crowd & Atmosphere |
| **CONCESSIONS & AMENITIES** | Food & Beverage Quality, Concession Service & Speed, Merchandise & Team Store |
| **ENTERTAINMENT & ENGAGEMENT** | Game Entertainment & Presentation, Promotions & Special Events, Team Performance & Game Quality |
| **SERVICE & OPERATIONS** | Staff Interactions & Service, Facilities & Cleanliness, Weather, Technology & Digital Experience |
| **VALUE & OVERALL** | Pricing & Value Perception, Overall Experience & Loyalty, Ticketing & Purchase Experience |
| **EGRESS & DEPARTURE** | Egress, stadium departure |
| **OTHER** | Other |

---

## 🗄️ Database Objects

### Environment

```sql
USE ROLE TBRDP_DW_PROD_CORTEX_USER;
USE WAREHOUSE TBRDP_DW_CORTEX_XS_WH;
USE DATABASE TBRDP_DW_DEV;
USE SCHEMA IM_RPT;
```

### Views Created

| View Name | Purpose | AI Functions Used |
|-----------|---------|-------------------|
| `V_OVERALL_FEEDBACK_ANALYSIS` | Response-level feedback with AI classification | AI_CLASSIFY, AI_SENTIMENT |
| `V_OVERALL_FEEDBACK_SENTENCE_LEVEL` | Sentence-by-sentence breakdown of OVERALL_NUMRAT_OT | AI_COMPLETE (single call) |
| `V_QUALITATIVE_FEEDBACK_ALL` | Unified view of all 13 open-text fields | AI_CLASSIFY, AI_SENTIMENT |
| `V_QUALITATIVE_FEEDBACK_SENTENCE_LEVEL` | Sentence-level analysis of all open-text fields | AI_COMPLETE (single call) |
| `V_MERCH_NO_ANALYSIS_SIMPLE` | Merchandise non-purchase reason analysis | AI_CLASSIFY, AI_SENTIMENT |
| `V_CATEGORY_INSIGHTS` | AI-generated insights by category (AI_AGG) | AI_AGG |
| `V_EXECUTIVE_SUMMARY` | Leadership summaries by sentiment | AI_SUMMARIZE_AGG |
| `V_CORTEX_AI_COSTS` | Daily cost monitoring (last 30 days) | — |
| `V_CORTEX_QUERY_COSTS` | Query-level cost tracking (last 7 days) | — |

### Qualitative Feedback Fields

These open-text fields are analyzed in `V_QUALITATIVE_FEEDBACK_ALL` and `V_QUALITATIVE_FEEDBACK_SENTENCE_LEVEL`:

| Field | Description |
|-------|-------------|
| `OVERALL_NUMRAT_OT` | Primary overall experience feedback |
| `TB_ADDON_8_1` | Tickets/Seats issues |
| `TB_ADDON_8_2` | Staff/Service issues |
| `TB_ADDON_8_3` | Entertainment issues |
| `TB_ADDON_8_4` | Concessions/Food issues |
| `TB_ADDON_8_5` | Cleanliness issues |
| `TB_ADDON_8_6` | Parking issues |
| `TB_ADDON_8_7` | Retail/Merchandise issues |
| `TB_ADDON_8_8` | Safety/Security issues |
| `TB_ADDON_8_9` | App issues |
| `TB_ADDON_8_10` | Other fan behavior issues |
| `TB_ADDON_8_11` | Other miscellaneous issues |
| `INCENTIVES_OT` | Ticket purchase decision factors |

---

## ⚡ Snowflake Cortex AI Functions

| Function | Purpose | Used In |
|----------|---------|---------|
| `AI_CLASSIFY` | Categorize text into predefined labels | All analysis views |
| `AI_SENTIMENT` | Extract sentiment score (-1 to +1) | All analysis views |
| `AI_COMPLETE` | Generate structured JSON output (sentence splitting + classification) | Sentence-level views |
| `AI_AGG` | Aggregate insights across multiple rows | V_CATEGORY_INSIGHTS |
| `AI_SUMMARIZE_AGG` | Generate summaries across rows | V_EXECUTIVE_SUMMARY |

### Model Used

```
snowflake-llama3.3-70b
```

This model provides:
- **75% cost reduction** via SwiftKV optimization
- **128K context window**
- High accuracy for classification and summarization tasks

---

## 🚀 Deployment

### Prerequisites

- Snowflake account with Cortex AI enabled
- Role: `TBRDP_DW_PROD_CORTEX_USER` (or `ACCOUNTADMIN` for initial setup)
- Warehouse: `TBRDP_DW_CORTEX_XS_WH`
- Access to base view: `V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI`

### Step 1: Run SQL Deployment Script

```sql
-- In Snowflake worksheet, run:
-- Copy and paste contents of VOC_INSIGHTS_AGENT_COMPLETE.sql
-- Execute the entire script
```

### Step 2: Upload Semantic Model

```sql
PUT file://tampa_bay_rays_voc_complete.yaml 
    @TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS
    AUTO_COMPRESS=FALSE
    OVERWRITE=TRUE;

-- Refresh directory
ALTER STAGE TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS REFRESH;

-- Verify upload
LIST @TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS;
```

### Step 3: Verify Deployment

```sql
-- Test overall feedback analysis
SELECT ai_category, sentiment_category, COUNT(*) 
FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
WHERE season = 2025
GROUP BY 1, 2
ORDER BY 3 DESC
LIMIT 10;

-- Test sentence-level analysis
SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_SENTENCE_LEVEL
WHERE season = 2025
LIMIT 5;

-- Test executive summary
SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_EXECUTIVE_SUMMARY;
```

---

## 📊 Usage Examples

### Query Overall Feedback by Category

```sql
SELECT 
  ai_category,
  parent_category,
  sentiment_category,
  COUNT(*) AS feedback_count,
  ROUND(AVG(sentiment_score), 3) AS avg_sentiment
FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_ANALYSIS
WHERE season = 2025
GROUP BY 1, 2, 3
ORDER BY feedback_count DESC;
```

### Get Sentence-Level Insights for Specific Category

```sql
SELECT 
  sentence_text,
  sentiment_category,
  game_date
FROM TBRDP_DW_DEV.IM_RPT.V_OVERALL_FEEDBACK_SENTENCE_LEVEL
WHERE ai_category = 'Food & Beverage Quality'
  AND sentiment_category = 'Negative'
  AND season = 2025
ORDER BY game_date DESC
LIMIT 20;
```

### View Category Insights with AI Summaries

```sql
SELECT 
  ai_category,
  feedback_count,
  positive_pct,
  negative_pct,
  category_insights
FROM TBRDP_DW_DEV.IM_RPT.V_CATEGORY_INSIGHTS
WHERE season = 2025
ORDER BY feedback_count DESC;
```

### Get Executive Summary for Leadership

```sql
SELECT 
  parent_category,
  sentiment_category,
  feedback_count,
  executive_summary
FROM TBRDP_DW_DEV.IM_RPT.V_EXECUTIVE_SUMMARY
ORDER BY feedback_count DESC;
```

### Analyze All Qualitative Feedback Sources

```sql
SELECT 
  feedback_source,
  COUNT(*) AS total_feedback,
  COUNT(CASE WHEN sentiment = 'Negative' THEN 1 END) AS negative_count,
  ROUND(100.0 * COUNT(CASE WHEN sentiment = 'Negative' THEN 1 END) / COUNT(*), 1) AS negative_pct
FROM TBRDP_DW_DEV.IM_RPT.V_QUALITATIVE_FEEDBACK_ALL
WHERE season = 2025
GROUP BY 1
ORDER BY total_feedback DESC;
```

### Monitor Cortex AI Costs

```sql
-- Daily costs by function
SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_CORTEX_AI_COSTS
WHERE usage_date >= CURRENT_DATE() - 7
ORDER BY usage_date DESC;

-- Top expensive queries
SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_CORTEX_QUERY_COSTS
LIMIT 20;
```

---

## 📈 Key Metrics Definitions

| Metric | Definition | Range |
|--------|------------|-------|
| **Overall Satisfaction** | Fan rating of overall experience | 1-10 scale |
| **NPS (Net Promoter Score)** | % Promoters (9-10) - % Detractors (0-6) | -100 to +100 |
| **Sentiment Score** | AI-generated emotional tone | -1 (negative) to +1 (positive) |
| **Promoter** | Satisfaction rating 9-10 | — |
| **Passive** | Satisfaction rating 7-8 | — |
| **Detractor** | Satisfaction rating 0-6 | — |

---

## 💰 Cost Optimization

The deployment includes several cost optimizations:

| Optimization | Impact |
|--------------|--------|
| **Single AI call per feedback** | Reduced from 3 calls to 1 in sentence-level views |
| **snowflake-llama3.3-70b model** | 75% cost reduction via SwiftKV |
| **Direct base table access** | Avoids nested view AI call multiplication |
| **Cost monitoring views** | Visibility into daily and query-level spend |

### Recommended Warehouse Size

```
MEDIUM or smaller
```

Larger warehouses do not improve Cortex AI performance but increase costs.

---

## 🔒 Security & Permissions

### Required Grants

```sql
-- Warehouse access
GRANT USAGE ON WAREHOUSE TBRDP_DW_CORTEX_XS_WH TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- Database and schema access
GRANT USAGE ON DATABASE TBRDP_DW_DEV TO ROLE TBRDP_DW_PROD_CORTEX_USER;
GRANT USAGE ON SCHEMA TBRDP_DW_DEV.IM_RPT TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- View access
GRANT SELECT ON ALL VIEWS IN SCHEMA TBRDP_DW_DEV.IM_RPT TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- Semantic model stage access
GRANT READ ON STAGE TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- Cortex AI functions
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE TBRDP_DW_PROD_CORTEX_USER;
```

---

## 🐛 Troubleshooting

### Issue: View returns no results

```sql
-- Check base table has data for season
SELECT COUNT(*), season 
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE season BETWEEN 2023 AND 2025
GROUP BY season;

-- Check feedback field is populated
SELECT COUNT(*) 
FROM TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
WHERE OVERALL_NUMRAT_OT IS NOT NULL 
  AND LENGTH(TRIM(OVERALL_NUMRAT_OT)) > 10;
```

### Issue: AI_COMPLETE returns NULL

```sql
-- Test AI function directly
SELECT AI_COMPLETE(
  'snowflake-llama3.3-70b',
  'Return only: ["test"]',
  {'temperature': 0.1, 'max_tokens': 100}
);
```

### Issue: Model not available

```sql
-- Check available models in your region
SHOW PARAMETERS LIKE 'CORTEX%' IN ACCOUNT;

-- Alternative model if snowflake-llama3.3-70b unavailable
-- Replace with: 'llama3.1-70b' or 'mistral-large2'
```

### Issue: Cost monitoring views fail

```sql
-- These require ACCOUNTADMIN or specific grants to ACCOUNT_USAGE
USE ROLE ACCOUNTADMIN;
SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY LIMIT 1;
```

---

## 🗓️ Maintenance

### Recommended Tasks

| Task | Frequency | Command |
|------|-----------|---------|
| Review cost monitoring | Weekly | `SELECT * FROM V_CORTEX_AI_COSTS` |
| Validate category distribution | Monthly | See verification queries in SQL script |
| Update season filter | Annually | Modify `BETWEEN 2023 AND 2025` as needed |
| Refresh semantic model | As needed | Re-upload YAML to stage |

---

## 🔮 Future Enhancements

- [ ] Microsoft Teams integration via Azure Bot Service
- [ ] Real-time streaming analysis for in-game feedback
- [ ] Predictive models for fan churn risk
- [ ] Multi-modal analysis (photos from fan submissions)
- [ ] Automated alerting for negative sentiment spikes

---

## 📞 Support

| Contact | Purpose |
|---------|---------|
| Tampa Bay Rays Analytics Team | Internal questions |
| [Snowflake Cortex AI Documentation](https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql) | Technical reference |
| [Snowflake Support](https://community.snowflake.com/) | Platform issues |

---

## 📄 License

© 2025 Tampa Bay Rays Baseball, LLC. All rights reserved.

---

## 🙏 Acknowledgments

- Built with [Snowflake Cortex AI](https://www.snowflake.com/en/data-cloud/cortex/)
- Survey data collected via [Qualtrics](https://www.qualtrics.com/)
- Data integration powered by [Fivetran](https://www.fivetran.com/)

---

**Last Updated**: December 2025  
**Version**: 2.0  
**Maintained by**: Tampa Bay Rays Strategy & Analytics Team
