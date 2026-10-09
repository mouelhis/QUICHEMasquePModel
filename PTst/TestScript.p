// [TEST] Test selection only; no production C++ counterpart.
// Test selection only. Each implementation machine is shared across scenarios;
// no test-specific fault is injected into MasqueClientSession/ServerSession.

test tcOneTunnelIsolation [main=OneTunnelDriver]:
    assert TunnelIsolation in
    (union QUICHEMasque, { MasqueTestDriver, OneTunnelDriver });

test tcReusePreservesClientUniqueness [main=ReuseSameTunnelDriver]:
    assert ClientStateUniqueness in
    (union QUICHEMasque, { MasqueTestDriver, ReuseSameTunnelDriver });

test tcTwoTunnelIsolation [main=TwoTunnelsDriver]:
    assert TunnelIsolation in
    (union QUICHEMasque, { MasqueTestDriver, TwoTunnelsDriver });

test tcSameTargetDifferentOwners [main=SameTargetDifferentOwnersDriver]:
    assert ClientStateUniqueness in
    (union QUICHEMasque, { MasqueTestDriver, SameTargetDifferentOwnersDriver });

test tcServerStateUniqueness [main=TwoTunnelsDriver]:
    assert ServerStateUniqueness in
    (union QUICHEMasque, { MasqueTestDriver, TwoTunnelsDriver });

test tcDatagramContextZero [main=TwoTunnelsDriver]:
    assert DatagramContextZero in
    (union QUICHEMasque, { MasqueTestDriver, TwoTunnelsDriver });

test tcStreamCloseLifecycle [main=StreamCloseRaceDriver]:
    assert TunnelLifecycle in
    (union QUICHEMasque, { MasqueTestDriver, StreamCloseRaceDriver });

test tcUnexpectedUdpSourceDropped [main=UnexpectedUdpSourceDriver]:
    assert UnexpectedUdpSourceDropped in
    (union QUICHEMasque, { MasqueTestDriver, UnexpectedUdpSourceDriver });

test tcConnectionCleanup [main=ConnectionCloseDriver]:
    assert ConnectionCleanup in
    (union QUICHEMasque, { MasqueTestDriver, ConnectionCloseDriver });

// EXPECTED TO EXPOSE CURRENT-SOURCE CANDIDATE BT-1 WITHOUT A SEEDED MUTATION.
// If this fails, inspect source data-flow and reproduce in C++ before reporting.
test tcBindTargetFidelity [main=BindTargetFidelityDriver]:
    assert BindTargetFidelity in
    (union QUICHEMasque, { MasqueTestDriver, BindTargetFidelityDriver });

test tcBindForwardFidelity [main=BindTargetFidelityDriver]:
    assert BindForwardFidelity in
    (union QUICHEMasque, { MasqueTestDriver, BindTargetFidelityDriver });

// Same source-level properties through the uncompressed/open-context branch.
test tcBindUncompressedTargetFidelity [main=BindUncompressedTargetFidelityDriver]:
    assert BindTargetFidelity in
    (union QUICHEMasque, { MasqueTestDriver, BindUncompressedTargetFidelityDriver });

test tcBindUncompressedForwardFidelity [main=BindUncompressedTargetFidelityDriver]:
    assert BindForwardFidelity in
    (union QUICHEMasque, { MasqueTestDriver, BindUncompressedTargetFidelityDriver });

// Exploratory OS fd reuse only; no stale callback is injected. This should not
// be called a bug unless a counterexample is mapped to event-loop semantics and
// reproduced against C++.
test tcFdReuseIsolation [main=FdReuseAfterCloseDriver]:
    assert TunnelIsolation in
    (union QUICHEMasque, { MasqueTestDriver, FdReuseAfterCloseDriver });

// Source-derived failure-path candidate BC-1; no implementation mutation.
// With nondeterministic real GetOrCreate failure checkpoints, P should find a
// bad prefix if the BIND caller reaches PrepareBindPacket with nullptr.
test tcBindStateCreationSafety [main=BindCreateFailureDriver]:
    assert BindStateCreationSafety in
    (union QUICHEMasque, { MasqueTestDriver, BindCreateFailureDriver });
