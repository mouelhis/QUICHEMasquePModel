// ============================================================================
// TEMPORAL PROPERTY: server connection cleanup
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
// Requirement (safety form):
//   G( ServerConnectionClosed(c) -> LiveServerTunnels(c) = {} )
//
// C++ justification:
//   MasqueServerSession::OnConnectionClosed server cc:183-190 explicitly calls
//   connect_udp_server_states_.clear(); comment says clearing closes all sockets.
//   ConnectUdpServerState::~... cc:962-978 unregisters visitors/socket and
//   destroys fd. Therefore a closed server connection retaining modeled live
//   CONNECT-UDP state contradicts the implementation's intended cleanup step.
//
// Monitor refinement: created/removed announcements are ghost observations of
// list insertion/destruction; meServerConnectionClosed is announced only after
// the modeled clear completes.
spec ConnectionCleanup observes
    meServerTunnelCreated,
    meServerTunnelRemoved,
    meServerConnectionClosed
{
    var live: set[tStreamKey];

    // [GHOST] Bad-prefix monitor for server connection cleanup; no C++ state.
    start state Check {
        // [GHOST/CXX] State becomes live at server ConnectUdpServerState insertion cc:681-683.
        // COMMUNICATION-IN [meServerTunnelCreated]
        //   implementation/environment announce --meServerTunnelCreated--> ConnectionCleanup
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meServerTunnelCreated do (p: tServerTunnelEvent) {
            live += ((connectionId = p.connectionId, streamId = p.streamId));
        }

        // [GHOST/CXX] Removal corresponds to stream-close erase cc:192-196 or
        // connection-close list clearing cc:183-190, with dtor cc:962-978.
        // COMMUNICATION-IN [meServerTunnelRemoved]
        //   implementation/environment announce --meServerTunnelRemoved--> ConnectionCleanup
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meServerTunnelRemoved do (p: tServerTunnelEvent) {
            var key: tStreamKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            if (key in live) live -= (key);
        }

        // [GHOST/CXX] OnConnectionClosed completion corresponds to server cc:183-190.
        // COMMUNICATION-IN [meServerConnectionClosed]
        //   implementation/environment announce --meServerConnectionClosed--> ConnectionCleanup
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meServerConnectionClosed do {
            assert sizeof(live) == 0,
                format("Server connection closed with live CONNECT-UDP streams: {0}", live);
        }
    }
}
