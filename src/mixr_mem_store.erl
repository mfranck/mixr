-module(mixr_mem_store).
-behaviour(mixr_backend_store).

-export([
         init/1
         , terminate/1
         , count/1
         , exist/3
         , save/6
         , find/2
         , delete/2
         , append/3
         , prepend/3
        ]).

-record(r, {
          key,
          value,
          cas,
          expiration,
          flag}).

init(_) ->
  [].

terminate(_) ->
  ok.

count(State) ->
  {length(State), State}.

exist(State, Key, CAS) ->
  case lists:keyfind(Key, 1, State) of
    {Key, #r{cas = CAS1, expiration = 0}} when CAS =:= 0; CAS1 =:= CAS ->
      {true, State};
    {Key, #r{cas = CAS1, expiration = Expiration}} when CAS =:= 0; CAS1 =:= CAS ->
      case edate:compare(Expiration, edate:today()) of
        -1 ->
          {true, State};
        _ ->
          {false, remove(State, Key)}
      end;
    _ ->
      {false, State}
  end.

save(State, Key, Value, CAS, Expiration, Flags) ->
  Expiration1 = if
                  Expiration =:= 0 -> 0;
                  true -> edate:add(edate:today(), Expiration, seconds)
                end,
  Record = #r{
              key = Key,
              value = Value,
              cas = CAS,
              expiration = Expiration1,
              flag = Flags},
  Result = case lookup(State, Key) of
             {{ok, _}, State} ->
               {ok, lists:keyreplace(Key, 1, State, {Key, Record})};
             {not_found, State1} ->
               {ok, [{Key, Record} | State1]};
             _ ->
               {error, State}
           end,
  case Result of
    {ok, State2} ->
      {{ok, CAS}, State2};
    {error, State2} ->
      {error, State2};
    _ ->
      {error, State}
  end.

find(State, Key) ->
  case lookup(State, Key) of
    {{ok,
      #r{key = Key, value = Value, cas = CAS, expiration = Expiration, flag = Flags}},
     State1} ->
      {{ok, {Key, Value, CAS, expiration(Expiration), Flags}}, State1};
    Other ->
      Other
  end.

delete(State, Key) ->
  case exist(State, Key, 0) of
    {true, State} ->
      {ok, remove(State, Key)};
    {false, State1} ->
      {not_found, State1}
  end.

append(State, Key, Value) ->
  xpend(State, Key, Value, fun(Current, New) ->
                               <<Current/binary, New/binary>>
                           end).

prepend(State, Key, Value) ->
  xpend(State, Key, Value, fun(Current, New) ->
                               <<New/binary, Current/binary>>
                           end).

% Private

lookup(State, Key) ->
  case exist(State, Key, 0) of
    {true, State} ->
      case lists:keyfind(Key, 1, State) of
        {Key, Data} -> {{ok, Data}, State};
        _ -> {error, State}
      end;
    {false, State1} ->
      {not_found, State1}
  end.

remove(State, Key) ->
  lists:keydelete(Key, 1, State).

expiration(0) -> 0;
expiration(Date) ->
  Expiration = calendar:datetime_to_gregorian_seconds(Date) -
               calendar:datetime_to_gregorian_seconds(edate:today()),
  if
    Expiration > 0 -> Expiration;
    true -> 1
  end.

xpend(State, Key, Value, Fun) ->
  case lookup(State, Key) of
    {{ok,
      #r{key = Key, value = CurrentValue, cas = CAS, flag = 0} = Data},
     State1} ->
      {{ok, CAS},
       lists:keyreplace(
         Key, 1, State1,
         {Key, Data#r{value = Fun(CurrentValue, Value)}})};
    {{ok,
      #r{cas = CAS}},
     State1} ->
      {{ok, CAS}, State1};
    Other ->
      Other
  end.

