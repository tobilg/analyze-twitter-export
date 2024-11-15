-- Prepare the tables
CREATE TABLE hashtag (hashtag_id BIGINT PRIMARY KEY, hashtag VARCHAR);
CREATE TABLE url (url_id BIGINT PRIMARY KEY, url VARCHAR, expanded_url VARCHAR);
CREATE TABLE "user" (user_id VARCHAR PRIMARY KEY, screen_name VARCHAR, "name" VARCHAR);
CREATE TABLE tweet(tweet_id VARCHAR PRIMARY KEY, created_at TIMESTAMP, "content" VARCHAR, content_expanded VARCHAR, favorite_count INTEGER, retweet_count INTEGER, "language" VARCHAR, is_reply BOOLEAN);
CREATE TABLE rel_tweet_hashtag (tweet_id VARCHAR, hashtag_id BIGINT, FOREIGN KEY (tweet_id) REFERENCES tweet (tweet_id), FOREIGN KEY (hashtag_id) REFERENCES hashtag (hashtag_id));
CREATE TABLE rel_tweet_mentioned_user (tweet_id VARCHAR, user_id VARCHAR, FOREIGN KEY (tweet_id) REFERENCES tweet (tweet_id), FOREIGN KEY (user_id) REFERENCES "user" (user_id));
CREATE TABLE rel_tweet_replied_user (tweet_id VARCHAR, user_id VARCHAR, FOREIGN KEY (tweet_id) REFERENCES tweet (tweet_id), FOREIGN KEY (user_id) REFERENCES "user" (user_id));
CREATE TABLE rel_tweet_url (tweet_id VARCHAR, url_id BIGINT, FOREIGN KEY (tweet_id) REFERENCES tweet (tweet_id), FOREIGN KEY (url_id) REFERENCES url (url_id));

-- Just load the raw JSON data
CREATE OR REPLACE TABLE raw_tweets AS SELECT * FROM read_json('data/tweets.json');

-- Extract the needed tweet data
CREATE OR REPLACE TABLE extracted_tweets AS 
SELECT
  tweet.id AS id,
  strptime(tweet.created_at, '%a %b %d %H:%M:%S %z %Y')::TIMESTAMP AS created_at,
  tweet.full_text AS content,
  tweet.entities.urls AS urls,
  tweet.entities.user_mentions AS mentions,
  tweet.entities.hashtags AS hashtags,
  tweet.favorite_count::int AS favorite_count,
  tweet.retweet_count::int AS retweet_count,
  tweet.lang AS language,
  CASE
    WHEN tweet.in_reply_to_status_id_str IS NOT NULL THEN true
    ELSE false
  END AS is_reply,
  tweet.in_reply_to_user_id_str AS reply_to_user_id,
  tweet.in_reply_to_screen_name AS reply_to_screen_name
FROM 
  raw_tweets;

-- Extract the URLs from the tweets
CREATE OR REPLACE TABLE tweet_urls AS 
WITH tweet_urls AS (
  SELECT
    id,
    unnest(urls) AS url_data
  FROM extracted_tweets
)
SELECT
  id,
  url_data.url AS url,
  url_data.expanded_url AS expanded_url,
  url_data.indices[1] AS start_position
FROM 
  tweet_urls
ORDER BY id ASC, start_position ASC;

-- Expand the URLs in the tweets
CREATE OR REPLACE TABLE tweet_expanded_contents AS
WITH prepared_contents AS (
  SELECT
    et.id,
    et.content,
    replace(et.content, tu.url, tu.expanded_url) AS cleaned_content,
    RANK() OVER (PARTITION BY tu.id ORDER BY tu.start_position ASC) AS url_rank,
    tu.url,
    tu.expanded_url
  FROM 
    extracted_tweets et
  INNER JOIN 
    tweet_urls tu
  ON 
    et.id = tu.id
),
pre_final AS (SELECT
  id,
  cleaned_content,
  CASE
    WHEN url_rank = 1 THEN cleaned_content
    WHEN url_rank > 1 AND url_rank <= MAX(url_rank) OVER (PARTITION BY id) THEN replace(LAG(cleaned_content, 1) OVER (PARTITION BY id ORDER BY url_rank), url, expanded_url)
    ELSE 'ERROR'
  END AS new_content,
  url_rank,
  url,
  expanded_url,
  CASE
    WHEN MAX(url_rank) OVER (PARTITION BY id) = url_rank THEN true
    ELSE false
  END AS is_latest
FROM 
  prepared_contents
),
final AS (SELECT
  id,
  CASE 
    WHEN is_latest AND url_rank > 1 THEN replace(LAG(new_content, 1) OVER (PARTITION BY id ORDER BY url_rank), url, expanded_url)
    ELSE new_content
  END AS final_content,
  url_rank,
  is_latest
FROM
  pre_final
)
SELECT
  id as tweet_id,
  replace(final_content, '\\n', ' ') AS final_content
FROM
  final
WHERE 
  is_latest = true;

-- Create the URL table with distinct URLs
INSERT INTO url
WITH urls AS (
  SELECT
    url,
    expanded_url
  FROM tweet_urls
)
SELECT DISTINCT
  row_number() over () as url_id,
  url,
  expanded_url
FROM urls;

-- Create the tweet table
INSERT INTO tweet
SELECT
  id as tweet_id,
  created_at,
  content,
  CASE
    WHEN t.final_content IS NOT NULL THEN t.final_content
    ELSE content
  END AS content_expanded,
  favorite_count,
  retweet_count,
  language,
  is_reply
FROM 
  extracted_tweets
LEFT OUTER JOIN
  tweet_expanded_contents t
ON
  extracted_tweets.id = t.tweet_id;

INSERT INTO rel_tweet_url
SELECT
  tu.id AS tweet_id,
  u.url_id
FROM 
  tweet_urls tu
INNER JOIN
  url u
ON
  tu.url = u.url;

-- Create the raw mentioned users table
CREATE OR REPLACE TABLE raw_tweet_mentioned_users AS 
WITH tweet_mentions AS (
  SELECT
    id,
    unnest(mentions) AS mention_data
  FROM extracted_tweets
)
SELECT
  id,
  mention_data.id_str AS user_id,
  mention_data.screen_name AS screen_name,
  mention_data.name AS name
FROM
  tweet_mentions
ORDER BY id ASC, mention_data.id_str ASC;

-- Create the raw replied users table
CREATE OR REPLACE TABLE raw_tweet_replied_users AS 
SELECT
  id as tweet_id,
  reply_to_user_id as user_id,
  reply_to_screen_name as screen_name,
  NULL as name
FROM 
  extracted_tweets
WHERE 
  is_reply = true
AND
  reply_to_user_id IS NOT NULL
AND
  reply_to_screen_name IS NOT NULL;

-- Create the user table
INSERT INTO "user"
SELECT DISTINCT
  CASE
    WHEN r.user_id IS NOT NULL THEN r.user_id::varchar
    WHEN m.user_id IS NOT NULL THEN m.user_id::varchar
    ELSE 'ERROR'
  END AS user_id,
  CASE
    WHEN r.screen_name IS NOT NULL THEN r.screen_name::varchar
    WHEN m.screen_name IS NOT NULL THEN m.screen_name::varchar
    ELSE 'ERROR'
  END AS screen_name,
  CASE
    WHEN r.name IS NOT NULL THEN r.name::varchar
    WHEN m.name IS NOT NULL THEN m.name::varchar
    ELSE NULL
  END AS name
FROM
  (
    SELECT DISTINCT
      user_id,
      screen_name,
      name
    FROM raw_tweet_replied_users
  ) r
FULL OUTER JOIN
  (
    SELECT DISTINCT
      user_id,
      screen_name,
      name
    FROM raw_tweet_mentioned_users
  ) m
ON
  r.user_id = m.user_id
WHERE
  r.user_id != '-1'
AND
  m.user_id != '-1'
ORDER BY user_id ASC;
INSERT INTO "user" VALUES ('-1', 'Dummy User', 'Dummy User');

-- Create the replied users relation table 
INSERT INTO rel_tweet_replied_user
SELECT DISTINCT
  tweet_id,
  user_id
FROM 
  raw_tweet_replied_users
WHERE 
  user_id IN (SELECT DISTINCT user_id FROM "user");

-- Create the mentioned users relation table
INSERT INTO rel_tweet_mentioned_user
SELECT DISTINCT
  id AS tweet_id,
  user_id
FROM 
  raw_tweet_mentioned_users
WHERE 
  user_id IN (SELECT DISTINCT user_id FROM "user");

-- Create the hashtag table
INSERT INTO hashtag
WITH tweet_hashtags AS (
  SELECT
    unnest(hashtags) AS hashtag_data
  FROM extracted_tweets
),
hashtag_data AS (
  SELECT DISTINCT
    hashtag_data.text AS hashtag
  FROM
    tweet_hashtags
  ORDER BY hashtag ASC
)
SELECT
  row_number() over () as hashtag_id,
  hashtag
FROM hashtag_data;

INSERT INTO rel_tweet_hashtag
WITH tweet_hashtags AS (
  SELECT
    id,
    unnest(hashtags) AS hashtag_data
  FROM extracted_tweets
),
hashtag_data AS (
  SELECT
    id,
    hashtag_data.text AS hashtag
  FROM
    tweet_hashtags
  ORDER BY id ASC, hashtag ASC
)
SELECT
  hd.id as tweet_id,
  h.hashtag_id,
FROM 
  hashtag_data hd
INNER JOIN
  hashtag h
ON
  hd.hashtag = h.hashtag;

-- Drop the raw tables
DROP TABLE raw_tweets;
DROP TABLE extracted_tweets;
DROP TABLE tweet_urls;
DROP TABLE tweet_expanded_contents;
DROP TABLE raw_tweet_mentioned_users;
DROP TABLE raw_tweet_replied_users;
