#!/bin/bash
set -e

# Unzip the data
unzip -o src-data/twitter-*.zip -d src-data/tweets

# Create the data directory
mkdir -p data

# Move the relevant data files to the data directory
mv src-data/tweets/data/tweets.js data/tweets.json

# Remove the source directory
rm -rf src-data/tweets

# Remove the window wrapper from the data files
sed -i '' -e 's/^window.*[[:space:]]=[[:space:]]\(.*\)$/\1/' data/*