# Mob AI Operating Model Design

Date: 2026-07-31

## Purpose

Promptbanken needs a practical way to let specialized AI agents improve
different parts of the product without turning shared files and external
contracts into uncontrolled integration points.

The first version of Mob AI is an internal engineering and content workflow.
It does not add a user-facing AI team, autonomous production access, or a new
application surface.

## Decision

Use the existing module map as the control plane for agent work. Every task
gets one primary module, an explicit write boundary, a named interface
artifact, acceptance criteria, and required verification. Implementation,
independent verification, contract judgment, and release remain separate
responsibilities when risk requires it.

This approach is preferred over:

1. A single general agent with repository-wide write access, which would be
   faster to start but would preserve the current collision risks.
2. A fully automated multi-agent platform, which would add orchestration code
   before the team has validated the operating model on real tasks.

## Scope

This design creates four documentation artifacts:

- `docs/module-map-2026-07-31.md`: module ownership, interfaces, and maturity.
- `docs/mob-ai-operating-model.md`: roles, workflow, handoffs, and definition
  of done.
- `docs/agent-boundaries.md`: allowed write surfaces and verification rules.
- this design specification: rationale, scope, and acceptance criteria.

No production code, prompt content, database schema, MCP contract, deployment
configuration, or runtime behavior changes in this phase.

## Architecture

The operating model has four layers:

1. **Task control:** a mob lead creates a task card with module, write scope,
   contract, acceptance criteria, verification, and release scope.
2. **Module execution:** one specialized agent implements within the approved
   boundary.
3. **Independent judgment:** QA checks behavior and a contract judge checks
   external interfaces or collision points.
4. **Release control:** a release agent verifies repository, build, deploy,
   and live state; the human product owner retains material risk decisions.

Green modules may execute in parallel when write sets are disjoint. Yellow
modules serialize work around shared files. Red modules accept only boundary
extraction and contract-building tasks until their maturity improves.

## Interface and Data Flow

The task card is the handoff contract between roles. It carries:

```text
goal -> module -> allowed writes -> interface artifact -> acceptance criteria
     -> verification evidence -> independent judgment -> release decision
```

Agents may read broadly to understand dependencies. They may only write to
the paths named in the task card. Discovering a required out-of-scope edit is
a routing event: the task returns to the mob lead for decomposition or an
explicitly revised boundary.

## Failure Handling

- Ambiguous module or write scope: stop before implementation and split or
  clarify the task.
- Contract failure: return to the implementing module; do not waive it inside
  the same agent pass.
- Shared-file conflict: serialize work and assign one owner for that collision
  point.
- Missing automated test: require a documented manual flow and record the
  residual risk.
- Production or secret requirement outside the task: stop and request human
  authorization.

## Verification Strategy

Verification scales with the module:

- Frontend: at least `npm run build` plus relevant desktop/mobile flows.
- MCP: Python startup/checks plus the relevant MCP contract profile.
- Supabase: migration review, grants/RLS checks, rollback assessment, and
  relevant SQL scenarios.
- Content: registry/file synchronization and web/MCP consistency.
- Release: clean relevant git state, deploy health, and named live flows.

The agent that implemented a change cannot be the only source of evidence
when an external contract or collision point is affected.

## Rollout

1. Use the model on one small task in a green module.
2. Review clarity of the task card, boundary adherence, verification quality,
   and elapsed effort.
3. Adjust the documentation based on evidence from the pilot.
4. Use the model on yellow modules only after the pilot succeeds.
5. Treat decomposition of `script.js` and creation of a Supabase RPC contract
   as separate future design and implementation cycles.

## Non-Goals

- No permanent autonomous agents or background execution.
- No agent receives standing permission to deploy or change production data.
- No attempt to split `script.js` in this documentation phase.
- No machine-readable Supabase RPC contract is created in this phase.
- No shared risk-checker package is extracted in this phase.

## Acceptance Criteria

- Every currently known module has a maturity level and interface artifact.
- Ready, conditional, and blocked agent surfaces are distinguishable.
- Shared collision points have explicit ownership and review rules.
- A reusable task-card format and definition of done exist.
- The first pilot can be started without inventing additional governance.
- The documents contain no placeholders, contradictory ownership, or implied
  production authority.
