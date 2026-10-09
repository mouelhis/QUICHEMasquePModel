// ============================================================================
// Event boundary and instrumentation catalog
// SOURCE SNAPSHOT: bundled under ReferenceCpp/; baseline lineage google/quiche d22f60e (2026-10-08)
// ============================================================================
// GLOBAL COMMUNICATION DIAGRAM (semantic boundaries, not object ownership):
//
//   TestDriver
//      | ceSendPacket / close stimuli
//      v
//   MasqueClientSession
//      | teConnectRequest / teClientDatagram / teBindContextAssign
//      v
//   Http3Transport
//      | seConnectRequest / seHttpDatagram / seBindContextAssign
//      v
//   MasqueServerSession
//      | ueProxyWrite
//      v
//   UdpEnvironment  <---->  abstract UDP peer
//      | seUdpReadable
//      +--------------------> MasqueServerSession
//                               | teServerDatagram
//                               v
//                           Http3Transport
//                               | ceHttpDatagram
//                               v
//                           MasqueClientSession
//
//   `me*` announcements fan out only to PSpec monitors and NEVER feed back into
//   implementation machines. CONNECT/capsule traffic is reliable in this model;
//   HTTP Datagrams may be lost/reordered according to the environment model.
//
// TRACEABILITY TAGS USED THROUGHOUT THIS FILE:
//   [CXX]   direct correspondence to the pinned QUICHE source block/symbol.
//   [ABS]   deliberate abstraction; comment states what is omitted and why.
//   [ENV]   environment/transport behavior outside the audited MASQUE object.
//   [GHOST] verification-only observation/provenance; never drives implementation.
//   [TEST]  finite test-harness choice with no production C++ counterpart.
//
// Events prefixed c/s/t/u correspond to implementation or environment actions.
// Events prefixed `me` are observation-only ghost instrumentation: they are
// announced after/before concrete modeled steps but never drive implementation
// control flow. This separation is required for independent monitor oracles.

// [TEST] Test/bootstrap only; no direct C++ counterpart.
// [TEST] harness wiring only.
// DEFINITION [EVENT eConfigureTransport]: Test-only bootstrap event that wires the abstract HTTP/3 transport to the client, server, driver, and finite environment configuration.
event eConfigureTransport: (client: machine, server: machine, driver: machine, config: tModelConfig);
// [TEST] harness wiring only.
// DEFINITION [EVENT eConfigureUdp]: Test-only bootstrap event that wires the UDP peer/event-loop environment to the server and driver.
event eConfigureUdp: (server: machine, driver: machine, config: tModelConfig);
// [TEST] harness synchronization only.
// DEFINITION [EVENT eTransportReady]: Test-harness readiness notification emitted after Http3Transport is configured.
event eTransportReady;
// [TEST] harness synchronization only.
// DEFINITION [EVENT eUdpReady]: Test-harness readiness notification emitted after UdpEnvironment is configured.
event eUdpReady;

// CLIENT API/CALLBACK BOUNDARY
// [CXX] ceSendPacket:
//   CONNECT-UDP      MasqueClientSession::SendPacket cc:441-469
//   CONNECT-UDP-BIND MasqueClientSession::SendConnectUdpBindPacket cc:422-439
// DEFINITION [EVENT ceSendPacket]: Client API action: represents SendPacket for CONNECT-UDP or SendConnectUdpBindPacket for CONNECT-UDP-BIND, depending on model mode.
event ceSendPacket: tClientSendRequest;
// Abstracts delivery of CONNECT response to the underlying stream/session.
// [ENV/CXX] delivery boundary for the CONNECT response to the client stream/session.
// DEFINITION [EVENT ceConnectResponse]: Client-side delivery of the HTTP response for the CONNECT request; used to observe status/lifecycle, not to gate optimistic DATAGRAM sending.
event ceConnectResponse: tConnectResponse;
// [CXX] callback ConnectUdpClientState::OnHttp3Datagram cc:658-725.
// DEFINITION [EVENT ceHttpDatagram]: Client callback boundary for ConnectUdpClientState::OnHttp3Datagram on the stream that owns the CONNECT-UDP state.
event ceHttpDatagram: tHttpDatagram;
// [CXX] MasqueClientSession::OnStreamClosed cc:552-593.
// DEFINITION [EVENT ceStreamClosed]: Client callback boundary for MasqueClientSession::OnStreamClosed(stream_id).
event ceStreamClosed: int;
// [CXX] MasqueClientSession::OnConnectionClosed cc:537-550.
// DEFINITION [EVENT ceConnectionClosed]: Client callback boundary for MasqueClientSession::OnConnectionClosed.
event ceConnectionClosed;
// [CXX] public CloseConnectUdpStream declaration client h:180-182 / cc:483-499.
// DEFINITION [EVENT ceCloseEncapsulatedSession]: Client-side request to close all CONNECT-UDP state associated with one EncapsulatedClientSession.
event ceCloseEncapsulatedSession: int;

// SERVER API/CALLBACK BOUNDARY
// [CXX] HandleMasqueRequest CONNECT-UDP branch cc:413-699.
// DEFINITION [EVENT seConnectRequest]: Server request-handler boundary for the CONNECT-UDP branch of MasqueServerSession::HandleMasqueRequest.
event seConnectRequest: tConnectRequest;
// [CXX] ConnectUdpServerState::OnCompressionAssignCapsule cc:1089-1107.
// DEFINITION [EVENT seBindContextAssign]: Server callback for a CONNECT-UDP-BIND CompressionAssign capsule.
event seBindContextAssign: tBindContextAssign;
// [CXX] ConnectUdpServerState::OnHttp3Datagram cc:1013-1087.
// DEFINITION [EVENT seHttpDatagram]: Server callback boundary for ConnectUdpServerState::OnHttp3Datagram.
event seHttpDatagram: tHttpDatagram;
// [CXX] Semantic result of OnSocketEvent/ReadPacket server cc:703-874.
// DEFINITION [EVENT seUdpReadable]: Semantic UDP readable result delivered from the event-loop/socket environment after a packet is read with fd and peer address.
event seUdpReadable: tUdpReadable;
// [CXX] MasqueServerSession::OnStreamClosed (removes matching state).
// DEFINITION [EVENT seStreamClosed]: Server callback boundary for MasqueServerSession::OnStreamClosed(stream_id).
event seStreamClosed: int;
// [CXX] OnConnectionClosed cc:183-190 clears all CONNECT-UDP state.
// DEFINITION [EVENT seConnectionClosed]: Server callback boundary for MasqueServerSession::OnConnectionClosed.
event seConnectionClosed;

// [ENV] HTTP/3 / QUIC transport boundary. These are NOT claimed as a QUIC state
// machine. They preserve reliable CONNECT/capsule traffic vs unreliable HTTP
// Datagrams and expose allowed cross-channel reordering.
// [ENV/CXX] transport of client stream->SendRequest (client cc:223-224).
// DEFINITION [EVENT teConnectRequest]: Reliable HTTP/3 request-stream transport of the CONNECT request after the local SendRequest API accepts it.
event teConnectRequest: tConnectRequest;
// [ENV/CXX] transport of server CONNECT response (server cc:685-699).
// DEFINITION [EVENT teConnectResponse]: Reliable HTTP/3 response-stream transport from server request handling back to the client stream/session.
event teConnectResponse: tConnectResponse;
// [ENV/CXX] capsule transport feeding BIND compression assignment visitors.
// DEFINITION [EVENT teBindContextAssign]: Reliable capsule-stream transport of CONNECT-UDP-BIND CompressionAssign.
event teBindContextAssign: tBindContextAssign;
// [ENV/CXX] unreliable HTTP Datagram after client SendHttp3Datagram cc:442/463-464.
// DEFINITION [EVENT teClientDatagram]: Unreliable HTTP Datagram transport from client to server after local SendHttp3Datagram acceptance.
event teClientDatagram: tHttpDatagram;
// [ENV/CXX] unreliable HTTP Datagram after server SendHttp3Datagram cc:862-868.
// DEFINITION [EVENT teServerDatagram]: Unreliable HTTP Datagram transport from server to client after local SendHttp3Datagram acceptance.
event teServerDatagram: tHttpDatagram;
// [ENV] scheduler-only release of delayed CONNECT request.
// DEFINITION [EVENT teFlushPendingConnects]: Environment-only scheduler event that releases delayed reliable CONNECT requests to explore cross-channel ordering.
event teFlushPendingConnects;
// [ENV] scheduler-only release of delayed BIND context assignment.
// DEFINITION [EVENT teFlushPendingBindContexts]: Environment-only scheduler event that releases delayed BIND context assignments to explore capsule/DATAGRAM ordering.
event teFlushPendingBindContexts;
// [ENV] QUIC stream reset/close notification boundary.
// DEFINITION [EVENT teResetStream]: Abstract QUIC stream reset/close notification propagated to both MASQUE session endpoints.
event teResetStream: int;
// [ENV] QUIC connection-close notification boundary.
// DEFINITION [EVENT teCloseConnection]: Abstract QUIC connection-close notification propagated to both MASQUE session endpoints.
event teCloseConnection;

// [ENV] UDP socket/event-loop environment. C++ write/read boundary is server
// ConnectUdpServerState::OnHttp3Datagram and HandleConnectUdpSocketEvent.
// [ENV/CXX] UDP write/read boundary around server cc:1080-1086 and cc:729-874.
// DEFINITION [EVENT ueProxyWrite]: UDP environment boundary representing the proxy socket WritePacket toward a selected peer and possible later peer reply.
event ueProxyWrite: tUdpWrite;

// ------------------------- PURE MONITOR INSTRUMENTATION ----------------------
// [GHOST] Every `me*` event below is observation-only. It never drives a C++-
// corresponding transition; the announce site in PSrc carries the exact C++ block.
// [GHOST/CXX] observes client state insertion cc:226-232.
// DEFINITION [EVENT meClientTunnelCreated]: Ghost observation of insertion of one client ConnectUdpClientState; monitor-only and never drives implementation behavior.
event meClientTunnelCreated: tClientTunnelEvent;
// [GHOST/CXX] observes client state erase cc:483-499 / 567-581.
// DEFINITION [EVENT meClientTunnelRemoved]: Ghost observation of erasure/destruction of one client ConnectUdpClientState.
event meClientTunnelRemoved: tClientTunnelEvent;
// [GHOST/CXX] observes server state insertion cc:681-683.
// DEFINITION [EVENT meServerTunnelCreated]: Ghost observation of insertion of one server ConnectUdpServerState after socket setup succeeds.
event meServerTunnelCreated: tServerTunnelEvent;
// [GHOST/CXX] observes server state erase/destruction cc:192-196 / 966-982.
// DEFINITION [EVENT meServerTunnelRemoved]: Ghost observation of erasure/destruction of one server ConnectUdpServerState and its socket ownership.
event meServerTunnelRemoved: tServerTunnelEvent;
// [GHOST/CXX] observes BIND context assignment processing cc:727-752 / server cc:1089-1107.
// DEFINITION [EVENT meBindContextAssigned]: Ghost observation that a BIND context-id-to-address mapping was installed.
event meBindContextAssigned: tBindContextAssign;

// [GHOST/CXX] observes accepted client API datagram before SendHttp3Datagram.
// DEFINITION [EVENT meClientDatagramApiAccepted]: Ghost observation that the client local HTTP Datagram API accepted a routing-relevant datagram for transmission.
event meClientDatagramApiAccepted: tClientDatagramEvent;
// [GHOST/CXX] observes local SendHttp3Datagram rejection/status abstraction.
// DEFINITION [EVENT meClientDatagramApiRejected]: Ghost observation that the client local HTTP Datagram API rejected the datagram submission.
event meClientDatagramApiRejected: tClientDatagramEvent;
// [GHOST] Source-derived bad-action witness: in BIND mode, a nullable
// GetOrCreate... result would be dereferenced by PrepareBindPacket at client
// cc:426-433. `stage` identifies which modeled source return produced null.
// DEFINITION [EVENT meBindPrepareOnNullState]: Ghost bad-action witness: BIND caller is about to dereference a null ConnectUdpClientState returned by GetOrCreateConnectUdpClientState.
event meBindPrepareOnNullState: tClientStateFailureStage;
// [GHOST/ENV] observes lower-stream early datagram drop before visitor registration.
// DEFINITION [EVENT meEarlyDatagramDropped]: Ghost observation that an HTTP Datagram arrived before the server stream had a registered CONNECT-UDP datagram visitor.
event meEarlyDatagramDropped: (connectionId: int, streamId: int, packetId: int);
// [GHOST/CXX] observes BIND datagram drop when Context ID/address mapping is absent.
// DEFINITION [EVENT meBindContextMissingDropped]: Ghost observation that a BIND datagram was dropped because its context mapping or required inline target was unavailable.
event meBindContextMissingDropped: (side: tEndpointSide, connectionId: int, streamId: int, contextId: int, packetId: int);
// [GHOST/ENV] observes unreliable HTTP Datagram loss.
// DEFINITION [EVENT meTransportDatagramLost]: Ghost observation of allowed unreliable HTTP Datagram loss in the transport environment.
event meTransportDatagramLost: (connectionId: int, streamId: int, packetId: int);

// [GHOST/CXX] observes server UDP WritePacket target cc:1080-1086.
// DEFINITION [EVENT meProxyDatagramForwardedToTarget]: Ghost observation of the exact fd/stream/target/context selected immediately before proxy UDP WritePacket.
event meProxyDatagramForwardedToTarget: tProxyForwardEvent;
// [GHOST/ENV] independent peer-side observation after UDP write.
// DEFINITION [EVENT meTargetReceivedPacket]: Independent environment observation that the chosen UDP peer received the proxy-forwarded packet.
event meTargetReceivedPacket: tProxyForwardEvent;
// [GHOST/ENV] independent reverse-reply provenance before server fd lookup.
// DEFINITION [EVENT meUdpReplyGenerated]: Independent environment provenance for a UDP reply, captured before QUICHE reverse fd/context lookup.
event meUdpReplyGenerated: tUdpReplyProvenance;
// [GHOST/CXX] observes semantic ReadPacket result at server cc:729-874.
// DEFINITION [EVENT meUdpReadableObserved]: Ghost observation of the server-readable callback after fd lookup and peer-address extraction.
event meUdpReadableObserved: tUdpObservedEvent;
// [GHOST/CXX] observes non-BIND source mismatch drop at server cc:815-820.
// DEFINITION [EVENT meUnexpectedUdpDropped]: Ghost observation that server validation rejected a UDP reply because the peer/context was unexpected.
event meUnexpectedUdpDropped: tUdpObservedEvent;
// [GHOST/CXX] observes reverse SendHttp3Datagram acceptance at server cc:836-862.
// DEFINITION [EVENT meProxyDatagramAcceptedForClient]: Ghost observation that the server selected a stream/context and accepted the reverse HTTP Datagram for client transport.
event meProxyDatagramAcceptedForClient: tProxyReturnEvent;
// [GHOST/CXX] observes client ProcessPacket call at client cc:720-722.
// DEFINITION [EVENT meClientPacketDelivered]: Ghost observation of the client ProcessPacket boundary, including decoded peer and actually delivered address.
event meClientPacketDelivered: tClientDeliveryEvent;
// [GHOST/CXX] observes invalid/missing context rejection in client/server BIND decode.
// DEFINITION [EVENT meInvalidContextDropped]: Ghost observation of invalid nonzero/unknown context-id rejection.
event meInvalidContextDropped: (side: tEndpointSide, connectionId: int, streamId: int, contextId: int, packetId: int);

// [GHOST/CXX] observes CONNECT response callback/lifecycle result.
// DEFINITION [EVENT meConnectResponseObserved]: Ghost observation of the response class delivered to the client for a CONNECT stream.
event meConnectResponseObserved: (connectionId: int, streamId: int, responseClass: tResponseClass);
// [GHOST/CXX] observes CloseConnectUdpStream client cc:483-499.
// DEFINITION [EVENT meEncapsulatedSessionClosed]: Ghost observation that the encapsulated client connection was closed because its MASQUE stream closed.
event meEncapsulatedSessionClosed: (encapsulatedSessionId: int, streamId: int);
// [GHOST/CXX] observes client OnConnectionClosed cc:537-550.
// DEFINITION [EVENT meClientConnectionClosed]: Ghost observation of client MASQUE connection teardown.
event meClientConnectionClosed;
// [GHOST/CXX] observes server OnConnectionClosed cc:183-190.
// DEFINITION [EVENT meServerConnectionClosed]: Ghost observation of server MASQUE connection teardown.
event meServerConnectionClosed;
// [GHOST/CXX] observes unknown-fd path after server lookup cc:703-727.
// DEFINITION [EVENT meUnknownSocketEvent]: Ghost observation of an event-loop fd that cannot be associated with any live CONNECT-UDP server state.
event meUnknownSocketEvent: (connectionId: int, fdId: int, packetId: int);
