# QUICHE MASQUE CONNECT-UDP / CONNECT-UDP-BIND: source-traceable P model

This package is an implementation-oriented P abstraction of the Google QUICHE
MASQUE CONNECT-UDP and CONNECT-UDP-BIND paths.

## Source pin

All inline C++ line references are pinned to:

`google/quiche @ d22f60e1389182a78bdeddd81c130a9161afd46d`  
`refs/heads/main`, 2026-10-08.

The principal source files are `masque_client_session.{h,cc}` and
`masque_server_session.{h,cc}` under `quiche/quic/masque/`.

## How to read the P code

The correspondence is **inside the P model itself**, immediately next to the
state, field, handler, helper, or transition that it explains.

- `[CXX]`: direct correspondence to a pinned C++ symbol/block and line range.
- `[ABS]`: deliberate abstraction; the comment explains what is collapsed and why.
- `[ENV]`: QUIC/HTTP/3, OS socket, or event-loop behavior outside the audited MASQUE object.
- `[GHOST]`: verification-only provenance/observation; never drives implementation behavior.
- `[TEST]`: finite test-harness choice only.

Start with:

- `PSrc/MasqueClientSession.p`
- `PSrc/MasqueServerSession.p`
- `PSrc/Definitions.p`
- `PSpec/*.p`

`PDocs/TRACEABILITY.md` is only an index; it is not a substitute for the inline
comments.

## Faithfulness decisions

`ConnectUdpClientState` and `ConnectUdpServerState` are passive tuples owned by
the session machines rather than separate P machines, because the C++ stores
those objects in session-owned `std::list`s. Making them independently scheduled
machines would invent concurrency.

The server reverse route uses the same fd-based first-match lookup as
`HandleConnectUdpSocketEvent`; the previous deliberate `index = 0` mutation is
**not present** in this package.

The transport and UDP machines are explicit environment abstractions. In
particular, an HTTP Datagram chosen to become observable before CONNECT state
creation is not delivered to a nonexistent server-state visitor; it is treated
at the lower stream boundary as an early drop. See inline `[ENV]` comments and
`PDocs/ABSTRACTION_LEDGER.md`.

## Temporal properties

Each `PSpec/*.p` starts from a temporal safety requirement and then implements a
finite-event bad-prefix monitor. The formulas are repeated inline in the monitor
files. The most important checks are:

- tunnel/return-route isolation;
- client/server state uniqueness;
- non-BIND Context ID 0;
- stream and connection lifecycle cleanup;
- CONNECT-UDP-BIND client->target fidelity;
- CONNECT-UDP-BIND reverse peer-address fidelity;
- CONNECT-UDP-BIND nullable-state creation safety.

See `PDocs/TEMPORAL_PROPERTIES.md`.

## Source-level candidates retained without mutation

The line-by-line audit currently exposes two source-level candidates. Neither is labeled a confirmed upstream bug without C++ reproduction.

**BC-1: missing BIND null check.** `GetOrCreateConnectUdpClientState` has several real `nullptr` exits. `SendPacket` checks the result, while `SendConnectUdpBindPacket` calls `PrepareBindPacket` directly. `BindStateCreationSafety` explores those existing failure points without injecting corruption.

**BT-1: reverse peer-address fidelity.** The latest pinned client code has a data flow worth testing carefully in C++:
for CONNECT-UDP-BIND, the client computes a per-datagram `target_address` while
decoding the returned datagram, but the final `ProcessPacket` call passes the
state's `target_server_address_`. The BIND state was created using a default
empty socket address. The P model mirrors that exact behavior; it does not repair
it. `BindTargetFidelity` independently checks the decoded peer against the
address delivered to the encapsulated client.

This package labels that **BT-1, a source-level candidate**, not a confirmed
upstream bug. A focused C++ regression/reproduction test is required before a
community report. See `PDocs/BUG_CANDIDATES.md`.

## Project layout

```text
QUICHEMasquePModel.pproj
PSrc/
  Definitions.p
  Events.p
  MasqueClientSession.p
  MasqueServerSession.p
  Http3Transport.p
  UdpEnvironment.p
  Modules.p
PSpec/
  TunnelIsolation.p
  StateUniqueness.p
  TunnelLifecycle.p
  DatagramContext.p
  ConnectionCleanup.p
  BindForwardFidelity.p
  BindTargetFidelity.p
  BindStateCreationSafety.p
PTst/
  TestDriver.p
  TestScript.p
PDocs/
  UPSTREAM_PIN.md
  TRACEABILITY.md
  ABSTRACTION_LEDGER.md
  TEMPORAL_PROPERTIES.md
  BUG_CANDIDATES.md
  METHODOLOGY.md
  VALIDATION.md
```

## Suggested checks

From the project root, using the user's installed P toolchain:

```bash
p compile
p check -tc tcTwoTunnelIsolation -i 10000 --sch-pct 3
p check -tc tcStreamCloseLifecycle -i 10000 --sch-pct 3
p check -tc tcUnexpectedUdpSourceDropped -i 10000 --sch-pct 3
p check -tc tcBindForwardFidelity -i 10000 --sch-pct 3
p check -tc tcBindStateCreationSafety -i 10000 --sch-pct 3
p check -tc tcBindTargetFidelity -i 10000 --sch-pct 3
p check -tc tcBindUncompressedTargetFidelity -i 10000 --sch-pct 3
```

`tcBindTargetFidelity` is expected to be the focused test for BT-1 because the P
implementation intentionally follows the current C++ data flow. A P failure is
still only a **candidate trace** until it is validated against the C++ semantics
and reproduced in executable QUICHE.

## Validation caveat

The package-generation container does not contain the P compiler/.NET runtime,
so the archive is statically checked but not compiler-validated here. Run
`p compile` first in the existing P environment. See `PDocs/VALIDATION.md`.


## Reading this source-annotated edition

Start with:

1. `ReferenceCpp/*.numbered.txt`: exact C++ snapshot and line numbers.
2. `PSrc/Definitions.p`: every enum/type has a `DEFINITION` comment.
3. `PSrc/Events.p`: every event has a `DEFINITION` comment and the global communication diagram.
4. `PSrc/MasqueClientSession.p` / `MasqueServerSession.p`: code-aligned machines.
5. `PSpec/*.p`: temporal requirements expressed in `G(...)` safety form before monitor code.
6. `PDocs/COMMUNICATION_DIAGRAMS.md` and `PDocs/SYNCHRONY.md`.

Every `on` and executable `send` is preceded by a local communication diagram comment.
The implementation machines do not branch on test scenario names; scenario selection is confined to `PTst`.

### Candidate-focused tests

`tcBindTargetFidelity` is intended to expose the current BIND return-address data flow without injecting a wrong route.

`tcBindCreateFailure` validates the nullable-state safety property. Its abstract local-failure choices should be treated as reachability hypotheses until reproduced with a C++ test.

No `index = 0` mutation exists in this edition.
