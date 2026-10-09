// ============================================================================
// HTTP/3/QUIC environment abstraction
// UPSTREAM PIN used for boundary references:
// google/quiche @ d22f60e1389182a78bdeddd81c130a9161afd46d
// ============================================================================
// TRACEABILITY TAGS USED THROUGHOUT THIS FILE:
//   [CXX]   direct correspondence to the pinned QUICHE source block/symbol.
//   [ABS]   deliberate abstraction; comment states what is omitted and why.
//   [ENV]   environment/transport behavior outside the audited MASQUE object.
//   [GHOST] verification-only observation/provenance; never drives implementation.
//   [TEST]  finite test-harness choice with no production C++ counterpart.
//
// THIS MACHINE IS NOT A MODEL OF QUIC INTERNALS.
// It exists because the audited C++ methods call into stream/HTTP-Datagram APIs
// whose scheduling/loss behavior is outside MasqueClientSession/ServerSession.
//
// Source boundary facts preserved:
//   * Client SendRequest is invoked before state insertion: client cc:207-233.
//   * Client SendPacket invokes SendHttp3Datagram immediately: cc:455-460.
//   * BIND CreateCompressedContext writes a capsule and uses the context before
//     acknowledgement: cc:731-740; datagram send follows in cc:422-439.
//   * HTTP Datagrams are not modeled as reliable transport.
//
// Abstraction rationale: properties concern association/lifecycle, so transport
// packetization, ACKs, congestion control, and crypto are irrelevant. We retain
// only ordering/loss choices capable of changing those associations.

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
machine Http3Transport {
    // [ENV] Endpoint references used only to deliver abstract QUIC/HTTP3 outcomes.
    var client: machine;
    var server: machine;
    // [TEST] Harness readiness callback target; no QUICHE field counterpart.
    var driver: machine;
    // [TEST/ENV] Finite admissible transport outcomes; no QUICHE field counterpart.
    var config: tModelConfig;

    // [ENV/ABS] Pending reliable operations used only to expose legal cross-channel
    // reordering. They are not claimed to correspond to QUIC internal queue fields.
    var pendingConnects: seq[tConnectRequest];
    var pendingBindContexts: seq[tBindContextAssign];
    // [TEST/ENV] Bounds scenario-specific close injection after the first datagram.
    var firstClientDatagramSeen: bool;

    // [ENV] P-only environment lifecycle; no QUICHE class/state correspondence.
    start state Init {
        entry { firstClientDatagramSeen = false; }

        // COMMUNICATION-IN [eConfigureTransport]
        //   TestDriver --eConfigureTransport--> Http3Transport
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on eConfigureTransport goto Active with (inputs: (client: machine, server: machine, driver: machine, config: tModelConfig)) {
            client = inputs.client;
            server = inputs.server;
            driver = inputs.driver;
            config = inputs.config;
            // COMMUNICATION-OUT [eTransportReady]
            //   Http3Transport --eTransportReady--> driver
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send driver, eTransportReady;
        }
    }

    // [ENV] P-only dispatcher for external HTTP/3/QUIC outcomes.
    state Active {
        // [CXX] Boundary: stream->SendRequest from client cc:223-224.
        // COMMUNICATION-IN [teConnectRequest]
        //   MasqueClientSession/MasqueServerSession --teConnectRequest--> Http3Transport
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on teConnectRequest do (request: tConnectRequest) {
            if (config.allowDatagramBeforeRequest && $) {
                // Over-approximation of cross-channel observation: hold request
                // while a later HTTP Datagram may become observable first.
                pendingConnects += (sizeof(pendingConnects), request);
                // COMMUNICATION-OUT [teFlushPendingConnects]
                //   Http3Transport --teFlushPendingConnects--> this
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send this, teFlushPendingConnects;
            } else {
                // COMMUNICATION-OUT [seConnectRequest]
                //   Http3Transport --seConnectRequest--> server
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send server, seConnectRequest, request;
            }
        }

        // Boundary: stream->WriteCapsule from client CreateCompressedContext
        // cc:731-740. Stream order is reliable, but HTTP Datagram delivery is a
        // different channel; optional holding exposes that cross-channel race.
        // [ENV] Models reliable delivery/possible scheduling of a BIND context-assignment
        // capsule between client/server visitors; this is not a MASQUE session C++ state.
        // COMMUNICATION-IN [teBindContextAssign]
        //   MasqueClientSession/MasqueServerSession --teBindContextAssign--> Http3Transport
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on teBindContextAssign do (assign: tBindContextAssign) {
            if (config.allowBindContextDatagramReordering && $) {
                pendingBindContexts += (sizeof(pendingBindContexts), assign);
                // COMMUNICATION-OUT [teFlushPendingBindContexts]
                //   Http3Transport --teFlushPendingBindContexts--> this
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send this, teFlushPendingBindContexts;
            } else {
                // COMMUNICATION-OUT [seBindContextAssign]
                //   Http3Transport --seBindContextAssign--> server
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send server, seBindContextAssign, assign;
            }
        }

        // Boundary: SendHttp3Datagram from client cc:459-460 / BIND cc:442.
        // [ENV] Models HTTP/3 Datagram transport after client SendHttp3Datagram.
        // Loss is admissible because HTTP Datagrams are unreliable; visitor existence is preserved.
        // COMMUNICATION-IN [teClientDatagram]
        //   MasqueClientSession/MasqueServerSession --teClientDatagram--> Http3Transport
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on teClientDatagram do (datagram: tHttpDatagram) {
            var i: int;
            var pendingFound: bool;
            var pendingIndex: int;
            var request: tConnectRequest;
            var assign: tBindContextAssign;

            // Unreliable HTTP Datagram environment outcome.
            if (!DatagramDelivered(config)) {
                announce meTransportDatagramLost,
                    (connectionId = datagram.connectionId,
                     streamId = datagram.streamId,
                     packetId = datagram.packet.id);
                return;
            }

            // First account for an intentionally held BIND CompressionAssign.
            // This does not violate reliable stream ordering internally; it only
            // varies its observation relative to a DATAGRAM-channel delivery.
            pendingFound = false;
            pendingIndex = -1;
            i = 0;
            while (i < sizeof(pendingBindContexts)) {
                if (pendingBindContexts[i].connectionId == datagram.connectionId &&
                    pendingBindContexts[i].streamId == datagram.streamId &&
                    pendingBindContexts[i].contextId == datagram.contextId) {
                    pendingFound = true;
                    pendingIndex = i;
                    break;
                }
                i = i + 1;
            }
            if (pendingFound) {
                assign = pendingBindContexts[pendingIndex];
                pendingBindContexts -= (pendingIndex);
                if ($) {
                    // COMMUNICATION-OUT [seHttpDatagram]
                    //   Http3Transport --seHttpDatagram--> server
                    //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                    //   this send represents only its later externally observable delivery, not its immediate return value.
                    send server, seHttpDatagram, datagram;
                    // COMMUNICATION-OUT [seBindContextAssign]
                    //   Http3Transport --seBindContextAssign--> server
                    //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                    //   this send represents only its later externally observable delivery, not its immediate return value.
                    send server, seBindContextAssign, assign;
                } else {
                    // COMMUNICATION-OUT [seBindContextAssign]
                    //   Http3Transport --seBindContextAssign--> server
                    //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                    //   this send represents only its later externally observable delivery, not its immediate return value.
                    send server, seBindContextAssign, assign;
                    // COMMUNICATION-OUT [seHttpDatagram]
                    //   Http3Transport --seHttpDatagram--> server
                    //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                    //   this send represents only its later externally observable delivery, not its immediate return value.
                    send server, seHttpDatagram, datagram;
                }
                return;
            }

            // Optional optimistic-data/request ordering abstraction.
            pendingFound = false;
            pendingIndex = -1;
            i = 0;
            while (i < sizeof(pendingConnects)) {
                if (pendingConnects[i].connectionId == datagram.connectionId &&
                    pendingConnects[i].streamId == datagram.streamId) {
                    pendingFound = true;
                    pendingIndex = i;
                    break;
                }
                i = i + 1;
            }

            if (pendingFound) {
                request = pendingConnects[pendingIndex];
                pendingConnects -= (pendingIndex);

                // [ABS->CXX boundary] If the HTTP Datagram becomes observable
                // before HandleMasqueRequest has created ConnectUdpServerState,
                // the stream has no registered Http3DatagramVisitor yet. The
                // lower QuicSpdyStream datagram-dispatch path drops a datagram
                // that has no visitor; it cannot call
                // ConnectUdpServerState::OnHttp3Datagram before the constructor
                // registers that visitor (server cc:946-960). Therefore model
                // the early arrival as a lower-layer drop, then deliver the
                // reliable CONNECT request. This avoids a model-only callback
                // into a server state that does not exist in C++.
                if ($) {
                    announce meEarlyDatagramDropped,
                        (connectionId = datagram.connectionId,
                         streamId = datagram.streamId,
                         packetId = datagram.packet.id);
                    // COMMUNICATION-OUT [seConnectRequest]
                    //   Http3Transport --seConnectRequest--> server
                    //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                    //   this send represents only its later externally observable delivery, not its immediate return value.
                    send server, seConnectRequest, request;
                } else {
                    // COMMUNICATION-OUT [seConnectRequest]
                    //   Http3Transport --seConnectRequest--> server
                    //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                    //   this send represents only its later externally observable delivery, not its immediate return value.
                    send server, seConnectRequest, request;
                    // COMMUNICATION-OUT [seHttpDatagram]
                    //   Http3Transport --seHttpDatagram--> server
                    //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                    //   this send represents only its later externally observable delivery, not its immediate return value.
                    send server, seHttpDatagram, datagram;
                }
            } else {
                // Harness-only close race used to exercise destructor/lifecycle
                // behavior. It is not attributed to a specific C++ line.
                if (config.closeAfterFirstClientDatagram && !firstClientDatagramSeen) {
                    firstClientDatagramSeen = true;
                    if ($) {
                        // COMMUNICATION-OUT [seStreamClosed]
                        //   Http3Transport --seStreamClosed--> server
                        //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                        //   this send represents only its later externally observable delivery, not its immediate return value.
                        send server, seStreamClosed, datagram.streamId;
                        // COMMUNICATION-OUT [ceStreamClosed]
                        //   Http3Transport --ceStreamClosed--> client
                        //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                        //   this send represents only its later externally observable delivery, not its immediate return value.
                        send client, ceStreamClosed, datagram.streamId;
                        // COMMUNICATION-OUT [seHttpDatagram]
                        //   Http3Transport --seHttpDatagram--> server
                        //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                        //   this send represents only its later externally observable delivery, not its immediate return value.
                        send server, seHttpDatagram, datagram;
                    } else {
                        // COMMUNICATION-OUT [seHttpDatagram]
                        //   Http3Transport --seHttpDatagram--> server
                        //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                        //   this send represents only its later externally observable delivery, not its immediate return value.
                        send server, seHttpDatagram, datagram;
                        // COMMUNICATION-OUT [seStreamClosed]
                        //   Http3Transport --seStreamClosed--> server
                        //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                        //   this send represents only its later externally observable delivery, not its immediate return value.
                        send server, seStreamClosed, datagram.streamId;
                        // COMMUNICATION-OUT [ceStreamClosed]
                        //   Http3Transport --ceStreamClosed--> client
                        //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                        //   this send represents only its later externally observable delivery, not its immediate return value.
                        send client, ceStreamClosed, datagram.streamId;
                    }
                } else {
                    // COMMUNICATION-OUT [seHttpDatagram]
                    //   Http3Transport --seHttpDatagram--> server
                    //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                    //   this send represents only its later externally observable delivery, not its immediate return value.
                    send server, seHttpDatagram, datagram;
                }
            }
        }

        // [ENV] P-only scheduler action that releases delayed CONNECT requests;
        // it models cross-channel ordering, not a QUICHE method or queue field.
        // COMMUNICATION-IN [teFlushPendingConnects]
        //   MasqueClientSession/MasqueServerSession --teFlushPendingConnects--> Http3Transport
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on teFlushPendingConnects do {
            var request: tConnectRequest;
            while (sizeof(pendingConnects) > 0) {
                request = pendingConnects[0];
                pendingConnects -= (0);
                // COMMUNICATION-OUT [seConnectRequest]
                //   Http3Transport --seConnectRequest--> server
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send server, seConnectRequest, request;
            }
        }

        // [ENV] P-only scheduler action that releases delayed BIND context assignments;
        // used only to explore legal ordering between capsule and datagram delivery.
        // COMMUNICATION-IN [teFlushPendingBindContexts]
        //   MasqueClientSession/MasqueServerSession --teFlushPendingBindContexts--> Http3Transport
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on teFlushPendingBindContexts do {
            var assign: tBindContextAssign;
            while (sizeof(pendingBindContexts) > 0) {
                assign = pendingBindContexts[0];
                pendingBindContexts -= (0);
                // COMMUNICATION-OUT [seBindContextAssign]
                //   Http3Transport --seBindContextAssign--> server
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send server, seBindContextAssign, assign;
            }
        }

        // Boundary: server backend produces response headers after state setup
        // (server cc:685-699); transport delivers them to client stream/session.
        // [ENV] Models reliable HTTP response delivery from server stream to client callback.
        // The MASQUE-side response semantics remain in the session machines.
        // COMMUNICATION-IN [teConnectResponse]
        //   MasqueClientSession/MasqueServerSession --teConnectResponse--> Http3Transport
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on teConnectResponse do (response: tConnectResponse) {
            // COMMUNICATION-OUT [ceConnectResponse]
            //   Http3Transport --ceConnectResponse--> client
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send client, ceConnectResponse, response;
            if (config.closeConnectionAfterConnectResponse &&
                response.responseClass == RESPONSE_2XX) {
                // COMMUNICATION-OUT [ceConnectionClosed]
                //   Http3Transport --ceConnectionClosed--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceConnectionClosed;
                // COMMUNICATION-OUT [seConnectionClosed]
                //   Http3Transport --seConnectionClosed--> server
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send server, seConnectionClosed;
            }
        }

        // [CXX] Boundary: server `it->stream()->SendHttp3Datagram` cc:862-868.
        // COMMUNICATION-IN [teServerDatagram]
        //   MasqueClientSession/MasqueServerSession --teServerDatagram--> Http3Transport
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on teServerDatagram do (datagram: tHttpDatagram) {
            if (!DatagramDelivered(config)) {
                announce meTransportDatagramLost,
                    (connectionId = datagram.connectionId,
                     streamId = datagram.streamId,
                     packetId = datagram.packet.id);
                return;
            }
            // COMMUNICATION-OUT [ceHttpDatagram]
            //   Http3Transport --ceHttpDatagram--> client
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send client, ceHttpDatagram, datagram;
        }

        // Boundary abstraction for stream reset/close callbacks.
        // [ENV] Models QUIC stream reset/close notification reaching both MASQUE sessions.
        // Concrete stream machinery is outside the audited MASQUE source files.
        // COMMUNICATION-IN [teResetStream]
        //   MasqueClientSession/MasqueServerSession --teResetStream--> Http3Transport
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on teResetStream do (streamId: int) {
            // COMMUNICATION-OUT [ceStreamClosed]
            //   Http3Transport --ceStreamClosed--> client
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send client, ceStreamClosed, streamId;
            // COMMUNICATION-OUT [seStreamClosed]
            //   Http3Transport --seStreamClosed--> server
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send server, seStreamClosed, streamId;
        }

        // [ENV] Models connection-close notification fan-out to client/server callbacks.
        // QUIC connection teardown internals are intentionally outside this model.
        // COMMUNICATION-IN [teCloseConnection]
        //   MasqueClientSession/MasqueServerSession --teCloseConnection--> Http3Transport
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on teCloseConnection do {
            // COMMUNICATION-OUT [ceConnectionClosed]
            //   Http3Transport --ceConnectionClosed--> client
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send client, ceConnectionClosed;
            // COMMUNICATION-OUT [seConnectionClosed]
            //   Http3Transport --seConnectionClosed--> server
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send server, seConnectionClosed;
        }
    }
}
