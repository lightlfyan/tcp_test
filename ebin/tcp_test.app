{application,tcp_test,
             [{description,"simple tcp_test"},
              {vsn,"1"},
              {registered,[]},
              {applications,[kernel,stdlib]},
              {mod,{tcp_test_app,[]}},
              {env,[]},
              {modules,[simple_srv,tcp_test_app,tcp_test_srv,tcp_test_srv2,
                        tcp_test_sup]}]}.
