// ============================================================================
// MasqueClientSession -- source-traceable P abstraction
// SOURCE SNAPSHOT: bundled under ReferenceCpp/; baseline lineage google/quiche d22f60e (2026-10-08)
// C++: quiche/quic/masque/masque_client_session.{h,cc}
// Stable source:
//   https://quiche.googlesource.com/quiche/+/d22f60e1389182a78bdeddd81c130a9161afd46d/quiche/quic/masque/masque_client_session.cc
//   https://quiche.googlesource.com/quiche/+/d22f60e1389182a78bdeddd81c130a9161afd46d/quiche/quic/masque/masque_client_session.h
// ============================================================================
// TRACEABILITY TAGS USED THROUGHOUT THIS FILE:
//   [CXX]   direct correspondence to the pinned QUICHE source block/symbol.
//   [ABS]   deliberate abstraction; comment states what is omitted and why.
//   [ENV]   environment/transport behavior outside the audited MASQUE object.
//   [GHOST] verification-only observation/provenance; never drives implementation.
//   [TEST]  finite test-harness choice with no production C++ counterpart.
//
// Modeling principle:
//   MasqueClientSession is schedulable because its public calls/callbacks can
//   interleave with transport callbacks. ConnectUdpClientState is NOT a P
//   machine: C++ stores passive objects in std::list<ConnectUdpClientState>
//   (header line 408). We therefore keep them in `clientStates`.
//
// Important current-source observation preserved exactly in the BIND return
// path: OnHttp3Datagram computes a local `target_address` (cc:674-718) but calls
// ProcessPacket(..., target_server_address_) (client cc:720-722). The P model does not
// repair or mutate this behavior; it exposes both decoded and delivered targets
// to an independent temporal property. See PSpec/BindTargetFidelity.p.

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
machine MasqueClientSession {
    // [GHOST] session connection identity; C++ connection_id() is the source identity. QUICHE uses connection_id() for logs;
    // the integer is a finite ghost key so monitors can distinguish sessions.
    var connectionId: int;

    // [ENV] abstract HTTP/3/QUIC boundary; not a C++ field correspondence.
    var transport: machine;

    // [TEST] scenario controls, not a C++ field.
    var config: tModelConfig;

    // [CXX] std::list<ConnectUdpClientState> connect_udp_client_states_
    // client header:408. Sequence preserves iteration order and erase semantics.
    var clientStates: seq[tClientTunnelState];

    // [CXX] ConnectUdpClientState::bind_context_ip_map_ client h:284-285.
    // Representation abstraction: flattened by stream; see Definitions.p.
    var clientBindContexts: seq[tBindContextState];

    // [ABS] QUIC allocates client-initiated bidirectional stream IDs.
    // We model only uniqueness/progression (0,4,8,...) because stream-number
    // identity, not QUIC stream allocator internals, is checked here.
    var nextStreamId: int;

    // [CXX] connection()->connected() / OnConnectionClosed lifecycle abstraction.
    var connectionOpen: bool;

    // [ABS] P lifecycle wrapper only. C++ has no `Init` enum/state; construction
    // of the actual MasqueClientSession occurs outside this focused model. This
    // state installs finite boundary references, then the object is treated live.
    start state Init {
        entry (inputs: (connectionId: int, transport: machine, config: tModelConfig)) {
            // MODEL bootstrap only.
            connectionId = inputs.connectionId;
            transport = inputs.transport;
            config = inputs.config;
            nextStreamId = 0;
            connectionOpen = true;
            goto Active;
        }
    }

    // [ABS] P event-dispatch wrapper for the lifetime of the C++ session object;
    // each handler below maps to a concrete public method or callback.
    state Active {
        // --------------------------------------------------------------------
        // [CXX] API: CONNECT-UDP SendPacket cc:441-469
        // [CXX] API: CONNECT-UDP-BIND SendConnectUdpBindPacket cc:422-439
        // [CXX] Shared state creation: GetOrCreateConnectUdpClientState cc:99-233
        // --------------------------------------------------------------------
        // COMMUNICATION-IN [ceSendPacket]
        //   Http3Transport/TestDriver --ceSendPacket--> MasqueClientSession
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on ceSendPacket do (req: tClientSendRequest) {
            var isBind: bool;
            var found: bool;
            var index: int;
            var lookup: (found: bool, index: int);
            var streamId: int;
            var stateTarget: tAddress;
            var tunnelState: tClientTunnelState;
            var datagram: tHttpDatagram;
            var monitorDatagram: tClientDatagramEvent;
            var contextLookup: (found: bool, index: int);
            var contextId: int;
            var contextCount: int;
            var contextMappedTarget: tAddress;
            var hasInlineTarget: bool;
            var inlineTarget: tAddress;
            var i: int;

            // [ABS] calls after connection close are outside normal
            // successful API operation. This guard prevents model-only sends.
            if (!connectionOpen) return;

            // [CXX] MasqueClientSession::IsBind() client h:397; public APIs are
            // SendPacket client cc:441-469 and SendConnectUdpBindPacket cc:422-439.
            isBind = config.udpMode == MODE_CONNECT_UDP_BIND;

            // [CXX] SendConnectUdpBindPacket passes default QuicSocketAddress()
            // into GetOrCreate... at client cc:430-431; SendPacket passes the
            // concrete requested target at cc:448-449. Preserve that exact lookup
            // key instead of special-casing comparison inside the helper.
            if (isBind) stateTarget = EmptyAddress();
            else stateTarget = req.target;

            // [CXX] GetOrCreate... loops the list and compares stored target,
            // encapsulated session pointer, and IsBind()==state.is_bind()
            // exactly at client cc:102-110.
            lookup = FindClientState(
                clientStates,
                req.encapsulatedSessionId,
                stateTarget,
                isBind);
            found = lookup.found;
            index = lookup.index;

            if (!found) {
                // [CXX] cc:131-190: URI parse/template expansion/canonicalization
                // can return nullptr. One nondet success bit abstracts this whole
                // pure-string family because exact bytes do not affect tunnel
                // identity after target has been decoded.
                if (!BranchSucceeds(config)) {
                    // [CXX] GetOrCreate... returns nullptr from URI/template setup
                    // at client cc:131-190. SendPacket checks nullptr at 450-452,
                    // but SendConnectUdpBindPacket immediately dereferences the
                    // result at 430-433. [GHOST] records that bad action; returning
                    // here is the finite terminal abstraction of the ensuing C++
                    // null dereference/crash, not a repair of source behavior.
                    if (isBind) announce meBindPrepareOnNullState,
                        CLIENT_STATE_FAIL_URI_SETUP;
                    return;
                }

                // [CXX] cc:191-196: CreateOutgoingBidirectionalStream can fail due
                // to stream/flow-control limits.
                if (!BranchSucceeds(config)) {
                    // [CXX] client cc:191-196 returns nullptr when stream creation
                    // is blocked (the source explicitly cites flow-control limits).
                    // BIND caller cc:426-433 has no nullptr guard.
                    if (isBind) announce meBindPrepareOnNullState,
                        CLIENT_STATE_FAIL_STREAM_CREATE;
                    return;
                }

                streamId = nextStreamId;
                nextStreamId = nextStreamId + 4;

                // `stateTarget` already holds the exact GetOrCreate argument.

                // [CXX] cc:207-224 constructs headers and calls stream->SendRequest
                // BEFORE cc:230-236 inserts ConnectUdpClientState.
                // Failure (bytes_sent==0 at cc:219-224) leaves no client state.
                if (!BranchSucceeds(config)) {
                    // [CXX] client cc:219-224 returns nullptr when SendRequest
                    // reports zero bytes. BIND caller cc:426-433 then dereferences
                    // the null pointer; non-BIND caller guards it at cc:446-449.
                    if (isBind) announce meBindPrepareOnNullState,
                        CLIENT_STATE_FAIL_REQUEST_SEND;
                    return;
                }

                // COMMUNICATION-OUT [teConnectRequest]
                //   MasqueClientSession --teConnectRequest--> transport
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send transport, teConnectRequest,
                    (connectionId = connectionId,
                     streamId = streamId,
                     headers = MakeConnectHeaders(stateTarget, isBind),
                     client = this);

                // [CXX] cc:226-232 list push; constructor cc:609-623 registers the
                // HTTP Datagram visitor (and BIND visitor when applicable).
                tunnelState = (
                    streamId = streamId,
                    encapsulatedSessionId = req.encapsulatedSessionId,
                    target = stateTarget,
                    isBind = isBind,
                    datagramVisitorRegistered = true
                );
                clientStates += (sizeof(clientStates), tunnelState);
                index = sizeof(clientStates) - 1;

                announce meClientTunnelCreated,
                    (connectionId = connectionId,
                     streamId = streamId,
                     encapsulatedSessionId = req.encapsulatedSessionId,
                     target = stateTarget,
                     isBind = isBind);
            }

            // [CXX] CONNECT-UDP SendPacket cc:455-460 writes Context ID 0 then
            // immediately calls SendHttp3Datagram; it does NOT wait for 2xx.
            hasInlineTarget = false;
            inlineTarget = EmptyAddress();

            if (!isBind) {
                contextId = 0;
            } else {
                // [CXX] BIND PrepareBindPacket cc:843-896 calls
                // GetContextForAddress cc:827-843. That helper prefers an exact
                // compressed mapping and otherwise reuses an open/uncompressed
                // context (map value == default QuicSocketAddress).
                contextLookup = FindBindContextForSend(
                    clientBindContexts,
                    clientStates[index].streamId,
                    req.target);

                if (contextLookup.found) {
                    contextId = clientBindContexts[contextLookup.index].contextId;
                    contextMappedTarget =
                        clientBindContexts[contextLookup.index].target;
                } else {
                    // [CXX] next_available_context_id_ starts at 2 (h:284) and
                    // AllocateContextId adds 2 (cc:754-757). Context-close
                    // behavior is modeled separately from allocation in this
                    // bounded harness; existing live entries determine 2,4,6...
                    contextCount = 0;
                    i = 0;
                    while (i < sizeof(clientBindContexts)) {
                        if (clientBindContexts[i].streamId ==
                            clientStates[index].streamId) {
                            contextCount = contextCount + 1;
                        }
                        i = i + 1;
                    }
                    contextId = 2 + (2 * contextCount);

                    // [CXX] PrepareBindPacket chooses CreateUncompressedContext
                    // or CreateCompressedContext at cc:851-858 based on
                    // bind_use_uncompressed_context_ (client h:154-162,409).
                    if (config.bindUseUncompressedContext) {
                        contextMappedTarget = EmptyAddress();
                    } else {
                        contextMappedTarget = req.target;
                    }

                    clientBindContexts += (sizeof(clientBindContexts),
                        (streamId = clientStates[index].streamId,
                         contextId = contextId,
                         target = contextMappedTarget));

                    // [CXX] CreateCompressedContext cc:731-740 or
                    // CreateUncompressedContext cc:740-752 emits a
                    // CompressionAssign capsule and uses the context pre-ack.
                    // COMMUNICATION-OUT [teBindContextAssign]
                    //   MasqueClientSession --teBindContextAssign--> transport
                    //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                    //   this send represents only its later externally observable delivery, not its immediate return value.
                    send transport, teBindContextAssign,
                        (connectionId = connectionId,
                         streamId = clientStates[index].streamId,
                         contextId = contextId,
                         target = contextMappedTarget);
                }

                // [CXX] PrepareBindPacket cc:858-896:
                // exact mapped target -> compressed payload;
                // empty mapped target -> append IP-version/address/port.
                if (IsEmptyAddress(contextMappedTarget)) {
                    hasInlineTarget = true;
                    inlineTarget = req.target;
                }
            }

            datagram = (
                connectionId = connectionId,
                streamId = clientStates[index].streamId,
                contextId = contextId,
                hasInlineTarget = hasInlineTarget,
                inlineTarget = inlineTarget,
                packet = req.packet
            );

            monitorDatagram = (
                connectionId = connectionId,
                streamId = clientStates[index].streamId,
                encapsulatedSessionId = clientStates[index].encapsulatedSessionId,
                target = req.target,
                isBind = isBind,
                contextId = contextId,
                packetId = req.packet.id
            );

            // [CXX] SendHttp3Datagram returns DatagramStatus (SendPacket cc:459-469; BIND call cc:442). We preserve accepted/rejected partition,
            // but not enum detail because routing properties observe only
            // datagrams that the local session accepted for transmission.
            if (DatagramAcceptedLocally(config)) {
                announce meClientDatagramApiAccepted, monitorDatagram;
                // COMMUNICATION-OUT [teClientDatagram]
                //   MasqueClientSession --teClientDatagram--> transport
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send transport, teClientDatagram, datagram;
            } else {
                announce meClientDatagramApiRejected, monitorDatagram;
            }
        }

        // CONNECT response is deliberately observation-only for data sending:
        // SendPacket/SendConnectUdpBindPacket can issue HTTP Datagrams without
        // waiting for a successful response (current source path above).
        // [CXX] Callback corresponding to CONNECT response processing for the stream;
        // client response/lifecycle path around masque_client_session.cc:238-263.
        // COMMUNICATION-IN [ceConnectResponse]
        //   Http3Transport/TestDriver --ceConnectResponse--> MasqueClientSession
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on ceConnectResponse do (response: tConnectResponse) {
            announce meConnectResponseObserved,
                (connectionId = response.connectionId,
                 streamId = response.streamId,
                 responseClass = response.responseClass);
        }

        // --------------------------------------------------------------------
        // CALLBACK: ConnectUdpClientState::OnHttp3Datagram cc:658-725
        // --------------------------------------------------------------------
        // [CXX] ConnectUdpClientState::OnHttp3Datagram, client cc:658-725.
        // BIND context decoding is cc:674-718; final ProcessPacket call is cc:720-722.
        // COMMUNICATION-IN [ceHttpDatagram]
        //   Http3Transport/TestDriver --ceHttpDatagram--> MasqueClientSession
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on ceHttpDatagram do (datagram: tHttpDatagram) {
            var lookup: (found: bool, index: int);
            var index: int;
            var contextLookup: (found: bool, index: int);
            var decodedTarget: tAddress;
            var deliveredTarget: tAddress;

            // [CXX] dispatch is via stream's registered Http3DatagramVisitor
            // (constructor cc:619). We explicitly resolve the owning passive
            // state by stream ID.
            lookup = FindClientStateByStream(clientStates, datagram.streamId);
            if (!lookup.found) return;
            index = lookup.index;

            if (!clientStates[index].isBind) {
                // [CXX] cc:663-673: parse Context ID and drop if non-zero.
                if (datagram.contextId != 0) {
                    announce meInvalidContextDropped,
                        (side = SIDE_CLIENT,
                         connectionId = connectionId,
                         streamId = datagram.streamId,
                         contextId = datagram.contextId,
                         packetId = datagram.packet.id);
                    return;
                }
                decodedTarget = clientStates[index].target;
            } else {
                // [CXX] cc:674-718: read Context ID; reject unknown context.
                // If map value is empty, cc:688-714 parses the inline
                // IP-version/address/port. Otherwise cc:715-716 uses the mapped
                // compressed target. `hasInlineTarget/inlineTarget` is the
                // semantic replacement for those serialized address bytes.
                contextLookup = FindBindContextById(
                    clientBindContexts,
                    datagram.streamId,
                    datagram.contextId);
                if (!contextLookup.found) {
                    announce meBindContextMissingDropped,
                        (side = SIDE_CLIENT,
                         connectionId = connectionId,
                         streamId = datagram.streamId,
                         contextId = datagram.contextId,
                         packetId = datagram.packet.id);
                    return;
                }
                if (IsEmptyAddress(clientBindContexts[contextLookup.index].target)) {
                    if (!datagram.hasInlineTarget) {
                        announce meBindContextMissingDropped,
                            (side = SIDE_CLIENT,
                             connectionId = connectionId,
                             streamId = datagram.streamId,
                             contextId = datagram.contextId,
                             packetId = datagram.packet.id);
                        return;
                    }
                    decodedTarget = datagram.inlineTarget;
                } else {
                    decodedTarget =
                        clientBindContexts[contextLookup.index].target;
                }
            }

            // [CXX] EXACT CURRENT C++ DATA FLOW:
            //   cc:720  http_payload = reader.ReadRemainingPayload();
            //   cc:721-722 ProcessPacket(http_payload, target_server_address_)
            // The local `target_address` decoded above is NOT passed. For a BIND
            // state target_server_address_ was initialized from the empty address
            // passed at cc:426-433. We preserve that behavior, without mutation.
            deliveredTarget = clientStates[index].target;

            announce meClientPacketDelivered,
                (connectionId = connectionId,
                 streamId = datagram.streamId,
                 encapsulatedSessionId = clientStates[index].encapsulatedSessionId,
                 isBind = clientStates[index].isBind,
                 decodedTarget = decodedTarget,
                 deliveredTarget = deliveredTarget,
                 contextId = datagram.contextId,
                 packetId = datagram.packet.id);
        }

        // --------------------------------------------------------------------
        // CALLBACK: MasqueClientSession::OnStreamClosed cc:552-593
        // CONNECT-UDP list erase specifically cc:563-577.
        // --------------------------------------------------------------------
        // [CXX] MasqueClientSession::OnStreamClosed, client cc:552-593;
        // CONNECT-UDP state erasure is cc:563-577.
        // COMMUNICATION-IN [ceStreamClosed]
        //   Http3Transport/TestDriver --ceStreamClosed--> MasqueClientSession
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on ceStreamClosed do (streamId: int) {
            var i: int;
            var removed: tClientTunnelState;
            var j: int;

            i = 0;
            while (i < sizeof(clientStates)) {
                if (clientStates[i].streamId == streamId) {
                    removed = clientStates[i];
                    // [CXX] list erase destroys state; dtor cc:625-632 unregisters
                    // stream visitors. Atomicity is appropriate because the C++
                    // erase/destructor executes in one callback stack frame.
                    clientStates -= (i);

                    announce meClientTunnelRemoved,
                        (connectionId = connectionId,
                         streamId = removed.streamId,
                         encapsulatedSessionId = removed.encapsulatedSessionId,
                         target = removed.target,
                         isBind = removed.isBind);

                    // Representation cleanup for object-local bind map.
                    j = 0;
                    while (j < sizeof(clientBindContexts)) {
                        if (clientBindContexts[j].streamId == streamId) {
                            clientBindContexts -= (j);
                        } else {
                            j = j + 1;
                        }
                    }

                    // [CXX] cc:568-573 closes the encapsulated client connection
                    // after erasing state.
                    announce meEncapsulatedSessionClosed,
                        (encapsulatedSessionId = removed.encapsulatedSessionId,
                         streamId = removed.streamId);
                } else {
                    i = i + 1;
                }
            }
        }

        // --------------------------------------------------------------------
        // API: CloseConnectUdpStream cc:483-499
        // --------------------------------------------------------------------
        // [CXX] MasqueClientSession::CloseConnectUdpStream, client cc:483-499;
        // this handler models the encapsulated-session-triggered stream reset/removal path.
        // COMMUNICATION-IN [ceCloseEncapsulatedSession]
        //   Http3Transport/TestDriver --ceCloseEncapsulatedSession--> MasqueClientSession
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on ceCloseEncapsulatedSession do (encapsulatedSessionId: int) {
            var i: int;
            var j: int;
            var removed: tClientTunnelState;

            i = 0;
            while (i < sizeof(clientStates)) {
                if (clientStates[i].encapsulatedSessionId == encapsulatedSessionId) {
                    removed = clientStates[i];
                    // [CXX] cc:490-493 saves stream pointer then erases state
                    // BEFORE testing write_side_closed()/Reset.
                    clientStates -= (i);

                    announce meClientTunnelRemoved,
                        (connectionId = connectionId,
                         streamId = removed.streamId,
                         encapsulatedSessionId = removed.encapsulatedSessionId,
                         target = removed.target,
                         isBind = removed.isBind);

                    j = 0;
                    while (j < sizeof(clientBindContexts)) {
                        if (clientBindContexts[j].streamId == removed.streamId) {
                            clientBindContexts -= (j);
                        } else {
                            j = j + 1;
                        }
                    }

                    // [CXX] cc:496-498 resets only if write side is still open.
                    // We conservatively send a reset callback; a duplicate close
                    // finds no state and is harmless in this model.
                    // COMMUNICATION-OUT [teResetStream]
                    //   MasqueClientSession --teResetStream--> transport
                    //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                    //   this send represents only its later externally observable delivery, not its immediate return value.
                    send transport, teResetStream, removed.streamId;
                } else {
                    i = i + 1;
                }
            }
        }

        // --------------------------------------------------------------------
        // CALLBACK: OnConnectionClosed cc:537-550.
        // --------------------------------------------------------------------
        // [CXX] MasqueClientSession::OnConnectionClosed, client cc:537-550.
        // The owned CONNECT-UDP state list is synchronously destroyed with the session lifecycle.
        // COMMUNICATION-IN [ceConnectionClosed]
        //   Http3Transport/TestDriver --ceConnectionClosed--> MasqueClientSession
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on ceConnectionClosed do {
            var i: int;

            connectionOpen = false;

            // [CXX] cc:543 calls base, then cc:544-549 closes all encapsulated
            // CONNECT-UDP sessions. This method does NOT explicitly erase the
            // CONNECT-UDP list; do not invent such erasure here.
            i = 0;
            while (i < sizeof(clientStates)) {
                announce meEncapsulatedSessionClosed,
                    (encapsulatedSessionId = clientStates[i].encapsulatedSessionId,
                     streamId = clientStates[i].streamId);
                i = i + 1;
            }
            announce meClientConnectionClosed;
        }
    }
}
