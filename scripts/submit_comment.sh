#!/bin/bash
# Submit a comment
# Usage: ./submit_comment.sh <user_id> <post_id> [parent_comment_id] <body>
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Usage: $0 <user_id> <post_id> [parent_comment_id] <body>"
  echo "      If parent_comment_id is provided, it will be a reply to that comment"
  exit 1
fi

if [ -n "$4" ]; then
  # Has parent comment ID
  curl -X POST http://localhost:8080/api/v1/comments \
    -H "Content-Type: application/json" \
    -d "{\"author\": $1, \"post\": $2, \"parent\": $3, \"body\": \"$4\"}" \
    -w "\n"
else
  # No parent comment ID
  curl -X POST http://localhost:8080/api/v1/comments \
    -H "Content-Type: application/json" \
    -d "{\"author\": $1, \"post\": $2, \"parent\": null, \"body\": \"$3\"}" \
    -w "\n"
fi


