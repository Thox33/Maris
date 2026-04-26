# Authority Model Decision

See also:

- [`../index.md`](../index.md)
- [`../architecture/overview.md`](../architecture/overview.md)
- [`../architecture/actor_model.md`](../architecture/actor_model.md)

Status: accepted on 2026-04-05

## Decision

The project uses a hybrid authority model.

The chosen near-term baseline is:

- movement remains trusted co-op and owning-peer-authoritative
- inventory, world mutation, structures, placement, and persistence remain host-authoritative
- block and structure breaking moves to host-authoritative damage, cooldown, and completion
- clients render replicated crack feedback from the host-owned damaged-target state

This means the client only starts or refreshes primary-use intent while the host owns canonical damaged-target progression, hit timing, and completion.

## Context

The project already had a mixed model in practice:

- player movement is processed on the owning peer and replicated outward
- world tile mutation is performed on the host
- structure mutation is performed on the host
- inventory and held-slot state are performed on the host
- saves are written on the host

The main unresolved area was breaking and primary item use.

At the time of this decision, break progress is accumulated locally on the interacting client and only the final break request is validated on the host. That is responsive, but it makes timing authority ambiguous and keeps mining separate from future item-use rules.

## Why This Direction

This direction keeps the current project pragmatic for trusted co-op while fixing the subsystem that would become expensive to retrofit later.

Host-authoritative breaking is preferred because:

- cooperative mining becomes straightforward because multiple players can damage the same target state
- the host can validate range, target identity, equipped item, hit cadence, and completion in one place
- future modifiers such as tools, buffs, debuffs, and actor-specific mining speed become easier to implement consistently
- mining can share a unified item-use cooldown model with later combat or tool interactions
- clients can render shared crack feedback from host-emitted stage updates, so responsiveness does not require client-owned break completion

Movement is intentionally not changed in the same step because:

- the current trusted-co-op movement path is acceptable for the project's scope
- host-authoritative movement is a larger rollback/prediction/interpolation problem
- the project gets more value right now from fixing interaction authority than from rebuilding movement replication

## Rejected Alternatives

### Fully client-authoritative breaking

Rejected because it makes cooperative mining, server-side hit cadence, cooldown rules, and future modifiers harder to keep consistent.

### Full host-authoritative movement and breaking in one change

Rejected for now because it is a much larger behavioral rewrite and would mix two separate architecture changes into one rollout.

## Consequences

After this decision, the intended authority profile is:

- movement: trusted co-op, owning-peer-authoritative, remote-smoothed
- block/structure breaking: host-authoritative target damage, item-use cooldown, and completion
- placement: host-authoritative validation and mutation
- inventory: host-authoritative state
- chunk and structure state: host-authoritative mutation and replication
- persistence: host-authoritative writes

Expected implementation shape for breaking:

- client sends start/stop item-use intent against a target
- host resolves the active item from authoritative inventory state
- host enforces item-use cooldown and applies discrete hits to a canonical damaged-target state
- multiple players may damage the same target together
- damaged targets remain visible and resumable for a short timeout before clearing
- host emits crack-stage updates and final mutation once durability is exhausted
- clients render replicated crack feedback but must not own hit timing or break completion

## Follow-Up

Implementation work following this decision should:

- keep the host-side version as a unified use-authority path, not as a separate client-timed mining system
- keep movement behavior unchanged during that refactor
- extend the same authority lane later if combat or other primary-use actions join it
