%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Carlos Gonzalez Florido.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc Default callbacks
-module(nkservice_rest_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-export([parse_url/1, make_listen/2]).

-include_lib("nklib/include/nklib.hrl").
-include_lib("nkpacket/include/nkpacket.hrl").

%% ===================================================================
%% Util
%% ===================================================================


%% @private
parse_url({nkservice_rest_conns, Multi}) ->
    {ok, {nkservice_rest_conns, Multi}};

parse_url(Url) ->
    case nkpacket_resolve:resolve(Url, #{resolve_type=>listen, protocol=>nkservice_rest_protocol}) of
        {ok, Multi} ->
            {ok, {nkservice_rest_conns, Multi}};
        {error, Error} ->
            {error, Error}
    end.


%% @doc
make_listen(SrvId, Endpoints) ->
    make_listen(SrvId, Endpoints, #{}).


%% @private
make_listen(_SrvId, [], Acc) ->
    Acc;
make_listen(SrvId, [#{id:=Id, url:={nkservice_rest_conns, Conns}}=Entry|Rest], Acc) ->
    Opts = maps:get(opts, Entry, #{}),
    Transps = make_listen_transps(SrvId, Id, Conns, Opts, []),
    make_listen(SrvId, Rest, Acc#{Id => Transps}).


%% @private
make_listen_transps(_SrvId, _Id, [], _Opts, Acc) ->
    lists:reverse(Acc);

make_listen_transps(SrvId, Id, [Conn|Rest], Opts, Acc) ->
    #nkconn{opts=ConnOpts, transp=_Transp} = Conn,
    Opts2 = maps:merge(ConnOpts, Opts),
    Opts3 = Opts2#{
        class => {nkservice_rest, SrvId, Id},
        path => maps:get(path, Opts2, <<"/">>),
        get_headers => [<<"user-agent">>]
    },
    Conn2 = Conn#nkconn{opts=Opts3},
    make_listen_transps(SrvId, Id, Rest, Opts, [Conn2|Acc]).

