import pkg/chronos
import pkg/quic
import ../multiaddress
import ../multicodec
import ../stream/connection
import ../wire
import ../upgrademngrs/upgrade
import ./transport

export multiaddress
export multicodec
export connection
export transport

type
  P2PConnection = connection.Connection
  QuicConnection = quic.Connection

type
  QuicTransport* = ref object of Transport
    listener: Listener
  QuicSession* = ref object of Session
    connection: QuicConnection
  QuicStream* = ref object of P2PConnection
    stream: Stream
    cached: seq[byte]

func new*(_: type QuicTransport): QuicTransport =
  QuicTransport()

func new*(_: type QuicTransport, upgrade: Upgrade): QuicTransport =
  QuicTransport(upgrader: upgrade)

proc new(_: type QuicStream, stream: Stream): QuicStream =
  let quicstream = QuicStream(stream: stream)
  procCall P2PConnection(quicstream).initStream()
  quicstream

method handles*(transport: QuicTransport, address: MultiAddress): bool =
  if not procCall Transport(transport).handles(address):
    return false
  QUIC.match(address)

method start*(transport: QuicTransport, address: MultiAddress) {.async.} =
  doAssert transport.listener.isNil, "start() already called"
  transport.listener = listen(initTAddress(address).tryGet)
  await procCall Transport(transport).start(address)

method stop*(transport: QuicTransport) {.async.} =
  if transport.running:
    await procCall Transport(transport).stop()
    await transport.listener.stop()

method accept*(transport: QuicTransport): Future[Session] {.async.} =
  doAssert not transport.listener.isNil, "call start() before calling accept()"
  let connection = await transport.listener.accept()
  return QuicSession(connection: connection)

method dial*(transport: QuicTransport,
             address: MultiAddress): Future[Session] {.async.} =
  let connection = await dial(initTAddress(address).tryGet)
  result = QuicSession(connection: connection)

method getStream*(session: QuicSession,
                  direction = Direction.In): Future[P2PConnection] {.async.} =
  var stream: Stream
  case direction:
    of Direction.In:
      stream = await session.connection.incomingStream()
    of Direction.Out:
      stream = await session.connection.openStream()
      await stream.write(@[]) # QUIC streams do not exist until data is sent
  return QuicStream.new(stream)

method readOnce*(stream: QuicStream,
                 pbytes: pointer,
                 nbytes: int): Future[int] {.async.} =
  if stream.cached.len == 0:
    stream.cached = await stream.stream.read()
  if stream.cached.len <= nbytes:
    copyMem(pbytes, addr stream.cached[0], stream.cached.len)
    result = stream.cached.len
    stream.cached = @[]
  else:
    copyMem(pbytes, addr stream.cached[0], nbytes)
    result = nbytes
    stream.cached = stream.cached[nbytes..^1]

{.push warning[LockLevel]: off.}
method write*(stream: QuicStream, bytes: seq[byte]) {.async.} =
  await stream.stream.write(bytes)
{.pop.}

method closeImpl*(stream: QuicStream) {.async.} =
  await stream.stream.close()
  await procCall P2PConnection(stream).closeImpl()

method close*(session: QuicSession) {.async.} =
  await session.connection.close()

method join*(session: QuicSession) {.async.} =
  await session.connection.waitClosed()

when not defined(libp2p_experimental_quic):
  {.fatal: "QUIC must be explicitly enabled  '-d:libp2p_experimental_quic'".}