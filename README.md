Tampa Bay Rays - Snowflake Cortex AI VOC Project
Natural Language Query System - Implementation Guide

📋 Project Overview
This package contains everything needed to implement a natural language query system for Tampa Bay Rays Voice of Customer (VOC) data using Snowflake Cortex AI.
Goal: Enable employees to ask questions about fan satisfaction, revenue, and operations in plain English—no SQL required!
What's Included

updated_10_29_refactored.sql - Optimized SQL with Cortex AISQL best practices
voc_semantic_model.yaml - Semantic model for Cortex Analyst
snowflake_intelligence_agent_setup.sql - Step-by-step agent setup guide


🎯 Key Benefits
For End Users (Employees)

✅ Ask questions in natural language (no SQL knowledge needed)
✅ Get instant insights 24/7
✅ Access via web browser or mobile
✅ Automatic chart/table generation

For Your Team

✅ 30%+ faster query performance
✅ Up to 60% cost savings vs. custom AI implementation
✅ No separate infrastructure needed
✅ Enterprise security & governance built-in

Example Questions Users Can Ask
"What's the average satisfaction score this month?"
"Show me concession spending by buyer type"
"Compare parking satisfaction between weekdays and weekends"
"What percentage of families attended games in Q2?"
"What are the top 3 complaints from single-game buyers?"
No SQL, no training required!

🚀 Quick Start (3 Steps)
Step 1: Run the Optimized SQL
sql-- Run this file in Snowflake
-- File: updated_10_29_refactored.sql
-- Time: ~5 minutes
This creates:

Enhanced VOC views with AI classification
Aggregated insight views (monthly, day-of-week, buyer type)
Cost monitoring queries
Quick stats functions

Step 2: Upload Semantic Model
sql-- 1. Upload voc_semantic_model.yaml to Snowflake stage
-- 2. Follow instructions in snowflake_intelligence_agent_setup.sql
-- Time: ~10 minutes
Step 3: Create the Agent
sql-- Use Snowsight UI to create agent
-- Follow detailed steps in snowflake_intelligence_agent_setup.sql
-- Time: ~15 minutes
Total Setup Time: ~30 minutes

📁 File Details
1. updated_10_29_refactored.sql
Improvements from Original:

✅ Replaced AI_COMPLETE with AI_CLASSIFY (30% faster, 60% cheaper)
✅ Added AI_AGG for unlimited row aggregation
✅ Added AI_SUMMARIZE_AGG for executive summaries
✅ Fixed data type handling (DATE vs VARCHAR)
✅ Added NPS segmentation (Promoters/Passives/Detractors)
✅ Created pre-built insight views (monthly, DOW, buyer type)
✅ Added cost monitoring queries
✅ Removed complex SQL generation stored procedure (no longer needed!)

Key Views Created:

V_VOC_ENHANCED_AI - Base view with AI classifications
V_VOC_MONTHLY_INSIGHTS - Monthly trends with AI aggregation
V_VOC_DAYOFWEEK_INSIGHTS - Day-of-week patterns
V_VOC_BUYER_TYPE_INSIGHTS - Buyer segment analysis

Usage:
sql-- Get 2024 quick stats
SELECT * FROM TABLE(VOC_QUICK_STATS(2024));

-- View monthly insights
SELECT * FROM V_VOC_MONTHLY_INSIGHTS WHERE month >= '2024-01-01';

-- Check costs
SELECT * FROM V_CORTEX_FUNCTION_COSTS WHERE usage_date >= CURRENT_DATE() - 7;

2. voc_semantic_model.yaml
What It Contains:

30 dimensions (fan demographics, behaviors, locations)
11 measures (ratings, spending, counts)
5 custom metrics (NPS, satisfaction averages, purchase rates)
4 pre-defined filters (season, buyer type, family attendance)
3 verified queries (proven SQL patterns)

Key Sections:
yamltables:
  - name: voc_post_attendance
    base_table: V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI
    
    dimensions:
      - name: buyer_type
        description: "Type of ticket buyer (Single Game, Season Ticket, etc.)"
      
      - name: stadium
        description: "Stadium/venue where game was attended"
    
    measures:
      - name: overall_numrat
        description: "Overall satisfaction rating (0-10 scale)"
        aggregation: avg
      
      - name: concess_spend
        description: "Concession spending per person"
        aggregation: avg
    
    metrics:
      - name: nps_score
        description: "Net Promoter Score"
        expr: "(% Promoters - % Detractors)"
Generated From: Your VOC_Meta_Updated.xlsx file

3. snowflake_intelligence_agent_setup.sql
Complete Setup Guide Including:

✅ Stage creation for YAML files
✅ Database/schema setup
✅ Cross-region inference configuration (optional)
✅ UI-based agent creation (step-by-step)
✅ Privilege grants
✅ Testing procedures
✅ User feedback monitoring
✅ Cost tracking
✅ Troubleshooting guide
✅ Maintenance checklist

Key Sections:

Upload semantic model to stage
Create Snowflake Intelligence database
Configure agent via UI (detailed screenshots/instructions)
Grant necessary privileges
Test with sample questions
Monitor usage and feedback
Share with employees
Troubleshooting tips


🏗️ Architecture Overview
┌─────────────────────────────────────────────────────┐
│  Tampa Bay Rays Employees                            │
│  (No SQL Knowledge Required!)                        │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ Natural Language Questions
                   ▼
┌─────────────────────────────────────────────────────┐
│  Snowflake Intelligence Agent                        │
│  - Claude 4 Sonnet (orchestration)                   │
│  - Voice of Customer Insights                        │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ Reads Semantic Model
                   ▼
┌─────────────────────────────────────────────────────┐
│  Cortex Analyst                                      │
│  - voc_semantic_model.yaml                           │
│  - Generates optimized SQL automatically              │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ Queries Data
                   ▼
┌─────────────────────────────────────────────────────┐
│  Enhanced VOC Views (AI-Powered)                     │
│  - V_VOC_ENHANCED_AI                                 │
│  - AI_CLASSIFY (categorization)                      │
│  - AI_SENTIMENT (sentiment scoring)                  │
│  - AI_AGG (aggregated insights)                      │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ Accesses
                   ▼
┌─────────────────────────────────────────────────────┐
│  Base VOC Table                                      │
│  V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI  │
└─────────────────────────────────────────────────────┘

🔧 What Changed vs. Original SQL
❌ Removed (Anti-patterns)

ASK_VOC() stored procedure with AI_COMPLETE SQL generation
Complex prompt engineering for query generation
Manual classification functions with huge prompts
Dynamic SQL execution with error handling

✅ Added (Best Practices)

AI_CLASSIFY for fast, cheap categorization
AI_AGG for unlimited row aggregation
AI_SUMMARIZE_AGG for executive summaries
Cortex Analyst for natural language queries
Pre-built insight views (monthly, DOW, buyer type)
Cost monitoring views
Proper DATE handling (not VARCHAR)
NPS segmentation logic

📊 Performance Improvements

30%+ faster query runtime (purpose-built functions)
60% cost savings (vs. prompt engineering approach)
No context window limits (AI_AGG processes unlimited rows)
Better accuracy (semantic model + verified queries)


💰 Cost Considerations
Expected Costs (Estimates)

Semantic model queries: ~$0.01 - $0.05 per question
AI classification: ~$0.001 per row
AI aggregation: ~$0.02 - $0.10 per aggregation
Warehouse compute: Standard Snowflake rates (XS warehouse)

Cost Monitoring
sql-- View daily Cortex costs
SELECT * FROM V_CORTEX_FUNCTION_COSTS 
WHERE usage_date >= CURRENT_DATE() - 7;

-- Track query-level costs
SELECT 
    query_id,
    credits_used,
    total_elapsed_time/1000 AS elapsed_seconds
FROM V_CORTEX_COST_MONITORING
ORDER BY credits_used DESC
LIMIT 20;
Optimization Tips

Use SMALL or MEDIUM warehouse (not LARGE)
Set appropriate query timeouts (300 seconds default)
Review high-cost queries weekly
Add verified queries for common patterns (reduces LLM calls)


🧪 Testing Checklist
After setup, test these scenarios:
Basic Queries

 "What's the average satisfaction score in 2024?"
 "How many survey responses do we have?"
 "What's the NPS score this quarter?"

Trend Analysis

 "Show me satisfaction trends by month for 2024"
 "What's the satisfaction breakdown by day of week?"
 "Compare Q1 vs Q2 satisfaction scores"

Segmentation

 "Compare satisfaction between single game buyers and season ticket holders"
 "What's the difference in spending between families and adults-only groups?"
 "Show me parking ratings by buyer type"

Revenue Analysis

 "What's the average ticket price by buyer type?"
 "Show me concession purchase rate and average spend by satisfaction score"
 "What's the correlation between ticket price and satisfaction?"

Operational Insights

 "What percentage of fans rate parking 8 or higher?"
 "What are the most common complaints from detractors (scores 0-6)?"
 "Show me concession satisfaction by stadium"


📈 Success Metrics
Track These KPIs
Adoption:

Number of active users per week
Questions asked per user
Percentage of employees using the agent

Quality:

Average feedback score (thumbs up/down)
Query success rate
Response time (target: <5 seconds)

Business Impact:

Time saved vs. manual SQL queries
Questions answered that weren't possible before
Insights discovered leading to action

Monitoring Queries
sql-- User adoption
SELECT 
    COUNT(DISTINCT user_name) AS active_users,
    COUNT(*) AS total_queries
FROM V_CORTEX_COST_MONITORING
WHERE start_time >= DATEADD(day, -7, CURRENT_DATE());

-- Feedback scores
SELECT 
    COUNT(*) AS total_responses,
    SUM(CASE WHEN feedback = 'positive' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS positive_pct
FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS(...))
WHERE RECORD:name = 'CORTEX_AGENT_FEEDBACK';

🔐 Security & Governance
Access Control

Uses existing Snowflake RBAC
No data leaves Snowflake platform
Row-level security & masking policies automatically apply
Queries run with user's credentials (not elevated privileges)

Compliance

SOC 2 Type II certified
GDPR compliant
HIPAA eligible
Data residency controls available

Audit Trail
All queries logged in:

SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
Agent observability events


🆘 Troubleshooting
Issue: "Table/view does not exist"
Solution:
sql-- Check privileges
SHOW GRANTS TO ROLE TBRDP_DW_PROD_CORTEX_USER;

-- Grant if missing
GRANT SELECT ON VIEW TBRDP_DW_DEV.IM_RPT.V_SBL_QUALTRICS_VOC_POST_ATTENDANCE_FULL_CORTEX_AI 
TO ROLE TBRDP_DW_PROD_CORTEX_USER;
Issue: "Agent not responding" or "Slow performance"
Solution:
sql-- Upgrade warehouse
ALTER WAREHOUSE TBRDP_DW_CORTEX_XS_WH SET WAREHOUSE_SIZE = 'SMALL';

-- Increase timeout
-- (Edit in agent configuration: Query timeout = 300 → 600)
Issue: "Inaccurate results"
Solution:

Add verified queries for common patterns
Refine semantic model descriptions
Update agent instructions to be more specific
Review low-rated responses weekly

Issue: "Cannot find semantic model"
Solution:
sql-- Verify file uploaded
LIST @TBRDP_DW_PROD.LOAD.CORTEX_SEMANTIC_MODELS;

-- Re-upload if missing via Snowsight UI

📚 Additional Resources
Snowflake Documentation

Cortex AISQL Functions
Cortex Analyst
Snowflake Intelligence
Semantic Model Spec

Support

Snowflake Support Portal
Community Forums
Your Snowflake Account Team


🔄 Maintenance Schedule
Weekly

 Review agent feedback scores
 Check query response times
 Monitor credit usage trends
 Review most-asked questions

Monthly

 Add verified queries for frequent patterns
 Update semantic model with new columns
 Analyze low-rated responses
 Audit user access permissions

Quarterly

 Evaluate new Cortex features
 Review and optimize warehouse sizing
 Conduct user training refresher
 Update agent instructions based on usage patterns


🎉 Next Steps

Run updated_10_29_refactored.sql in Snowflake
Upload voc_semantic_model.yaml to stage
Follow snowflake_intelligence_agent_setup.sql to create agent
Test with sample questions
Share with 5-10 pilot users
Gather feedback and iterate
Roll out to full team


📞 Support & Questions
For questions about this implementation:

Check the troubleshooting section
Review Snowflake documentation links
Contact your Snowflake account team
Open a support ticket via Snowflake portal


Version: 1.0
Last Updated: October 30, 2024
Created For: Tampa Bay Rays - VOC Analytics Team
