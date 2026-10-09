# Traceability convention

The P source is the primary traceability artifact. Every implementation-facing state field, event, state-machine handler, route lookup, lifecycle action, and monitor observation is annotated inline.

Tags used in P comments:

- `[CXX]`: direct correspondence to a named C++ symbol or source block at the pinned commit.
- `[ABS]`: deliberate finite abstraction. The inline comment states what is collapsed and why the checked property does not depend on the omitted detail.
- `[ENV]`: behavior belonging to QUIC/HTTP/3, the OS UDP socket, or the event loop rather than the audited MASQUE object itself.
- `[GHOST]`: verification-only provenance/observation. Ghost values/events never select an implementation route or modify implementation state.
- `[TEST]`: finite harness choice only; no production C++ counterpart.

## Main structural correspondences

| P structure | P location | Pinned C++ source |
|---|---|---|
| `tClientTunnelState` | `PSrc/Definitions.p` | `ConnectUdpClientState` fields, client header L283-L291; ctor/dtor client cc L613-L635 |
| `clientStates` | `PSrc/MasqueClientSession.p` | `connect_udp_client_states_`, client header L408; creation client cc L102-L236 |
| `tServerTunnelState` | `PSrc/Definitions.p` | `ConnectUdpServerState` fields, server header L158-L166; ctor/dtor server cc L950-L982 |
| `serverStates` | `PSrc/MasqueServerSession.p` | `connect_udp_server_states_`, server header L260 |
| `tBindContextState` | `PSrc/Definitions.p` | client `bind_context_ip_map_` h L288-L289; server map h L164-L166 |
| client send handler | `MasqueClientSession.p::ceSendPacket` | client cc L426-L473 and GetOrCreate L102-L236 |
| client return handler | `MasqueClientSession.p::ceHttpDatagram` | client cc L662-L729 |
| server CONNECT setup | `MasqueServerSession.p::seConnectRequest` | server cc L417-L702 |
| server forward path | `MasqueServerSession.p::seHttpDatagram` | server cc L1013-L1087 |
| server reverse path | `MasqueServerSession.p::seUdpReadable` | server cc L707-L877 |
| stream teardown | both session machines | client cc L556-L597; server cc L196-L210 |
| connection teardown | both session machines | client cc L541-L554; server cc L187-L194 |

Do not use this table instead of the P comments when reviewing a counterexample: the inline comment immediately above each modeled operation is the authoritative local mapping.
