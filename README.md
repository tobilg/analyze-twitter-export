# analyze-twitter-export
Analyze your Twitter export data with the help of [DuckDB](https://duckdb.org/).

## Usage
The following steps are required to analyze your Twitter export data.

1. Install DuckDB.  
    This can be done with running the `scripts/install_duckdb.sh` script (it assumes you're on a Linux machine). Otherwise you could do a `brew install duckdb` on MacOS, or follow the [instructions](https://duckdb.org/docs/installation) for your platform from the DuckDB website.
2. Copy the downloaded Twitter export data to the `src-data` directory.  
    This should be the zip file you downloaded from Twitter.
3. Prepare the Twitter export data for import into DuckDB.  
    The data needs to be converted into a format that can be imported into DuckDB. This can be done with running the `scripts/prepare_tweets.sh` script.
4. Create a DuckDB database from your Twitter export data.  
    This can be done with running the `scripts/create_database.sh` script. The result will be a file called `twitter.duckdb` in the `data` directory.
5. Analyze the data.  
    This can be done with running `duckdb data/twitter.duckdb` in the project root directory, and then executing the SQL queries inside the started DuckDB CLI.
 
## Entity Relationship Diagram
The following diagram shows the structure of the resulting database.

![Twitter Export Database ERD](docs/erd.png)

## Example Queries
The following example queries can be used to analyze the data.

### Show all tweets and replies
```sql
SELECT 
    * 
FROM 
    tweet
ORDER BY created_at DESC;
```

### Show all tweets with expanded content (w/o replies)
```sql
SELECT 
    tweet_id, created_at, content_expanded, favorite_count, retweet_count, language
FROM 
    tweet
WHERE
    is_reply = false
ORDER BY created_at DESC;
```

### Number of tweets per day
```sql
SELECT 
    strftime(created_at, '%Y-%m-%d') as day, COUNT(*) as count
FROM 
    tweet
GROUP BY day
ORDER BY day;
```

### Most used hashtags
```sql
SELECT 
    h.hashtag, COUNT(distinct rh.tweet_id) as count
FROM 
    hashtag h
INNER JOIN
    rel_tweet_hashtag rh ON h.hashtag_id = rh.hashtag_id
GROUP BY h.hashtag
ORDER BY count DESC;
```

### Most mentioned users
```sql
SELECT 
    u.screen_name, COUNT(distinct ru.tweet_id) as count
FROM 
    user u
INNER JOIN
    rel_tweet_mentioned_user ru ON u.user_id = ru.user_id
GROUP BY u.screen_name
ORDER BY count DESC;
```