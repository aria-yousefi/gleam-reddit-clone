#!/bin/bash
# Submit a post
# Usage: ./submit_post.sh <user_id> <subreddit_name> <body>
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Usage: $0 <user_id> <subreddit_name> <body>"
  exit 1
fi

curl -X POST http://localhost:8080/api/v1/posts \
  -H "Content-Type: application/json" \
  -d "{\"author\": $1, \"sub\": \"$2\", \"body\": \"$3\"}" \
  -w "\n"


