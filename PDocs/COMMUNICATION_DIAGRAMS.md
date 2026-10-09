# Communication diagrams

This document is a reading aid. The authoritative mapping remains inline in `PSrc/*.p` and `PSpec/*.p`.

## Global CONNECT-UDP path

```text
 External client/API
       |
       | ceSendPacket
       v
 MasqueClientSession
       |
       | teConnectRequest       (reliable request stream)
       | teClientDatagram       (unreliable HTTP Datagram)
       | teBindContextAssign    (reliable capsule stream, BIND only)
       v
 Http3Transport
       |
       | seConnectRequest
       | seHttpDatagram
       | seBindContextAssign
       v
 MasqueServerSession
       |
       | ueProxyWrite           (semantic UDP WritePacket boundary)
       v
 UdpEnvironment -----> UDP peer
       ^                   |
       | seUdpReadable     | reply
       +-------------------+
       |
 MasqueServerSession
       |
       | teServerDatagram
       v
 Http3Transport
       |
       | ceHttpDatagram
       v
 MasqueClientSession
       |
       | ProcessPacket(payload, address)
       v
 EncapsulatedClientSession
```

`me*` events are ghost observation edges from implementation/environment steps to monitors. They never feed back into the implementation machines.

## Why request and datagram edges are distinct

The C++ request/capsule paths use stream semantics, while HTTP Datagrams are unreliable. The model therefore permits loss/reordering only on the datagram edges. It also permits cross-channel ordering where a DATAGRAM can become observable before the reliable CONNECT request has installed the server visitor; the model represents that as a lower-layer early drop rather than calling a non-existent `ConnectUdpServerState`.

## Local diagrams

Every `on` and every executable P `send` has an adjacent `COMMUNICATION-IN` or `COMMUNICATION-OUT` comment. These comments are intentionally repetitive so a reader can understand a file without switching to this document.
