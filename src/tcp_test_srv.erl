-module(tcp_test_srv).
-author("lightlfyan").

-compile(export_all).

% -export ([
%     start_link/0,
%     start2/1,
%     bot/1,
%     server/0,
%     c1/0
%     ]). 

% rebar compile
% erl -pa ./ebin -boot start_sasl
% appmon:start().
% application:start(tcp_test).
% tcp_test_srv:bot(100).

% tcp_test_srv:server().
% tcp_test-srv:c1().


start_link() ->
    proc_lib:start_link(?MODULE, start2, [self()]).

bot(Num) ->
    [spawn(fun client/0) || _ <- lists:seq(1, Num) ].

start() ->
    Opts = [binary, 
            {packet, 1},
            {reuseaddr, true},
            {backlog, 1024},
            {buffer,20},    % byte
            {active, false}],
    % timer:apply_after(1000, ?MODULE, client, []),
    case gen_tcp:listen(8081, Opts) of
        {ok, LSock} ->
            error_logger:info_msg("~p~n", ["listen ok"]),
            acceptor_loop(LSock);
        {error, Reason} ->
            error_logger:info_msg("~p~n", [Reason])
    end,
    {ok, self()}.

start2(Parent) ->
    register(listener, self()),
    process_flag(trap_exit, true),
    Opts = [
        binary,
        {packet, 0},
        {reuseaddr, true},
        {backlog, 1024},
        {buffer, 64},
        {active, false}
        ],
    case gen_tcp:listen(8081, Opts) of
        {ok, LSock} ->
            proc_lib:init_ack(Parent, {ok, self()}),
            error_logger:info_msg("~p~n", ["listen ok"]),
            acceptor_loop2(LSock),
            respawn_stuff(LSock);
        {error, Reason} ->
            error_logger:info_msg("start2 ~p~n", [Reason]),
            proc_lib:init_ack(Parent, Reason)
    end.

respawn_stuff(LSock) ->
    receive
        {'EXIT', _From, _Reason} ->
            spawn_link(?MODULE, worker2, [LSock]);
        Any -> 
            error_logger:info_msg("~p~n", [Any])
    end.

% only acceptor one connection
acceptor_loop(LSock) ->
    case gen_tcp:accept(LSock) of
        {ok, CSock} ->
            error_logger:info_msg("~p~n", ["accept ok"]),
            handle(CSock),
            acceptor_loop(LSock);
        {_, Reason} ->
            error_logger:info_msg("~p~n", [Reason])
    end.

% concurrent version
acceptor_loop2(LSock) ->
    % spawn_link(?MODULE, worker, [LSock, 10]).
    [spawn_link(?MODULE, worker2, [LSock]) || _ <- lists:seq(1,5)].

worker(LSock) ->
    case gen_tcp:accept(LSock) of
        {ok, CSock} ->
            Pid = spawn_link(?MODULE, handle, [CSock]),
            gen_tcp:controlling_process(CSock, Pid),
            worker(LSock);
        {error, Reason} ->
            error_logger:info_msg("in worker ~p~n", [Reason])
    end.


worker2(LSock) ->
    WorkerPid = self(),
    erlang:spawn(
        fun() ->
            case gen_tcp:accept(LSock) of
                {ok, CSock} ->
                    gen_tcp:controlling_process(CSock, WorkerPid),
                    WorkerPid ! {WorkerPid, CSock};
                {error, Reason} ->
                    WorkerPid ! {WorkerPid, error, Reason}
            end
        end
        ),
    receive
        {WorkerPid, CSock} ->
            CPid = spawn_link(?MODULE, goto_handle, [CSock]),
            gen_tcp:controlling_process(CSock, CPid),
            worker2(LSock);
        {WorkerPid, error, Reason} ->
            error_logger:info_msg("in worker2 ~p~n", [Reason])
    end.

goto_handle(CSock) ->
    % atom can't gc
    Name = list_to_atom("handler_" ++ pid_to_list(self())),
    register(Name, self()),
    handle(CSock).

handle(CSock) ->
    handle(CSock, 0, []).

handle(CSock, 0, <<NLen:16, Bin/binary>>) ->
    error_logger:info_msg("Title len: ~p~n bin len: ~p~n", [NLen, bit_size(Bin)]),
    % error_logger:info_msg("bin: ~p~n", [Bin]),
    if 
        bit_size(Bin) > NLen ->
            <<Data:NLen/binary, Rest/binary>> = Bin,
            error_logger:info_msg("complete pacake: ~p ~n", [Data]),
            gen_tcp:send(CSock, <<"end">>),
            handle(CSock, 0, Rest);
        bit_size(Bin) == NLen ->
            error_logger:info_msg("complete pacake: ~p ~n", [Bin]),
            gen_tcp:send(CSock, <<"end">>),
            handle(CSock);
        true ->
            RestLen = NLen - bit_size(Bin),
            error_logger:info_msg("need reset len: ~p~n", [RestLen]),
            handle(CSock, RestLen, Bin)
    end;
handle(CSock, SLen, Data) ->
    error_logger:info_msg("~p handle recving"),
    inet:setopts(CSock, [{active, once}]),
    receive
        {tcp, CSock, Bin} when SLen > 0 ->
            error_logger:info_msg("need: ~p~n bin len: ~p~n", [SLen, bit_size(Bin)]),
            inet:setopts(CSock, [{active, once}]),
            BSize = bit_size(Bin),
            if
                BSize > SLen ->
                    <<_Need:SLen/binary, Rest/binary>> = Bin,
                    % error_logger:info_msg("complete packet: ~p ~n", [[Data, Need]]),
                    error_logger:info_msg("end"),
                    gen_tcp:send(CSock, <<"end">>),
                    handle(CSock, 0, Rest);
                BSize == SLen ->
                    % error_logger:info_msg("complete packet: ~p ~n", [[Data, Bin]]),
                    error_logger:info_msg("end"),
                    gen_tcp:send(CSock, <<"end">>),
                    handle(CSock);
                true ->
                    RestLen = SLen - BSize,
                    handle(CSock, RestLen, list_to_binary([Data, Bin]))
            end;
        {tcp, CSock, Bin} ->
            error_logger:info_msg("receive bin: ~p~n", [Bin]),
            inet:setopts(CSock, [{active, once}]),
            handle(CSock, 0, Bin);
            % ok;
        Other ->
            inet:setopts(CSock, [{active, once}]),
            error_logger:info_msg("receive other: ~p~n", [Other]),
            gen_tcp:send(CSock, Other),
            handle(CSock)
    end.


client() ->
    Opts = [
        binary,
        {packet, 0},
        {delay_send, true}
        ],
    {ok, Sock} = gen_tcp:connect("localhost", 8081, Opts),
    c_loop(Sock, 0).
    % inet:setopts(Sock, [{delay_send, true}]),

c_loop(Sock, Counter) when Counter < 100 ->
    Msg = << <<I>> || I <- lists:seq(1, 100) >>,
    Len = bit_size(Msg),
    error_logger:info_msg("len ~p", [Len]),
    ok = gen_tcp:send(Sock, <<Len:16>>),
    ok = gen_tcp:send(Sock, Msg),
    receive
    after 3000 ->
        c_loop(Sock, Counter+1)
    end;
c_loop(Sock, _) -> 
    gen_tcp:close(Sock).



%% =======================================================================
%% big package test
%% =======================================================================

server() ->
    {ok, LSock} = gen_tcp:listen(8082, [binary, {packet, 0},
                                        {active, false}]),
    {ok, Sock} = gen_tcp:accept(LSock),
    % {ok, Bin} = do_recv(Sock),
    do_recv(Sock),
    ok = gen_tcp:close(Sock),
    ok.
    % Bin.

do_recv(Sock) ->
    case gen_tcp:recv(Sock, 0) of
        {ok, B} ->
            error_logger:info_msg("~p ~n", [B]),
            do_recv(Sock);
        {error, closed} ->
            ok
    end.

do_recv(Sock, Bs) ->
    case gen_tcp:recv(Sock, 0) of
        {ok, B} ->
            error_logger:info_msg("~p ~n", [B]),
            do_recv(Sock, [Bs, B]);
        {error, closed} ->
            ok
            % {ok, list_to_binary(Bs)}
    end.

c1() ->
    {ok, Sock} = gen_tcp:connect("localhost", 8082, 
                                  [binary, 
                                  {packet, 0},
                                  {linger, true}]),
    {ok, P} = file:open("bigfile", [read]),
    mkmsg(P, Sock),
    file:close(P).

mkmsg(P, Sock) ->
    case file:read_line(P) of
        {ok, Content} ->
            gen_tcp:send(Sock, Content),
            mkmsg(P, Sock);
        eof ->
            % gen_tcp:cloe(Sock),
            ok
    end.


    % ok = gen_tcp:send(Sock, list_to_binary(lists:seq(1, 200))),
    % ok = gen_tcp:close(Sock).

% mkmsg(Sock) ->
%     _P = erlang:open_port("bigfile", [stream,line, in,eof]),
%     receive
%         {_, {data, {eol, Msg}}} ->
%             gen_tcp:send(Sock, Msg);
%         {_, eof} ->
%             mkmsg(Sock)
%     end.

