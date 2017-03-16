%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Carlos Gonzalez Florido.  All Rights Reserved.
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

-module(nkservice_util).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').

-export([call/2, call/3]).
-export([parse_syntax/3, parse_transports/1]).
-export([make_id/1, update_uuid/2]).
-export([get_debug_info/2]).
-export([register_for_changes/1, notify_updated_service/1]).

-include_lib("nkpacket/include/nkpacket.hrl").


-define(API_TIMEOUT, 30).


%% ===================================================================
%% Public
%% ===================================================================


%% @doc Safe call (no exceptions)
call(Dest, Msg) ->
    call(Dest, Msg, 5000).


%% @doc Safe call (no exceptions)
call(Dest, Msg, Timeout) ->
    case nklib_util:call(Dest, Msg, Timeout) of
        {error, {exit, {{timeout, _Fun}, _Stack}}} ->
            {error, timeout};
        {error, {exit, {{noproc, _Fun}, _Stack}}} ->
            {error, process_not_found};
        Other ->
            Other
    end.


%% @doc
parse_syntax(Spec, Syntax, Defaults) ->
    Opts = #{return=>map, defaults=>Defaults},
    case nklib_config:parse_config(Spec, Syntax, Opts) of
        {ok, Parsed, Other} -> {ok, maps:merge(Other, Parsed)};
        {error, Error} -> {error, Error}
    end.


%% @private
parse_transports([{[{_, _, _, _}|_], Opts}|_]=Transps) when is_map(Opts) ->
    {ok, Transps};

parse_transports(Spec) ->
    case nkpacket:multi_resolve(Spec, #{resolve_type=>listen}) of
        {ok, List} ->
            {ok, List};
        _ ->
            error
    end.


%% @doc Generates the service id from any name
-spec make_id(nkservice:name()) ->
    nkservice:id().

make_id(Name) ->
    list_to_atom(
        string:to_lower(
            case binary_to_list(nklib_util:hash36(Name)) of
                [F|Rest] when F>=$0, F=<$9 -> [$A+F-$0|Rest];
                Other -> Other
            end)).


%% @private
update_uuid(Id, Name) ->
    LogPath = nkservice_app:get(log_path),
    Path = filename:join(LogPath, atom_to_list(Id)++".uuid"),
    case read_uuid(Path) of
        {ok, UUID} ->
            ok;
        {error, Path} ->
            UUID = nklib_util:uuid_4122(),
            save_uuid(Path, Name, UUID)
    end,
    UUID.


%% @private
read_uuid(Path) ->
    case file:read_file(Path) of
        {ok, Binary} ->
            case binary:split(Binary, <<$,>>) of
                [UUID|_] when byte_size(UUID)==36 -> {ok, UUID};
                _ -> {error, Path}
            end;
        _ -> 
            {error, Path}
    end.


%% @private
save_uuid(Path, Name, UUID) ->
    Content = [UUID, $,, to_bin(Name)],
    case file:write_file(Path, Content) of
        ok ->
            ok;
        Error ->
            lager:warning("Could not write file ~s: ~p", [Path, Error]),
            ok
    end.


%%%% @private
%%-spec error_code(nkservice:id(), nkservice:error()) ->
%%    {integer(), binary()}.
%%
%%error_code(SrvId, Error) ->
%%    case SrvId:error_code(Error) of
%%        {Code, Text} ->
%%            {Code, to_bin(Text)};
%%        {Code, Fmt, List} ->
%%            case catch io_lib:format(nklib_util:to_list(Fmt), List) of
%%                {'EXIT', _} ->
%%                    {Code, <<"Invalid format: ", (to_bin(Fmt))/binary>>};
%%                Val ->
%%                    {Code, list_to_binary(Val)}
%%            end
%%    end.




%% @doc Registers a pid to receive changes in service config
-spec register_for_changes(nkservice:id()) ->
    ok.

register_for_changes(SrvId) ->
    nklib_proc:put({notify_updated_service, SrvId}).


%% @doc 
-spec notify_updated_service(nkservice:id()) ->
    ok.

notify_updated_service(SrvId) ->
    lists:foreach(
        fun({_, Pid}) -> Pid ! {nkservice_updated, SrvId} end,
        nklib_proc:values({notify_updated_service, SrvId})).


%% @doc
-spec get_debug_info(nkservice:id(), module()) ->
    {ok, term()} | not_found.

get_debug_info(SrvId, Module) ->
    try nkservice_srv:get_item(SrvId, debug) of
        Debug ->
            case lists:keyfind(Module, 1, Debug) of
                {_, Data} -> {true, Data};
                false -> false
            end
    catch
        error:{service_not_found, _} ->
            % Service module not yet created
            get_debug_info2(SrvId, Module)
    end.


%% @private
get_debug_info2(SrvId, Module) ->
    try
        Debug = nkservice_srv:get(SrvId, nkservice_debug, []),
        case lists:keyfind(Module, 1, Debug) of
            {_, Data} -> {true, Data};
            false -> false
        end
    catch
        _:_ -> 
            % Service does not exists
            not_found
    end.


%% @private
to_bin(Term) -> nklib_util:to_binary(Term).



