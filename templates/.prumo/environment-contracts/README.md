# Environment contracts

Layer 8: the environment the build and the tests run in is declared, not assumed, and can be
reproduced on any runner. A test that depends on the state of the runner is a bet, not a test.

One file per environment (`ENV-<name>.md`), stating:

- the declaration that builds it (for example `flake.nix` with a default dev shell, or a pinned
  container image by digest) and the command every CI job runs inside it;
- tool versions that matter, pinned;
- external services the tests reach, and how they are provided (local, stub, none);
- what running outside the environment means: the build is invalid, not degraded.

Nothing in this directory is checked mechanically yet. It is a declaration a human reviews.
