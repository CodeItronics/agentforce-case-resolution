# Agentforce Case Resolution POC

An open-source proof of concept by [CodeITronics](https://codeitronics.com/?utm_source=github&utm_medium=readme): the deterministic,
tested actions behind a Salesforce Agentforce agent that helps a customer whose order arrived damaged, late or never arrived.

**Status: internal proof of concept on synthetic data.** The actions, data model and tests are built and pass in an
Agentforce-enabled scratch org. The agent configuration (topics and instructions wired to these actions) is the next step.

## Why the actions decide, not the model

The agent explains and asks; the rules live in Apex, where they're testable:

| Action | What it does | Guardrail |
|---|---|---|
| `Get Order Status` | Order status, product, delivery date, source, as-of time | Sharing decides what the asking user can see; another customer's order is `NOT_FOUND`, same as a made-up one |
| `Get Resolution Policy` | Approved policy text and version for a problem category | An expired policy returns `POLICY_EXPIRED` and no text |
| `Propose Resolution` | Allowed paths and a reason: replacement, refund (needs approval), carrier investigation, escalate | Deterministic rules: claim window, valid policy, "delivered but not received" goes to the carrier first |
| `Request Resolution` | Records a refund, replacement or escalation for a person to act on | Refunds are created as `Pending Approval` and never move money; the idempotency key makes retries return the first request |

Every action returns one outcome (`SUCCESS`, `NOT_FOUND`, `NOT_AUTHORIZED`, `VALIDATION_ERROR`, `POLICY_EXPIRED`,
`DUPLICATE`) and writes an audit row with a correlation id. Identity comes from the signed-in user, never from the chat.

## Run it

```bash
sf org create scratch --definition-file config/project-scratch-def.json --target-dev-hub <your-dev-hub> --alias af-cr --duration-days 7
sf project deploy start -o af-cr --source-dir force-app
sf apex run test -o af-cr --class-names CR_ActionsTest --code-coverage --result-format human
```

The scratch org definition enables `Einstein1AIPlatform` with the agent platform settings. Your Dev Hub must allow
Agentforce scratch orgs.

## Tests

`CR_ActionsTest` (9 tests, 96% coverage) covers: the owner sees their order; another customer's order looks like a
made-up one; a user without access is refused; an expired policy is never used; the resolution rules; refunds wait for
approval and retries are safe; every action is audited.

## License

MIT
