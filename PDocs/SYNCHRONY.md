# Synchronous calls and P scheduling

The audit distinguishes **C++ call synchrony** from **network/event delivery**.

The pattern

```p
send peer, request, ...;
while (!quit) {
  receive {
    case reply: ...
    case otherIncomingEvent: ...
  }
}
```

is appropriate only when the modeled program actually performs a blocking/correlated interaction with an independently scheduled component while remaining able to service selected incoming work.

That is **not** the shape of the audited QUICHE MASQUE CONNECT-UDP code in this source snapshot.

## Calls that are synchronous in C++ and therefore remain in one P handler

- `CreateOutgoingBidirectionalStream()` — client `masque_client_session.cc:L191-L196`.
- `stream->SendRequest(...)` return value — client `L219-L224`.
- URI parsing/template/canonicalization — client `L131-L190`.
- DNS lookup — server `masque_server_session.cc:L624-L637`.
- `GetActiveStream` — server `L650-L657`.
- UDP socket create/bind/register — server `L659-L675`.
- `SendHttp3Datagram(...)` returns `DatagramStatus` synchronously, but the audited code only logs that status; actual peer delivery is modeled asynchronously.
- `QuicUdpSocketApi::WritePacket(...)` returns `WriteResult` synchronously at server `L1080-L1086`; the result is logged and does not control routing in this code.

For these calls, introducing a separate P machine and waiting for a reply would add artificial interleavings. Where failure matters, the model chooses the source-visible return class *inside the same handler*.

## Asynchronous boundaries

- CONNECT request/response delivery over HTTP/3.
- HTTP Datagrams.
- capsule delivery.
- stream/connection-close callbacks.
- UDP socket readability callbacks.

Those are represented with P events and can interleave.

If a future audited QUICHE revision introduces a blocking cross-component request/reply whose correlation matters, use the guarded `receive` loop pattern and document the exact C++ wait/callback correspondence beside it.
