# Temporal safety properties

The formulas below are the requirements. The `PSpec/*.p` files are executable finite-event safety monitors (bad-prefix automata) over model observations. Each P monitor repeats its formula and source observation mapping inline.

Notation: `G` means globally / always. These are safety or conditional-correspondence properties; they intentionally avoid requiring eventual delivery of unreliable HTTP Datagrams.

## TI — tunnel isolation

`G(ValidUdpReply(p,t) && ClientAcceptsSameReply(p,t') -> t' = t)`

A reply generated from a concrete UDP write must not be associated with another tunnel. Expected stream/fd/target provenance is captured by `UdpEnvironment` before the server fd lookup.

## DC — non-BIND Context ID

`G(NonBindForward(p,c) -> c = 0)`

Matches client send context construction (client cc L459-L464) and server non-BIND receive/reverse handling (server cc L1021-L1030 and L856-L860).

## TL — lifecycle exclusion

`G(Removed(t) -> !ForwardAfterRemoval(t))`

Refines the ownership consequence of client/server state erase and visitor/socket unregister. The monitor is event based and does not claim a stronger C++ memory theorem.

## CU — connection cleanup

`G(ServerConnectionClosed(c) -> LiveServerTunnels(c) = {})`

Matches server `OnConnectionClosed` clearing `connect_udp_server_states_` (cc L187-L194).

## BF — BIND forward-target fidelity

`G(ClientBindDatagramAccepted(p,target=T,context=C) && ProxyForwardsSamePacket(p,target=T',context=C') -> T'=T && C'=C)`

Checks client target/context encoding against the peer address selected by server `WritePacket`.

## BT — BIND reverse-target fidelity

`G(ValidUdpReply(p,peer=T) && ClientDeliversSamePacket(p,decoded=D,delivered=A) -> D=T && A=T)`

and the local consistency form:

`G(ClientBindDelivery(p,decoded=D,delivered=A) -> A=D)`

This property is intentionally independent of current source behavior. It expresses the meaning of `EncapsulatedClientSession::ProcessPacket(packet, target_server_address)` in client header L68-L71: the address supplied with a decapsulated BIND packet should identify the peer encoded by the BIND context or inline address.

## BC — BIND nullable-state creation safety

`G(PrepareBindPacket(state) -> state != null)`

`GetOrCreateConnectUdpClientState` has concrete nullable returns at client cc L135-L193, L195-L200, and L223-L227. The non-BIND caller checks null at L448-L452; the BIND caller invokes `PrepareBindPacket` directly at L430-L433. `BindStateCreationSafety` recognizes the bad prefix without injecting a wrong pointer or route.
