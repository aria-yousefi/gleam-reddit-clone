-module(project_4_reddit_helper).
-export([system_time_millisecond/0]).

system_time_millisecond() ->
    erlang:system_time(millisecond).

