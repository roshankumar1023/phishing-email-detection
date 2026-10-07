-- Phishing email analysis: SQL queries (SQLite)
--
-- Database: data/phishing.db, built by notebooks/analysis.ipynb (Stage 2)
-- Table:    emails, one row per cleaned email (no email text is stored)
--   email_id           row id after cleaning
--   email_type         'Phishing Email' or 'Safe Email'
--   label              1 = Phishing, 0 = Safe
--   urgency_score      count of urgent phrases (urgent, verify, act now, ...)
--   url_count          number of links (http/https or www, spaced forms included)
--   has_ip_url         1 if any link points to a raw IP address, else 0
--   exclamation_count  number of "!" characters
--   email_length       number of characters
--   bait_score         count of sensitive-info phrases (password, bank account, ...)
--
-- Run standalone:  sqlite3 data/phishing.db < queries/analysis.sql
-- Requires SQLite 3.25+ for window functions (NTILE, SUM() OVER).
-- Note: the notebook splits this file on semicolons, so comments must not contain one.


-- Query 1: Summary by email type
-- One row per class: how many emails, what share of the dataset, the average of
-- each feature, and the percentage of emails containing an IP-address link.
-- SUM(COUNT(*)) OVER () is a window function that totals the counts across all
-- groups, which lets us compute "% of total" without a second query.
SELECT
    email_type,
    COUNT(*)                                             AS email_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_total,
    ROUND(AVG(urgency_score), 3)                         AS avg_urgency_score,
    ROUND(AVG(url_count), 3)                             AS avg_url_count,
    ROUND(AVG(has_ip_url), 4)                            AS avg_has_ip_url,
    ROUND(AVG(exclamation_count), 3)                     AS avg_exclamation_count,
    ROUND(AVG(email_length), 1)                          AS avg_email_length,
    ROUND(AVG(bait_score), 3)                            AS avg_bait_score,
    ROUND(100.0 * SUM(has_ip_url) / COUNT(*), 2)         AS pct_with_ip_url
FROM emails
GROUP BY email_type
ORDER BY email_type;


-- Query 2: Top 5% highest-risk phishing emails
-- The CTE ranks every phishing email by urgency_score, then bait_score (highest
-- first), and NTILE(20) cuts that ranking into 20 equal buckets of 5% each.
-- Bucket 1 is the top 5%. email_id is a final tie-breaker so the result is the
-- same every run (many emails share the same scores).
WITH ranked_phishing AS (
    SELECT
        email_id,
        urgency_score,
        bait_score,
        url_count,
        has_ip_url,
        exclamation_count,
        email_length,
        NTILE(20) OVER (
            ORDER BY urgency_score DESC, bait_score DESC, email_id
        ) AS risk_bucket
    FROM emails
    WHERE label = 1
)
SELECT
    email_id,
    urgency_score,
    bait_score,
    url_count,
    has_ip_url,
    exclamation_count,
    email_length
FROM ranked_phishing
WHERE risk_bucket = 1
ORDER BY urgency_score DESC, bait_score DESC, email_id;


-- Query 3: "Evasive" phishing
-- Phishing emails with no urgency phrases, no links, and no IP links: the ones a
-- keyword/URL rule filter has nothing to catch. Reported as a count and as a
-- percentage of all phishing emails.
SELECT
    SUM(CASE WHEN urgency_score = 0 AND url_count = 0 AND has_ip_url = 0
             THEN 1 ELSE 0 END)                                       AS evasive_count,
    COUNT(*)                                                          AS total_phishing,
    ROUND(100.0 * SUM(CASE WHEN urgency_score = 0 AND url_count = 0 AND has_ip_url = 0
                           THEN 1 ELSE 0 END) / COUNT(*), 2)          AS pct_of_phishing
FROM emails
WHERE label = 1;
