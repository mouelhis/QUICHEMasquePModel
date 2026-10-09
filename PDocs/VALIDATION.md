# Package validation

This package was statically validated after the final inline-traceability pass.

## Checks completed in the generation environment

- 17 `.p` files scanned; delimiter balance: **0 issues**.
- every P function, P state, start state, and event handler has a nearby explicit
  `[CXX]`, `[ABS]`, `[ENV]`, `[GHOST]`, or `[TEST]` correspondence tag;
- every `type` and `enum` in `PSrc/Definitions.p` has a nearby traceability tag;
- every event declaration in `PSrc/Events.p` has a nearby traceability tag;
- all 8 `PSpec/*.p` files contain an explicit temporal `G(...)` requirement;
- 16 machine declarations, 10 spec declarations, and 15 test declarations were
  found with **no duplicate names**;
- the former deliberate `index = 0` reverse-route mutation is absent;
- the faithful reverse route contains
  `FindServerStateByFd(serverStates, udp.fdId)` and indexes through the returned
  `stateLookup.index`;
- old `PDocs/faithfulness` material was removed to avoid stale/conflicting source
  mappings;
- final ZIP integrity is checked with `unzip -t` after packaging.

## Compiler-validation limitation

The generation container does **not** contain the P compiler or the .NET runtime.
Therefore this archive is intentionally **not claimed compiler-validated here**.
Run this first in the existing P environment:

```bash
p compile
```

Then run the focused checks, for example:

```bash
p check -tc tcTwoTunnelIsolation -i 10000 --sch-pct 3
p check -tc tcBindStateCreationSafety -i 10000 --sch-pct 3
p check -tc tcBindTargetFidelity -i 10000 --sch-pct 3
p check -tc tcBindUncompressedTargetFidelity -i 10000 --sch-pct 3
```

A P compiler error is a packaging/model defect, not evidence of a QUICHE bug. A
P counterexample is a source-level candidate until its path is mapped back to the
pinned C++ and reproduced with a focused executable C++ test.
