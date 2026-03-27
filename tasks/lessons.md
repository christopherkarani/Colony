# Lessons

- Local path package dependencies are for iteration only. Production manifests and GitHub releases must resolve published GitHub tags by default, and any local package override must be explicit opt-in so downstream users never need sibling checkouts to build.
- When a migration requirement says "no changes in the dependency repo" or demands verification against a published tag, do not solve the task with local dependency-repo SPI or shim work. Prove the public dependency surface first, and if it is insufficient, stop and surface that constraint before implementing.
