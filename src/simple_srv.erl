-module(simple_srv).
-compile(export_all).

server() ->
    {ok, LSock} = gen_tcp:listen(5678, [binary, {packet, 0}, 
                                        {active, false}]),
    do_accept(LSock).

do_accept(LSock) ->
    {ok, Sock} = gen_tcp:accept(LSock),
    spawn(?MODULE, sender2, [Sock]),
    do_accept(LSock).
    % sender(Sock),
    % recver(Sock),
    % ok = gen_tcp:close(Sock).

sender2(Sock) ->
    receive
    after 3000 ->
        B = crypto:rand_bytes(4),
        gen_tcp:send(Sock, B),
        sender2(Sock)
    end.

sender(Sock) ->
    lists:map(fun(Term) ->
        gen_tcp:send(Sock, term_to_binary(Term))
    end, [{1,2,3,4}, {[1,2,3], "test"}]).

recver(Sock) ->
    case gen_tcp:recv(Sock,0) of
        {ok, B} ->
            gen_tcp:send(Sock, B),
            error_logger:info_msg("ok ~p ~n", binary_to_term(B)),
            recver(Sock);
        {error, closed} ->
            error_logger:info_msg("closed ~n")
    end.  

client() ->
    {ok, Sock} = gen_tcp:connect("localhost", 5678, 
                                 [binary, {packet, 2}]),
    recver(Sock),
    sender(Sock),
    ok = gen_tcp:close(Sock).

test() ->
    {ok, Sock} = gen_tcp:connect("localhost", 5678, [binary, {package, 2},{active, false}]),
    prim_inet:recv(Sock, 100, 10).
