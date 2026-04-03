"""
Deploy SP_VOC_DAILY_REPORT_CARD stored procedure to Snowflake.
Uses snowflake-connector-python with externalbrowser auth 
(falls back to cached OAuth token).
"""
import snowflake.connector
import os

SQL_FILE = r'c:\Users\ytaketani\voc_insights_agent\VOC_STEP2_stored_procedure.sql'

# Read the full SQL file
with open(SQL_FILE, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Skip the comment header (lines 1-23), start at CREATE OR REPLACE
sql = ''.join(lines[23:]).strip()
print(f"SQL length: {len(sql)} chars")

# Connect using externalbrowser (will use cached OAuth token)
conn = snowflake.connector.connect(
    account='hta92307.east-us-2.azure',
    user='YTAKETANI@RAYSBASEBALL.COM',
    authenticator='externalbrowser',
    database='TBRDP_DW_DEV',
    schema='IM_RPT',
    warehouse='TBRDP_DW_CORTEX_XS_WH',
    role='ACCOUNTADMIN'
)

try:
    cur = conn.cursor()
    print("Connected. Deploying stored procedure...")
    cur.execute(sql)
    result = cur.fetchone()
    print(f"Result: {result}")
    cur.close()
finally:
    conn.close()

print("Done.")
