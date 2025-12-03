#!/bin/bash
# Upvote a post
# Usage: ./upvote_post.sh <post_id> <user_id>
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <post_id> <user_id>"
  exit 1
fi

curl -X POST http://localhost:8080/api/v1/posts/$1/upvote \
  -H "Content-Type: application/json" \
  -d "{\"user_id\": $2}" \
  -w "\n"


