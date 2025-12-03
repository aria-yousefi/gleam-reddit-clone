#!/bin/bash
# Create a subreddit
# Usage: ./create_subreddit.sh <name>
if [ -z "$1" ]; then
  echo "Usage: $0 <subreddit_name>"
  exit 1
fi

curl -X POST http://localhost:8080/api/v1/subreddits \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$1\"}" \
  -w "\n"


