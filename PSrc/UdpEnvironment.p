// ============================================================================
// UDP socket / peer environment abstraction
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
// This // SYNCHRONY RULE FOR THIS MODEL:
//   Do NOT turn ordinary in-process C++ function calls into P request/reply messages.
//   Doing so would invent scheduler interleavings absent from the implementation.
//   Source calls whose return value immediately controls the same stack frame
//   (URI expansion, stream creation, SendRequest return, socket create/bind/register,
//   SendHttp3Datagram status, WritePacket status) are represented in the same handler.
//   A send+receive correlation loop is reserved for a genuinely synchronous interaction
//   that crosses an independently scheduled modeled component. No audited MASQUE
//   CONNECT-UDP call in this snapshot requires that pattern. See PDocs/SYNCHRONY.md.
//
// machine models the world outside the proxy's UDP socket. It is NOT part
// of QUICHE implementation state.
//
// C++ boundaries:
//   forward: ConnectUdpServerState::OnHttp3Datagram constructs target_address
//            and WritePacket(fd_, ..., peer) at server cc:1080-1086.
//   reverse: OnSocketEvent/HandleConnectUdpSocketEvent reads fd/PEER_ADDRESS at
//            server cc:729-874 and then applies target/context validation.
//
// Monitor provenance is emitted BEFORE the server's fd lookup so expected route
// identity is independent of the implementation decision under verification.

machine UdpEnvironment {
    // [ENV] Destination for semantic socket-readable callbacks.
    var server: machine;
    // [TEST] Harness readiness callback target.
    var driver: machine;
    // [TEST/ENV] Finite peer/loss choices; no production field counterpart.
    var config: tModelConfig;

    // [ENV] P-only environment lifecycle; no C++ state-machine counterpart.
    start state Init {
        // COMMUNICATION-IN [eConfigureUdp]
        //   TestDriver --eConfigureUdp--> UdpEnvironment
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on eConfigureUdp goto Active with (inputs: (server: machine, driver: machine, config: tModelConfig)) {
            server = inputs.server;
            driver = inputs.driver;
            config = inputs.config;
            // COMMUNICATION-OUT [eUdpReady]
            //   UdpEnvironment --eUdpReady--> driver
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send driver, eUdpReady;
        }
    }

    // [ENV] P-only UDP peer/event-loop dispatcher.
    state Active {
        // [ENV] Boundary corresponding to server UDP WritePacket (server cc:1080-1086)
        // followed, when a peer reply exists, by ReadPacket/PEER_ADDRESS at cc:729-874.
        // COMMUNICATION-IN [ueProxyWrite]
        //   MasqueServerSession --ueProxyWrite--> UdpEnvironment
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on ueProxyWrite do (write: tUdpWrite) {
            var replyMode: tUdpReplyMode;
            var source: tAddress;
            var replyPacket: tPacket;
            var validSource: bool;

            // Ghost observation of the exact (stream,fd,target,context) selected
            // by server code before leaving the process boundary.
            announce meTargetReceivedPacket,
                (connectionId = write.connectionId,
                 streamId = write.streamId,
                 fdId = write.fdId,
                 target = write.target,
                 isBind = write.isBind,
                 contextId = write.contextId,
                 packetId = write.packet.id);

            replyMode = config.udpReplyMode;
            if (replyMode == UDP_REPLY_NONDET) {
                if ($) replyMode = UDP_REPLY_VALID;
                else if ($) replyMode = UDP_REPLY_UNEXPECTED_SOURCE;
                else replyMode = UDP_REPLY_NONE;
            }
            if (replyMode == UDP_REPLY_NONE) return;

            if (replyMode == UDP_REPLY_VALID) {
                source = write.target;
                validSource = true;
            } else {
                source = OtherAddress(write.target);
                validSource = false;
            }

            // Packet ID transformation is verification-only provenance; bytes
            // are otherwise unconstrained/opaque to association properties.
            replyPacket = Packet(write.packet.id + 1000);

            announce meUdpReplyGenerated,
                (connectionId = write.connectionId,
                 expectedStreamId = write.streamId,
                 expectedFdId = write.fdId,
                 expectedTarget = write.target,
                 expectedContextId = write.contextId,
                 isBind = write.isBind,
                 source = source,
                 validSource = validSource,
                 packetId = replyPacket.id);

            // Semantic readable event contains only fd, peer/source and payload,
            // matching what server gets from event-loop + ReadPacket. No tunnel
            // index is supplied by the environment.
            // COMMUNICATION-OUT [seUdpReadable]
            //   UdpEnvironment --seUdpReadable--> server
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send server, seUdpReadable,
                (connectionId = write.connectionId,
                 fdId = write.fdId,
                 source = source,
                 packet = replyPacket);
        }
    }
}
