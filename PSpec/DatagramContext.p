// ============================================================================
// TEMPORAL PROPERTIES: CONNECT-UDP context rules and unexpected-source drop
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
// P1 (non-BIND Context ID):
//   G( NonBindDatagramAcceptedOrForwarded(d) -> context(d) = 0 )
// C++:
//   client SendPacket writes byte/context 0 cc:455-460;
//   server OnHttp3Datagram drops nonzero cc:1021-1030 and writes Context ID 0 on
//   reverse cc:852-856; client drops nonzero cc:663-673.
// BIND is intentionally excluded: context IDs >=2 are normal there.
//
// P2 (unexpected non-BIND UDP source is never forwarded after rejection):
//   G( UnexpectedSourceDropped(k) -> G_no_same_packet( !ReturnAccepted(k) ) )
// C++ server cc:815-820 continues/drops when peer_address != expected target.

spec DatagramContextZero observes
    meClientDatagramApiAccepted,
    meProxyDatagramForwardedToTarget,
    meProxyDatagramAcceptedForClient,
    meClientPacketDelivered
{
    // [GHOST] Context-ID bad-prefix monitor; no production C++ state.
    start state Check {
        // [GHOST/CXX] Client non-BIND context is written as 0 at client cc:455-460.
        // COMMUNICATION-IN [meClientDatagramApiAccepted]
        //   implementation/environment announce --meClientDatagramApiAccepted--> DatagramContextZero
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meClientDatagramApiAccepted do (p: tClientDatagramEvent) {
            if (!p.isBind) {
                assert p.contextId == 0,
                    "QUICHE non-BIND CONNECT-UDP client emitted non-zero Context ID";
            }
        }

        // [GHOST/CXX] Server parses incoming context in OnHttp3Datagram cc:1021-1043.
        // COMMUNICATION-IN [meProxyDatagramForwardedToTarget]
        //   implementation/environment announce --meProxyDatagramForwardedToTarget--> DatagramContextZero
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meProxyDatagramForwardedToTarget do (p: tProxyForwardEvent) {
            if (!p.isBind) {
                assert p.contextId == 0,
                    "Proxy forwarded non-zero non-BIND CONNECT-UDP Context ID";
            }
        }

        // [GHOST/CXX] Server non-BIND reverse path emits context 0 at server cc:852-868.
        // COMMUNICATION-IN [meProxyDatagramAcceptedForClient]
        //   implementation/environment announce --meProxyDatagramAcceptedForClient--> DatagramContextZero
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meProxyDatagramAcceptedForClient do (p: tProxyReturnEvent) {
            if (!p.isBind) {
                assert p.contextId == 0,
                    "Proxy generated non-zero non-BIND CONNECT-UDP Context ID";
            }
        }

        // [GHOST/CXX] Client consumes the datagram in OnHttp3Datagram cc:658-725.
        // COMMUNICATION-IN [meClientPacketDelivered]
        //   implementation/environment announce --meClientPacketDelivered--> DatagramContextZero
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meClientPacketDelivered do (p: tClientDeliveryEvent) {
            if (!p.isBind) {
                assert p.contextId == 0,
                    "Client delivered non-zero non-BIND CONNECT-UDP Context ID";
            }
        }
    }
}

spec UnexpectedUdpSourceDropped observes
    meUnexpectedUdpDropped,
    meProxyDatagramAcceptedForClient
{
    var rejected: set[tFdPacketKey];

    // [GHOST] Unexpected-source safety monitor state; no production C++ state.
    start state Check {
        // [GHOST/CXX] Drop occurs at server source-address check cc:815-820.
        // COMMUNICATION-IN [meUnexpectedUdpDropped]
        //   implementation/environment announce --meUnexpectedUdpDropped--> UnexpectedUdpSourceDropped
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meUnexpectedUdpDropped do (p: tUdpObservedEvent) {
            rejected += ((connectionId = p.connectionId,
                         fdId = p.fdId,
                         packetId = p.packetId));
        }

        // [GHOST/CXX] Any later acceptance would correspond to server SendHttp3Datagram cc:862-868.
        // COMMUNICATION-IN [meProxyDatagramAcceptedForClient]
        //   implementation/environment announce --meProxyDatagramAcceptedForClient--> UnexpectedUdpSourceDropped
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meProxyDatagramAcceptedForClient do (p: tProxyReturnEvent) {
            var key: tFdPacketKey;
            key = (connectionId = p.connectionId,
                   fdId = p.fdId,
                   packetId = p.packetId);
            assert !(key in rejected),
                format("Packet {0} rejected as unexpected UDP source was later sent to client", key);
        }
    }
}
