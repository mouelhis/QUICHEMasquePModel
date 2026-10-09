// ============================================================================
// TEMPORAL PROPERTIES: live state uniqueness
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
// Client requirement:
//   G( CreateClient(k) -> !LiveClient(k) before create )
// where k=(connection, encapsulated session, target, mode).
// C++ GetOrCreate search cc:102-110 should reuse matching live state; BIND caller
// uses empty target cc:426-433 so one BIND state per encapsulated session/mode.
//
// Server requirements:
//   G( live states have unique stream IDs )
//   G( live states have unique owned fds )
// C++ ConnectUdpServerState owns fd (server h:154-162), list inserted only after
// one FdWrapper transfer cc:681-683, and destructor destroys that fd cc:962-978.

spec ClientStateUniqueness observes meClientTunnelCreated, meClientTunnelRemoved
{
    var live: map[tClientSemanticKey, int];

    // [GHOST] Client uniqueness automaton over list insertion/removal observations.
    start state Check {
        // [GHOST/CXX] Client state insertion: GetOrCreate... client cc:226-232.
        // COMMUNICATION-IN [meClientTunnelCreated]
        //   implementation/environment announce --meClientTunnelCreated--> ClientStateUniqueness
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meClientTunnelCreated do (p: tClientTunnelEvent) {
            var key: tClientSemanticKey;
            key = (
                connectionId = p.connectionId,
                encapsulatedSessionId = p.encapsulatedSessionId,
                target = p.target,
                isBind = p.isBind
            );
            assert !(key in live),
                format("Duplicate live client state for semantic key {0}", key);
            live[key] = p.streamId;
        }

        // [GHOST/CXX] Client state erasure: OnStreamClosed cc:563-577 or
        // CloseConnectUdpStream cc:483-499.
        // COMMUNICATION-IN [meClientTunnelRemoved]
        //   implementation/environment announce --meClientTunnelRemoved--> ClientStateUniqueness
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meClientTunnelRemoved do (p: tClientTunnelEvent) {
            var key: tClientSemanticKey;
            key = (
                connectionId = p.connectionId,
                encapsulatedSessionId = p.encapsulatedSessionId,
                target = p.target,
                isBind = p.isBind
            );
            if (key in live) live -= (key);
        }
    }
}

spec ServerStateUniqueness observes meServerTunnelCreated, meServerTunnelRemoved
{
    var streamToFd: map[tStreamKey, int];
    var fdToStream: map[tFdKey, int];

    // [GHOST] Server uniqueness monitor state; no production C++ state.
    start state Check {
        // [GHOST/CXX] Server state insertion after registration at server cc:675-687.
        // COMMUNICATION-IN [meServerTunnelCreated]
        //   implementation/environment announce --meServerTunnelCreated--> ServerStateUniqueness
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meServerTunnelCreated do (p: tServerTunnelEvent) {
            var skey: tStreamKey;
            var fkey: tFdKey;
            skey = (connectionId = p.connectionId, streamId = p.streamId);
            fkey = (connectionId = p.connectionId, fdId = p.fdId);

            assert !(skey in streamToFd),
                format("Duplicate server state for stream {0}", skey);
            assert !(fkey in fdToStream),
                format("FD {0} aliases more than one live server state", fkey);

            streamToFd[skey] = p.fdId;
            fdToStream[fkey] = p.streamId;
        }

        // [GHOST/CXX] Server state removal/dtor at server cc:192-196 / 966-982.
        // COMMUNICATION-IN [meServerTunnelRemoved]
        //   implementation/environment announce --meServerTunnelRemoved--> ServerStateUniqueness
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meServerTunnelRemoved do (p: tServerTunnelEvent) {
            var skey: tStreamKey;
            var fkey: tFdKey;
            skey = (connectionId = p.connectionId, streamId = p.streamId);
            fkey = (connectionId = p.connectionId, fdId = p.fdId);
            if (skey in streamToFd) streamToFd -= (skey);
            if (fkey in fdToStream) fdToStream -= (fkey);
        }
    }
}
