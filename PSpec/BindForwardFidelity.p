// ============================================================================
// TEMPORAL PROPERTY: CONNECT-UDP-BIND client->proxy target preservation
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
// Requirement BF-1 (safety / conditional correspondence):
//
//   G( ClientBindDatagramAccepted(p, target=T, context=C)
//      && ProxyForwardsSamePacket(p, target=T', context=C')
//      -> T' = T && C' = C )
//
// This deliberately does NOT require eventual forwarding because HTTP Datagrams
// are unreliable. It constrains the route only when the packet is observed at
// the server's UDP write boundary.
//
// C++ correspondence:
//   client public target input:
//     masque_client_session.h:L151-L155
//     masque_client_session.cc:L422-L439
//   BIND packet/context preparation:
//     masque_client_session.cc:L827-L896
//   server BIND context lookup / inline-address parse:
//     masque_server_session.cc:L1013-L1087
//   concrete UDP peer selected for WritePacket:
//     masque_server_session.cc:L1080-L1086
//
// Monitor independence:
//   Expected target is captured from the client API-side accepted-datagram ghost
//   event before server context resolution. Actual target is captured immediately
//   before server WritePacket. The monitor does not derive both from one server
//   state lookup.
//
// Abstraction note:
//   packetId is verification provenance representing payload identity; it is not
//   a QUICHE wire field. The finite harness generates unique IDs.

spec BindForwardFidelity observes
    meClientDatagramApiAccepted,
    meProxyDatagramForwardedToTarget
{
    var expectedTarget: map[tReplyKey, tAddress];
    var expectedContext: map[tReplyKey, int];

    // [GHOST] Bad-prefix automaton implementing BF-1; no production C++ state.
    start state Check {
        // [GHOST/CXX] Expected target/context recorded at client send boundary:
        // BIND SendConnectUdpBindPacket cc:422-439 and PrepareBindPacket cc:843-896.
        // COMMUNICATION-IN [meClientDatagramApiAccepted]
        //   implementation/environment announce --meClientDatagramApiAccepted--> BindForwardFidelity
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meClientDatagramApiAccepted do (p: tClientDatagramEvent) {
            var key: tReplyKey;
            if (p.isBind) {
                key = (connectionId = p.connectionId, packetId = p.packetId);
                expectedTarget[key] = p.target;
                expectedContext[key] = p.contextId;
            }
        }

        // [GHOST/CXX] Actual peer recorded immediately before server UDP WritePacket,
        // ConnectUdpServerState::OnHttp3Datagram server cc:1080-1086.
        // COMMUNICATION-IN [meProxyDatagramForwardedToTarget]
        //   implementation/environment announce --meProxyDatagramForwardedToTarget--> BindForwardFidelity
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meProxyDatagramForwardedToTarget do (p: tProxyForwardEvent) {
            var key: tReplyKey;
            if (p.isBind) {
                key = (connectionId = p.connectionId, packetId = p.packetId);
                assert key in expectedTarget,
                    format("BIND forward packet {0} has no client provenance", key);
                assert p.target == expectedTarget[key],
                    format("BIND forward target mismatch {0}: client requested {1}, proxy used {2}",
                           key, expectedTarget[key], p.target);
                assert p.contextId == expectedContext[key],
                    format("BIND forward context mismatch {0}: client used {1}, proxy used {2}",
                           key, expectedContext[key], p.contextId);
            }
        }
    }
}
