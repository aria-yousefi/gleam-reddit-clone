//// Gleam Reddit Clone — Single-file version (project_4_reddit.gleam)

// Requires: gleam_stdlib, gleam_otp

import gleam/dict
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/otp/actor
import gleam/result
import gleam/set

// ============================
// Types & shared definitions
// ============================

pub type UserId {
  UserId(Int)
}

pub type SubId =
  String

pub type PostId {
  PostId(Int)
}

pub type CommentId {
  CommentId(Int)
}

pub type DMId {
  DMId(Int)
}

pub type Karma {
  Karma(ups: Int, downs: Int)
}

pub fn karma_score(k: Karma) -> Int {
  k.ups - k.downs
}

pub type Post {
  Post(
    id: PostId,
    author: UserId,
    sub: SubId,
    body: String,
    karma: Karma,
    ts_ms: Int,
  )
}

pub type Comment {
  Comment(
    id: CommentId,
    author: UserId,
    post: PostId,
    parent: Option(CommentId),
    body: String,
    karma: Karma,
    ts_ms: Int,
  )
}

pub type DM {
  DM(id: DMId, from: UserId, to: UserId, body: String, ts_ms: Int)
}

pub type Subreddit {
  Subreddit(
    name: SubId,
    members: set.Set(UserId),
    posts: List(PostId),
    karma: Karma,
  )
}

pub type FeedItem {
  FeedPost(post: Post)
  FeedComment(comment: Comment, on: PostId)
}

// Engine protocol
pub type EngineMsg {
  Register(reply_to: process.Subject(EngineReply))

  CreateSub(name: SubId, reply_to: process.Subject(EngineReply))
  JoinSub(user: UserId, name: SubId)
  LeaveSub(user: UserId, name: SubId)

  SubmitPost(author: UserId, sub: SubId, body: String)
  SubmitComment(
    author: UserId,
    post: PostId,
    parent: Option(CommentId),
    body: String,
  )

  UpvotePost(user: UserId, post: PostId)
  DownvotePost(user: UserId, post: PostId)
  UpvoteComment(user: UserId, comment: CommentId)
  DownvoteComment(user: UserId, comment: CommentId)

  GetFeed(user: UserId, limit: Int, reply_to: process.Subject(EngineReply))

  SendDM(from: UserId, to: UserId, body: String)
  GetDMs(user: UserId, reply_to: process.Subject(EngineReply))

  Snapshot(reply_to: process.Subject(dict.Dict(String, Int)))
  AttachUser(user: UserId, subject: process.Subject(ClientMsg))
  SamplePost(reply_to: process.Subject(EngineReply))
}

pub type EngineReply {
  Registered(user: UserId)
  SubCreated(name: SubId)
  Posted(post: Post)
  Commented(comment: Comment)
  Feed(items: List(FeedItem))
  DMs(items: List(DM))
  Ack
  Fail(reason: String)
  PostSample(sample: Option(Post))
}

// ============================
// Engine (single process)
// ============================

pub type UserMsg {
  NotifyPost(post: Post)
  NotifyComment(comment: Comment)
}

pub type EngineState {
  EngineState(
    users: dict.Dict(UserId, process.Subject(ClientMsg)),
    subs: dict.Dict(SubId, Subreddit),
    posts: dict.Dict(PostId, Post),
    comments: dict.Dict(CommentId, Comment),
    dms: dict.Dict(UserId, List(DM)),
    next_user_id: Int,
    next_post_id: Int,
    next_comment_id: Int,
    next_dm_id: Int,
    stats: dict.Dict(String, Int),
    votes: set.Set(String),
  )
}

pub fn engine_start() -> process.Subject(EngineMsg) {
  let assert Ok(started) =
    actor.new(engine_init(Nil))
    |> actor.on_message(engine_handle)
    |> actor.start

  started.data
}

fn engine_init(_msg: Nil) -> EngineState {
  EngineState(
    users: dict.new(),
    subs: dict.new(),
    posts: dict.new(),
    comments: dict.new(),
    dms: dict.new(),
    next_user_id: 1,
    next_post_id: 1,
    next_comment_id: 1,
    next_dm_id: 1,
    stats: dict.from_list([
      #("posts", 0),
      #("comments", 0),
      #("votes", 0),
      #("dms", 0),
      #("joins", 0),
      #("leaves", 0),
    ]),
    votes: set.new(),
  )
}

fn find_in_list(items: List(#(k, v)), key: k) -> Result(v, Nil) {
  case list.find(items, fn(pair) { pair.0 == key }) {
    Ok(pair) -> Ok(pair.1)
    Error(_) -> Error(Nil)
  }
}

fn dict_get_fallback(d: dict.Dict(k, v), key: k) -> Result(v, Nil) {
  find_in_list(dict.to_list(d), key)
}

fn bump(stat: String, st: EngineState) -> EngineState {
  let current = dict_get_fallback(st.stats, stat) |> result.unwrap(0)
  let new_val = current + 1
  EngineState(..st, stats: dict.insert(st.stats, stat, new_val))
}

@external(erlang, "project_4_reddit_helper", "system_time_millisecond")
fn erlang_system_time_millisecond() -> Int

fn now_ms() -> Int {
  // erlang:system_time(millisecond) -> integer() >= 0
  erlang_system_time_millisecond()
}

fn engine_handle(
  st: EngineState,
  msg: EngineMsg,
) -> actor.Next(EngineState, EngineMsg) {
  case msg {
    Register(reply) -> {
      let id = UserId(st.next_user_id)
      process.send(reply, Registered(id))
      actor.continue(EngineState(..st, next_user_id: st.next_user_id + 1))
    }

    CreateSub(name, reply) -> {
      case dict.has_key(st.subs, name) {
        True -> {
          process.send(reply, Fail("sub exists"))
          actor.continue(st)
        }
        False -> {
          let sub: Subreddit = Subreddit(name, set.new(), [], Karma(0, 0))
          process.send(reply, SubCreated(name))
          let subs2: dict.Dict(SubId, Subreddit) =
            dict.insert(st.subs, name, sub)
          actor.continue(EngineState(..st, subs: subs2))
        }
      }
    }

    JoinSub(user, name) -> {
      let sub = dict_get_fallback(st.subs, name)
      case sub {
        Error(_) -> actor.continue(st)
        Ok(Subreddit(n, members, posts, k)) -> {
          let members2: set.Set(UserId) = set.insert(members, user)
          let sub2: Subreddit = Subreddit(n, members2, posts, k)
          let subs2: dict.Dict(SubId, Subreddit) =
            dict.insert(st.subs, name, sub2)
          actor.continue(bump("joins", EngineState(..st, subs: subs2)))
        }
      }
    }

    LeaveSub(user, name) -> {
      let sub = dict_get_fallback(st.subs, name)
      case sub {
        Error(_) -> actor.continue(st)
        Ok(Subreddit(n, members, posts, k)) -> {
          let members2: set.Set(UserId) = set.delete(members, user)
          let sub2: Subreddit = Subreddit(n, members2, posts, k)
          let subs2: dict.Dict(SubId, Subreddit) =
            dict.insert(st.subs, name, sub2)
          actor.continue(bump("leaves", EngineState(..st, subs: subs2)))
        }
      }
    }

    SubmitPost(author, sub_name, body) -> {
      case dict_get_fallback(st.subs, sub_name) {
        Error(_) -> {
          actor.continue(st)
        }
        Ok(sub) -> {
          let id = PostId(st.next_post_id)
          let post = Post(id, author, sub_name, body, Karma(0, 0), now_ms())
          let posts2: dict.Dict(PostId, Post) = dict.insert(st.posts, id, post)
          let st1 =
            EngineState(..st, posts: posts2, next_post_id: st.next_post_id + 1)
          let sub2: Subreddit =
            Subreddit(sub.name, sub.members, [id, ..sub.posts], sub.karma)
          // Notify members (best-effort)
          let _ =
            set.to_list(sub.members)
            |> list.each(fn(u: UserId) {
              case dict_get_fallback(st1.users, u) {
                Ok(s) -> process.send(s, EngineNotify(NotifyPost(post)))
                Error(_) -> Nil
              }
            })
          let subs2: dict.Dict(SubId, Subreddit) =
            dict.insert(st1.subs, sub_name, sub2)
          actor.continue(bump("posts", EngineState(..st1, subs: subs2)))
        }
      }
    }

    SubmitComment(author, post_id, parent, body) -> {
      case dict_get_fallback(st.posts, post_id) {
        Error(_) -> {
          actor.continue(st)
        }
        Ok(p) -> {
          let id = CommentId(st.next_comment_id)
          let c =
            Comment(id, author, post_id, parent, body, Karma(0, 0), now_ms())
          let comments2: dict.Dict(CommentId, Comment) =
            dict.insert(st.comments, id, c)
          let st1 =
            EngineState(
              ..st,
              comments: comments2,
              next_comment_id: st.next_comment_id + 1,
            )

          // Best-effort notify post author if registered
          let Post(_, post_author, _, _, _, _) = p
          let st2 = case dict_get_fallback(st1.users, post_author) {
            Ok(s) -> {
              process.send(s, EngineNotify(NotifyComment(c)))
              st1
            }
            Error(_) -> st1
          }

          actor.continue(bump("comments", st2))
        }
      }
    }

    UpvotePost(user, pid) -> {
      let UserId(user_id) = user
      let PostId(post_id) = pid
      let vote_key =
        "p:" <> int.to_string(user_id) <> ":" <> int.to_string(post_id)
      case set.contains(st.votes, vote_key) {
        True -> {
          // User already voted on this post
          actor.continue(st)
        }
        False -> {
          case dict_get_fallback(st.posts, pid) {
            Error(_) -> actor.continue(st)
            Ok(p) -> {
              let p2 = Post(..p, karma: Karma(p.karma.ups + 1, p.karma.downs))
              let posts2: dict.Dict(PostId, Post) =
                dict.insert(st.posts, pid, p2)
              let votes2: set.Set(String) = set.insert(st.votes, vote_key)
              actor.continue(bump(
                "votes",
                EngineState(..st, posts: posts2, votes: votes2),
              ))
            }
          }
        }
      }
    }

    DownvotePost(user, pid) -> {
      let UserId(user_id) = user
      let PostId(post_id) = pid
      let vote_key =
        "p:" <> int.to_string(user_id) <> ":" <> int.to_string(post_id)
      case set.contains(st.votes, vote_key) {
        True -> {
          // User already voted on this post
          actor.continue(st)
        }
        False -> {
          case dict_get_fallback(st.posts, pid) {
            Error(_) -> actor.continue(st)
            Ok(p) -> {
              let p2 = Post(..p, karma: Karma(p.karma.ups, p.karma.downs + 1))
              let posts2: dict.Dict(PostId, Post) =
                dict.insert(st.posts, pid, p2)
              let votes2: set.Set(String) = set.insert(st.votes, vote_key)
              actor.continue(bump(
                "votes",
                EngineState(..st, posts: posts2, votes: votes2),
              ))
            }
          }
        }
      }
    }

    UpvoteComment(user, cid) -> {
      let UserId(user_id) = user
      let CommentId(comment_id) = cid
      let vote_key =
        "c:" <> int.to_string(user_id) <> ":" <> int.to_string(comment_id)
      case set.contains(st.votes, vote_key) {
        True -> {
          // User already voted on this comment
          actor.continue(st)
        }
        False -> {
          case dict_get_fallback(st.comments, cid) {
            Error(_) -> actor.continue(st)
            Ok(c) -> {
              let c2 =
                Comment(..c, karma: Karma(c.karma.ups + 1, c.karma.downs))
              let comments2: dict.Dict(CommentId, Comment) =
                dict.insert(st.comments, cid, c2)
              let votes2: set.Set(String) = set.insert(st.votes, vote_key)
              actor.continue(bump(
                "votes",
                EngineState(..st, comments: comments2, votes: votes2),
              ))
            }
          }
        }
      }
    }

    DownvoteComment(user, cid) -> {
      let UserId(user_id) = user
      let CommentId(comment_id) = cid
      let vote_key =
        "c:" <> int.to_string(user_id) <> ":" <> int.to_string(comment_id)
      case set.contains(st.votes, vote_key) {
        True -> {
          // User already voted on this comment
          actor.continue(st)
        }
        False -> {
          case dict_get_fallback(st.comments, cid) {
            Error(_) -> actor.continue(st)
            Ok(c) -> {
              let c2 =
                Comment(..c, karma: Karma(c.karma.ups, c.karma.downs + 1))
              let comments2: dict.Dict(CommentId, Comment) =
                dict.insert(st.comments, cid, c2)
              let votes2: set.Set(String) = set.insert(st.votes, vote_key)
              actor.continue(bump(
                "votes",
                EngineState(..st, comments: comments2, votes: votes2),
              ))
            }
          }
        }
      }
    }

    GetFeed(user, limit, reply) -> {
      // Get all posts from user's subscribed subreddits
      let user_subs =
        dict.to_list(st.subs)
        |> list.filter(fn(pair) { set.contains({ pair.1 }.members, user) })
      let all_post_ids = list.flat_map(user_subs, fn(pair) { { pair.1 }.posts })

      // Get all posts from subscribed subreddits
      let posts_results =
        list.map(all_post_ids, fn(pid) { dict_get_fallback(st.posts, pid) })
      let posts = result.values(posts_results)

      // Get all comments on those posts
      let all_comments: List(Comment) =
        dict.to_list(st.comments) |> list.map(fn(pair) { pair.1 })

      let comments_on_user_posts =
        list.filter(all_comments, fn(c: Comment) {
          list.contains(all_post_ids, c.post)
        })

      // Create feed items from posts
      let post_items = list.map(posts, FeedPost)

      // Create feed items from comments (include the post ID)
      let comment_items =
        list.map(comments_on_user_posts, fn(c: Comment) {
          FeedComment(c, c.post)
        })

      // Combine and sort by timestamp (most recent first)
      let all_items = list.append(post_items, comment_items)

      // Sort by timestamp (descending - most recent first)
      // We need to extract ts_ms from each FeedItem
      let sorted_items =
        list.sort(all_items, fn(a: FeedItem, b: FeedItem) {
          let ts_a = case a {
            FeedPost(p) -> p.ts_ms
            FeedComment(c, _) -> c.ts_ms
          }
          let ts_b = case b {
            FeedPost(p) -> p.ts_ms
            FeedComment(c, _) -> c.ts_ms
          }
          // Descending order (newest first) - reverse the comparison
          case int.compare(ts_a, ts_b) {
            order.Lt -> order.Gt
            order.Eq -> order.Eq
            order.Gt -> order.Lt
          }
        })

      // Apply limit
      let limited_items = list.take(sorted_items, limit)

      process.send(reply, Feed(limited_items))
      actor.continue(st)
    }

    SendDM(from, to, body) -> {
      let id = DMId(st.next_dm_id)
      let dm = DM(id, from, to, body, now_ms())
      let inbox: List(DM) = dict_get_fallback(st.dms, to) |> result.unwrap([])
      let dms2: dict.Dict(UserId, List(DM)) =
        dict.insert(st.dms, to, [dm, ..inbox])
      let st1 = EngineState(..st, dms: dms2, next_dm_id: st.next_dm_id + 1)
      actor.continue(bump("dms", st1))
    }

    GetDMs(user, reply) -> {
      let inbox = dict_get_fallback(st.dms, user) |> result.unwrap([])
      process.send(reply, DMs(inbox))
      actor.continue(st)
    }

    Snapshot(reply) -> {
      process.send(reply, st.stats)
      actor.continue(st)
    }

    AttachUser(user, subject) -> {
      let users2: dict.Dict(UserId, process.Subject(ClientMsg)) =
        dict.insert(st.users, user, subject)
      actor.continue(EngineState(..st, users: users2))
    }

    SamplePost(reply) -> {
      let posts: List(Post) = dict.to_list(st.posts) |> list.map(fn(p) { p.1 })
      case posts {
        [] -> {
          process.send(reply, PostSample(None))
          actor.continue(st)
        }
        _ -> {
          let idx = int.absolute_value(st.next_post_id) % list.length(posts)
          let p = case list_at(posts, idx) {
            Ok(v) -> Some(v)
            Error(_) -> None
          }
          process.send(reply, PostSample(p))
          actor.continue(st)
        }
      }
    }
  }
}

// (Helper API used by clients)
// Ask the engine to register, expect a reply
pub fn register_user(engine: process.Subject(EngineMsg)) -> UserId {
  case process.call(engine, 5000, fn(reply) { Register(reply) }) {
    Registered(id) -> id
    _ -> UserId(0)
  }
}

pub fn attach_user(
  engine: process.Subject(EngineMsg),
  id: UserId,
  subj: process.Subject(ClientMsg),
) -> Nil {
  process.send(engine, AttachUser(id, subj))
  Nil
}

// ============================
// Zipf utilities
// ============================

pub fn pmf(n: Int, s: Float) -> List(Float) {
  let denom =
    list.range(1, n)
    |> list.map(int.to_float)
    |> list.map(fn(x) {
      float.power(x, s) |> result.unwrap(0.0) |> fn(p) { 1.0 /. p }
    })
    |> list.fold(0.0, fn(x, acc) { acc +. x })
  list.range(1, n)
  |> list.map(int.to_float)
  |> list.map(fn(x) {
    let p = float.power(x, s) |> result.unwrap(0.0)
    let weight = 1.0 /. p
    weight /. denom
  })
}

fn cdf_go(ws: List(Float), acc_sum: Float, acc_rev: List(Float)) -> List(Float) {
  case ws {
    [] -> list.reverse(acc_rev)
    [w, ..rest] -> {
      let s = acc_sum +. w
      cdf_go(rest, s, [s, ..acc_rev])
    }
  }
}

pub fn cdf(weights: List(Float)) -> List(Float) {
  cdf_go(weights, 0.0, [])
}

fn sample_go(ws: List(Float), u01: Float, idx: Int, acc: Float) -> Int {
  case ws {
    [] -> idx
    [w, ..rest] -> {
      let acc2 = acc +. w
      case u01 <=. acc2 {
        True -> idx
        False -> sample_go(rest, u01, idx + 1, acc2)
      }
    }
  }
}

pub fn sample(weights: List(Float), u01: Float) -> Int {
  sample_go(weights, u01, 1, 0.0)
}

fn list_at_go(a: List(a), index: Int) -> Result(a, Nil) {
  case a {
    [] -> Error(Nil)
    [h, ..t] -> {
      case index == 0 {
        True -> Ok(h)
        False -> list_at_go(t, index - 1)
      }
    }
  }
}

fn list_at(a: List(a), index: Int) -> Result(a, Nil) {
  list_at_go(a, index)
}

// ============================
// User client (simulated)
// ============================

pub type ClientCfg {
  ClientCfg(
    connect_ms: Int,
    online_ms: Int,
    offline_ms: Int,
    sub_pool: List(SubId),
    zipf_weights: List(Float),
  )
}

pub type ClientState {
  ClientState(
    id: UserId,
    engine: process.Subject(EngineMsg),
    connected: Bool,
    subs: List(SubId),
    rng: Int,
    cfg: ClientCfg,
    self: process.Subject(ClientMsg),
    online_since_tick: Option(Int),
    offline_since_tick: Option(Int),
    tick_count: Int,
  )
}

pub type ClientMsg {
  Start
  Tick
  GoOffline
  GoOnline
  EngineNotify(UserMsg)
  EngineReply(EngineReply)
}

fn client_init_with_self(
  engine: process.Subject(EngineMsg),
  cfg: ClientCfg,
  self: process.Subject(ClientMsg),
) -> ClientState {
  // for potential Engine→ClientMsg notifications
  let id = register_user(engine)
  attach_user(engine, id, self)
  ClientState(id, engine, False, [], 1_234_567, cfg, self, None, None, 0)
}

pub fn client_start(
  engine: process.Subject(EngineMsg),
  cfg: ClientCfg,
) -> process.Subject(ClientMsg) {
  let init_fn = fn(self: process.Subject(ClientMsg)) {
    // Build initial state with a handle to our own subject
    let st = client_init_with_self(engine, cfg, self)
    Ok(actor.initialised(st) |> actor.returning(self))
  }

  let assert Ok(subject) =
    actor.new_with_initialiser(1000, init_fn)
    |> actor.on_message(client_handle)
    |> actor.start

  subject.data
}

fn schedule_delayed_message(
  delay_ms: Int,
  subject: process.Subject(ClientMsg),
  message: ClientMsg,
) -> Nil {
  let timer_fn = fn() {
    process.sleep(delay_ms)
    process.send(subject, message)
    Nil
  }
  let _ = process.spawn(timer_fn)
  Nil
}

fn client_handle(
  st: ClientState,
  msg: ClientMsg,
) -> actor.Next(ClientState, ClientMsg) {
  case msg {
    Start -> {
      // Wait for connect_ms before going online
      schedule_delayed_message(st.cfg.connect_ms, st.self, GoOnline)
      // Start the tick loop to handle timing checks
      process.send(st.self, Tick)
      actor.continue(st)
    }

    Tick -> {
      let tick_ms = 50
      // Each tick represents ~50ms of activity
      let st2 = ClientState(..st, tick_count: st.tick_count + 1)

      // Act while online and check timing
      case st2.connected {
        True -> {
          // Check if we've been online long enough
          case st2.online_since_tick {
            None -> {
              // This shouldn't happen, but handle it
              let st3 =
                ClientState(..st2, online_since_tick: Some(st2.tick_count))
              process.sleep(tick_ms)
              let st4 = act_online(st3)
              process.send(st4.self, Tick)
              actor.continue(st4)
            }
            Some(online_start_tick) -> {
              let elapsed_ticks = st2.tick_count - online_start_tick
              let elapsed_ms = elapsed_ticks * tick_ms
              case elapsed_ms >= st2.cfg.online_ms {
                True -> {
                  // Time to go offline
                  process.send(st2.self, GoOffline)
                  actor.continue(st2)
                }
                False -> {
                  // Continue acting online
                  process.sleep(tick_ms)
                  let st3 = act_online(st2)
                  process.send(st3.self, Tick)
                  actor.continue(st3)
                }
              }
            }
          }
        }
        False -> {
          // Offline - check if we've been offline long enough
          case st2.offline_since_tick {
            None -> {
              // Just went offline or initial state, continue waiting
              process.sleep(tick_ms)
              process.send(st2.self, Tick)
              actor.continue(st2)
            }
            Some(offline_start_tick) -> {
              let elapsed_ticks = st2.tick_count - offline_start_tick
              let elapsed_ms = elapsed_ticks * tick_ms
              case elapsed_ms >= st2.cfg.offline_ms {
                True -> {
                  // Time to go back online
                  process.send(st2.self, GoOnline)
                  actor.continue(st2)
                }
                False -> {
                  // Continue waiting offline
                  process.sleep(tick_ms)
                  process.send(st2.self, Tick)
                  actor.continue(st2)
                }
              }
            }
          }
        }
      }
    }

    GoOnline -> {
      let st2 =
        ClientState(
          ..st,
          connected: True,
          online_since_tick: Some(st.tick_count),
          offline_since_tick: None,
        )
      // Start acting
      process.send(st2.self, Tick)
      actor.continue(st2)
    }

    GoOffline -> {
      // Leave all subreddits when going offline
      list.each(st.subs, fn(sub: SubId) {
        process.send(st.engine, LeaveSub(st.id, sub))
      })
      let st2 =
        ClientState(
          ..st,
          connected: False,
          online_since_tick: None,
          offline_since_tick: Some(st.tick_count),
          subs: [],
        )
      // Wait for offline_ms before going back online (handled in Tick)
      process.send(st2.self, Tick)
      actor.continue(st2)
    }

    EngineNotify(_n) -> {
      actor.continue(st)
    }

    EngineReply(_reply) -> {
      // Ignore engine replies for now
      actor.continue(st)
    }
  }
}

fn act_online(st: ClientState) -> ClientState {
  // Randomly choose an action: join, post, comment, vote, dm
  let rng_raw = st.rng * 1_103_515_245 + 12_345
  let rng2 = int.absolute_value(rng_raw) % 2_147_483_647
  let choice = rng2 % 100
  let st = ClientState(..st, rng: rng2)

  case choice < 10 {
    True -> {
      let n = list.length(st.cfg.sub_pool)
      let rank = sample(st.cfg.zipf_weights, rand01(st.rng))
      let idx = clamp(rank - 1, 0, n - 1)
      let sub = list_at(st.cfg.sub_pool, idx) |> result.unwrap("general")
      process.send(st.engine, JoinSub(st.id, sub))
      ClientState(..st, subs: list.unique([sub, ..st.subs]))
    }
    False ->
      case choice < 35 {
        True -> {
          case st.subs {
            [] -> st
            subs -> {
              let i = { st.rng % list.length(subs) } |> int.absolute_value
              let s = list_at(subs, i) |> result.unwrap("general")
              // Generate post body (simplified - no synchronous repost to avoid blocking)
              let body = random_post_body(st.rng)
              process.send(st.engine, SubmitPost(st.id, s, body))
              st
            }
          }
        }
        False ->
          case choice < 60 {
            True -> {
              let pid = PostId({ st.rng % 1000 } |> int.absolute_value)
              process.send(
                st.engine,
                SubmitComment(st.id, pid, None, "nice post"),
              )
              st
            }
            False ->
              case choice < 85 {
                True -> {
                  let pid = PostId({ st.rng % 1000 } |> int.absolute_value)
                  process.send(st.engine, UpvotePost(st.id, pid))
                  st
                }
                False -> {
                  let to =
                    UserId({ { st.rng % 5000 } |> int.absolute_value } + 1)
                  process.send(st.engine, SendDM(st.id, to, "hey!"))
                  st
                }
              }
          }
      }
  }
}

fn rand01(seed: Int) -> Float {
  { int.to_float(int.absolute_value(seed) % 65_535) /. 65_535.0 }
}

fn clamp(x: Int, lo: Int, hi: Int) -> Int {
  case x < lo {
    True -> lo
    False -> {
      case x > hi {
        True -> hi
        False -> x
      }
    }
  }
}

fn random_post_body(r: Int) -> String {
  "post-" <> int.to_string(int.absolute_value(r) % 65_535)
}

// ============================
// Simulator + Main
// ============================

pub fn sim_run(n_users: Int, n_subs: Int, seconds: Int) -> Nil {
  let eng = engine_start()

  // create subs
  let names =
    list.range(1, n_subs) |> list.map(fn(i) { "r/" <> int.to_string(i) })
  list.each(names, fn(n) {
    let r = process.new_subject()
    process.send(eng, CreateSub(n, r))
    let _ = process.receive(r, 5000)
  })

  // Zipf weights
  let weights = pmf(n_subs, 1.07)

  // spawn users
  let cfg =
    ClientCfg(
      connect_ms: 100,
      online_ms: 500,
      offline_ms: 300,
      sub_pool: names,
      zipf_weights: weights,
    )
  let _clients =
    list.range(1, n_users)
    |> list.map(fn(_i) { client_start(eng, cfg) })
    |> list.each(fn(c) { process.send(c, Start) })

  // run for duration
  sleep_ms(seconds * 1000)

  // Give the engine time to finish processing pending messages
  io.println("\nWaiting for engine to process remaining messages...")
  sleep_ms(2000)

  // Collect and print stats
  io.println("Collecting statistics...")
  let stats_subject = process.new_subject()
  process.send(eng, Snapshot(stats_subject))
  case process.receive(stats_subject, 15_000) {
    Ok(stats) -> {
      io.println("Stats received from engine")
      print_stats(stats, n_users, n_subs, seconds)
    }
    Error(_) -> {
      io.println("ERROR: Failed to receive stats from engine (timeout)")
    }
  }
}

fn sleep_ms(ms: Int) {
  process.sleep(ms)
}

fn find_stat(stats_list: List(#(String, Int)), key: String) -> Int {
  case list.find(stats_list, fn(pair) { pair.0 == key }) {
    Ok(pair) -> pair.1
    Error(_) -> 0
  }
}

fn print_stats(
  stats: dict.Dict(String, Int),
  n_users: Int,
  n_subs: Int,
  seconds: Int,
) -> Nil {
  let stats_list = dict.to_list(stats)
  let posts = find_stat(stats_list, "posts")
  let comments = find_stat(stats_list, "comments")
  let votes = find_stat(stats_list, "votes")
  let dms = find_stat(stats_list, "dms")
  let joins = find_stat(stats_list, "joins")
  let leaves = find_stat(stats_list, "leaves")
  let total = posts + comments + votes + dms + joins + leaves

  io.println("")
  io.println("=== Reddit Simulator Results ===")
  io.println("Configuration:")
  io.println("  Users: " <> int.to_string(n_users))
  io.println("  Subreddits: " <> int.to_string(n_subs))
  io.println("  Duration: " <> int.to_string(seconds) <> " seconds")
  io.println("")
  io.println("Activity:")
  io.println("  Posts: " <> int.to_string(posts))
  io.println("  Comments: " <> int.to_string(comments))
  io.println("  Votes: " <> int.to_string(votes))
  io.println("  Direct Messages: " <> int.to_string(dms))
  io.println("  Subreddit Joins: " <> int.to_string(joins))
  io.println("  Subreddit Leaves: " <> int.to_string(leaves))
  io.println("")
  io.println("Performance:")
  io.println("  Total Actions: " <> int.to_string(total))
  io.println("  Actions/sec: " <> int.to_string(total / seconds))
  io.println("================================")
  io.println("")
}

pub fn main() {
  io.println("Starting Reddit Simulator...")
  let n_users = 300
  let n_subs = 10
  let seconds = 30

  sim_run(n_users, n_subs, seconds)
  io.println("Simulation complete!")
}
