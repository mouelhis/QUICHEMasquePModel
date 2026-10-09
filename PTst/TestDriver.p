// [TEST] All machines and scenario branches in this file are harness-only;
// they have no production C++ state-machine counterpart. They exercise the same
// generic implementation machines with different external inputs/outcomes.
// ============================================================================
// Bounded scenario harness -- not implementation state
// UPSTREAM PIN for invoked API boundaries:
// google/quiche @ d22f60e1389182a78bdeddd81c130a9161afd46d
// ============================================================================
// The driver only chooses finite inputs and calls modeled public boundaries.
// Implementation behavior remains in PSrc machines and is shared by all tests.
// Client sends correspond to SendPacket cc:445-473 or, when config is BIND,
// SendConnectUdpBindPacket cc:426-443. Close call corresponds to
// CloseConnectUdpStream cc:487-503.

machine MasqueTestDriver {
    var scenario: tScenario;
    var config: tModelConfig;
    var transport: machine;
    var udp: machine;
    var client: machine;
    var server: machine;
    var transportReady: bool;
    var udpReady: bool;

    // [TEST] Harness construction/configuration only.
    start state Init {
        entry (selectedScenario: tScenario) {
            scenario = selectedScenario;
            config = ConfigForScenario(scenario);
            transportReady = false;
            udpReady = false;

            transport = new Http3Transport();
            udp = new UdpEnvironment();
            server = new MasqueServerSession((
                connectionId = 1,
                transport = transport,
                udpEnvironment = udp,
                config = config
            ));
            client = new MasqueClientSession((
                connectionId = 1,
                transport = transport,
                config = config
            ));

            // COMMUNICATION-OUT [eConfigureTransport]
            //   MasqueTestDriver --eConfigureTransport--> transport
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send transport, eConfigureTransport,
                (client = client, server = server, driver = this, config = config);
            // COMMUNICATION-OUT [eConfigureUdp]
            //   MasqueTestDriver --eConfigureUdp--> udp
            //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
            //   this send represents only its later externally observable delivery, not its immediate return value.
            send udp, eConfigureUdp,
                (server = server, driver = this, config = config);

            goto WaitingForEnvironment;
        }
    }

    // [TEST] Harness readiness barrier only.
    state WaitingForEnvironment {
        // [TEST] Records transport-harness readiness.
        // COMMUNICATION-IN [eTransportReady]
        //   TestDriver --eTransportReady--> MasqueTestDriver
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on eTransportReady do {
            transportReady = true;
            if (udpReady) goto Running;
        }

        // [TEST] Records UDP-harness readiness.
        // COMMUNICATION-IN [eUdpReady]
        //   TestDriver --eUdpReady--> MasqueTestDriver
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on eUdpReady do {
            udpReady = true;
            if (transportReady) goto Running;
        }
    }

    // [TEST] Emits finite API inputs; implementation behavior remains in PSrc.
    state Running {
        entry {
            var targetA: tAddress;
            var targetB: tAddress;

            targetA = Address(10, 443);
            targetB = Address(20, 8443);

            if (scenario == SCENARIO_ONE_TUNNEL) {
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetA, packet = Packet(1));
            }
            else if (scenario == SCENARIO_REUSE_SAME_TUNNEL) {
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetA, packet = Packet(1));
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetA, packet = Packet(2));
            }
            else if (scenario == SCENARIO_TWO_TUNNELS) {
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetA, packet = Packet(1));
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 2, target = targetB, packet = Packet(2));
            }
            else if (scenario == SCENARIO_SAME_TARGET_DIFFERENT_OWNERS) {
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetA, packet = Packet(1));
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 2, target = targetA, packet = Packet(2));
            }
            else if (scenario == SCENARIO_STREAM_CLOSE_RACE) {
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetA, packet = Packet(1));
            }
            else if (scenario == SCENARIO_CONNECTION_CLOSE) {
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetA, packet = Packet(1));
            }
            else if (scenario == SCENARIO_UNEXPECTED_UDP_SOURCE) {
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetA, packet = Packet(1));
            }
            else if (scenario == SCENARIO_BIND_TARGET_FIDELITY) {
                // One BIND stream/session, two destination contexts through the
                // compressed-context branch (client cc:731-740,846-879).
                // This is normal source behavior, not a mutation.
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetA, packet = Packet(1));
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetB, packet = Packet(2));
            }
            else if (scenario == SCENARIO_BIND_UNCOMPRESSED_TARGET_FIDELITY) {
                // Same public BIND API inputs, but config maps exactly to
                // bind_use_uncompressed_context_ (client h:160-164,409), thus
                // exercising CreateUncompressedContext and inline peer metadata.
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetA, packet = Packet(1));
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetB, packet = Packet(2));
            }
            else if (scenario == SCENARIO_BIND_CREATE_FAILURE) {
                // [TEST] One ordinary BIND API call with [ENV] local failures
                // enabled. The implementation machine, not the test, decides at
                // which real nullable-return checkpoint failure occurs.
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetA, packet = Packet(1));
            }
            else if (scenario == SCENARIO_FD_REUSE_AFTER_CLOSE) {
                // Close one tunnel and create another; allocator may reuse only
                // the fd that the first state has already destroyed.
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 1, target = targetA, packet = Packet(1));
                // COMMUNICATION-OUT [ceCloseEncapsulatedSession]
                //   MasqueTestDriver --ceCloseEncapsulatedSession--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceCloseEncapsulatedSession, 1;
                // COMMUNICATION-OUT [ceSendPacket]
                //   MasqueTestDriver --ceSendPacket--> client
                //   P meaning: asynchronous enqueue. If the adjacent C++ call is locally synchronous,
                //   this send represents only its later externally observable delivery, not its immediate return value.
                send client, ceSendPacket,
                    (encapsulatedSessionId = 2, target = targetB, packet = Packet(2));
            }
        }
    }
}

machine OneTunnelDriver {
    // [TEST] Single-scenario wrapper; no C++ counterpart.
    start state Init { entry { var d: machine; d = new MasqueTestDriver(SCENARIO_ONE_TUNNEL); } }
}
machine ReuseSameTunnelDriver {
    // [TEST] Single-scenario wrapper; no C++ counterpart.
    start state Init { entry { var d: machine; d = new MasqueTestDriver(SCENARIO_REUSE_SAME_TUNNEL); } }
}
machine TwoTunnelsDriver {
    // [TEST] Single-scenario wrapper; no C++ counterpart.
    start state Init { entry { var d: machine; d = new MasqueTestDriver(SCENARIO_TWO_TUNNELS); } }
}
machine SameTargetDifferentOwnersDriver {
    // [TEST] Single-scenario wrapper; no C++ counterpart.
    start state Init { entry { var d: machine; d = new MasqueTestDriver(SCENARIO_SAME_TARGET_DIFFERENT_OWNERS); } }
}
machine StreamCloseRaceDriver {
    // [TEST] Single-scenario wrapper; no C++ counterpart.
    start state Init { entry { var d: machine; d = new MasqueTestDriver(SCENARIO_STREAM_CLOSE_RACE); } }
}
machine ConnectionCloseDriver {
    // [TEST] Single-scenario wrapper; no C++ counterpart.
    start state Init { entry { var d: machine; d = new MasqueTestDriver(SCENARIO_CONNECTION_CLOSE); } }
}
machine UnexpectedUdpSourceDriver {
    // [TEST] Single-scenario wrapper; no C++ counterpart.
    start state Init { entry { var d: machine; d = new MasqueTestDriver(SCENARIO_UNEXPECTED_UDP_SOURCE); } }
}
machine BindTargetFidelityDriver {
    // [TEST] Single-scenario wrapper; no C++ counterpart.
    start state Init { entry { var d: machine; d = new MasqueTestDriver(SCENARIO_BIND_TARGET_FIDELITY); } }
}
machine BindUncompressedTargetFidelityDriver {
    // [TEST] Single-scenario wrapper; no C++ counterpart.
    start state Init { entry { var d: machine; d = new MasqueTestDriver(SCENARIO_BIND_UNCOMPRESSED_TARGET_FIDELITY); } }
}
machine FdReuseAfterCloseDriver {
    // [TEST] Single-scenario wrapper; no C++ counterpart.
    start state Init { entry { var d: machine; d = new MasqueTestDriver(SCENARIO_FD_REUSE_AFTER_CLOSE); } }
}

machine BindCreateFailureDriver {
    // [TEST] Single-scenario wrapper; no C++ counterpart.
    start state Init { entry { var d: machine; d = new MasqueTestDriver(SCENARIO_BIND_CREATE_FAILURE); } }
}
