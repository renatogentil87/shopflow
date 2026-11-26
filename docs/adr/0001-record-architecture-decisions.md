# 1. Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-11-25

## Context
ShopFlow is built as a learning and portfolio project to demonstrate solutions-architecture and
DevOps practice. The *reasoning* behind each architectural choice (why Aurora over DynamoDB, why OIDC
over access keys, which DR pattern, and so on) is as important as the implementation — both for
learning and for anyone reviewing the repository. That reasoning needs to live somewhere durable and
close to the code.

## Decision
We will record every significant architecture decision as an Architecture Decision Record (ADR) in
`docs/adr/`, using the lightweight Michael Nygard format (Context / Decision / Consequences). ADRs are
numbered sequentially and are immutable once Accepted — a later decision that changes an earlier one
is a new ADR that supersedes it, rather than an edit.

Each build milestone in `ROADMAP.md` lists the decisions to capture; write the ADR when the decision
is made, and link it from the roadmap status table.

## Consequences
- The repo carries a visible decision log — valuable for learning and as a portfolio signal.
- A small per-decision writing overhead, accepted deliberately.
- Superseded ADRs stay in history (marked Superseded by #N) rather than being deleted, so the
  evolution of the design is traceable.

## Template
See `template.md` in this folder for the ADR format to copy for each new record.
