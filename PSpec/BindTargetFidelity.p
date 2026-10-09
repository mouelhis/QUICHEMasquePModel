// ============================================================================
// TEMPORAL PROPERTY: CONNECT-UDP-BIND return peer-address fidelity
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
// Requirement BT-1 (safety / conditional correspondence):
//
//   G( ValidUdpReply(p, peer=T)
//      && ClientDeliverSamePacket(p, isBind=true, decoded=D, delivered=A)
//      -> D = T && A = T )
//
// A weaker local form is also checked:
//   G( ClientDeliver(d) && d.isBind -> d.deliveredTarget = d.decodedTarget )
//
// Interpretation:
//   A CONNECT-UDP-BIND response identifies the UDP peer either through a
//   compressed Context ID mapping or through inline IP+port metadata carried by
//   an open/uncompressed context. The address supplied to
//   EncapsulatedClientSession::ProcessPacket must therefore identify that peer.
//
// Exact C++ correspondence:
//   EncapsulatedClientSession API parameter:
//     masque_client_session.h:L64-L67 (ProcessPacket address parameter) and L223-L292 (ConnectUdpClientState)
//   BIND state creation passes an empty target address:
//     masque_client_session.cc:L422-L433
//   compressed/open context selection and packet encoding:
//     masque_client_session.cc:L727-L757, L827-L896
//   client reverse callback decodes `target_address`:
//     masque_client_session.cc:L658-L722
//   current ProcessPacket call:
//     masque_client_session.cc:L720-L722
//
// Source observation under audit:
//   `target_address` is computed in the BIND branch, but the current call is
//   ProcessPacket(http_payload, target_server_address_). For a BIND state,
//   target_server_address_ originates from the empty QuicSocketAddress passed at
//   L430-L431. The P implementation preserves this exact data flow; it does not
//   inject a wrong target.
//
// Oracle independence:
//   `meUdpReplyGenerated` is announced by UdpEnvironment from the concrete
//   outbound UDP write association before the server performs fd/context reverse
//   lookup. Thus `networkTarget` is independent of the client state being tested.
//   `decodedTarget` and `deliveredTarget` are observations of the client callback.
//
// STATUS:
//   A violation is a strong source-level *bug candidate*, not by itself a final
//   upstream bug claim. Confirm with a focused C++ test/reproduction and review
//   intended CONNECT-UDP-BIND API semantics before reporting.

spec BindTargetFidelity observes
    meUdpReplyGenerated,
    meClientPacketDelivered
{
    var networkTarget: map[tReplyKey, tAddress];
    var networkIsBind: map[tReplyKey, bool];
    var networkValidSource: map[tReplyKey, bool];

    // [GHOST] Bad-prefix automaton implementing BT-1; no production C++ state.
    start state Check {
        // [GHOST/ENV] Independent expected peer captured outside QUICHE before the
        // server fd lookup; reverse read boundary is server cc:729-874.
        // COMMUNICATION-IN [meUdpReplyGenerated]
        //   implementation/environment announce --meUdpReplyGenerated--> BindTargetFidelity
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meUdpReplyGenerated do (p: tUdpReplyProvenance) {
            var key: tReplyKey;
            key = (connectionId = p.connectionId, packetId = p.packetId);
            networkTarget[key] = p.expectedTarget;
            networkIsBind[key] = p.isBind;
            networkValidSource[key] = p.validSource;
        }

        // [GHOST/CXX] Decoded/delivered address observed at client OnHttp3Datagram
        // cc:658-725, especially target decode cc:688-718 and ProcessPacket cc:720-722.
        // COMMUNICATION-IN [meClientPacketDelivered]
        //   implementation/environment announce --meClientPacketDelivered--> BindTargetFidelity
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meClientPacketDelivered do (p: tClientDeliveryEvent) {
            var key: tReplyKey;
            key = (connectionId = p.connectionId, packetId = p.packetId);

            if (p.isBind) {
                assert p.deliveredTarget == p.decodedTarget,
                    format("BIND local peer-address mismatch on stream {0}, context {1}, packet {2}: decoded {3}, delivered {4}",
                           p.streamId, p.contextId, p.packetId,
                           p.decodedTarget, p.deliveredTarget);

                assert key in networkTarget,
                    format("BIND client delivery {0} has no independent UDP provenance", key);
                assert networkIsBind[key],
                    format("BIND client delivery {0} originated from non-BIND provenance", key);

                if (networkValidSource[key]) {
                    assert p.decodedTarget == networkTarget[key],
                        format("BIND decoded peer mismatch {0}: UDP peer {1}, decoded {2}",
                               key, networkTarget[key], p.decodedTarget);
                    assert p.deliveredTarget == networkTarget[key],
                        format("BIND ProcessPacket address mismatch {0}: UDP peer {1}, delivered {2}",
                               key, networkTarget[key], p.deliveredTarget);
                }
            }
        }
    }
}
