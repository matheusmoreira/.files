# Round-zero checks

Deterministic checks the coordinator runs before spawning any
review agent. Scripts decide what scripts can decide; agents get
the rest. Every check here was once a finding an agent had to
make — the goal is that no agent ever has to make it again.

Protocol:

1. The project's own gates run first: clean build, full test
   suite. A project's suite is its accumulated checker — when a
   review round finds a mechanical class, the check belongs THERE
   (it outlives this skill and runs in CI), not here.
2. These generic checks run second. They are project-independent
   git and text hygiene only.
3. Anything red is coordinator work to triage before critics
   launch.

Conventions: each check is a standalone bash script taking
`<repository> <commit-range>`, printing findings to stdout, one
per line, and exiting nonzero when it found anything.
