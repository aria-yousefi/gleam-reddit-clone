#!/bin/bash
# Send a direct message
# Usage: ./send_dm.sh <from_user_id> <to_user_id> <message>
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "Usage: $0 <from_user_id> <to_user_id> <message>"
  exit 1
fi

curl -X POST http://localhost:8080/api/v1/messages \
  -H "Content-Type: application/json" \
  -d "{\"from\": $1, \"to\": $2, \"body\": \"$3\"}" \
  -w "\n"


