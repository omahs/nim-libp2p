{.used.}

import unittest2, sequtils
import stew/byteutils
import ../../libp2p/[peerid,
                     crypto/crypto,
                     protocols/pubsub/mcache,
                     protocols/pubsub/rpc/message]

var rng = newRng()

proc randomPeerId(): PeerId =
  PeerId.init(PrivateKey.random(ECDSA, rng[]).get()).get()

const MsgIdGenSuccess = "msg id generation success"

suite "MCache":
  test "put/get":
    var mCache = MCache.init(3, 5)
    var msg = Message(fromPeer: randomPeerId(), seqno: "12345".toBytes())
    let msgId = defaultMsgIdProvider(msg).expect(MsgIdGenSuccess)
    mCache.put(msgId, msg)
    check mCache.get(msgId).isSome and mCache.get(msgId).get() == msg

  test "window":
    var mCache = MCache.init(3, 5)

    for i in 0..<3:
      var
        msg =
          Message(fromPeer: randomPeerId(), seqno: "12345".toBytes(), topic: "foo")
      mCache.put(defaultMsgIdProvider(msg).expect(MsgIdGenSuccess), msg)

    for i in 0..<5:
      var
        msg =
          Message(fromPeer: randomPeerId(), seqno: "12345".toBytes(), topic: "bar")
      mCache.put(defaultMsgIdProvider(msg).expect(MsgIdGenSuccess), msg)

    var mids = mCache.window("foo")
    check mids.len == 3

    var id = toSeq(mids)[0]
    check mCache.get(id).get().topic == "foo"

  test "shift - shift 1 window at a time":
    var mCache = MCache.init(1, 5)

    for i in 0..<3:
      var
        msg =
          Message(fromPeer: randomPeerId(), seqno: "12345".toBytes(), topic: "foo")
      mCache.put(defaultMsgIdProvider(msg).expect(MsgIdGenSuccess), msg)

    mCache.shift()
    check mCache.window("foo").len == 0

    for i in 0..<3:
      var
        msg =
          Message(fromPeer: randomPeerId(), seqno: "12345".toBytes(), topic: "bar")
      mCache.put(defaultMsgIdProvider(msg).expect(MsgIdGenSuccess), msg)

    mCache.shift()
    check mCache.window("bar").len == 0

    for i in 0..<3:
      var
        msg =
          Message(fromPeer: randomPeerId(), seqno: "12345".toBytes(), topic: "baz")
      mCache.put(defaultMsgIdProvider(msg).expect(MsgIdGenSuccess), msg)

    mCache.shift()
    check mCache.window("baz").len == 0

  test "shift - 2 windows at a time":
    var mCache = MCache.init(1, 5)

    for i in 0..<3:
      var
        msg =
          Message(fromPeer: randomPeerId(), seqno: "12345".toBytes(), topic: "foo")
      mCache.put(defaultMsgIdProvider(msg).expect(MsgIdGenSuccess), msg)

    for i in 0..<3:
      var
        msg =
          Message(fromPeer: randomPeerId(), seqno: "12345".toBytes(), topic: "bar")
      mCache.put(defaultMsgIdProvider(msg).expect(MsgIdGenSuccess), msg)

    for i in 0..<3:
      var
        msg =
          Message(fromPeer: randomPeerId(), seqno: "12345".toBytes(), topic: "baz")
      mCache.put(defaultMsgIdProvider(msg).expect(MsgIdGenSuccess), msg)

    mCache.shift()
    check mCache.window("foo").len == 0

    mCache.shift()
    check mCache.window("bar").len == 0
