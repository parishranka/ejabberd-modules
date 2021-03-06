%%% @author  Pablo Polvorin <pablo.polvorin@process-one.net>
%%% @doc  PostgresQL interface
%%% This is a rewrite of the pgsql driver, main differences:
%%%    * Uses binaries rather than lists
%%%    * Protocol code implemented using gen_fsm 
%%%    * Options for decoding values
%%%    * Support for for batch insert/updates 

-module(pgsql2).


% @doc This interface isn't backwards compatible with pgsql. 
%      By default, fields returned by the server are converted to
%      appropriate erlang values, if an appropriate type converted is defined 
%      (float -> float, date -> calendar:date(), timestamp -> calendar:datetime(),.. )
%      See options in connect/4.
%
%       
%
%
-define(Q_TIMEOUT,10000).

-export([connect/4,
    stop/1,
    prepare/3,
    close_prepared/2,
    pq/3,
    q/2,
    q/3,
    q/4,
    execute/3,
    execute_many/3,
    get_parameters/1,
    apply_in_tx/3]).	


% @spec connect(User,Password,Database,[Option]) -> {ok,Pid} 
% @type Option =  {connection, Connection} |  {protocol_response_format,RespFormat} | 
% 				  {type_decoders,[Module]} | {decode_response,boolean()}
% @type Connection =  {tcp,Host, Port}
% @type RespFormat = binary | text
% @doc Start a pgsql2 driver process, witch maps 1:1 to a database connection.
%      Defaults: {connection,{tcp,"localhost",5432}},{protocol_response_format,binary},{type_decoders,[]}
%                {decode_response,true} 
%
%	   decode_response whether the driver should attempt to decode return values or not. Can be overridde 
%      using query options
%
%      type_decoders  let the user specify new decoders, TODO: NOT YET IMPLEMENTED!
%  
%	   protocol_response_format is the format in witch the Postgres server will return data to the driver.
%      This shouldn't affect the way in witch data is returned from the driver when decode_response is 
%      set to true, as the data decoders should take care of decoding the response into the appropriate 
%      erlang value (note that  for types that doesn't have a decoder, the data is returned to the client as-is, 
%      so the underling format would be visible). The format can be override using query options
%      Note that queries using q/2 aren't affected by this setting, and the response from postgres is always
%      in text format. 
%      Currently, the driver only sends data to the server in text format.
%
%      TODO: would be better to remove the option that allows binary format,
%      from the postgres manuall: "Keep in mind that binary representations for
%      complex data types might change across server versions; the text format
%      is usually the more portable choice."
connect(User,Password,Database,Options) ->
	Opts = [{user,User},{password,Password},{database,Database}|Options],
	pgsql2_proto:start_link(Opts).
	
	
stop(Pid) ->
	gen_fsm:sync_send_event(Pid,stop).

% @spec prepare(Pid, Name , QueryString) -> ok | {error, Reason}
% @type Name = atom()
% @type QueryString = iolist()
% @doc  Register the given statement under the given name. Later, that
%       name can be used to refer to this query. 
%       The statment could have placeholders, denoted by $1..$N. 
%
%       The intended implementation is to prepare the statment at the 
%       database level.
% @see pq/3
prepare(Pid, Name, QueryString) when is_atom(Name) ->
    gen_fsm:sync_send_event(Pid, {prepare, Name, QueryString}, ?Q_TIMEOUT).

% @spec close_prepare(Pid, Name) -> ok | {error, Reason}
% @type Name = atom()
% @doc  Free resources associated with a prepared statement.$N. 
close_prepared(Pid, Name) when is_atom(Name) ->
    gen_fsm:sync_send_event(Pid, {close_prepared, Name}, ?Q_TIMEOUT).

% @spec pq(Pid, Name, Parameters) -> {ok,[Row]} | {error, Reason}
% @type Row = list()
% @doc  Execute the named prepared statement, using the supplied
%       parameters. The parameter list (could be empty) must have the 
%       same number of elements as the number of placeholders in the 
%       corresponding statment.
pq(Pid, Name, Params) ->
    gen_fsm:sync_send_event(Pid, {pq, Name, Params}, ?Q_TIMEOUT).

% @spec q(Pid,Query) -> {ok,[Row]} | {error,Reason}
% @type Query = iolist()
% @type Row = list()
% @doc Execute the given Query. The query must not have
%      any placeholder.
%      This function is intended to be used for 
% 	   select-like queries. For insert/updates use execute/3 
%      or execute_many/3.
%      Note that the safest way to build queries containing 
%      parameters is to use q/4
% @see q/4
% @see execute/3
% @see execute_many/3
q(Pid,Query) ->
	gen_fsm:sync_send_event(Pid,{q,Query},?Q_TIMEOUT).

% @doc Same as q(Pid,Query,Params,[])
% @see q/4
q(Pid,Query,Params) ->
	q(Pid,Query,Params,[]).

% @spec q(Pid,Query,Params,Options) -> {ok,[Row]} | {error,Reason}
% @type Query = iolist()
% @type Params = list()
% @type Options = [Option]
% @type Option = {response_format,Format} | {decode_response,boolean()} 
% @type Format = binary | text
% @type Row = list()
% @doc Execute the given Query. The query could have 
%      placeholders, denoted by $1..$N. The parameters
%      list (could be empty) must have the same number of
%      elements as the number of placeholders in in the 
%      query string.
%      This function is intended to be used for 
% 	   select-like queries. For insert/updates use execute/3 
%      or execute_many/3.
q(Pid,Query,Params,Options) ->
	gen_fsm:sync_send_event(Pid,{q,Query,Params,Options},?Q_TIMEOUT).


% @spec q(Pid,Query,MultiParams) -> ok | {error,Reason}
% @type Query = iolist()
% @type MultiParams = [Params]
% @type Params = list()
% @doc Prepare a database operation and then
%      execute it against all parameter lists
%      found in the list MultiParams.
%      For batch insert/updates this function
%      should be faster than performing successive
%      calls to execute/3, as the command has to
%      be parsed only once.
execute_many(Pid,Query,Params) ->
	gen_fsm:sync_send_event(Pid,{execute_batch,Query,Params},?Q_TIMEOUT).


% @spec q(Pid,Query,Params) -> ok | {error,Reason}
% @type Query = iolist()
% @type Params = list()
% @doc Execute a database operation.
%      For batch insert/updates use execute_many/3.
%      For select-like queries use any of q/2,q/3,q/4
%      instead. 
execute(Pid,Query,Params) ->
	gen_fsm:sync_send_event(Pid,{execute,Query,Params},?Q_TIMEOUT).


%% @doc Apply the given function in a transactional context 
%%      whithin this connection.
%%      The transaction will be commited if the function 
%%      returns normally, and a rollback is done if the function
%%      throws any exception.
%%      The Function is called with the connection as the first 
%%      argument with the rest of the arguments following.
%%      apply_in_tx(Connection,F,[a,b]) would result in
%%      apply(F,[Connection,a,b])
%%
%%      IMPORTANT!: this implementation isn't safe to be used
%%                  from multiple client process. 
%%TODO: See status field in ready_for_query, to be sure
%% that the transaction is going ok
apply_in_tx(Pid,Fun,Args) ->
	ok = gen_fsm:sync_send_event(Pid,{execute,"BEGIN",[]},?Q_TIMEOUT),
	try 
		R = apply(Fun,[Pid|Args]),
		ok = gen_fsm:sync_send_event(Pid,{execute,"COMMIT",[]},?Q_TIMEOUT),
		R
	catch
		Type:Error ->
        ok=gen_fsm:sync_send_event(Pid,{execute,"ROLLBACK",[]},?Q_TIMEOUT),
					  throw({tx_error,Type,Error})
	end.
		
 
% @spec get_parameters(Pid) -> {ok,[Parameter]}
% @type Parameter = {Key,Value}
% @doc return the parameters of the server, given 
%      after successfull authentication
%
get_parameters(Pid) ->
	gen_fsm:sync_send_all_state_event(Pid,get_parameters).

