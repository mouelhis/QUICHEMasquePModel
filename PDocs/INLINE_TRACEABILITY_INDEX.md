# Inline traceability index

This file is only an index; the same correspondence appears in P comments.

| P concept | C++ source block |
|---|---|
| client state lookup/create | `ReferenceCpp/masque_client_session.cc:L99-L233` |
| non-BIND client send | `masque_client_session.cc:L441-L469` |
| BIND client send | `masque_client_session.cc:L422-L439` |
| client stream close/removal | `masque_client_session.cc:L552-L593` |
| client explicit tunnel close | `masque_client_session.cc:L483-L499` |
| client state ctor/dtor visitors | `masque_client_session.cc:L609-L632` |
| client reverse datagram decode/delivery | `masque_client_session.cc:L658-L725` |
| BIND context creation/lookup/encoding | `masque_client_session.cc:L727-L896` |
| server request validation/socket setup | `masque_server_session.cc:L413-L699` |
| server connection/stream cleanup | `masque_server_session.cc:L183-L207` |
| event-loop dispatch | `masque_server_session.cc:L703-L727` |
| server reverse UDP lookup/read/validation | `masque_server_session.cc:L729-L874` |
| server state ctor/dtor/socket ownership | `masque_server_session.cc:L946-L978` |
| server client->UDP decode/write | `masque_server_session.cc:L1013-L1087` |
| server BIND context assign/close | `masque_server_session.cc:L1089-L1125` |
| encapsulated delivery into inner QUIC | `masque_encapsulated_client_session.cc:L58-L63` |
