-module(mixr_utils).

-export([
         cas/1
        ]).

cas(0) ->
  {Mega,Sec,Micro} = os:timestamp(),
  (Mega*1000000+Sec)*1000000+Micro;
cas(CAS) -> CAS.

