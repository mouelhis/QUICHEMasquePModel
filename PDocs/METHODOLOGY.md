# Verification methodology

Methodological inspiration: **“Lessons Learned from Incorporating Formal Methods in Huawei Cloud Reliability,” EuroSys 2026, DOI 10.1145/3767295.3803626.** The paper motivates using precise specifications and systematic state-space exploration while keeping the relationship between the formal model and implementation evidence explicit.

For this project the practical discipline is:

1. **Pin implementation source.** All line references point to one immutable QUICHE revision.
2. **Model implementation behavior, not desired behavior.** If source behavior is suspicious, the P implementation mirrors it; the desired rule belongs in a separate temporal monitor.
3. **Document every abstraction at the point of use.** An abstraction must say what is dropped and why the property remains meaningful.
4. **Keep the oracle independent.** `[GHOST]` provenance observes boundaries and never affects implementation choices. Expected and actual values should not both be derived from the lookup under test.
5. **Use mutation only to validate monitors, not to claim bugs.** The earlier manual `index = 0` experiment is not part of this faithful package.
6. **Distinguish model counterexample from implementation defect.** A candidate must be translated back into a C++ execution/test before a community bug claim.

The P model is therefore best viewed as an implementation-oriented executable abstraction plus independent safety oracles, not as a proof of all C++/QUIC behavior.
