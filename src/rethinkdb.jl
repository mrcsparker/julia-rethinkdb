module RethinkDB

import JSON

include("query.jl")

type RethinkDBConnection
  socket :: Base.TCPSocket
end

# TODO: handle error is not connected or incorrect handshake
function connect(server::AbstractString = "localhost", port::Int = 28015)
  c = RethinkDBConnection(Base.connect(server, port))
  handshake(c)
  c
end

function handshake(conn::RethinkDBConnection)
  # Version.V0_4
  version = UInt32(0x400c2d20)

  # Key Size
  key_size = UInt32(0)

  # Protocol.JSON
  protocol = UInt32(0x7e6970c7)

  handshake = pack_command([version, key_size, protocol])
  write(conn.socket, handshake)
  is_valid_handshake(conn)
end

function is_valid_handshake(conn::RethinkDBConnection)
  readstring(conn.socket) == "SUCCESS"
end

function readstring(sock::TCPSocket, msg = "")
  c = read(sock, UInt8)
  s = convert(Char, c)
  msg = string(msg, s)
  if (s == '\0')
    return chop(msg)
  else
    readstring(sock, msg)
  end
end

function pack_command(args...)
  o = Base.IOBuffer()
  for enc_val in args
    write(o, enc_val)
  end
  o.data
end

function disconnect(conn::RethinkDBConnection)
  close(conn.socket)
end

function exec(conn::RethinkDBConnection, q::RQL)
  j = JSON.json([1 ; Array[q.query]])
  send_command(conn, j)
end

function token()
  t = Array{UInt64}(1)
  t[1] = object_id(t)
  return t[1]
end

function send_command(conn::RethinkDBConnection, json)
  t = token()
  q = pack_command([ t, convert(UInt32, length(json)), json ])

  write(conn.socket, q)
  read_response(conn, t)
end

function read_response(conn::RethinkDBConnection, token)
  remote_token = read(conn.socket, UInt64)
  if remote_token != token
    return "Error"
  end

  len = read(conn.socket, UInt32)
  res = read(conn.socket, len)

  output = convert(UTF8String, res)
  JSON.parse(output)
end

function do_test()
  r = RethinkDB

  c = r.connect()

  #db_create("tester") |> d -> exec(c, d) |> println
  #db_drop("tester") |> d -> exec(c, d) |> println
  #db_list() |> d -> exec(c, d) |> println

  #db_create("test_db") |> d -> exec(c, d) |> println
  #db("test_db") |> d -> table_create(d, "test_table") |> d -> exec(c, d) |> println
  #db("test_table") |> d -> table_drop("foo") |> d -> exec(c, d) |> println

  #db("test_db") |>
  #  d -> table(d, "test_table") |>
  #  d -> insert(d, { "status" => "open", "item" => [{"name" => "foo", "amount" => "22"}] }) |>
  #  d -> exec(c, d) |> println

  r.db("test_db") |>
    d -> r.table(d, "test_table") |>
    d -> r.filter(d, { "status" => "open"}) |>
    d -> r.skip(d, 3) |>
    d -> r.has_fields(d, "xxx") |>
    d -> r.exec(c, d) |> println

  #now() |>
  #  d -> date(d) |>
  #  d -> exec(c, d) |> println

  #db("test_db") |>
  #  d -> table(d, "test_table") |>
  #  sync |> println

  r.db("test_db") |>
    d -> r.table(d, "test_table") |>
    d -> r.filter(d, r.js("(function(s) { return s.status === 'open'; })")) |>
    d -> r.exec(c, d) |> println

  r.db("test_db") |>
    d -> r.config(d) |> println

  r.disconnect(c)
end

end
