# VOC Insights Agent - Tampa Bay Rays

## 📊 Overview

The **VOC (Voice of Customer) Insights Agent** is an AI-powered analytics platform built on Snowflake Cortex AI that transforms fan feedback from post-game surveys into actionable business intelligence. This system enables 24/7 natural language querying of fan sentiment, satisfaction metrics, and revenue insights.

## 🎯 Key Features

- **AI-Powered Classification**: Automatically categorizes feedback into topics (Food & Beverage, Parking, Entertainment, etc.)
- **Sentiment Analysis**: Measures emotional tone of feedback (-1 to 1 scale)
- **NPS Segmentation**: Automatically segments fans into Promoters, Passives, and Detractors
- **Revenue Insights**: Analyzes ticket prices, concession purchases, and merchandise sales by segment
- **Semantic Search**: Natural language search across all fan feedback
- **Monthly Trend Analysis**: AI-generated summaries of top complaints and sentiment trends
- **Buyer Type Analysis**: Compares satisfaction and revenue across Single Game, Season Ticket Holders, Groups, etc.
- **Cost Monitoring**: Tracks Snowflake Cortex AI usage and costs

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Data Sources                         │
│  Qualtrics Post-Game Survey → Snowflake (Fivetran)    │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│              Base View (Raw Survey Data)                │
│  V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI    │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│          Enhanced View (AI Enrichment Layer)            │
│              V_VOC_ENHANCED_AI                          │
│  • AI Classification  • Sentiment Analysis              │
│  • NPS Segmentation   • Revenue Indicators              │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│              Analytical Views & Functions               │
│  • V_VOC_MONTHLY_INSIGHTS                               │
│  • V_VOC_BUYER_TYPE_INSIGHTS                            │
│  • VOC_QUICK_STATS()                                    │
│  • classify_feedback_v2()                               │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│            Cortex Search Service                        │
│         VOC_FEEDBACK_SEARCH                             │
│  (Semantic search across all feedback)                  │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│          Natural Language Interface                     │
│  Cortex Analyst + Semantic Model (voc_insights)        │
└─────────────────────────────────────────────────────────┘
```

## 📁 Repository Structure

```
voc-insights-agent/
├── VOC_INSIGHTS_AGENT_COMPLETE.sql    # Main deployment script
├── voc_semantic_model.yaml            # Cortex Analyst semantic model
├── README.md                           # This file
├── docs/
│   ├── DEPLOYMENT.md                  # Deployment instructions
│   ├── USAGE_EXAMPLES.md              # Query examples
│   └── ARCHITECTURE.md                # Technical architecture
└── examples/
    └── sample_queries.sql             # Common query patterns
```

## 🚀 Quick Start

### Prerequisites

- Snowflake account with Cortex AI enabled
- Role: `TBRDP_DW_PROD_CORTEX_USER`
- Warehouse: `TBRDP_DW_CORTEX_XS_WH`
- Base view: `V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI`

### Deployment

1. **Clone the repository**
   ```bash
   git clone https://github.com/tampabayrays/voc-insights-agent.git
   cd voc-insights-agent
   ```

2. **Run the deployment script**
   ```sql
   -- In Snowflake worksheet:
   -- Copy and paste contents of VOC_INSIGHTS_AGENT_COMPLETE.sql
   -- Run the entire script
   ```

3. **Upload semantic model**
   ```sql
   PUT file://voc_semantic_model.yaml 
   @TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS
   AUTO_COMPRESS=FALSE
   OVERWRITE=TRUE;
   ```

4. **Verify deployment**
   ```sql
   -- Test quick stats
   SELECT * FROM TABLE(TBRDP_DW_DEV.IM_RPT.VOC_QUICK_STATS(2024));
   
   -- Test search service
   SELECT * FROM TABLE(VOC_FEEDBACK_SEARCH!SEARCH('parking'));
   ```

## 📊 Core Components

### 1. Enhanced View (V_VOC_ENHANCED_AI)

The foundation view that enriches raw survey data with AI insights:

```sql
SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
WHERE game_date_clean >= '2024-01-01'
LIMIT 10;
```

**Added Columns:**
- `primary_topic` - AI-classified feedback category
- `sentiment_score` - Sentiment from -1 (negative) to 1 (positive)
- `nps_segment` - Promoter/Passive/Detractor
- `has_children` - Boolean flag for family attendance
- `game_month`, `game_day_of_week`, etc. - Time dimensions

### 2. Monthly Insights View

Aggregated metrics with AI-generated summaries:

```sql
SELECT 
    month,
    total_responses,
    avg_satisfaction,
    promoter_pct,
    top_complaints_analysis,
    executive_summary
FROM TBRDP_DW_DEV.IM_RPT.V_VOC_MONTHLY_INSIGHTS
ORDER BY month DESC;
```

### 3. Buyer Type Analysis

Compare segments to identify revenue opportunities:

```sql
SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_VOC_BUYER_TYPE_INSIGHTS;
```

### 4. Quick Stats Function

Retrieve key metrics for any year:

```sql
SELECT * FROM TABLE(TBRDP_DW_DEV.IM_RPT.VOC_QUICK_STATS(2024));
```

### 5. Classification Functions

Classify individual feedback:

```sql
-- Single label
SELECT TBRDP_DW_DEV.IM_RPT.classify_feedback_v2(
    'The food was cold and overpriced'
);

-- Multi-label (up to 3 categories)
SELECT TBRDP_DW_DEV.IM_RPT.classify_feedback_multilabel(
    'Great seats but parking was terrible and expensive'
);
```

### 6. Cortex Search Service

Semantic search across all feedback:

```sql
SELECT * 
FROM TABLE(VOC_FEEDBACK_SEARCH!SEARCH(
    'complaints about temperature and heat',
    LIMIT => 20
));
```

## 📈 Usage Examples

### Example 1: Monthly NPS Trends
```sql
SELECT 
    month,
    total_responses,
    ROUND(avg_satisfaction, 2) as avg_satisfaction,
    ROUND(promoter_pct, 1) as promoter_pct,
    ROUND(detractor_pct, 1) as detractor_pct,
    ROUND((promoter_pct - detractor_pct), 1) as nps
FROM TBRDP_DW_DEV.IM_RPT.V_VOC_MONTHLY_INSIGHTS
WHERE month >= '2024-01-01'
ORDER BY month;
```

### Example 2: Revenue by Satisfaction Segment
```sql
SELECT 
    nps_segment,
    COUNT(*) as responses,
    ROUND(AVG(ticket_price_clean), 2) as avg_ticket_price,
    AVG(CASE WHEN CONCESS_SCREENER_DESC = 'Yes' THEN 1 ELSE 0 END) * 100 as concession_rate
FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
WHERE YEAR(game_date_clean) = 2024
GROUP BY nps_segment
ORDER BY 
    CASE nps_segment 
        WHEN 'Promoter' THEN 1 
        WHEN 'Passive' THEN 2 
        WHEN 'Detractor' THEN 3 
    END;
```

### Example 3: Top Topics by Month
```sql
SELECT 
    DATE_TRUNC('month', game_date_clean) as month,
    primary_topic,
    COUNT(*) as mention_count,
    ROUND(AVG(OVERALL_NUMRAT), 2) as avg_satisfaction,
    ROUND(AVG(sentiment_score), 3) as avg_sentiment
FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
WHERE YEAR(game_date_clean) = 2024
GROUP BY 1, 2
ORDER BY 1 DESC, 3 DESC;
```

### Example 4: Family vs Adult-Only Comparison
```sql
SELECT 
    CASE WHEN has_children THEN 'Families' ELSE 'Adults Only' END as group_type,
    COUNT(*) as responses,
    ROUND(AVG(OVERALL_NUMRAT), 2) as avg_satisfaction,
    ROUND(AVG(ticket_price_clean), 2) as avg_ticket_price,
    AVG(CASE WHEN CONCESS_SCREENER_DESC = 'Yes' THEN 1 ELSE 0 END) * 100 as concession_rate,
    AVG(CASE WHEN MERCH_SCREENER_DESC = 'Yes' THEN 1 ELSE 0 END) * 100 as merch_rate
FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
WHERE YEAR(game_date_clean) = 2024
GROUP BY 1;
```

## 💰 Cost Management

Monitor Cortex AI usage and costs:

```sql
-- Daily function usage
SELECT * FROM TBRDP_DW_DEV.IM_RPT.V_CORTEX_FUNCTION_COSTS
WHERE usage_date >= DATEADD(day, -7, CURRENT_DATE())
ORDER BY usage_date DESC, total_calls DESC;

-- Query-level cost tracking
SELECT 
    DATE_TRUNC('day', start_time) as usage_day,
    COUNT(*) as total_queries,
    SUM(credits_used) as total_credits,
    ROUND(AVG(elapsed_seconds), 2) as avg_seconds
FROM TBRDP_DW_DEV.IM_RPT.V_CORTEX_COST_MONITORING
WHERE start_time >= DATEADD(day, -30, CURRENT_DATE())
GROUP BY 1
ORDER BY 1 DESC;
```

## 🛠️ Maintenance

### Refresh Search Service
```sql
ALTER CORTEX SEARCH SERVICE VOC_FEEDBACK_SEARCH REFRESH;
```

### Update Semantic Model
```sql
-- After editing voc_semantic_model.yaml:
PUT file://voc_semantic_model.yaml 
@TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS
OVERWRITE=TRUE;
```

### Monitor Data Quality
```sql
SELECT 
    DATE_TRUNC('week', game_date_clean) as week,
    COUNT(*) as total_responses,
    COUNT(OVERALL_NUMRAT) as has_rating,
    COUNT(OVERALL_NUMRAT_OT) as has_text_feedback,
    COUNT(CASE WHEN LENGTH(OVERALL_NUMRAT_OT) > 50 THEN 1 END) as substantive_feedback
FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
WHERE game_date_clean >= DATEADD(month, -3, CURRENT_DATE())
GROUP BY 1
ORDER BY 1 DESC;
```

## 📚 Key Metrics Definitions

| Metric | Definition | Range |
|--------|-----------|-------|
| **Overall Satisfaction** | Fan rating of overall experience | 1-10 scale |
| **NPS (Net Promoter Score)** | % Promoters (9-10) - % Detractors (0-6) | -100 to +100 |
| **Sentiment Score** | AI-generated emotional tone | -1 (negative) to +1 (positive) |
| **Concession Purchase Rate** | % of fans who purchased F&B | 0-100% |
| **Family Attendance Rate** | % of groups with children | 0-100% |

## 🔒 Security & Permissions

Required grants:
```sql
GRANT USAGE ON WAREHOUSE TBRDP_DW_CORTEX_XS_WH TO ROLE TBRDP_DW_PROD_CORTEX_USER;
GRANT USAGE ON DATABASE TBRDP_DW_DEV TO ROLE TBRDP_DW_PROD_CORTEX_USER;
GRANT USAGE ON SCHEMA TBRDP_DW_DEV.IM_RPT TO ROLE TBRDP_DW_PROD_CORTEX_USER;
GRANT SELECT ON ALL VIEWS IN SCHEMA TBRDP_DW_DEV.IM_RPT TO ROLE TBRDP_DW_PROD_CORTEX_USER;
GRANT READ ON STAGE TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS TO ROLE TBRDP_DW_PROD_CORTEX_USER;
```

## 🐛 Troubleshooting

### Issue: Search service not returning results
```sql
-- Check service status
SHOW CORTEX SEARCH SERVICES;

-- Refresh service
ALTER CORTEX SEARCH SERVICE VOC_FEEDBACK_SEARCH REFRESH;
```

### Issue: AI functions returning errors
```sql
-- Verify Cortex AI is enabled
SHOW PARAMETERS LIKE 'CORTEX%' IN ACCOUNT;

-- Check for null/invalid input
SELECT COUNT(*) 
FROM TBRDP_DW_DEV.IM_RPT.V_VOC_ENHANCED_AI
WHERE OVERALL_NUMRAT_OT IS NULL 
   OR LENGTH(OVERALL_NUMRAT_OT) < 10;
```

## 📞 Support

For questions or issues:
- **Data Team**: Contact Tampa Bay Rays Analytics
- **Snowflake Support**: [Snowflake Cortex AI Documentation](https://docs.snowflake.com/en/user-guide/snowflake-cortex)

## 📄 License

© 2025 Tampa Bay Rays Baseball, LLC. All rights reserved.

## 🙏 Acknowledgments

- Built with [Snowflake Cortex AI](https://www.snowflake.com/en/data-cloud/cortex/)
- Survey data collected via Qualtrics
- Data integration powered by Fivetran

---

**Last Updated**: November 4, 2025  
**Version**: 1.0  
**Maintained by**: Tampa Bay Rays Data & Analytics Team
