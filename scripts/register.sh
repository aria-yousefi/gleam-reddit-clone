#!/bin/bash
# Register a new user
curl -X POST http://localhost:8080/api/v1/register \
  -H "Content-Type: application/json" \
  -w "\n"


