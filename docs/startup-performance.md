# Emacs startup performance measurement

Use this procedure for issue #80 Phase 2 before/after comparisons.

1. Use a normal machine state with required Emacs packages already installed.
2. Start Emacs normally; do not use `p3/config-reload` as a substitute for a fresh process.
3. After startup completes, run `M-x p3/startup-profile-report` and copy the entire report.
4. Exit Emacs completely and repeat until three reports are captured.
5. Capture three fresh-process reports on GNU/Linux and three on native Windows where practical.
6. Retain every sample; note a suspected cold-filesystem outlier rather than silently dropping it.

Compare `Total init`, `package-initialize`, `use-package-bootstrap`, aggregate `use-package-ensure`, config-cache phases, and material `module:*` phases. A current-cache startup normally has no `config-cache-build` phase.

Record the Phase 2A baseline on PR #85 and/or issue #80 **before PR #85 is merged**. Repeat the identical procedure after Phase 2B. CI verifies structural behavior only and must not enforce startup-time thresholds.

Hosted-runner timings are not a substitute for workstation baselines: runner provisioning, filesystem caches, package state, and virtualization differ from normal interactive use. If one workstation platform is unavailable during Phase 2A, record that explicitly rather than substituting a CI wall-clock value.
