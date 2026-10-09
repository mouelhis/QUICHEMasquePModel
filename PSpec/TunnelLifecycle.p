// ============================================================================
// TEMPORAL PROPERTY: no use after modeled tunnel destruction
// SOURCE SNAPSHOT: bundled under ReferenceCpp/; baseline lineage google/quiche d22f60e (2026-10-08)
// ============================================================================
// MODEL-VALIDATION PRINCIPLE:
//   This monitor is specified independently from implementation routing state.
//   Mutation tests may be used only to validate monitor sensitivity; seeded faults
//   are never reported as implementation bugs.
//
// MONITOR REFINEMENT RULE:
//   Formula below is the requirement. The P spec is its finite-event safety
//   monitor over [GHOST] observations. Ghost events do not select routes, mutate
//   tunnel state, or make transport decisions.
//
// Safety requirement:
//   G( ForwardOrReturn(c,s,...) -> LiveServer(c,s) )
//   G( Deliver(c,s,...)         -> LiveClient(c,s) )
//
// C++ lifecycle basis:
//   client list erase on stream close cc:563-577; CloseConnectUdpStream cc:483-499; client state dtor unregisters visitor cc:625-632.
//   server list remove_if on stream close cc:192-196; dtor unregister/destroy
//   cc:962-978; connection close clears list cc:183-190.
//
// This is a bad-prefix safety monitor, not a liveness claim.
spec TunnelLifecycle observes
    meClientTunnelCreated,
    meClientTunnelRemoved,
    meServerTunnelCreated,
    meServerTunnelRemoved,
    meProxyDatagramForwardedToTarget,
    meProxyDatagramAcceptedForClient,
    meClientPacketDelivered
{
    var liveClient: map[tStreamKey, bool];
    var liveServer: map[tStreamKey, bool];

    // [GHOST] Liveness-set safety monitor; this is not a production C++ state.
    start state Check {
        // [GHOST/CXX] Client state insertion at client cc:226-232.
        // COMMUNICATION-IN [meClientTunnelCreated]
        //   implementation/environment announce --meClientTunnelCreated--> TunnelLifecycle
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meClientTunnelCreated do (p: tClientTunnelEvent) {
            liveClient[(connectionId = p.connectionId, streamId = p.streamId)] = true;
        }

        // [GHOST/CXX] Client state erase at client cc:483-499 / 567-581.
        // COMMUNICATION-IN [meClientTunnelRemoved]
        //   implementation/environment announce --meClientTunnelRemoved--> TunnelLifecycle
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meClientTunnelRemoved do (p: tClientTunnelEvent) {
            var key: tStreamKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            if (key in liveClient) liveClient -= (key);
        }

        // [GHOST/CXX] Server state insertion at server cc:681-683.
        // COMMUNICATION-IN [meServerTunnelCreated]
        //   implementation/environment announce --meServerTunnelCreated--> TunnelLifecycle
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meServerTunnelCreated do (p: tServerTunnelEvent) {
            liveServer[(connectionId = p.connectionId, streamId = p.streamId)] = true;
        }

        // [GHOST/CXX] Server removal/dtor at server cc:192-196 / 966-982.
        // COMMUNICATION-IN [meServerTunnelRemoved]
        //   implementation/environment announce --meServerTunnelRemoved--> TunnelLifecycle
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meServerTunnelRemoved do (p: tServerTunnelEvent) {
            var key: tStreamKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            if (key in liveServer) liveServer -= (key);
        }

        // [GHOST/CXX] Use of server state at UDP WritePacket server cc:1080-1086.
        // COMMUNICATION-IN [meProxyDatagramForwardedToTarget]
        //   implementation/environment announce --meProxyDatagramForwardedToTarget--> TunnelLifecycle
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meProxyDatagramForwardedToTarget do (p: tProxyForwardEvent) {
            var key: tStreamKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            assert key in liveServer,
                format("UDP forwarding after server tunnel removal: {0}", key);
        }

        // [GHOST/CXX] Use of server state at SendHttp3Datagram server cc:836-862.
        // COMMUNICATION-IN [meProxyDatagramAcceptedForClient]
        //   implementation/environment announce --meProxyDatagramAcceptedForClient--> TunnelLifecycle
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meProxyDatagramAcceptedForClient do (p: tProxyReturnEvent) {
            var key: tStreamKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            assert key in liveServer,
                format("HTTP Datagram generated after server tunnel removal: {0}", key);
        }

        // [GHOST/CXX] Use of client state at ProcessPacket client cc:720-722.
        // COMMUNICATION-IN [meClientPacketDelivered]
        //   implementation/environment announce --meClientPacketDelivered--> TunnelLifecycle
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meClientPacketDelivered do (p: tClientDeliveryEvent) {
            var key: tStreamKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            assert key in liveClient,
                format("Packet delivered after client tunnel removal: {0}", key);
        }
    }
}
