#!/bin/bash
# Join a subreddit
# Usage: ./join_subreddit.sh <subreddit_name> <user_id>
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <subreddit_name> <user_id>"
  exit 1
fi

curl -X POST http://localhost:8080/api/v1/subreddits/$1/join \
  -H "Content-Type: application/json" \
  -d "{\"user_id\": $2}" \
  -w "\n"


