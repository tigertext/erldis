-module(erldis_pool_sup).

-export([
  start_link/1,
  start_link/2,
  stop/0,
  init/1,
  add_pid/2,
  get_pids/1,
  get_random_pid/1
]).

-define(SUPERVISOR_RESTART_FREQUENCY, 5000).

%%
%% @doc Starts a supervisor that manages pools of Redis connections.
%% 
%% ConnList is a list of {{Host, Port}, PoolSize} tuples.
%% PoolSize connections will be opened to each {Host, Port}.
%%
%% ConnList = [{{"localhost", 6379}, 5}, {{"localhost", 6380}, 5}].
%%
%% The above ConnList specifies 5 connections to localhost:6379 and 5 connections to
%% localhost:6380.
%%
start_link(ConnList) -> start_link(ConnList, true).


start_link(ConnList, ManageSupervisor) ->
  % Create an ETS table to hold the list of child PIDs
  catch ets:new(?MODULE, [public, named_table, bag]),
  
  % Ensure the table is cleared
  ets:delete_all_objects(?MODULE),
  
  % Start a supervisor to manage the connections
  {ok, Pid} = supervisor:start_link({local, ?MODULE}, ?MODULE, [ConnList]),
  
  case ManageSupervisor of
    true ->
      spawn(fun() ->
                    monitor_sup(ConnList, Pid)
            end),
      ok;
    _ -> ok
  end,
  
  {ok, Pid}.
  
stop() ->
    case whereis(?MODULE)  of
        undefined -> ok;
        Pid ->
            MonitorRef = erlang:monitor(process, Pid),
            exit(Pid, shutdown),
            receive 
                _ -> ok
            end,
            erlang:demonitor(MonitorRef)
    end.
    
restart_sup(ConnList) ->
    error_logger:error_msg("restarting erldis_pool_sup supervisor in ~p ms~n", [?SUPERVISOR_RESTART_FREQUENCY]),
    timer:sleep(?SUPERVISOR_RESTART_FREQUENCY),
    process_flag(trap_exit, true),
    case catch start_link(ConnList) of
        {ok, Pid} ->
            error_logger:info_msg("erldis_pool_sup restarted successfully~n", []),
            unlink(Pid),
            ok;
        Reason ->
            error_logger:error_msg("Unable to restart erldis_pool_sup: ~p~n", [Reason]),
            restart_sup(ConnList)
    end.

monitor_do(MonitorRef, ConnList, Pid) ->
    receive
        {'DOWN', _Ref, process, Pid, _Reason} ->
            restart_sup(ConnList),
            erlang:demonitor(MonitorRef);
        _ ->
            monitor_do(MonitorRef, ConnList, Pid)
    end.

monitor_sup(ConnList, Pid) ->
    MonitorRef = erlang:monitor(process, Pid),
    monitor_do(MonitorRef, ConnList, Pid).
    
%%
%% @doc Returns the supervisor specifications for the children.
%%
init([ConnList]) ->
  % Merge the connections so that duplicate host/port pairs are combined
  ConnDict = lists:foldl(fun({HostPort, PoolSize}, Dict) ->
    case dict:is_key(HostPort, Dict) of
      true ->
        % Get the current pool size and add to it, return the new dict
        {_, ExistingPoolSize} = dict:fetch(HostPort, Dict),
        dict:store(HostPort, {HostPort, ExistingPoolSize + PoolSize}, Dict);
      false ->
        dict:store(HostPort, {HostPort, PoolSize}, Dict)
    end
  end, dict:new(), ConnList),
  ConnListMerged = lists:map(fun({_K, V}) -> V end, dict:to_list(ConnDict)),
  
  ChildSpecs = lists:flatten(lists:map(fun({{Host, Port}, PoolSize}) ->
    lists:map(fun(X) -> 
      {Host ++ "_" ++ integer_to_list(Port) ++ "_" ++ integer_to_list(X),
        {erldis_client, start_link, [Host, Port]},
        transient, 2000, worker, [?MODULE]}
    end, lists:seq(1, PoolSize))
  end, ConnListMerged)),
  {ok, {{one_for_one, 20, 5}, ChildSpecs}}.

%%
%% @doc Adds a Redis connection {Host, Port} pair and Pid into ETS.
%%
add_pid({Host, Port}, Pid) ->
  case whereis(?MODULE) of
    undefined -> ok;
    _ -> ets:insert(?MODULE, {{Host, Port}, Pid})
  end.

%%
%% @doc Returns a list of Pids for the given {Host, Port} pair.
%%
get_pids({Host, Port}) ->
  lists:map(fun({_K, V}) -> V end, ets:lookup(?MODULE, {Host, Port})).
  
%%
%% @doc Returns a random Pid in the pool for a given {Host, Port} pair.
%%
get_random_pid({Host, Port}) ->
  Pids = get_pids({Host, Port}),
  lists:nth(erlang:phash(now(), length(Pids)), Pids).