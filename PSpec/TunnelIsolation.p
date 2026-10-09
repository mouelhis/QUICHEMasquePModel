// ============================================================================
// TEMPORAL PROPERTY: tunnel association / reverse-route isolation
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
// P1 forward association:
//   G( Forward(c,s,fd,t,p) -> LiveServer(c,s,fd,...) && SelectedTarget=t )
//
// P2 reverse association, using independent environment provenance R:
//   G( ValidUdpReply(R) && Return(R') ->
//        R'.stream=R.stream && R'.fd=R.fd && R'.target=R.target )
//
// P3 client association (non-BIND):
//   G( Deliver(c,s,p) && !bind -> DeliveredTarget = StateTarget(c,s) )
// BIND return-address fidelity is intentionally a separate property in
// BindTargetFidelity.p because the C++ BIND state target is the empty address.
//
// C++ associations:
//   client GetOrCreate state lookup cc:102-110;
//   server state owns stream/target/fd h:154-162;
//   reverse lookup by fd cc:729-746;
//   non-BIND peer check cc:815-820;
//   reverse SendHttp3Datagram on selected state stream cc:862-868.
//
// Oracle independence rule: meUdpReplyGenerated is announced by UdpEnvironment
// from the outbound (stream,fd,target,context) BEFORE server reverse lookup. The
// monitor never uses server's selected state to manufacture its expected route.

spec TunnelIsolation observes
    meClientTunnelCreated,
    meClientTunnelRemoved,
    meServerTunnelCreated,
    meServerTunnelRemoved,
    meProxyDatagramForwardedToTarget,
    meUdpReplyGenerated,
    meUnexpectedUdpDropped,
    meProxyDatagramAcceptedForClient,
    meClientPacketDelivered
{
    var serverTargets: map[tStreamKey, tAddress];
    var serverFds: map[tStreamKey, int];
    var clientOwners: map[tStreamKey, int];
    var clientTargets: map[tStreamKey, tAddress];
    var clientIsBind: map[tStreamKey, bool];

    // Independent network provenance indexed by reply packet ghost identity.
    var replyStream: map[tReplyKey, int];
    var replyFd: map[tReplyKey, int];
    var replyTarget: map[tReplyKey, tAddress];
    var replyContext: map[tReplyKey, int];
    var replyIsBind: map[tReplyKey, bool];
    var replyValidSource: map[tReplyKey, bool];

    // [GHOST] Product-state bad-prefix automaton for TI; no production C++ state.
    start state Check {
        // [GHOST/CXX] Client association created by GetOrCreate... insertion cc:226-232.
        // COMMUNICATION-IN [meClientTunnelCreated]
        //   implementation/environment announce --meClientTunnelCreated--> TunnelIsolation
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meClientTunnelCreated do (p: tClientTunnelEvent) {
            var key: tStreamKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            clientOwners[key] = p.encapsulatedSessionId;
            clientTargets[key] = p.target;
            clientIsBind[key] = p.isBind;
        }

        // [GHOST/CXX] Client association removed at client cc:483-499 or 567-581.
        // COMMUNICATION-IN [meClientTunnelRemoved]
        //   implementation/environment announce --meClientTunnelRemoved--> TunnelIsolation
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meClientTunnelRemoved do (p: tClientTunnelEvent) {
            var key: tStreamKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            if (key in clientOwners) clientOwners -= (key);
            if (key in clientTargets) clientTargets -= (key);
            if (key in clientIsBind) clientIsBind -= (key);
        }

        // [GHOST/CXX] Server association created after socket registration, cc:675-687.
        // COMMUNICATION-IN [meServerTunnelCreated]
        //   implementation/environment announce --meServerTunnelCreated--> TunnelIsolation
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meServerTunnelCreated do (p: tServerTunnelEvent) {
            var key: tStreamKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            serverTargets[key] = p.target;
            serverFds[key] = p.fdId;
        }

        // [GHOST/CXX] Server association removed at server cc:192-196 / dtor 966-982.
        // COMMUNICATION-IN [meServerTunnelRemoved]
        //   implementation/environment announce --meServerTunnelRemoved--> TunnelIsolation
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meServerTunnelRemoved do (p: tServerTunnelEvent) {
            var key: tStreamKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            if (key in serverTargets) serverTargets -= (key);
            if (key in serverFds) serverFds -= (key);
        }

        // [GHOST/CXX] Forward route observed at server UDP WritePacket cc:1080-1086.
        // COMMUNICATION-IN [meProxyDatagramForwardedToTarget]
        //   implementation/environment announce --meProxyDatagramForwardedToTarget--> TunnelIsolation
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meProxyDatagramForwardedToTarget do (p: tProxyForwardEvent) {
            var key: tStreamKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            assert key in serverTargets,
                format("Forwarded packet {0} through unknown server stream {1}", p.packetId, key);
            assert key in serverFds,
                format("Forwarded packet {0} through stream without owned fd {1}", p.packetId, key);
            assert serverFds[key] == p.fdId,
                format("Forward path fd mismatch: stream {0} owns {1}, used {2}", key, serverFds[key], p.fdId);
            if (!p.isBind) {
                assert serverTargets[key] == p.target,
                    format("Cross-tunnel forward: stream {0} expected {1}, used {2}", key, serverTargets[key], p.target);
            }
        }

        // [GHOST/ENV] Independent reverse provenance captured before QUICHE fd lookup;
        // concrete reverse read/lookup begins at server cc:729-874.
        // COMMUNICATION-IN [meUdpReplyGenerated]
        //   implementation/environment announce --meUdpReplyGenerated--> TunnelIsolation
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meUdpReplyGenerated do (p: tUdpReplyProvenance) {
            var rkey: tReplyKey;
            rkey = (connectionId = p.connectionId, packetId = p.packetId);
            replyStream[rkey] = p.expectedStreamId;
            replyFd[rkey] = p.expectedFdId;
            replyTarget[rkey] = p.expectedTarget;
            replyContext[rkey] = p.expectedContextId;
            replyIsBind[rkey] = p.isBind;
            replyValidSource[rkey] = p.validSource;
        }

        // [GHOST/CXX] Non-BIND unexpected-peer drop corresponds to server cc:815-820.
        // COMMUNICATION-IN [meUnexpectedUdpDropped]
        //   implementation/environment announce --meUnexpectedUdpDropped--> TunnelIsolation
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meUnexpectedUdpDropped do (p: tUdpObservedEvent) {
            var rkey: tReplyKey;
            rkey = (connectionId = p.connectionId, packetId = p.packetId);

            // For an exact valid peer reply generated from the outbound write,
            // an "unexpected source" classification can indicate that reverse
            // lookup/context association selected different state. This check is
            // intentionally conditional on independent provenance.
            if (rkey in replyValidSource) {
                if (replyValidSource[rkey]) {
                    assert false,
                        format("Valid UDP reply {0} was rejected as unexpected; expected stream {1}, fd {2}, target {3}",
                               rkey, replyStream[rkey], replyFd[rkey], replyTarget[rkey]);
                }
            }
        }

        // [GHOST/CXX] Reverse tunnel chosen before SendHttp3Datagram server cc:836-862.
        // COMMUNICATION-IN [meProxyDatagramAcceptedForClient]
        //   implementation/environment announce --meProxyDatagramAcceptedForClient--> TunnelIsolation
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meProxyDatagramAcceptedForClient do (p: tProxyReturnEvent) {
            var key: tStreamKey;
            var rkey: tReplyKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            rkey = (connectionId = p.connectionId, packetId = p.packetId);

            assert key in serverTargets,
                format("Return packet {0} attached to unknown server stream {1}", p.packetId, key);
            assert rkey in replyStream,
                format("Return packet {0} has no independent UDP provenance", rkey);
            assert p.streamId == replyStream[rkey],
                format("Cross-tunnel reverse route {0}: expected stream {1}, used {2}", rkey, replyStream[rkey], p.streamId);
            assert p.fdId == replyFd[rkey],
                format("Cross-tunnel reverse route {0}: expected fd {1}, used {2}", rkey, replyFd[rkey], p.fdId);
            assert p.expectedTarget == replyTarget[rkey],
                format("Reverse-route target mismatch {0}: expected {1}, used {2}", rkey, replyTarget[rkey], p.expectedTarget);
            assert p.isBind == replyIsBind[rkey],
                format("Reverse-route mode mismatch for packet {0}", rkey);
            assert p.contextId == replyContext[rkey],
                format("Reverse-route context mismatch {0}: expected {1}, used {2}", rkey, replyContext[rkey], p.contextId);
        }

        // [GHOST/CXX] Final client delivery corresponds to ProcessPacket client cc:720-722.
        // COMMUNICATION-IN [meClientPacketDelivered]
        //   implementation/environment announce --meClientPacketDelivered--> TunnelIsolation
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meClientPacketDelivered do (p: tClientDeliveryEvent) {
            var key: tStreamKey;
            key = (connectionId = p.connectionId, streamId = p.streamId);
            assert key in clientOwners,
                format("Packet {0} delivered to removed/unknown client stream {1}", p.packetId, key);
            assert clientOwners[key] == p.encapsulatedSessionId,
                format("Cross-session delivery on stream {0}", key);
            assert clientIsBind[key] == p.isBind,
                format("Client mode mismatch on stream {0}", key);
            if (!p.isBind) {
                assert clientTargets[key] == p.deliveredTarget,
                    format("Non-BIND client target mismatch on stream {0}", key);
            }
        }
    }
}
