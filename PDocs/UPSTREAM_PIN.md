# Source revision and reproducibility

The exact line-number basis for this model is the C++ snapshot bundled under `ReferenceCpp/`.

The snapshot was supplied as `masque.zip` on 2026-10-09. It contains no `.git` metadata, so this package does **not** claim that the bundled bytes can independently prove a remote Git commit.

The previous audit was performed against Google QUICHE main at commit:

- `d22f60e1389182a78bdeddd81c130a9161afd46d`
- date: 2026-10-08

The bundled snapshot has the same audited MASQUE structure and is the authoritative source for all `Lx-Ly` references in this edition. See `SOURCE_SNAPSHOT.md` for SHA-256 hashes.

Primary files:

- `ReferenceCpp/masque_client_session.h`
- `ReferenceCpp/masque_client_session.cc`
- `ReferenceCpp/masque_server_session.h`
- `ReferenceCpp/masque_server_session.cc`
- `ReferenceCpp/masque_encapsulated_client_session.h`
- `ReferenceCpp/masque_encapsulated_client_session.cc`

Use the adjacent `*.numbered.txt` copies for direct side-by-side reading.
