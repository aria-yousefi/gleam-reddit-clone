#!/bin/bash
# Get user feed
# Usage: ./get_feed.sh <user_id> [limit]
if [ -z "$1" ]; then
  echo "Usage: $0 <user_id> [limit]"
  exit 1
fi

LIMIT=${2:-10}

curl -X GET "http://localhost:8080/api/v1/users/$1/feed?limit=$LIMIT" \
  -H "Content-Type: application/json" \
  -w "\n"


