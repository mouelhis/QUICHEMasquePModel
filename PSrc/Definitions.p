// ============================================================================
// QUICHE MASQUE CONNECT-UDP / CONNECT-UDP-BIND -- finite P data abstraction
// ============================================================================
// TRACEABILITY TAGS USED THROUGHOUT THIS FILE:
//   [CXX]   direct correspondence to the pinned QUICHE source block/symbol.
//   [ABS]   deliberate abstraction; comment states what is omitted and why.
//   [ENV]   environment/transport behavior outside the audited MASQUE object.
//   [GHOST] verification-only observation/provenance; never drives implementation.
//   [TEST]  finite test-harness choice with no production C++ counterpart.
//
// UPSTREAM PIN (all CPP: references in this project):
//   google/quiche @ d22f60e1389182a78bdeddd81c130a9161afd46d
//   2026-10-08, refs/heads/main when this audit was generated.
//
// Primary C++ sources:
//   quiche/quic/masque/masque_client_session.h/.cc
//   quiche/quic/masque/masque_server_session.h/.cc
//
// Scope decision:
//   * Modeled: CONNECT-UDP and CONNECT-UDP-BIND state/association/lifecycle,
//     HTTP Datagram context identity, UDP socket identity, stream identity,
//     connection/stream teardown, and transport/environment reordering/loss.
//   * Not modeled: CONNECT-IP, CONNECT-ETHERNET, byte encodings, TLS/QUIC packet
//     crypto, congestion control, memory allocation, logging, DNS contents.
//   * Every abstraction below says why it is adequate for the safety properties
//     that consume it. PDocs/ABSTRACTION_LEDGER.md gives the full ledger.
//
// IMPORTANT: integer packet IDs and integer host IDs are verification ghost
// identities. They are not fields added to the QUICHE protocol.

// Test scenarios are harness choices only; implementation machines are generic.
// [TEST] Finite scenario selector used only by PTst; no C++ counterpart.
// DEFINITION [ENUM tScenario]: Finite test-harness scenario selector. It changes only PTst stimuli/configuration; production machines remain scenario-agnostic.
enum tScenario {
    SCENARIO_ONE_TUNNEL,
    SCENARIO_REUSE_SAME_TUNNEL,
    SCENARIO_TWO_TUNNELS,
    SCENARIO_SAME_TARGET_DIFFERENT_OWNERS,
    SCENARIO_STREAM_CLOSE_RACE,
    SCENARIO_CONNECTION_CLOSE,
    SCENARIO_UNEXPECTED_UDP_SOURCE,
    SCENARIO_BIND_TARGET_FIDELITY,
    SCENARIO_BIND_UNCOMPRESSED_TARGET_FIDELITY,
    SCENARIO_BIND_CREATE_FAILURE,
    SCENARIO_FD_REUSE_AFTER_CLOSE
}

// [CXX] MasqueMode::kConnectUdp / kConnectUdpBind, consumed by
// MasqueClientSession::IsBind() and server request handling.
// Client header lines 401-409 show IsBind()/mode/list ownership.
// DEFINITION [ENUM tMasqueUdpMode]: Finite projection of the MASQUE modes relevant here: CONNECT-UDP and CONNECT-UDP-BIND.
enum tMasqueUdpMode {
    MODE_CONNECT_UDP,
    MODE_CONNECT_UDP_BIND
}

// Environment choice for packets arriving back on the proxy UDP socket.
// [ENV] Finite external UDP peer behavior; no C++ enum counterpart.
// DEFINITION [ENUM tUdpReplyMode]: Environment choice for whether a proxy UDP write receives no reply, a valid reply, an unexpected-source reply, or a nondeterministic choice.
enum tUdpReplyMode {
    UDP_REPLY_NONE,
    UDP_REPLY_VALID,
    UDP_REPLY_UNEXPECTED_SOURCE,
    UDP_REPLY_NONDET
}


// [GHOST] Classifies the concrete nullable-return checkpoints of
// GetOrCreateConnectUdpClientState (client cc:131-190,195-200,223-227).
// This is diagnostic provenance only; it does not choose whether a failure occurs.
// DEFINITION [ENUM tClientStateFailureStage]: Ghost diagnostic enum classifying source-derived failure points where GetOrCreateConnectUdpClientState can return null.
enum tClientStateFailureStage {
    CLIENT_STATE_FAIL_URI_SETUP,
    CLIENT_STATE_FAIL_STREAM_CREATE,
    CLIENT_STATE_FAIL_REQUEST_SEND
}

// [ABS] Semantic HTTP response class; collapses concrete status codes.
// DEFINITION [ENUM tResponseClass]: Abstraction of HTTP response status into 2xx/4xx/5xx classes sufficient for lifecycle and acceptance properties.
enum tResponseClass {
    RESPONSE_2XX,
    RESPONSE_4XX,
    RESPONSE_5XX
}

// [GHOST] Monitor provenance identifying which endpoint rejected a context.
// DEFINITION [ENUM tEndpointSide]: Ghost enum identifying whether a context-related observation occurred at client or server.
enum tEndpointSide {
    SIDE_CLIENT,
    SIDE_SERVER
}

// [CXX] QuicSocketAddress.  Equality is the only behavior needed by the model.
// Abstraction: host is an uninterpreted finite integer rather than IP bytes.
// DEFINITION [TYPE tAddress]: Semantic QuicSocketAddress abstraction: finite host identity plus port; preserves equality and peer identity, not IP byte representation.
type tAddress = (
    host: int,
    port: int
);

// [GHOST/ABS] Verification payload identity. `dataClass` allows later finite payload classes
// without byte-level modeling. C++ carries absl::string_view payload bytes.
// DEFINITION [TYPE tPacket]: Opaque payload abstraction with ghost packet identity used only for trace/monitor correlation.
type tPacket = (
    id: int,
    dataClass: int
);

// [CXX] HandleMasqueRequest validates CONNECT / connect-udp and path-derived
// target; client builds :method/:protocol/:scheme/:authority/:path at
// masque_client_session.cc:207-224. Server path/target parsing is around
// masque_server_session.cc:580-637.
// Abstraction: booleans represent syntactic validity; the decoded target is
// explicit because target association is what the safety properties inspect.
// [CXX/ABS] Semantic projection of CONNECT request headers used by server validation.
// DEFINITION [TYPE tConnectHeaders]: Semantic projection of CONNECT-UDP request headers and decoded target needed for server request validation.
type tConnectHeaders = (
    methodIsConnect: bool,
    protocolIsConnectUdp: bool,
    authorityPresent: bool,
    schemePresent: bool,
    pathPresent: bool,
    isBind: bool,
    target: tAddress
);

// [TEST/ENV] Environment/test controls. None of these fields are C++ member variables.
// They select admissible outcomes at external APIs (allocation, transport loss,
// event ordering). Defaults preserve the success path; scenario-specific tests
// widen behavior deliberately and document when that is an over-approximation.
// DEFINITION [TYPE tModelConfig]: Environment/test nondeterminism controls; fields are not copied from one C++ object and must not be interpreted as production configuration members.
type tModelConfig = (
    udpMode: tMasqueUdpMode,
    nondetLocalFailures: bool,
    allowDatagramLoss: bool,
    allowDatagramBeforeRequest: bool,
    allowBindContextDatagramReordering: bool,
    // [CXX] MasqueClientSession::bind_use_uncompressed_context_ (client h:405)
    // selected by set_bind_use_uncompressed_context() (client h:154-162).
    bindUseUncompressedContext: bool,
    closeAfterFirstClientDatagram: bool,
    closeConnectionAfterConnectResponse: bool,
    allowFdReuse: bool,
    udpReplyMode: tUdpReplyMode
);

// [CXX] MasqueClientSession::ConnectUdpClientState fields in
// masque_client_session.h:279-287:
//   stream_                         -> streamId
//   encapsulated_client_session_    -> encapsulatedSessionId (ghost identity)
//   target_server_address_          -> target
//   is_bind_                        -> isBind
// Visitor registration is established by ctor cc:609-623 and removed by dtor
// cc:625-632. We keep a bool so lifecycle properties can refer to this fact.
// Abstraction: the C++ object is passive state in std::list at h:404, so it is
// intentionally NOT a P machine and receives no independent scheduler.
// [CXX/ABS] Direct finite representation of one ConnectUdpClientState object.
// DEFINITION [TYPE tClientTunnelState]: Passive finite representation of one ConnectUdpClientState stored in the client list; not independently scheduled.
type tClientTunnelState = (
    // [CXX] stream_ (client h:279; ctor assignment cc:618).
    streamId: int,
    // [CXX] encapsulated_client_session_ (client h:280; cc:619).
    // [GHOST] The finite integer represents pointer identity only.
    encapsulatedSessionId: int,
    // [CXX] target_server_address_ (client h:282; cc:621).
    target: tAddress,
    // [CXX] is_bind_ (client h:287), set for BIND after insertion cc:232-235.
    isBind: bool,
    // [ABS] Derived registration fact, not a C++ bool member: ctor registers
    // the HTTP Datagram visitor at cc:619 and dtor unregisters at cc:625-632.
    datagramVisitorRegistered: bool
);

// [CXX] MasqueServerSession::ConnectUdpServerState fields in
// masque_server_session.h:154-162:
//   stream_                -> streamId
//   target_server_address_ -> target
//   fd_ (Owned)            -> fdId
//   is_bind_               -> isBind
//   bind_context_ip_map_ is modeled separately as tBindContextState entries.
// Constructor registers visitors cc:946-960; destructor unregisters socket and
// destroys fd cc:962-978. Passive object reasoning is the same as client side.
// [CXX/ABS] Direct finite representation of one ConnectUdpServerState object.
// DEFINITION [TYPE tServerTunnelState]: Passive finite representation of one ConnectUdpServerState stored in the server list; preserves stream/target/fd/mode/lifetime associations.
type tServerTunnelState = (
    // [CXX] stream_ (server h:154; ctor cc:953).
    streamId: int,
    // [CXX] target_server_address_ (server h:155; ctor cc:954).
    target: tAddress,
    // [CXX] owned fd_ (server h:156; ctor cc:955).
    fdId: int,
    // [CXX] is_bind_ (server h:158; ctor cc:957).
    isBind: bool,
    // [ABS] Derived visitor-registration fact: ctor cc:960-963; dtor 968-972.
    datagramVisitorRegistered: bool,
    // [ABS] Derived event-loop registration/ownership fact. Registration occurs
    // before state insertion at server cc:671-675; dtor unregisters cc:977-981.
    socketRegistered: bool
);

// [CXX] per-ConnectUdp{Client,Server}State bind_context_ip_map_.
// Client h:284-285, server h:160-162. Flattening object-local maps to a sequence
// keyed by stream preserves ownership and equality lookup while avoiding nested
// mutable containers in the state tuple. This is a representation abstraction,
// not a protocol behavior abstraction.
// DEFINITION [TYPE tBindContextState]: Flattened representation of one object-local BIND context-id-to-address map entry, keyed by owning stream.
type tBindContextState = (
    // [ABS] Owning-object identity. C++ map is object-local; flattening requires
    // the owning stream key so entries from different state objects cannot alias.
    streamId: int,
    // [CXX] key of bind_context_ip_map_ (client h:285; server h:160-162).
    contextId: int,
    // [CXX] map value QuicSocketAddress. Empty/default denotes open/uncompressed
    // context; nonempty denotes compressed peer mapping.
    target: tAddress
);

// HTTP Datagram semantic representation.
// [CXX]
//   * non-BIND: Context ID 0 + UDP payload (client cc:455-460;
//     server reverse cc:852-868).
//   * BIND compressed: Context ID + payload (client cc:861-875).
//   * BIND uncompressed: Context ID + IP-version/address/port + payload
//     (client cc:876-896; server reverse cc:836-862).
// Abstraction: byte serialization is replaced by semantic fields. This preserves
// all routing-relevant information while excluding parser byte-level defects;
// parser validation is therefore outside these safety claims.
// [CXX/ABS] Semantic representation of the routing-relevant HTTP Datagram fields.
// DEFINITION [TYPE tHttpDatagram]: Semantic HTTP Datagram representation preserving stream association, Context ID, optional inline BIND target, and opaque payload.
type tHttpDatagram = (
    // [GHOST] Enclosing connection identity for monitor correlation.
    connectionId: int,
    // [CXX] HTTP Datagram stream association / visitor stream_id.
    streamId: int,
    // [CXX] MASQUE Context ID encoded as a QUIC varint.
    contextId: int,
    // [ABS] Whether BIND wire bytes carry IP-version/address/port inline.
    hasInlineTarget: bool,
    // [ABS] Semantic value of those inline address bytes when present.
    inlineTarget: tAddress,
    // [ABS] Remaining UDP payload, represented by finite packet provenance.
    packet: tPacket
);

// [ABS/CXX] Semantic CONNECT request crossing the HTTP/3 boundary; fields preserve
// client SendRequest cc:207-224 and server HandleMasqueRequest cc:413-699 inputs.
// DEFINITION [TYPE tConnectRequest]: Transport record carrying the modeled CONNECT request, stream identity, connection identity, and originating client machine.
type tConnectRequest = (
    connectionId: int,
    streamId: int,
    headers: tConnectHeaders,
    client: machine
);

// [ABS/CXX] Semantic CONNECT response; preserves stream/connection and status class
// from server response construction cc:685-699 to the client callback boundary.
// DEFINITION [TYPE tConnectResponse]: Transport record carrying response class and the client destination for one CONNECT stream.
type tConnectResponse = (
    connectionId: int,
    streamId: int,
    responseClass: tResponseClass,
    client: machine
);

// [CXX/ABS] API input corresponding to SendPacket or SendConnectUdpBindPacket. The
// session-wide mode in tModelConfig determines which C++ API semantics apply.
// DEFINITION [TYPE tClientSendRequest]: External client stimulus: encapsulated-session identity, requested UDP peer, and payload.
type tClientSendRequest = (
    encapsulatedSessionId: int,
    target: tAddress,
    packet: tPacket
);

// Semantic Compression Assign capsule used by CONNECT-UDP-BIND.
// [CXX] client: CreateCompressedContext cc:731-740; server:
// OnCompressionAssignCapsule cc:1089-1107.
// DEFINITION [TYPE tBindContextAssign]: Semantic CompressionAssign capsule fields relevant to context ownership and target mapping.
type tBindContextAssign = (
    connectionId: int,
    streamId: int,
    contextId: int,
    target: tAddress
);

// Semantic UDP write. [CXX] server OnHttp3Datagram ultimately calls the UDP
// socket write path with fd_ and resolved target_address. `contextId` is ghost
// provenance retained only so the independent environment can correlate reply.
// DEFINITION [TYPE tUdpWrite]: Semantic proxy UDP write: selected stream, fd, target, context, payload, and server callback destination.
type tUdpWrite = (
    connectionId: int,
    streamId: int,
    fdId: int,
    target: tAddress,
    isBind: bool,
    contextId: int,
    packet: tPacket,
    server: machine
);

// Semantic readable callback. [CXX] OnSocketEvent gives fd, then ReadPacket gives
// PEER_ADDRESS and bytes (server cc:703-727, 733-784). Context is not provided by UDP;
// server reconstructs it from bind_context_ip_map_ when in BIND mode.
// DEFINITION [TYPE tUdpReadable]: Semantic UDP read result: connection/fd, peer source address, and payload; deliberately contains no tunnel index.
type tUdpReadable = (
    connectionId: int,
    fdId: int,
    source: tAddress,
    packet: tPacket
);

// ----------------------- monitor-only ghost records -------------------------
// [GHOST] Every record in this section is monitor-only provenance; none is a
// production QUICHE structure or an input to implementation routing decisions.
// These are independent observation records. They do not alter implementation
// decisions and exist to prevent a monitor from deriving both expected and
// actual values from the same potentially-faulty implementation lookup.
// DEFINITION [TYPE tUdpReplyProvenance]: Monitor-only independent record of the route expected for a generated UDP reply before server reverse lookup.
type tUdpReplyProvenance = (
    connectionId: int,
    expectedStreamId: int,
    expectedFdId: int,
    expectedTarget: tAddress,
    expectedContextId: int,
    isBind: bool,
    source: tAddress,
    validSource: bool,
    packetId: int
);

// [GHOST/CXX] Snapshot of client state insertion/removal (cc:226-232,487-503,567-581).
// DEFINITION [TYPE tClientTunnelEvent]: Ghost lifecycle record for one client tunnel state.
type tClientTunnelEvent = (
    connectionId: int,
    streamId: int,
    encapsulatedSessionId: int,
    target: tAddress,
    isBind: bool
);

// [GHOST/CXX] Snapshot of server state insertion/removal (cc:681-683,197-200).
// DEFINITION [TYPE tServerTunnelEvent]: Ghost lifecycle record for one server tunnel state.
type tServerTunnelEvent = (
    connectionId: int,
    streamId: int,
    fdId: int,
    target: tAddress,
    isBind: bool
);

// [GHOST/CXX] Observation of client send-side target/context before HTTP Datagram transport.
// DEFINITION [TYPE tClientDatagramEvent]: Ghost observation of client-side datagram API routing provenance.
type tClientDatagramEvent = (
    connectionId: int,
    streamId: int,
    encapsulatedSessionId: int,
    target: tAddress,
    isBind: bool,
    contextId: int,
    packetId: int
);

// [GHOST/CXX] Observation of server-selected UDP peer/fd at WritePacket cc:1080-1086.
// DEFINITION [TYPE tProxyForwardEvent]: Ghost observation of client-to-target forwarding at the proxy UDP boundary.
type tProxyForwardEvent = (
    connectionId: int,
    streamId: int,
    fdId: int,
    target: tAddress,
    isBind: bool,
    contextId: int,
    packetId: int
);

// [GHOST/CXX] Observation of server UDP read/source-validation path cc:729-827.
// DEFINITION [TYPE tUdpObservedEvent]: Ghost observation of reverse UDP read/validation metadata.
type tUdpObservedEvent = (
    connectionId: int,
    fdId: int,
    source: tAddress,
    expectedTarget: tAddress,
    packetId: int
);

// [GHOST/CXX] Observation of server reverse SendHttp3Datagram selection cc:836-862.
// DEFINITION [TYPE tProxyReturnEvent]: Ghost observation of server-to-client reverse HTTP Datagram routing choice.
type tProxyReturnEvent = (
    connectionId: int,
    streamId: int,
    fdId: int,
    expectedTarget: tAddress,
    isBind: bool,
    contextId: int,
    packetId: int
);

// [GHOST/CXX] `decodedTarget` is the peer address reconstructed from Context ID/address
// metadata. `deliveredTarget` is the address actually passed to
// EncapsulatedClientSession::ProcessPacket. Keeping both is essential for the
// CONNECT-UDP-BIND data-flow property.
// DEFINITION [TYPE tClientDeliveryEvent]: Ghost observation of client delivery with both decoded peer address and address actually passed to ProcessPacket.
type tClientDeliveryEvent = (
    connectionId: int,
    streamId: int,
    encapsulatedSessionId: int,
    isBind: bool,
    decodedTarget: tAddress,
    deliveredTarget: tAddress,
    contextId: int,
    packetId: int
);

// [GHOST] Monitor key for a stream within a connection.
// DEFINITION [TYPE tStreamKey]: Monitor key identifying a stream within a connection.
type tStreamKey = (
    connectionId: int,
    streamId: int
);

// [GHOST] Monitor key mirroring client GetOrCreate semantic identity cc:102-110.
// DEFINITION [TYPE tClientSemanticKey]: Monitor key identifying a client tunnel by connection, encapsulated-session, target, and mode.
type tClientSemanticKey = (
    connectionId: int,
    encapsulatedSessionId: int,
    target: tAddress,
    isBind: bool
);

// [GHOST] Monitor key for live fd ownership within a connection.
// DEFINITION [TYPE tFdKey]: Monitor key identifying a socket fd within a connection.
type tFdKey = (
    connectionId: int,
    fdId: int
);

// [GHOST] Monitor key correlating a packet observation with an fd.
// DEFINITION [TYPE tFdPacketKey]: Monitor key identifying a particular packet observed on an fd.
type tFdPacketKey = (
    connectionId: int,
    fdId: int,
    packetId: int
);

// [GHOST] Monitor correlation key for independently generated reply provenance.
// DEFINITION [TYPE tReplyKey]: Monitor key correlating a ghost packet identity with one connection.
type tReplyKey = (
    connectionId: int,
    packetId: int
);

// --------------------------- pure helper functions --------------------------
// [ABS] Constructor for the finite QuicSocketAddress abstraction defined above.
fun Address(host: int, port: int): tAddress {
    return (host = host, port = port);
}

// [CXX] default-constructed QuicSocketAddress() used by BIND creation at client
// cc:426-433 and server cc:600-604. `(0,0)` is only the finite-model encoding.
fun EmptyAddress(): tAddress {
    return (host = 0, port = 0);
}

// [ABS/CXX] Tests the finite encoding of a default/uninitialized QuicSocketAddress.
fun IsEmptyAddress(address: tAddress): bool {
    return address == EmptyAddress();
}

// [ENV] Environment-only construction of a peer unequal to the expected target.
fun OtherAddress(address: tAddress): tAddress {
    return (host = address.host + 100, port = address.port);
}

// [GHOST] Constructs finite payload provenance for the test/environment boundary.
fun Packet(id: int): tPacket {
    return (id = id, dataClass = 0);
}

// [ABS] External operation outcome abstraction. Call sites name the concrete C++
// operation in comments; this helper only selects success/failure.
fun BranchSucceeds(config: tModelConfig): bool {
    if (!config.nondetLocalFailures) return true;
    return $;
}

// [ABS] Abstracts SendHttp3Datagram's local acceptance status. The checked routing
// properties are conditional on accepted datagrams, so exact status enum values
// are irrelevant; rejection is retained as a possible local outcome.
fun DatagramAcceptedLocally(config: tModelConfig): bool {
    if (!config.nondetLocalFailures) return true;
    return $;
}

// [ENV] HTTP Datagram delivery is unreliable. This is an environment boundary, not a
// C++ branch in MasqueClientSession/MasqueServerSession.
fun DatagramDelivered(config: tModelConfig): bool {
    if (!config.allowDatagramLoss) return true;
    return $;
}

// [CXX] GetOrCreateConnectUdpClientState client cc:102-110 compares target,
// encapsulated session and IsBind(). The caller supplies an empty target in BIND
// mode at cc:430-431, so the helper itself performs the same three-way equality
// rather than weakening target comparison.
fun FindClientState(
    states: seq[tClientTunnelState],
    encapsulatedSessionId: int,
    requestedTarget: tAddress,
    isBind: bool
): (found: bool, index: int) {
    var i: int;
    i = 0;
    while (i < sizeof(states)) {
        if (states[i].encapsulatedSessionId == encapsulatedSessionId &&
            states[i].isBind == isBind &&
            states[i].target == requestedTarget) {
            return (found = true, index = i);
        }
        i = i + 1;
    }
    return (found = false, index = -1);
}

// [CXX] state removal / visitor dispatch uses stream identity (client
// OnStreamClosed cc:563-577; per-state visitor is registered on its stream).
fun FindClientStateByStream(
    states: seq[tClientTunnelState],
    streamId: int
): (found: bool, index: int) {
    var i: int;
    i = 0;
    while (i < sizeof(states)) {
        if (states[i].streamId == streamId) return (found = true, index = i);
        i = i + 1;
    }
    return (found = false, index = -1);
}

// [CXX] semantic association for client BIND contexts: client h:284-285 and
// GetContextForAddress cc:827-843.
fun FindBindContextByAddress(
    contexts: seq[tBindContextState],
    streamId: int,
    target: tAddress
): (found: bool, index: int) {
    var i: int;
    i = 0;
    while (i < sizeof(contexts)) {
        if (contexts[i].streamId == streamId && contexts[i].target == target) {
            return (found = true, index = i);
        }
        i = i + 1;
    }
    return (found = false, index = -1);
}

// [CXX] EXACT semantic correspondence to client GetContextForAddress cc:827-843:
// prefer an exact compressed target; otherwise return an uncompressed context
// (map value == default/empty QuicSocketAddress) if one exists.
fun FindBindContextForSend(
    contexts: seq[tBindContextState],
    streamId: int,
    target: tAddress
): (found: bool, index: int) {
    var i: int;
    var uncompressedIndex: int;
    uncompressedIndex = -1;
    i = 0;
    while (i < sizeof(contexts)) {
        if (contexts[i].streamId == streamId) {
            if (contexts[i].target == target) {
                return (found = true, index = i);
            }
            if (IsEmptyAddress(contexts[i].target)) {
                uncompressedIndex = i;
            }
        }
        i = i + 1;
    }
    if (uncompressedIndex >= 0) {
        return (found = true, index = uncompressedIndex);
    }
    return (found = false, index = -1);
}

// [CXX] Corresponds to the `uncompressed_context` fallback accumulated by the server
// reverse path at server cc:788-818.
fun FindUncompressedBindContext(
    contexts: seq[tBindContextState],
    streamId: int
): (found: bool, index: int) {
    return FindBindContextByAddress(contexts, streamId, EmptyAddress());
}

// [CXX] Models per-state bind_context_ip_map_ lookup by Context ID used by
// client/server BIND datagram decode paths (client cc:674-718; server cc:1021-1043).
fun FindBindContextById(
    contexts: seq[tBindContextState],
    streamId: int,
    contextId: int
): (found: bool, index: int) {
    var i: int;
    i = 0;
    while (i < sizeof(contexts)) {
        if (contexts[i].streamId == streamId && contexts[i].contextId == contextId) {
            return (found = true, index = i);
        }
        i = i + 1;
    }
    return (found = false, index = -1);
}

// [CXX] server dispatch of an HTTP Datagram is per stream-owned visitor; the
// finite model resolves that ownership explicitly by stream ID.
fun FindServerStateByStream(
    states: seq[tServerTunnelState],
    streamId: int
): (found: bool, index: int) {
    var i: int;
    i = 0;
    while (i < sizeof(states)) {
        if (states[i].streamId == streamId) return (found = true, index = i);
        i = i + 1;
    }
    return (found = false, index = -1);
}

// [CXX] EXACT algorithmic correspondence: server
// HandleConnectUdpSocketEvent cc:729-740 uses absl::c_find_if over
// connect_udp_server_states_ and compares connect_udp.fd() == fd.
fun FindServerStateByFd(
    states: seq[tServerTunnelState],
    fdId: int
): (found: bool, index: int) {
    var i: int;
    i = 0;
    while (i < sizeof(states)) {
        if (states[i].fdId == fdId) return (found = true, index = i);
        i = i + 1;
    }
    return (found = false, index = -1);
}

// [CXX] Server BIND reverse path searches context-address pairs for peer_address at
// server cc:784-827. This finite helper models the exact-address compressed
// context case. The open/uncompressed fallback is represented separately by
// FindUncompressedBindContext and inlineTarget, matching server cc:788-818 and
// reverse serialization cc:836-856.
fun FindBindContextByTarget(
    contexts: seq[tBindContextState],
    streamId: int,
    target: tAddress
): (found: bool, index: int) {
    return FindBindContextByAddress(contexts, streamId, target);
}

// [CXX] HandleMasqueRequest performs more detailed syntax/path checks. These five
// booleans preserve the accept/reject partition relevant to state creation.
fun HeadersAccepted(headers: tConnectHeaders): bool {
    return headers.methodIsConnect &&
           headers.protocolIsConnectUdp &&
           headers.authorityPresent &&
           headers.schemePresent &&
           headers.pathPresent;
}

// [CXX] client constructs CONNECT headers cc:207-224. In BIND mode the target URI
// parameters are * / * while the state target is an empty socket address; this
// semantic model uses EmptyAddress plus isBind instead of literal URL bytes.
fun MakeConnectHeaders(target: tAddress, isBind: bool): tConnectHeaders {
    var encodedTarget: tAddress;
    if (isBind) encodedTarget = EmptyAddress();
    else encodedTarget = target;
    return (
        methodIsConnect = true,
        protocolIsConnectUdp = true,
        authorityPresent = true,
        schemePresent = true,
        pathPresent = true,
        isBind = isBind,
        target = encodedTarget
    );
}

// [TEST] Scenario-to-environment configuration only; there is no C++ counterpart.
// It widens or narrows admissible outcomes without changing implementation logic.
fun ConfigForScenario(scenario: tScenario): tModelConfig {
    var config: tModelConfig;

    config = (
        udpMode = MODE_CONNECT_UDP,
        nondetLocalFailures = false,
        allowDatagramLoss = true,
        allowDatagramBeforeRequest = true,
        allowBindContextDatagramReordering = false,
        bindUseUncompressedContext = false,
        closeAfterFirstClientDatagram = false,
        closeConnectionAfterConnectResponse = false,
        allowFdReuse = false,
        udpReplyMode = UDP_REPLY_VALID
    );

    if (scenario == SCENARIO_STREAM_CLOSE_RACE) {
        config.closeAfterFirstClientDatagram = true;
        config.allowDatagramBeforeRequest = false;
        config.allowDatagramLoss = false;
    }
    if (scenario == SCENARIO_CONNECTION_CLOSE) {
        config.closeConnectionAfterConnectResponse = true;
        config.allowDatagramLoss = false;
    }
    if (scenario == SCENARIO_UNEXPECTED_UDP_SOURCE) {
        config.udpReplyMode = UDP_REPLY_UNEXPECTED_SOURCE;
        config.allowDatagramLoss = false;
        config.allowDatagramBeforeRequest = false;
    }
    if (scenario == SCENARIO_BIND_TARGET_FIDELITY) {
        // Deterministic successful compressed-context path isolates the C++ BIND
        // return-address data flow. No injected implementation mutation is used.
        config.udpMode = MODE_CONNECT_UDP_BIND;
        config.allowDatagramLoss = false;
        config.allowDatagramBeforeRequest = false;
        config.allowBindContextDatagramReordering = false;
        config.bindUseUncompressedContext = false;
    }
    if (scenario == SCENARIO_BIND_UNCOMPRESSED_TARGET_FIDELITY) {
        // Same property through the source's open/uncompressed-context branch:
        // client CreateUncompressedContext cc:740-752 and packet encoding
        // cc:876-896; server reverse reconstruction cc:836-862.
        config.udpMode = MODE_CONNECT_UDP_BIND;
        config.allowDatagramLoss = false;
        config.allowDatagramBeforeRequest = false;
        config.allowBindContextDatagramReordering = false;
        config.bindUseUncompressedContext = true;
    }
    if (scenario == SCENARIO_BIND_CREATE_FAILURE) {
        // [ENV] Explore real nullable-return checkpoints in client
        // GetOrCreateConnectUdpClientState. This is not a mutation: URI setup,
        // stream creation, and SendRequest all have nullptr exits in source.
        config.udpMode = MODE_CONNECT_UDP_BIND;
        config.nondetLocalFailures = true;
        config.allowDatagramLoss = false;
        config.allowDatagramBeforeRequest = false;
    }
    if (scenario == SCENARIO_FD_REUSE_AFTER_CLOSE) {
        // OS descriptors may be reused after Destroy(). This widens allocation
        // identity only; it does not invent a wrong lookup. Whether a queued
        // callback can survive UnregisterSocket is deliberately NOT assumed.
        config.allowFdReuse = true;
        config.allowDatagramLoss = false;
        config.allowDatagramBeforeRequest = false;
    }
    return config;
}
