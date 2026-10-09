# PForeign

Version 1 intentionally uses **no foreign runtime code**.

This is a fidelity choice. All protocol-visible state, equality tests, branch
outcomes and scheduler-relevant behavior stay inside P so that PChecker can
control them. In particular, addresses and packet identities are finite P
values rather than C# objects.

Foreign code should be introduced only for pure deterministic helpers whose
semantics cannot affect scheduling or hide a branch that exists in QUICHE.
Examples that may be added later are URI canonicalization trace adapters or
parsers used only during concrete-trace replay.
