#!/bin/bash

DATA_PATH="$PWD/data/twitter.duckdb"

rm -f $DATA_PATH

mkdir -p $PWD/data

duckdb $DATA_PATH < queries/create_database.sql
