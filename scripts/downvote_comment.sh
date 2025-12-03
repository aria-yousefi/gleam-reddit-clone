#!/bin/bash
# Downvote a comment
# Usage: ./downvote_comment.sh <comment_id> <user_id>
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <comment_id> <user_id>"
  exit 1
fi

curl -X POST http://localhost:8080/api/v1/comments/$1/downvote \
  -H "Content-Type: application/json" \
  -d "{\"user_id\": $2}" \
  -w "\n"


