# Bug-candidate status

No upstream QUICHE bug is claimed solely from this P package. A P counterexample must be mapped to the pinned C++ path and, for a community report, reproduced with a focused C++ test.

## BC-1 — CONNECT-UDP-BIND may dereference a null state on creation failure

**Status:** source-level candidate; not yet claimed confirmed.

Pinned client source data flow:

1. `GetOrCreateConnectUdpClientState` can return `nullptr` for URI/template/canonicalization failures (cc L135-L193), inability to create an outgoing bidirectional stream (L195-L200), and `SendRequest` returning zero bytes (L223-L227).
2. The ordinary `SendPacket` caller explicitly checks `connect_udp == nullptr` at L448-L452.
3. `SendConnectUdpBindPacket` obtains the same nullable result at L430-L431 and immediately calls `connect_udp->PrepareBindPacket(...)` at L432-L433 without an equivalent check.

The P model does not inject null. It enables only the existing source-derived failure checkpoints through `[ENV]` nondeterminism. If one occurs during a BIND API call, `[GHOST] meBindPrepareOnNullState` marks the first bad action and the `BindStateCreationSafety` temporal monitor rejects the trace.

A focused C++ test should force `CreateOutgoingBidirectionalStream()` or `SendRequest()` failure for BIND and confirm the behavior before filing upstream.

## BT-1 — CONNECT-UDP-BIND reverse peer address may be discarded

**Status:** source-level candidate; not yet claimed confirmed.

Pinned client source data flow:

1. `SendConnectUdpBindPacket` calls `GetOrCreateConnectUdpClientState(QuicSocketAddress(), ...)` — client cc L426-L433. Therefore the BIND state's `target_server_address_` is the default/empty address.
2. `ConnectUdpClientState::OnHttp3Datagram` reads the BIND context and computes a local `target_address`: inline peer at L692-L718, or compressed-map peer at L719-L720.
3. After decoding, L724 obtains payload, but L725-L726 calls `ProcessPacket(http_payload, target_server_address_)` instead of the just-computed `target_address`.
4. `EncapsulatedClientSession::ProcessPacket` explicitly accepts `QuicSocketAddress target_server_address` (client header L68-L71).

The P model mirrors that data flow literally: `decodedTarget` is calculated from the BIND context, while `deliveredTarget` is taken from the state's stored target. `BindTargetFidelity` checks the two independently. There is no `index = 0` or any equivalent seeded corruption in this path.

### Why this is not yet called a confirmed bug

The next step should be a small C++ regression test that constructs/uses a BIND state, returns a UDP packet from a known peer through both compressed and open/uncompressed context paths, and asserts that the encapsulated client receives that peer address in `ProcessPacket`. Only after confirming expected semantics and observing the mismatch in executable QUICHE should this be reported as an implementation defect.

## FD reuse

The model can optionally reuse an fd only after state destruction. This is exploratory environment coverage, not a bug claim. It deliberately does **not** assume that a stale readable callback survives `UnregisterSocket` because that must be established from the concrete event-loop implementation first.


## Candidate C: CONNECT-UDP-BIND decoded peer is not passed to ProcessPacket

Source snapshot evidence:

- `masque_client_session.cc:L674-L718` parses BIND context and computes local `target_address`.
- `masque_client_session.cc:L720-L722` calls
  `ProcessPacket(http_payload, target_server_address_)` instead.
- BIND state creation calls `GetOrCreateConnectUdpClientState(QuicSocketAddress(), ...)`
  at `L426-L427`, so the stored `target_server_address_` is the empty/default address.
- `masque_encapsulated_client_session.cc:L58-L63` passes the supplied address into
  `connection()->ProcessUdpPacket(..., server_address, ...)`.

The P implementation preserves this exact flow. `BindTargetFidelity` checks the temporal requirement that the address delivered with a BIND reply equals the peer decoded from the context/inline address. A P violation is a **source-level bug candidate**. Confirmation should use a focused C++ test before upstream reporting.

## Candidate D: BIND caller dereferences nullable GetOrCreate result

Source snapshot evidence:

- `GetOrCreateConnectUdpClientState` has explicit `nullptr` returns at client
  `L138`, `L168`, `L185`, `L195`, and `L223`.
- `SendPacket` guards the returned pointer at `L444-L449`.
- `SendConnectUdpBindPacket` obtains the pointer at `L426-L427` and dereferences
  it at `L428` without a null check.

`BindStateCreationSafety` captures the bad prefix. Reachability of each failure class
must be confirmed against the concrete caller/setup; the model does not claim that
every abstract local failure is reachable in every production configuration.
