# Reddit API Client Scripts

This directory contains shell scripts for testing the Reddit REST API. Each shell script accepts a required set of input parameters, and runs a curl command to access the Reddit Clone API.

## Prerequisites

- The API server must be running on `http://localhost:8080`
- `curl` must be installed

## Starting the Server

To start the API server, run:

```bash
gleam run -m api
```

If no port is specified, it defaults to 8080.


## Available Scripts

### User Management
- **register.sh** - Register a new user
  ```bash
  ./scripts/register.sh
  ```

### Subreddit Management
- **create_subreddit.sh** - Create a new subreddit
  ```bash
  ./scripts/create_subreddit.sh <subreddit_name>
  ```

- **join_subreddit.sh** - Join a subreddit
  ```bash
  ./scripts/join_subreddit.sh <subreddit_name> <user_id>
  ```

- **leave_subreddit.sh** - Leave a subreddit
  ```bash
  ./scripts/leave_subreddit.sh <subreddit_name> <user_id>
  ```

### Posts
- **submit_post.sh** - Submit a new post
  ```bash
  ./scripts/submit_post.sh <user_id> <subreddit_name> <body>
  ```

- **upvote_post.sh** - Upvote a post
  ```bash
  ./scripts/upvote_post.sh <post_id> <user_id>
  ```

- **downvote_post.sh** - Downvote a post
  ```bash
  ./scripts/downvote_post.sh <post_id> <user_id>
  ```

### Comments
- **submit_comment.sh** - Submit a comment (or reply to a comment)
  ```bash
  # Top-level comment
  ./scripts/submit_comment.sh <user_id> <post_id> <body>
  
  # Reply to a comment
  ./scripts/submit_comment.sh <user_id> <post_id> <parent_comment_id> <body>
  ```

- **upvote_comment.sh** - Upvote a comment
  ```bash
  ./scripts/upvote_comment.sh <comment_id> <user_id>
  ```

- **downvote_comment.sh** - Downvote a comment
  ```bash
  ./scripts/downvote_comment.sh <comment_id> <user_id>
  ```

### Feed
- **get_feed.sh** - Get user's personalized feed
  ```bash
  ./scripts/get_feed.sh <user_id> [limit]
  ```

### Direct Messages
- **send_dm.sh** - Send a direct message
  ```bash
  ./scripts/send_dm.sh <from_user_id> <to_user_id> <message>
  ```

- **get_dms.sh** - Get direct messages for a user
  ```bash
  ./scripts/get_dms.sh <user_id>
  ```

## Example Workflow

1. Start the server:
   ```bash
   gleam run server
   ```

2. Register a user:
   ```bash
   ./scripts/register.sh
   # Returns: {"user_id": 1}
   ```

3. Create a subreddit:
   ```bash
   ./scripts/create_subreddit.sh r/programming
   ```

4. Join the subreddit:
   ```bash
   ./scripts/join_subreddit.sh r/programming 1
   ```

5. Submit a post:
   ```bash
   ./scripts/submit_post.sh 1 r/programming "Hello, world!"
   ```

6. Get your feed:
   ```bash
   ./scripts/get_feed.sh 1 10
   ```

