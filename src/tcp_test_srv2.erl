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
    c2/0
    ]).

start_link() ->
    Pid = spawn_link(?MODULE, init, []),
    {ok, Pid}.

start() ->
    init().

init() ->
    Opts = [binary, 
            {packet, 1},
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
            handle(CSock),
            ?MODULE:acceptor(LSock);
        {error, Reason} ->
            error_logger:info_msg("~p ~n", [Reason])
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

    case lists:keyfind(State, 1, Config) of
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
    gen_tcp:send(Sock, <<"Other">>).
    gen_tcp:close(Sock).
