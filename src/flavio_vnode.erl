-module(flavio_vnode).
-behaviour(riak_core_vnode).
-include("flavio.hrl").

-export([start_vnode/1,
         init/1,
         terminate/2,
         handle_command/3,
         is_empty/1,
         delete/1,
         handle_handoff_command/3,
         handoff_starting/2,
         handoff_cancelled/1,
         handoff_finished/2,
         handle_handoff_data/2,
         encode_handoff_item/2,
         handle_coverage/4,
         handle_exit/3]).

-ignore_xref([
             start_vnode/1
             ]).

-record(state, {partition, ops_count=0, base_dir}).

%% API
start_vnode(I) ->
    riak_core_vnode_master:get_vnode_pid(I, ?MODULE).

init([Partition]) ->
    {ok, #state { partition=Partition, base_dir="flavio_data" }}.

%% Sample command: respond to a ping
handle_command(ping, _Sender, State) ->
    {reply, {pong, State#state.partition}, State};

handle_command({RefId, {add, {A, B}}}, _Sender, State=#state{ops_count=CurrentCount}) ->
    NewCount = CurrentCount + 1,
    NewState = State#state{ops_count=NewCount},
    {reply, {RefId, {A + B, State#state.partition}}, NewState};

handle_command({RefId, {post_msg, {Username, Stream, Msg}}}, _Sender,
               State=#state{partition=Partition, base_dir=BaseDir}) ->
    PartitionStr = integer_to_list(Partition),
    StreamPath = filename:join([BaseDir, PartitionStr, Username, Stream, "msgs"]),
    ok = filelib:ensure_dir(StreamPath),
    {ok, StreamIo} = fixsttio:open(StreamPath),
    Entry = fixstt:new(Msg),
    {ok, _NewStream, EntryId} = fixsttio:append(StreamIo, Entry),
    EntryWithId = fixstt:set(Entry, id, EntryId),
    {reply, {RefId, {EntryWithId, State#state.partition}}, State};

handle_command(Message, _Sender, State) ->
    ?PRINT({unhandled_command, Message}),
    {noreply, State}.

handle_handoff_command(_Message, _Sender, State) ->
    {noreply, State}.

handoff_starting(_TargetNode, State) ->
    {true, State}.

handoff_cancelled(State) ->
    {ok, State}.

handoff_finished(_TargetNode, State) ->
    {ok, State}.

handle_handoff_data(_Data, State) ->
    {reply, ok, State}.

encode_handoff_item(_ObjectName, _ObjectValue) ->
    <<>>.

is_empty(State) ->
    {true, State}.

delete(State) ->
    {ok, State}.

handle_coverage(stats, _KeySpaces, {_, RefId, _}, State=#state{ops_count=OpsCount}) ->
    {reply, {RefId, [{ops_count, OpsCount}]}, State};
handle_coverage(Req, _KeySpaces, _Sender, State) ->
    lager:warning("unknown coverage received ~p", [Req]),
    {norepl, State}.

handle_exit(_Pid, _Reason, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
