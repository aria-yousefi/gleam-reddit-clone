import argv
import gleam/bit_array
import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import mist
import project_4_reddit.{
  type Comment, type CommentId, type DM, type DMId, type EngineMsg,
  type EngineReply, type FeedItem, type Post, type PostId, type SubId,
  type UserId, CommentId, CreateSub, DMId, DMs, DownvoteComment, DownvotePost,
  Fail, Feed, FeedComment, FeedPost, GetDMs, GetFeed, JoinSub, LeaveSub, PostId,
  Register, Registered, SendDM, SubCreated, SubmitComment, SubmitPost,
  UpvoteComment, UpvotePost, UserId, engine_start,
}

// JSON encoding/decoding helpers

fn user_id_to_json(id: UserId) -> json.Json {
  case id {
    UserId(n) -> json.int(n)
  }
}

fn user_id_from_json(j: json.Json) -> Result(UserId, String) {
  let json_str = json.to_string(j)
  case json.parse(json_str, decode.int) {
    Ok(n) -> Ok(UserId(n))
    Error(_) -> Error("Invalid user ID")
  }
}

fn post_id_to_json(id: PostId) -> json.Json {
  case id {
    PostId(n) -> json.int(n)
  }
}

fn post_id_from_json(j: json.Json) -> Result(PostId, String) {
  let json_str = json.to_string(j)
  case json.parse(json_str, decode.int) {
    Ok(n) -> Ok(PostId(n))
    Error(_) -> Error("Invalid post ID")
  }
}

fn comment_id_to_json(id: CommentId) -> json.Json {
  case id {
    CommentId(n) -> json.int(n)
  }
}

fn comment_id_from_json(j: json.Json) -> Result(CommentId, String) {
  let json_str = json.to_string(j)
  case json.parse(json_str, decode.int) {
    Ok(n) -> Ok(CommentId(n))
    Error(_) -> Error("Invalid comment ID")
  }
}

fn karma_to_json(k: project_4_reddit.Karma) -> json.Json {
  json.object([
    #("ups", json.int(k.ups)),
    #("downs", json.int(k.downs)),
  ])
}

fn post_to_json(p: Post) -> json.Json {
  json.object([
    #("id", post_id_to_json(p.id)),
    #("author", user_id_to_json(p.author)),
    #("sub", json.string(p.sub)),
    #("body", json.string(p.body)),
    #("karma", karma_to_json(p.karma)),
    #("ts_ms", json.int(p.ts_ms)),
  ])
}

fn comment_to_json(c: Comment) -> json.Json {
  let parent_json = case c.parent {
    None -> json.null()
    Some(id) -> comment_id_to_json(id)
  }
  json.object([
    #("id", comment_id_to_json(c.id)),
    #("author", user_id_to_json(c.author)),
    #("post", post_id_to_json(c.post)),
    #("parent", parent_json),
    #("body", json.string(c.body)),
    #("karma", karma_to_json(c.karma)),
    #("ts_ms", json.int(c.ts_ms)),
  ])
}

fn dm_to_json(d: DM) -> json.Json {
  let id_int = case d.id {
    DMId(n) -> n
  }
  json.object([
    #("id", json.int(id_int)),
    #("from", user_id_to_json(d.from)),
    #("to", user_id_to_json(d.to)),
    #("body", json.string(d.body)),
    #("ts_ms", json.int(d.ts_ms)),
  ])
}

fn feed_item_to_json(item: FeedItem) -> json.Json {
  case item {
    FeedPost(post) -> {
      json.object([
        #("type", json.string("post")),
        #("post", post_to_json(post)),
      ])
    }
    FeedComment(comment, post_id) -> {
      json.object([
        #("type", json.string("comment")),
        #("comment", comment_to_json(comment)),
        #("post_id", post_id_to_json(post_id)),
      ])
    }
  }
}

// Helper to call engine and wait for reply
fn call_engine(
  engine: process.Subject(EngineMsg),
  msg_fn: fn(process.Subject(EngineReply)) -> EngineMsg,
) -> Result(EngineReply, String) {
  let reply_subject = process.new_subject()
  let msg = msg_fn(reply_subject)
  process.send(engine, msg)
  case process.receive(reply_subject, 5000) {
    Ok(reply) -> Ok(reply)
    Error(_) -> Error("Timeout waiting for engine reply")
  }
}

// Helper to send message to engine without waiting
fn send_engine(engine: process.Subject(EngineMsg), msg: EngineMsg) -> Nil {
  process.send(engine, msg)
  Nil
}

// Helper to parse query parameter
fn get_query_param(
  req: request.Request(BitArray),
  key: String,
) -> Option(String) {
  case request.get_query(req) {
    Ok(params) -> {
      case list.find(params, fn(pair) { pair.0 == key }) {
        Ok(#(_, value)) -> Some(value)
        Error(_) -> None
      }
    }
    Error(_) -> None
  }
}

// Helper to read body as string
fn body_to_string(body: mist.Connection) -> Result(String, String) {
  // For now, we'll need to read the body differently
  // This is a simplified version - in production you'd use mist.read_body
  Error("Body reading not implemented in this simplified version")
}

// Request handlers - simplified versions that work with the current setup
// Note: These need to be adapted to work with mist's body reading

fn json_response(
  status: Int,
  json_body: json.Json,
) -> response.Response(mist.ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string(json.to_string(json_body))),
  )
}

fn error_response(
  status: Int,
  message: String,
) -> response.Response(mist.ResponseData) {
  response.new(status)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(message)))
}

// Helper to decode JSON object field
fn get_json_field(
  obj: decode.Dynamic,
  field: String,
  decoder: decode.Decoder(a),
) -> Result(a, String) {
  let field_decoder = decode.field(field, decoder, decode.success)
  decode.run(obj, field_decoder)
  |> result.map_error(fn(_) { "Missing or invalid field: " <> field })
}

// Router - works with Request(BitArray) after read_request_body
pub fn route(
  engine: process.Subject(EngineMsg),
  req: request.Request(BitArray),
) -> response.Response(mist.ResponseData) {
  let method = req.method
  let path = request.path_segments(req)
  let body = req.body
  let body_str = case bit_array.to_string(body) {
    Ok(s) -> s
    Error(_) -> ""
  }

  case method, path {
    // Health check
    Get, ["api", "v1", "health"] -> {
      json_response(200, json.object([#("status", json.string("ok"))]))
    }

    // Register user
    Post, ["api", "v1", "register"] -> {
      case call_engine(engine, fn(reply) { Register(reply) }) {
        Ok(Registered(user_id)) -> {
          json_response(
            201,
            json.object([#("user_id", user_id_to_json(user_id))]),
          )
        }
        Ok(_) -> error_response(500, "Unexpected reply")
        Error(err) -> error_response(500, "Error: " <> err)
      }
    }

    // Create subreddit
    Post, ["api", "v1", "subreddits"] -> {
      case json.parse(body_str, decode.dynamic) {
        Ok(dynamic) -> {
          case get_json_field(dynamic, "name", decode.string) {
            Ok(name) -> {
              case call_engine(engine, fn(reply) { CreateSub(name, reply) }) {
                Ok(SubCreated(_)) -> {
                  json_response(
                    201,
                    json.object([
                      #("name", json.string(name)),
                      #("status", json.string("created")),
                    ]),
                  )
                }
                Ok(Fail(reason)) -> error_response(400, "Error: " <> reason)
                Ok(_) -> error_response(500, "Unexpected reply")
                Error(err) -> error_response(500, "Error: " <> err)
              }
            }
            Error(err) -> error_response(400, "Invalid request: " <> err)
          }
        }
        Error(_) -> error_response(400, "Invalid JSON")
      }
    }

    // Join subreddit
    Post, ["api", "v1", "subreddits", name, "join"] -> {
      case json.parse(body_str, decode.dynamic) {
        Ok(dynamic) -> {
          case get_json_field(dynamic, "user_id", decode.int) {
            Ok(user_id_int) -> {
              let user_id = UserId(user_id_int)
              send_engine(engine, JoinSub(user_id, name))
              json_response(
                200,
                json.object([
                  #("status", json.string("joined")),
                  #("subreddit", json.string(name)),
                  #("user_id", user_id_to_json(user_id)),
                ]),
              )
            }
            Error(err) -> error_response(400, "Invalid request: " <> err)
          }
        }
        Error(_) -> error_response(400, "Invalid JSON")
      }
    }

    // Leave subreddit
    Post, ["api", "v1", "subreddits", name, "leave"] -> {
      case json.parse(body_str, decode.dynamic) {
        Ok(dynamic) -> {
          case get_json_field(dynamic, "user_id", decode.int) {
            Ok(user_id_int) -> {
              let user_id = UserId(user_id_int)
              send_engine(engine, LeaveSub(user_id, name))
              json_response(
                200,
                json.object([
                  #("status", json.string("left")),
                  #("subreddit", json.string(name)),
                  #("user_id", user_id_to_json(user_id)),
                ]),
              )
            }
            Error(err) -> error_response(400, "Invalid request: " <> err)
          }
        }
        Error(_) -> error_response(400, "Invalid JSON")
      }
    }

    // Submit post
    Post, ["api", "v1", "posts"] -> {
      case json.parse(body_str, decode.dynamic) {
        Ok(dynamic) -> {
          case get_json_field(dynamic, "author", decode.int) {
            Ok(author_int) -> {
              case get_json_field(dynamic, "sub", decode.string) {
                Ok(sub) -> {
                  case get_json_field(dynamic, "body", decode.string) {
                    Ok(body_text) -> {
                      let author = UserId(author_int)
                      send_engine(engine, SubmitPost(author, sub, body_text))
                      json_response(
                        201,
                        json.object([
                          #("status", json.string("submitted")),
                          #("author", user_id_to_json(author)),
                          #("sub", json.string(sub)),
                        ]),
                      )
                    }
                    Error(err) ->
                      error_response(400, "Invalid request: " <> err)
                  }
                }
                Error(err) -> error_response(400, "Invalid request: " <> err)
              }
            }
            Error(err) -> error_response(400, "Invalid request: " <> err)
          }
        }
        Error(_) -> error_response(400, "Invalid JSON")
      }
    }

    // Submit comment
    Post, ["api", "v1", "comments"] -> {
      case json.parse(body_str, decode.dynamic) {
        Ok(dynamic) -> {
          case get_json_field(dynamic, "author", decode.int) {
            Ok(author_int) -> {
              case get_json_field(dynamic, "post", decode.int) {
                Ok(post_int) -> {
                  case get_json_field(dynamic, "body", decode.string) {
                    Ok(body_text) -> {
                      let author = UserId(author_int)
                      let post = PostId(post_int)
                      let parent = case
                        get_json_field(dynamic, "parent", decode.int)
                      {
                        Ok(parent_int) -> Some(CommentId(parent_int))
                        Error(_) -> None
                      }
                      send_engine(
                        engine,
                        SubmitComment(author, post, parent, body_text),
                      )
                      json_response(
                        201,
                        json.object([
                          #("status", json.string("submitted")),
                          #("author", user_id_to_json(author)),
                          #("post", post_id_to_json(post)),
                        ]),
                      )
                    }
                    Error(err) ->
                      error_response(400, "Invalid request: " <> err)
                  }
                }
                Error(err) -> error_response(400, "Invalid request: " <> err)
              }
            }
            Error(err) -> error_response(400, "Invalid request: " <> err)
          }
        }
        Error(_) -> error_response(400, "Invalid JSON")
      }
    }

    // Upvote post
    Post, ["api", "v1", "posts", post_id_str, "upvote"] -> {
      case int.parse(post_id_str) {
        Ok(post_id_int) -> {
          let post_id = PostId(post_id_int)
          case json.parse(body_str, decode.dynamic) {
            Ok(dynamic) -> {
              case get_json_field(dynamic, "user_id", decode.int) {
                Ok(user_id_int) -> {
                  let user_id = UserId(user_id_int)
                  send_engine(engine, UpvotePost(user_id, post_id))
                  json_response(
                    200,
                    json.object([
                      #("status", json.string("upvoted")),
                      #("post_id", post_id_to_json(post_id)),
                      #("user_id", user_id_to_json(user_id)),
                    ]),
                  )
                }
                Error(err) -> error_response(400, "Invalid request: " <> err)
              }
            }
            Error(_) -> error_response(400, "Invalid JSON")
          }
        }
        Error(_) -> error_response(400, "Invalid post_id")
      }
    }

    // Downvote post
    Post, ["api", "v1", "posts", post_id_str, "downvote"] -> {
      case int.parse(post_id_str) {
        Ok(post_id_int) -> {
          let post_id = PostId(post_id_int)
          case json.parse(body_str, decode.dynamic) {
            Ok(dynamic) -> {
              case get_json_field(dynamic, "user_id", decode.int) {
                Ok(user_id_int) -> {
                  let user_id = UserId(user_id_int)
                  send_engine(engine, DownvotePost(user_id, post_id))
                  json_response(
                    200,
                    json.object([
                      #("status", json.string("downvoted")),
                      #("post_id", post_id_to_json(post_id)),
                      #("user_id", user_id_to_json(user_id)),
                    ]),
                  )
                }
                Error(err) -> error_response(400, "Invalid request: " <> err)
              }
            }
            Error(_) -> error_response(400, "Invalid JSON")
          }
        }
        Error(_) -> error_response(400, "Invalid post_id")
      }
    }

    // Upvote comment
    Post, ["api", "v1", "comments", comment_id_str, "upvote"] -> {
      case int.parse(comment_id_str) {
        Ok(comment_id_int) -> {
          let comment_id = CommentId(comment_id_int)
          case json.parse(body_str, decode.dynamic) {
            Ok(dynamic) -> {
              case get_json_field(dynamic, "user_id", decode.int) {
                Ok(user_id_int) -> {
                  let user_id = UserId(user_id_int)
                  send_engine(engine, UpvoteComment(user_id, comment_id))
                  json_response(
                    200,
                    json.object([
                      #("status", json.string("upvoted")),
                      #("comment_id", comment_id_to_json(comment_id)),
                      #("user_id", user_id_to_json(user_id)),
                    ]),
                  )
                }
                Error(err) -> error_response(400, "Invalid request: " <> err)
              }
            }
            Error(_) -> error_response(400, "Invalid JSON")
          }
        }
        Error(_) -> error_response(400, "Invalid comment_id")
      }
    }

    // Downvote comment
    Post, ["api", "v1", "comments", comment_id_str, "downvote"] -> {
      case int.parse(comment_id_str) {
        Ok(comment_id_int) -> {
          let comment_id = CommentId(comment_id_int)
          case json.parse(body_str, decode.dynamic) {
            Ok(dynamic) -> {
              case get_json_field(dynamic, "user_id", decode.int) {
                Ok(user_id_int) -> {
                  let user_id = UserId(user_id_int)
                  send_engine(engine, DownvoteComment(user_id, comment_id))
                  json_response(
                    200,
                    json.object([
                      #("status", json.string("downvoted")),
                      #("comment_id", comment_id_to_json(comment_id)),
                      #("user_id", user_id_to_json(user_id)),
                    ]),
                  )
                }
                Error(err) -> error_response(400, "Invalid request: " <> err)
              }
            }
            Error(_) -> error_response(400, "Invalid JSON")
          }
        }
        Error(_) -> error_response(400, "Invalid comment_id")
      }
    }

    // Get feed
    Get, ["api", "v1", "users", user_id_str, "feed"] -> {
      case int.parse(user_id_str) {
        Ok(user_id_int) -> {
          let user_id = UserId(user_id_int)
          let limit = case get_query_param(req, "limit") {
            Some(limit_str) -> int.parse(limit_str) |> result.unwrap(10)
            None -> 10
          }
          case
            call_engine(engine, fn(reply) { GetFeed(user_id, limit, reply) })
          {
            Ok(Feed(items)) -> {
              let items_json = list.map(items, feed_item_to_json)
              json_response(
                200,
                json.object([
                  #("user_id", user_id_to_json(user_id)),
                  #("limit", json.int(limit)),
                  #("items", json.array(items_json, fn(x) { x })),
                ]),
              )
            }
            Ok(_) -> error_response(500, "Unexpected reply")
            Error(err) -> error_response(500, "Error: " <> err)
          }
        }
        Error(_) -> error_response(400, "Invalid user_id")
      }
    }

    // Send DM
    Post, ["api", "v1", "messages"] -> {
      case json.parse(body_str, decode.dynamic) {
        Ok(dynamic) -> {
          case get_json_field(dynamic, "from", decode.int) {
            Ok(from_int) -> {
              case get_json_field(dynamic, "to", decode.int) {
                Ok(to_int) -> {
                  case get_json_field(dynamic, "body", decode.string) {
                    Ok(body_text) -> {
                      let from = UserId(from_int)
                      let to = UserId(to_int)
                      send_engine(engine, SendDM(from, to, body_text))
                      json_response(
                        201,
                        json.object([
                          #("status", json.string("sent")),
                          #("from", user_id_to_json(from)),
                          #("to", user_id_to_json(to)),
                        ]),
                      )
                    }
                    Error(err) ->
                      error_response(400, "Invalid request: " <> err)
                  }
                }
                Error(err) -> error_response(400, "Invalid request: " <> err)
              }
            }
            Error(err) -> error_response(400, "Invalid request: " <> err)
          }
        }
        Error(_) -> error_response(400, "Invalid JSON")
      }
    }

    // Get DMs
    Get, ["api", "v1", "users", user_id_str, "messages"] -> {
      case int.parse(user_id_str) {
        Ok(user_id_int) -> {
          let user_id = UserId(user_id_int)
          case call_engine(engine, fn(reply) { GetDMs(user_id, reply) }) {
            Ok(DMs(dms)) -> {
              let dms_json = list.map(dms, dm_to_json)
              json_response(
                200,
                json.object([
                  #("user_id", user_id_to_json(user_id)),
                  #("messages", json.array(dms_json, fn(x) { x })),
                ]),
              )
            }
            Ok(_) -> error_response(500, "Unexpected reply")
            Error(err) -> error_response(500, "Error: " <> err)
          }
        }
        Error(_) -> error_response(400, "Invalid user_id")
      }
    }

    // 404 for unknown routes
    _, _ -> {
      error_response(404, "Not found")
    }
  }
}

// Start the API server
pub fn start_server(port: Int) -> Nil {
  io.println(
    "Starting Reddit API server on port " <> int.to_string(port) <> "...",
  )
  let engine = engine_start()
  let handler = fn(req) { route(engine, req) }

  // Create mist builder with body reading
  let builder =
    mist.new(handler)
    |> mist.port(port)
    |> mist.read_request_body(
      bytes_limit: 1_000_000,
      failure_response: error_response(400, "Body too large"),
    )

  case mist.start(builder) {
    Ok(_) -> {
      io.println(
        "Server started successfully on port " <> int.to_string(port) <> "!",
      )
      process.sleep_forever()
    }
    Error(_) -> {
      io.println("Failed to start server")
    }
  }
}

pub fn main() {
  let args = argv.load()
  let port = case args.arguments {
    ["server", port_str, ..] -> {
      case int.parse(port_str) {
        Ok(p) -> p
        Error(_) -> 8080
      }
    }
    _ -> 8080
  }
  start_server(port)
}
