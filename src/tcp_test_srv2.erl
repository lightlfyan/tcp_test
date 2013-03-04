-module(tcp_test_srv2).
-author("lightlfyan").

% receive packet by state machine for sequence
% how to start
% tcp_test_srv2:init()  % server
% tcp_test_srv2:c1()    % normal client
% tcp_test_srv2:c2()    % wrong client

-export ([
    start_link/0,
    start/0,
    c1/0,
    c2/0,
    c3/0
    ]).

start_link() ->
    Pid = spawn_link(?MODULE, init, []),
    {ok, Pid}.

start() ->
    init().

init() ->
    Opts = [binary, 
            {packet, 0},
            {reuseaddr, true},
            {backlog, 1024},
            {buffer,20},    % byte
            {active, false}],
    case gen_tcp:listen(8081, Opts) of
        {ok, LSock} ->
            error_logger:info_msg("~p~n", ["listen ok"]),
            acceptor(LSock);
        {error, Reason} ->
            error_logger:info_msg("~p~n", [Reason])
    end,
    {ok, self()}.

acceptor(LSock) ->
    case gen_tcp:accept(LSock) of
        {ok, CSock} ->
            error_logger:info_msg("~p ~n", [inet:peername(CSock)]),
            echo(CSock),
            acceptor(LSock);
        {error, Reason} ->
            error_logger:info_msg("~p ~n", [Reason])
    end.

echo(CSock) ->
    error_logger:info_msg("echo~n"),
    gen_tcp:send(CSock, term_to_binary("pong")),
    case gen_tcp:recv(CSock, 0, 3000) of
        {ok, Bin} ->
            error_logger:info_msg("~p ~n", [Bin]),
            gen_tcp:send(CSock, term_to_binary("pong")),
            echo(CSock);
        Other ->
            error_logger:info_msg("~p ~n", [Other])
    end. 

handle3(CSock) ->
    gen_tcp:close(CSock).

handle2(CSock) ->
    gen_tcp:send(CSock, term_to_binary({10001,2,3,[7], "中文"})),
    gen_tcp:send(CSock, term_to_binary({1002,2,3,[7], 10000000000, "test"})),
    gen_tcp:send(CSock, term_to_binary({1,2,3,[7, 321], 22342342, "test"})),
    gen_tcp:send(CSock, term_to_binary({1003,2,3,[7, 98], ["test1", "test2"], "test"})),
    gen_tcp:send(CSock, term_to_binary({1004,2,3,[7], [123, 234], "test"})),
    case gen_tcp:recv(CSock, 0) of
        {ok, Bin} -> 
            gen_tcp:send(CSock, Bin),
            error_logger:info_msg("~p ~n", [Bin]),
            error_logger:info_msg("~p ~n", [binary_to_term(Bin)]),
            handle2(CSock);
        {error, closed} ->
            error_logger:info_msg("sock closed ~n")
    end.

handle(CSock) ->
    handle(CSock, p1).

handle(CSock, State) ->
    case gen_tcp:recv(CSock, 0) of
        {ok, Bin} ->
            {finded, NextState, F} = get_handler(State),
            case catch F(CSock, Bin) of
                gone ->
                    error_logger:info_msg("gone~n"),
                    gen_tcp:close(CSock);
                {error, Reason} ->
                    error_logger:info_msg("~p ~n", [Reason]),
                    get_tcp:close(CSock);
                ok ->
                    ?MODULE:handle(CSock, NextState)
            end;
        Other ->
            error_logger:info_msg("~p ~n", [Other])
    end.

% look clearly
% but code nextstate in call function is more efficiently
get_handler(State) ->
    Sequence = [
    {p1,    p2,     fun p1/2},
    {p2,    p3,     fun p2/2},
    {p3,    common, fun p3/2},
    {common,common, fun common/2}
    ],

    case lists:keyfind(State, 1, Sequence) of
        {State, NextState, F} -> {finded, NextState, F};
        fase -> {finded, common, common}
    end.

% call back for protocal
p1(Sock, <<"Ping1">>) ->
    error_logger:info_msg("ok ping1~n"),
    gen_tcp:send(Sock, <<"Pong2">>);
p1(Sock, _) ->
    badprotocol(Sock).

p2(Sock, <<"Ping2">>) ->
    error_logger:info_msg("ok ping2~n"),
    gen_tcp:send(Sock, <<"Pong2">>);
p2(Sock, _) ->
    badprotocol(Sock).

p3(Sock, <<"Ping3">>) ->
    error_logger:info_msg("ok ping3~n"),
    gen_tcp:send(Sock, <<"Pong3">>);
p3(Sock, _) ->
    badprotocol(Sock).

common(Sock, <<"HeartBeat ping">>) ->
    error_logger:info_msg("ok HeartBeat~n"),
    get_tcp:send(Sock, <<"HeartBeat pong">>);
common(_Sock, _Other) ->
    throw(gone).

badprotocol(Sock) ->
    error_logger:info_msg("badprotocol  ~n"),
    gen_tcp:send(Sock, <<"bad protocal">>),
    throw(gone).

% normal client
c1() ->
    {ok, Sock} = gen_tcp:connect("localhost", 8081, 
                                  [binary, 
                                  {packet, 1}]),

    gen_tcp:send(Sock, <<"Ping1">>),
    gen_tcp:send(Sock, <<"Ping2">>),
    gen_tcp:send(Sock, <<"Ping3">>),
    gen_tcp:send(Sock, <<"HeartBeat">>),
    gen_tcp:send(Sock, <<"HeartBeat">>),
    gen_tcp:send(Sock, <<"HeartBeat">>),
    gen_tcp:send(Sock, <<"Other">>),
    gen_tcp:close(Sock).
    
% wrong client protocal
c2() ->
    {ok, Sock} = gen_tcp:connect("localhost", 8081, 
                                  [binary, 
                                  {packet, 1}]),

    gen_tcp:send(Sock, <<"Ping1">>),
    gen_tcp:send(Sock, <<"Ping3">>),
    gen_tcp:send(Sock, <<"Ping2">>),
    gen_tcp:send(Sock, <<"HeartBeat">>),
    gen_tcp:send(Sock, <<"Other">>),
    gen_tcp:close(Sock).


c3() ->
    {ok, Sock} = gen_tcp:connect("localhost", 8081, 
                                  [binary,
                                  {active, false}, 
                                  {packet, 2}]),

    work(Sock, 0).
    % gen_tcp:close(Sock).

work(Sock, Count) when Count < 10 ->
    gen_tcp:send(Sock, term_to_binary({1,2,3})),
    prim_inet:async_recv(Sock, 0, -1),
    work(Sock, Count+1);

    % case gen_tcp:recv(Sock, 0) of
    %     {ok, Bin} -> 
    %         error_logger:info_msg("client receive ~p ~n", [binary_to_term(Bin)]),
    %         work(Sock, Count+1);
    %     Other -> 
    %         error_logger:info_msg("client receive ~p ~n", [Other]),
    %         work(Sock, Count+1)
    % end;
work(_, _) -> done.

