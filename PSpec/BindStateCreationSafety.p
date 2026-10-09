// ============================================================================
// TEMPORAL PROPERTY: CONNECT-UDP-BIND nullable-state dereference safety
// SOURCE SNAPSHOT: bundled under ReferenceCpp/; baseline lineage google/quiche d22f60e (2026-10-08)
// ============================================================================
// MODEL-VALIDATION PRINCIPLE:
//   This monitor is specified independently from implementation routing state.
//   Mutation tests may be used only to validate monitor sensitivity; seeded faults
//   are never reported as implementation bugs.
//
// MONITOR REFINEMENT RULE:
//   The formula is the requirement. This P monitor recognizes a finite bad
//   prefix exposed by [GHOST] observation; it does not alter client control flow.
//
// Requirement BC-1:
//
//   G( PrepareBindPacket(state) -> state != null )
//
// Equivalent bad-prefix form used here:
//
//   G( !BindPrepareOnNullState )
//
// [CXX] Evidence at the pinned revision:
//   * GetOrCreateConnectUdpClientState can return nullptr during URI/template
//     processing: client cc:L131-L190.
//   * It can return nullptr when CreateOutgoingBidirectionalStream fails:
//     client cc:L191-L196.
//   * It can return nullptr when SendRequest returns 0: client cc:L219-L224.
//   * SendPacket checks `connect_udp == nullptr`: client cc:L444-L449.
//   * SendConnectUdpBindPacket has no equivalent check and calls
//     `connect_udp->PrepareBindPacket(...)`: client cc:L422-L433.
//
// [ABS] `meBindPrepareOnNullState` is emitted at the first source-derived point
// where a BIND call would dereference null. The P handler then terminates that
// API action; we do not attempt to model C++ undefined behavior after the null
// dereference. This is sufficient for the safety property above.

spec BindStateCreationSafety observes meBindPrepareOnNullState {
    // [GHOST] One-state safety automaton for BC-1; no production C++ state.
    start state Safe {
        // [GHOST/CXX] Bad action corresponds to BIND caller cc:426-433 dereferencing
        // a result that GetOrCreate... may return nullptr at cc:131-190,195-200,223-227.
        // COMMUNICATION-IN [meBindPrepareOnNullState]
        //   implementation/environment announce --meBindPrepareOnNullState--> BindStateCreationSafety
        //   P meaning: dequeue/observe this event, then execute the handler atomically
        //   until the next explicit scheduling point; C++ correspondence is documented in the adjacent [CXX] block.
        on meBindPrepareOnNullState do (stage: tClientStateFailureStage) {
            assert false,
                format("CONNECT-UDP-BIND would dereference null ConnectUdpClientState at failure stage {0}", stage);
        }
    }
}
