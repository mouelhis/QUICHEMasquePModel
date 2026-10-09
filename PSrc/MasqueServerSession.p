// ============================================================================
// MasqueServerSession -- source-traceable P abstraction
// SOURCE SNAPSHOT: bundled under ReferenceCpp/; baseline lineage google/quiche d22f60e (2026-10-08)
// C++: quiche/quic/masque/masque_server_session.{h,cc}
// Stable source:
//   https://quiche.googlesource.com/quiche/+/d22f60e1389182a78bdeddd81c130a9161afd46d/quiche/quic/masque/masque_server_session.cc
//   https://quiche.googlesource.com/quiche/+/d22f60e1389182a78bdeddd81c130a9161afd46d/quiche/quic/masque/masque_server_session.h
// ============================================================================
// TRACEABILITY TAGS USED THROUGHOUT THIS FILE:
//   [CXX]   direct correspondence to the pinned QUICHE source block/symbol.
//   [ABS]   deliberate abstraction; comment states what is omitted and why.
//   [ENV]   environment/transport behavior outside the audited MASQUE object.
//   [GHOST] verification-only observation/provenance; never drives implementation.
//   [TEST]  finite test-harness choice with no production C++ counterpart.
//
// C++ structural correspondence:
//   MasqueServerSession is an event-loop/session object (server h:48-86).
//   ConnectUdpServerState is a passive object stored in
//   std::list<ConnectUdpServerState> (server h:256), so it is represented by a
//   tuple in `serverStates`, NOT by an independently scheduled P machine.
//
// Reverse-routing fidelity is intentionally strict: the P helper
// FindServerStateByFd performs the same linear first-match fd lookup as
// HandleConnectUdpSocketEvent cc:729-740. No artificial wrong index is injected.

// SYNCHRONY RULE FOR THIS MODEL:
//   Do NOT turn ordinary in-process C++ function calls into P request/reply messages.
//   Doing so would invent scheduler interleavings absent from the implementation.
//   Source calls whose return value immediately controls the same stack frame
//   (URI expansion, stream creation, SendRequest return, socket create/bind/register,
//   SendHttp3Datagram status, WritePacket status) are represented in the same handler.
//   A send+receive correlation loop is reserved for a genuinely synchronous interaction
//   that crosses an independently scheduled modeled component. No audited MASQUE
//   CONNECT-UDP call in this snapshot requires that pattern. See PDocs/SYNCHRONY.md.
//
machine MasqueServerSession {
    // [GHOST/CXX] Finite identity for the enclosing QUIC connection; corresponds
    // to the session connection identity used by QUICHE, not to a new protocol field.
    var connectionId: int;

    // [ENV] External boundaries, not direct C++ members in this P-machine form.
    var transport: machine;
    var udpEnvironment: machine;
    // [TEST/ENV] Finite environment choices; no production C++ member.
    var config: tModelConfig;

    // [CXX] std::list<ConnectUdpServerState> connect_udp_server_states_
    // server h:256.
    var serverStates: seq[tServerTunnelState];

    // [CXX] ConnectUdpServerState::bind_context_ip_map_ h:160-162, flattened by
    // stream. See Definitions.p representation rationale.
    var serverBindContexts: seq[tBindContextState];

    // [ENV/ABS] Environment model of OS fd allocation. FdWrapper creates an actual socket
    // at server cc:659-663, so numerical descriptor selection is external to
    // QUICHE. Fresh IDs are the default; a freed ID may be reused only when
    // allowFdReuse is explicitly enabled.
    var nextFreshFdId: int;
    var freeFdIds: seq[int];

    // [CXX] connection()->connected() check appears in reverse path cc:822-827;
    // OnConnectionClosed cc:183-190 transitions the session out of service.
    var connectionOpen: bool;

    // [ABS] P lifecycle wrapper only. It is not a C++ state enum; construction
    // of MasqueServerSession and its inherited QUIC machinery is outside scope.
    start state Init {
        entry (inputs: (connectionId: int, transport: machine, udpEnvironment: machine, config: tModelConfig)) {
            connectionId = inputs.connectionId;
            transport = inputs.transport;
            udpEnvironment = inputs.udpEnvironment;
            config = inputs.config;
            nextFreshFdId = 100;
            connectionOpen = true;
            goto Active;
        }
    }

    // [ABS] P event-dispatch wrapper for the live C++ session. Every handler
    // below names the concrete C++ callback/method whose block it abstracts.
    state Active {
        // --------------------------------------------------------------------
        // [CXX] SERVER REQUEST: HandleMasqueRequest CONNECT-UDP branch cc:413-699.
        // --------------------------------------------------------------------
        // COMMUNICATION-IN [seConnectRequest]
        //   Http3Transport/UdpEnvironment --seConnectRequest--> MasqueServerSession
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on seConnectRequest do (req: tConnectRequest) {
            var tunnelState: tServerTunnelState;
            var fdId: int;
            var isBind: bool;

            if (!connectionOpen) return;

            // [CXX] method/protocol/scheme/authority/path and URI/path validation
            // are spread through HandleMasqueRequest; target path validation is
            // cc:580-637. Finite syntax booleans preserve accept/reject class.
            if (!HeadersAccepted(req.headers)) {
                // COMMUNICATION-OUT [teConnectResponse]
                //   MasqueServerSession --teConnectResponse--> transport
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send transport, teConnectResponse,
                    (connectionId = connectionId,
                     streamId = req.streamId,
                     responseClass = RESPONSE_4XX,
                     client = req.client);
                return;
            }

            isBind = req.headers.isBind;

            // [CXX] non-BIND cc:624-637 performs DNS LookupAddress and rejects an
            // uninitialized address. BIND *:* skips DNS and uses empty address
            // cc:600-604. We abstract DNS success, not the resolved address.
            if (!isBind) {
                if (!BranchSucceeds(config)) {
                    // COMMUNICATION-OUT [teConnectResponse]
                    //   MasqueServerSession --teConnectResponse--> transport
                    //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                    //   this send represents only its later externally observable delivery, not its immediate return value.
                    send transport, teConnectResponse,
                        (connectionId = connectionId,
                         streamId = req.streamId,
                         responseClass = RESPONSE_5XX,
                         client = req.client);
                    return;
                }
            }

            // [CXX] server cc:650-657 obtains the active stream and rejects nullptr.
            if (!BranchSucceeds(config)) {
                // COMMUNICATION-OUT [teConnectResponse]
                //   MasqueServerSession --teConnectResponse--> transport
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send transport, teConnectResponse,
                    (connectionId = connectionId,
                     streamId = req.streamId,
                     responseClass = RESPONSE_5XX,
                     client = req.client);
                return;
            }

            // [CXX] cc:659-663 FdWrapper socket creation.
            if (!BranchSucceeds(config)) {
                // COMMUNICATION-OUT [teConnectResponse]
                //   MasqueServerSession --teConnectResponse--> transport
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send transport, teConnectResponse,
                    (connectionId = connectionId,
                     streamId = req.streamId,
                     responseClass = RESPONSE_5XX,
                     client = req.client);
                return;
            }

            // [CXX] cc:667-670 QuicUdpSocketApi::Bind.
            if (!BranchSucceeds(config)) {
                // COMMUNICATION-OUT [teConnectResponse]
                //   MasqueServerSession --teConnectResponse--> transport
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send transport, teConnectResponse,
                    (connectionId = connectionId,
                     streamId = req.streamId,
                     responseClass = RESPONSE_5XX,
                     client = req.client);
                return;
            }

            // [CXX] cc:671-675 event_loop_->RegisterSocket readable callback.
            if (!BranchSucceeds(config)) {
                // COMMUNICATION-OUT [teConnectResponse]
                //   MasqueServerSession --teConnectResponse--> transport
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send transport, teConnectResponse,
                    (connectionId = connectionId,
                     streamId = req.streamId,
                     responseClass = RESPONSE_5XX,
                     client = req.client);
                return;
            }

            // [ENV] OS/FdWrapper descriptor identity. Reuse is only from descriptors
            // previously destroyed by modeled state teardown; no aliasing of two
            // simultaneously live sockets is injected.
            if (config.allowFdReuse && sizeof(freeFdIds) > 0 && $) {
                fdId = freeFdIds[0];
                freeFdIds -= (0);
            } else {
                fdId = nextFreshFdId;
                nextFreshFdId = nextFreshFdId + 1;
            }

            // [CXX] cc:681-683 pushes ConnectUdpServerState only after successful
            // create/bind/register and transfers fd ownership via extract_fd().
            // Constructor cc:946-960 registers stream datagram/BIND visitors.
            tunnelState = (
                streamId = req.streamId,
                target = req.headers.target,
                fdId = fdId,
                isBind = isBind,
                datagramVisitorRegistered = true,
                socketRegistered = true
            );
            serverStates += (sizeof(serverStates), tunnelState);

            announce meServerTunnelCreated,
                (connectionId = connectionId,
                 streamId = req.streamId,
                 fdId = fdId,
                 target = req.headers.target,
                 isBind = isBind);

            // [CXX] cc:685-699 produces status 200 only after state/socket ownership
            // is established.
            // COMMUNICATION-OUT [teConnectResponse]
            //   MasqueServerSession --teConnectResponse--> transport
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send transport, teConnectResponse,
                (connectionId = connectionId,
                 streamId = req.streamId,
                 responseClass = RESPONSE_2XX,
                 client = req.client);
        }

        // --------------------------------------------------------------------
        // BIND CAPSULE CALLBACK: ConnectUdpServerState::
        // OnCompressionAssignCapsule cc:1089-1107.
        // --------------------------------------------------------------------
        // [CXX] ConnectUdpServerState::OnCompressionAssignCapsule, server cc:1089-1107;
        // applies only to an already-created BIND state selected by stream identity.
        // COMMUNICATION-IN [seBindContextAssign]
        //   Http3Transport/UdpEnvironment --seBindContextAssign--> MasqueServerSession
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on seBindContextAssign do (assign: tBindContextAssign) {
            var stateLookup: (found: bool, index: int);
            var contextLookup: (found: bool, index: int);

            stateLookup = FindServerStateByStream(serverStates, assign.streamId);
            if (!stateLookup.found) return;
            if (!serverStates[stateLookup.index].isBind) return;

            // [CXX] cc:1095-1101 rejects duplicate context and otherwise inserts
            // context_id -> ip_address_port. Ack capsule is not modeled because
            // client source deliberately uses the context pre-ACK (client cc:727-752; TODOs at 739,753-754).
            contextLookup = FindBindContextById(
                serverBindContexts, assign.streamId, assign.contextId);
            if (contextLookup.found) return;

            serverBindContexts += (sizeof(serverBindContexts),
                (streamId = assign.streamId,
                 contextId = assign.contextId,
                 target = assign.target));

            announce meBindContextAssigned, assign;
        }

        // --------------------------------------------------------------------
        // HTTP DATAGRAM CALLBACK:
        // ConnectUdpServerState::OnHttp3Datagram cc:1013-1087.
        // --------------------------------------------------------------------
        // [CXX] ConnectUdpServerState::OnHttp3Datagram, server cc:1013-1087;
        // context parsing/target selection precede the UDP WritePacket at cc:1080-1086.
        // COMMUNICATION-IN [seHttpDatagram]
        //   Http3Transport/UdpEnvironment --seHttpDatagram--> MasqueServerSession
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on seHttpDatagram do (datagram: tHttpDatagram) {
            var stateLookup: (found: bool, index: int);
            var contextLookup: (found: bool, index: int);
            var tunnelState: tServerTunnelState;
            var target: tAddress;

            // [CXX] visitor registration binds callback to state/stream. Explicit
            // stream lookup is the finite-model equivalent.
            stateLookup = FindServerStateByStream(serverStates, datagram.streamId);
            if (!stateLookup.found) {
                // Possible only because HTTP Datagrams can race request/state
                // creation in the environment abstraction.
                announce meEarlyDatagramDropped,
                    (connectionId = connectionId,
                     streamId = datagram.streamId,
                     packetId = datagram.packet.id);
                return;
            }
            tunnelState = serverStates[stateLookup.index];

            if (!tunnelState.isBind) {
                // [CXX] cc:1021-1030 reads context and rejects nonzero for non-BIND.
                if (datagram.contextId != 0) {
                    announce meInvalidContextDropped,
                        (side = SIDE_SERVER,
                         connectionId = connectionId,
                         streamId = datagram.streamId,
                         contextId = datagram.contextId,
                         packetId = datagram.packet.id);
                    return;
                }
                // [CXX] cc:1041-1043 target_address = target_server_address_.
                target = tunnelState.target;
            } else {
                // [CXX] cc:1031-1040 resolves the context map entry. When that
                // entry is default/empty, cc:1044-1078 parses IP+port embedded
                // in the datagram; otherwise the mapped address is the target.
                contextLookup = FindBindContextById(
                    serverBindContexts, datagram.streamId, datagram.contextId);
                if (!contextLookup.found) {
                    announce meBindContextMissingDropped,
                        (side = SIDE_SERVER,
                         connectionId = connectionId,
                         streamId = datagram.streamId,
                         contextId = datagram.contextId,
                         packetId = datagram.packet.id);
                    return;
                }
                if (IsEmptyAddress(serverBindContexts[contextLookup.index].target)) {
                    if (!datagram.hasInlineTarget) {
                        announce meBindContextMissingDropped,
                            (side = SIDE_SERVER,
                             connectionId = connectionId,
                             streamId = datagram.streamId,
                             contextId = datagram.contextId,
                             packetId = datagram.packet.id);
                        return;
                    }
                    target = datagram.inlineTarget;
                } else {
                    target = serverBindContexts[contextLookup.index].target;
                }
            }

            // [CXX] cc:1080-1086 obtains remaining payload and WritePacket(fd_,
            // ..., peer=target_address). Announcement is ghost observation of
            // exactly that association before the environment write.
            announce meProxyDatagramForwardedToTarget,
                (connectionId = connectionId,
                 streamId = tunnelState.streamId,
                 fdId = tunnelState.fdId,
                 target = target,
                 isBind = tunnelState.isBind,
                 contextId = datagram.contextId,
                 packetId = datagram.packet.id);

            // COMMUNICATION-OUT [ueProxyWrite]
            //   MasqueServerSession --ueProxyWrite--> udpEnvironment
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send udpEnvironment, ueProxyWrite,
                (connectionId = connectionId,
                 streamId = tunnelState.streamId,
                 fdId = tunnelState.fdId,
                 target = target,
                 isBind = tunnelState.isBind,
                 contextId = datagram.contextId,
                 packet = datagram.packet,
                 server = this);
        }

        // --------------------------------------------------------------------
        // SOCKET CALLBACK: OnSocketEvent server cc:703-727 then
        // HandleConnectUdpSocketEvent cc:729-874.
        // --------------------------------------------------------------------
        // [CXX] MasqueServerSession::OnSocketEvent server cc:703-727 followed by
        // HandleConnectUdpSocketEvent cc:729-874. fd lookup is exactly cc:731-740.
        // COMMUNICATION-IN [seUdpReadable]
        //   Http3Transport/UdpEnvironment --seUdpReadable--> MasqueServerSession
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on seUdpReadable do (udp: tUdpReadable) {
            var stateLookup: (found: bool, index: int);
            var contextLookup: (found: bool, index: int);
            var tunnelState: tServerTunnelState;
            var datagram: tHttpDatagram;
            var contextId: int;
            var expectedTarget: tAddress;
            var hasInlineTarget: bool;
            var inlineTarget: tAddress;
            var uncompressedLookup: (found: bool, index: int);

            // [CXX] EXACT fd lookup cc:731-740; no injected mutation.
            stateLookup = FindServerStateByFd(serverStates, udp.fdId);
            if (!stateLookup.found) {
                // Corresponds to HandleConnectUdpSocketEvent returning false;
                // OnSocketEvent then tries other tunnel types and ultimately
                // reports unknown fd at cc:723-727.
                announce meUnknownSocketEvent,
                    (connectionId = connectionId,
                     fdId = udp.fdId,
                     packetId = udp.packet.id);
                return;
            }
            tunnelState = serverStates[stateLookup.index];
            hasInlineTarget = false;
            inlineTarget = EmptyAddress();

            if (!tunnelState.isBind) {
                // [CXX] cc:739-748 obtains expected target from selected state;
                // cc:782-784 obtains normalized peer address; cc:815-820 drops
                // peer != expected target.
                expectedTarget = tunnelState.target;
                contextId = 0;

                announce meUdpReadableObserved,
                    (connectionId = connectionId,
                     fdId = udp.fdId,
                     source = udp.source,
                     expectedTarget = expectedTarget,
                     packetId = udp.packet.id);

                if (udp.source != expectedTarget) {
                    announce meUnexpectedUdpDropped,
                        (connectionId = connectionId,
                         fdId = udp.fdId,
                         source = udp.source,
                         expectedTarget = expectedTarget,
                         packetId = udp.packet.id);
                    return;
                }
            } else {
                // [CXX] BIND reverse path cc:788-818 first searches for an exact
                // compressed mapping and simultaneously remembers an open
                // (empty-address) context. Exact match wins; otherwise the open
                // context carries the peer address inline. Without either,
                // cc:805-813 drops the UDP packet.
                contextLookup = FindBindContextByTarget(
                    serverBindContexts, tunnelState.streamId, udp.source);
                hasInlineTarget = false;
                inlineTarget = EmptyAddress();

                if (contextLookup.found) {
                    contextId =
                        serverBindContexts[contextLookup.index].contextId;
                    expectedTarget =
                        serverBindContexts[contextLookup.index].target;
                } else {
                    uncompressedLookup = FindUncompressedBindContext(
                        serverBindContexts, tunnelState.streamId);
                    if (!uncompressedLookup.found) {
                        announce meUnexpectedUdpDropped,
                            (connectionId = connectionId,
                             fdId = udp.fdId,
                             source = udp.source,
                             expectedTarget = EmptyAddress(),
                             packetId = udp.packet.id);
                        return;
                    }
                    contextId =
                        serverBindContexts[uncompressedLookup.index].contextId;
                    expectedTarget = udp.source;
                    hasInlineTarget = true;
                    inlineTarget = udp.source;
                }

                announce meUdpReadableObserved,
                    (connectionId = connectionId,
                     fdId = udp.fdId,
                     source = udp.source,
                     expectedTarget = expectedTarget,
                     packetId = udp.packet.id);
            }

            // [CXX] cc:822-827 refuses reverse forwarding once QUIC connection is
            // closed. We model that as a silent return plus no acceptance event.
            if (!connectionOpen) return;

            // [CXX] non-BIND writes Context ID 0 at cc:852-856; BIND writes selected
            // bind context/header at cc:836-856; then SendHttp3Datagram cc:862-868.
            datagram = (
                connectionId = connectionId,
                streamId = tunnelState.streamId,
                contextId = contextId,
                hasInlineTarget = hasInlineTarget,
                inlineTarget = inlineTarget,
                packet = udp.packet
            );

            if (DatagramAcceptedLocally(config)) {
                announce meProxyDatagramAcceptedForClient,
                    (connectionId = connectionId,
                     streamId = tunnelState.streamId,
                     fdId = tunnelState.fdId,
                     expectedTarget = expectedTarget,
                     isBind = tunnelState.isBind,
                     contextId = contextId,
                     packetId = udp.packet.id);
                // COMMUNICATION-OUT [teServerDatagram]
                //   MasqueServerSession --teServerDatagram--> transport
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send transport, teServerDatagram, datagram;
            }
        }

        // --------------------------------------------------------------------
        // CALLBACK: OnStreamClosed cc:196-210. CONNECT-UDP remove_if is
        // cc:192-196 and invokes ConnectUdpServerState destructor cc:962-978.
        // --------------------------------------------------------------------
        // [CXX] MasqueServerSession::OnStreamClosed, server cc:196-210;
        // CONNECT-UDP state erase/remove_if is cc:192-196.
        // COMMUNICATION-IN [seStreamClosed]
        //   Http3Transport/UdpEnvironment --seStreamClosed--> MasqueServerSession
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on seStreamClosed do (streamId: int) {
            var i: int;
            var j: int;
            var removed: tServerTunnelState;

            i = 0;
            while (i < sizeof(serverStates)) {
                if (serverStates[i].streamId == streamId) {
                    removed = serverStates[i];
                    serverStates -= (i);

                    // [CXX] destructor sequence cc:962-978 unregisters visitors,
                    // event-loop socket, then destroys fd. We collapse the
                    // synchronous destructor stack into this atomic transition.
                    announce meServerTunnelRemoved,
                        (connectionId = connectionId,
                         streamId = removed.streamId,
                         fdId = removed.fdId,
                         target = removed.target,
                         isBind = removed.isBind);

                    j = 0;
                    while (j < sizeof(serverBindContexts)) {
                        if (serverBindContexts[j].streamId == streamId) {
                            serverBindContexts -= (j);
                        } else {
                            j = j + 1;
                        }
                    }

                    // [ENV] OS may subsequently reuse a destroyed descriptor. Reuse
                    // never occurs while this state remains live.
                    if (config.allowFdReuse) {
                        freeFdIds += (sizeof(freeFdIds), removed.fdId);
                    }
                } else {
                    i = i + 1;
                }
            }
        }

        // --------------------------------------------------------------------
        // CALLBACK: OnConnectionClosed cc:183-190.
        // --------------------------------------------------------------------
        // [CXX] MasqueServerSession::OnConnectionClosed, server cc:183-190;
        // cc:192-193 clears CONNECT-UDP state, invoking per-state destruction.
        // COMMUNICATION-IN [seConnectionClosed]
        //   Http3Transport/UdpEnvironment --seConnectionClosed--> MasqueServerSession
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on seConnectionClosed do {
            var removed: tServerTunnelState;

            connectionOpen = false;

            // [CXX] cc:192-193 explicitly states clearing this list closes all
            // sockets. Each list element destructor performs unregister/destroy.
            while (sizeof(serverStates) > 0) {
                removed = serverStates[0];
                serverStates -= (0);

                announce meServerTunnelRemoved,
                    (connectionId = connectionId,
                     streamId = removed.streamId,
                     fdId = removed.fdId,
                     target = removed.target,
                     isBind = removed.isBind);
            }

            // Object-local context maps disappear with their owning state.
            while (sizeof(serverBindContexts) > 0) {
                serverBindContexts -= (0);
            }

            assert sizeof(serverStates) == 0,
                "Server CONNECT-UDP state survived MASQUE connection close";
            announce meServerConnectionClosed;
        }
    }
}
