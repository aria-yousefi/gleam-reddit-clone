# Project 4 - Reddit Gleam Simulator

## 1. Team Members

- Aria Yousefi
- Shane George Thomas

## 2. Steps to Run

```sh
gleam run -m api
```

Running the above will start the REST API server, which can then be accessed to interact with the client.

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