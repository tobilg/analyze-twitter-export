#! /bin/bash

mkdir -p docs/

duckerd -d data/twitter.duckdb -o docs/erd.png -w 1600 -H 1200 -f png -t neutral
