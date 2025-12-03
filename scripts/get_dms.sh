#!/bin/bash
# Get direct messages for a user
# Usage: ./get_dms.sh <user_id>
if [ -z "$1" ]; then
  echo "Usage: $0 <user_id>"
  exit 1
fi

curl -X GET http://localhost:8080/api/v1/users/$1/messages \
  -H "Content-Type: application/json" \
  -w "\n"


