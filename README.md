# Project 4 - Reddit Gleam Simulator

## 1. Team Members

- Aria Yousefi
- Shane George Thomas

## 2. Steps to Run

```sh
gleam run
```

## 3. Features

- Project simulates Reddit with the following features:
  - **User Registration**: Users can register and get unique IDs
  - **Subreddit Management**: Create, join, and leave subreddits
  - **Post Submission**: Users can create posts in subreddits they've joined
  - **Comment System**: Users can comment on posts with support for threaded comments (parent/child relationships)
  - **Voting System**: Users can upvote or downvote both posts and comments
  - **Direct Messaging**: Users can send and receive direct messages
  - **Feed Generation**: Users can retrieve personalized feeds from their subscribed subreddits
  - **Karma Tracking**: Posts and comments track upvotes and downvotes separately
  - **Real-time Notifications**: Users receive notifications when posts are created in their subreddits or comments are made on their posts
  - **Statistics Collection**: The engine tracks all activity metrics for performance analysis
  - **Zipf Distribution**: Uses Zipf distribution (s=1.07) to simulate realistic subreddit popularity patterns
  - Uses an actor for each client and engine to run Reddit in separate processes

## 4. Configuration

The simulator can be configured by modifying the `main()` function in `src/project_4_reddit.gleam`:

- **Number of Users**: Currently set to 150
- **Number of Subreddits**: Currently set to 10
- **Time Run**: Currently set to 5 seconds

Example configuration:
```gleam
let n_users = 150
let n_subs = 10
let seconds = 5
```

## 5. Metrics Recorded

The simulator tracks and displays the following performance metrics:

- **Posts**: Total number of posts created during the simulation
- **Comments**: Total number of comments posted
- **Votes**: Total number of upvotes and downvotes combined
- **Direct Messages**: Total number of DMs sent
- **Subreddit Joins**: Total number of subreddit join operations
- **Subreddit Leaves**: Total number of subreddit leave operations
- **Total Actions**: Sum of all operations performed
- **Actions/sec**: Throughput metric showing actions per second

Example Output
```
=== Reddit Simulator Results ===
Configuration:
  Users: 150
  Subreddits: 10
  Duration: 5 seconds

Activity:
  Posts: 5400
  Comments: 2550
  Votes: 4200
  Direct Messages: 4200
  Subreddit Joins: 2400
  Subreddit Leaves: 0

Performance:
  Total Actions: 18750
  Actions/sec: 3750
================================
```

## 6. Largest Input Configuration Simulated
- Number of Users: 100
- Number of Subreddits: 10
- Execution Time: 10 seconds

```
=== Reddit Simulator Results ===
Configuration:
  Users: 100
  Subreddits: 10
  Duration: 10 seconds

Activity:
  Posts: 5500
  Comments: 3600
  Votes: 4500
  Direct Messages: 3400
  Subreddit Joins: 2500
  Subreddit Leaves: 0

Performance:
  Total Actions: 19500
  Actions/sec: 1950
================================
```
