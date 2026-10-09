# Abstraction ledger

The model intentionally avoids claiming byte-for-byte or scheduler-for-scheduler equivalence with all of QUICHE. Each abstraction is also called out inline where it is used.

## A1 — Passive C++ state objects as P tuples

`ConnectUdpClientState` and `ConnectUdpServerState` are stored by the C++ session in `std::list`; they are not independently scheduled threads. Modeling them as separate P machines would introduce concurrency absent from the code. They are therefore tuples owned by the corresponding session machine.

Preserved: stream identity, encapsulated-session identity, target address, BIND mode, fd identity, context mappings, creation/removal order.

Omitted: pointer values, allocator behavior, move-constructor mechanics except where ownership semantics matter.

## A2 — Addresses

`QuicSocketAddress` is represented as `(host:int, port:int)`. Equality and initialized/default distinction are preserved. IPv4/IPv6 byte parsing is not modeled, so this model cannot establish parser memory-safety or malformed-wire correctness.

## A3 — Payloads

Payload bytes are represented by unique finite `packet.id` provenance plus a finite data class. The ID is `[GHOST]`, not a protocol field. This permits independent end-to-end correspondence checks without making routing decisions from ghost state.

## A4 — CONNECT request syntax

Detailed URI-template expansion, percent escaping, authority parsing, and DNS contents are collapsed to finite accept/reject branches and a semantic target. The exact C++ line block is attached at each branch. This is adequate for association/lifecycle properties after a target is decoded, but not for parser-validation claims.

## A5 — QUIC/HTTP/3 transport

`Http3Transport` is an environment machine, not a claim that QUICHE has that state machine. Reliable CONNECT/capsule delivery and unreliable HTTP Datagram delivery are separated. Cross-channel scheduling can vary. A datagram selected before the CONNECT request is observable is dropped at the lower stream boundary rather than delivered to a nonexistent `ConnectUdpServerState` visitor.

## A6 — UDP socket environment and fd allocation

The model preserves the server's fd-based state lookup. Numeric fd allocation is an OS concern, so fresh descriptors are the default and optional reuse is allowed only after modeled destruction. The model does not invent a stale callback surviving `UnregisterSocket`; that would require event-loop-specific evidence before being admitted.

## A7 — Local operation failures

URI setup, stream allocation, socket creation, bind, registration, and local HTTP Datagram acceptance may be abstracted as success/failure at the exact C++ checkpoints. A single helper chooses outcomes, but each call site identifies the concrete source operation. This avoids inventing failure points while keeping the state space finite.

## A8 — BIND context allocation

The model preserves the client allocator's even IDs beginning at 2 for the bounded scenarios. Context-close/reallocation sequences are not yet exhaustive. Therefore no claim about arbitrary long-lived context-ID lifecycle should be made from the current harness.

## A9 — Monitors

Properties are specified first as temporal safety requirements, then refined to P bad-prefix monitors over `[GHOST]` observations. Expected values are captured at an independent boundary whenever possible; the monitor does not use a suspect implementation lookup to generate both the expected and actual values.
