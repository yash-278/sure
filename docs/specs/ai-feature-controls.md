---
type: specification
area: finances
status: ready-for-agent
---

# Sure AI feature controls

Restored from the agreed conversation after the temporary worktree copy became unavailable. Product decisions and testing boundaries are approved. Implementation is authorised. This committed project copy is the implementation contract.

## Problem Statement

Sure's ChatGPT integration uses a global model selection for tasks with different capability and reasoning needs. The owner needs to see every AI feature, choose appropriate models across subscription and API connections, and recover from connection failures without accidentally changing models or incurring API charges.

## Solution

Build one AI settings page using the selected layout C: a feature list on the left and the selected feature's detail panel on the right. Connections, AI sharing and background pause controls appear above the feature area.

Each feature describes its purpose, the data it sends and its relative complexity. It has one unified model dropdown grouped by connection, plus an explicit reasoning-level selection where supported. No presets, automatic selections or automatic fallback. Deploy with AI sharing off; Yash selects models and enables sharing after verification.

## User Stories

1. As the owner, I want every AI feature listed together, so that I can understand where AI is used.
2. As the owner, I want a feature list with a detail panel, so that I can configure one feature while retaining context.
3. As the owner, I want each feature's purpose explained, so that I know what enabling it provides.
4. As the owner, I want to see what data is sent, so that I can make an informed sharing decision.
5. As the owner, I want complexity guidance in tooltips, so that I can judge whether a smaller or stronger model is appropriate.
6. As the owner, I want manual model selection without presets, so that the application does not assume my preferences.
7. As the owner, I want subscription and configured API models in one dropdown, so that I can choose across connections.
8. As the owner, I want the connection and billing source labelled, so that I can distinguish subscription allowance from API billing.
9. As the owner, I want identical model names on different connections kept distinct, so that requests use the intended connection.
10. As the owner, I want incompatible models disabled with explanations, so that I understand each feature's requirements.
11. As the owner, I want an explicit supported reasoning level, so that usage is not determined by an implicit default.
12. As the owner, I want reasoning controls only when supported, so that settings do not promise unavailable behaviour.
13. As the owner, I want unconfigured features to remain off, so that partial setup does not activate unwanted processing.
14. As the owner, I want existing global choices not to populate features automatically, so that migration does not replace my decisions.
15. As the owner, I want manual model entry for custom endpoints without discovery, so that compatible providers remain usable after verification.
16. As the owner, I want one selection for chat and its requested edits, so that conversations retain a consistent configuration.
17. As the owner, I want independent categorisation controls, so that routine classification need not use my chat model.
18. As the owner, I want separate merchant detection and enrichment models, so that I can configure their different tasks independently.
19. As the owner, I want separate bill-suggestion and insight-narration models, so that inference and writing can use different capabilities.
20. As the owner, I want separate PDF summary and transaction-extraction selections, so that each processing stage uses a deliberate choice.
21. As the owner, I want image capability checked for scans, so that unsuitable models do not receive images or trigger a replacement.
22. As the owner, I want manual and background triggers to share their feature's selection, so that the trigger does not change model usage.
23. As the owner, I want document search visibly marked unavailable through ChatGPT, so that I do not confuse generation with retrieval.
24. As the owner, I want authentication checked when opening settings, so that status reflects observed access.
25. As the owner, I want the last successful check displayed, so that stale status is not presented as current evidence.
26. As the owner, I want a synthetic model test with usage disclosure, so that I can verify generation without sending financial data.
27. As the owner, I want a reconnect action for expired ChatGPT authentication, so that I can recover without losing settings.
28. As the owner, I want API authentication errors to offer credential updates, so that recovery matches the connection type.
29. As the owner, I want outages distinguished from invalid credentials, so that I do not sign in again unnecessarily.
30. As the owner, I want to cancel login or restart an expired device code, so that an unfinished flow does not trap me.
31. As the owner, I want reconnect to preserve consent and model choices, so that authentication does not activate financial processing.
32. As the owner, I want quota exhaustion and reported reset information displayed, so that paused work is understandable.
33. As the owner, I want unavailable models to pause affected features without fallback, so that healthy features can continue predictably.
34. As the owner, I want eligible unfinished background work to resume after recovery, so that completed work is preserved.
35. As the owner, I want failed chat requests retried only on request, so that old interactions do not resume unexpectedly.
36. As the owner, I want uncertain financial writes checked before retrying, so that recovery cannot duplicate edits.
37. As the owner, I want existing permissions and destructive-action confirmation retained, so that model choice does not increase authority.
38. As the owner, I want statement extraction reviewed before import, so that extraction alone cannot change balances.
39. As the owner, I want global sharing and background pause controls, so that I can stop processing.
40. As the owner, I want to enable sharing myself after verification, so that activation remains my decision.

## Implementation Decisions

### Feature inventory

| Independent selection | Purpose and data |
|---|---|
| Chat and requested edits | Messages, history and permitted financial tool results support answers and authorised edits. |
| Transaction categorisation | Transaction inputs and available categories support classification. |
| Merchant detection | Transaction descriptions and existing merchants support matching. |
| Merchant enrichment | Merchant details support website suggestions; larger models do not guarantee factual accuracy. |
| Bill suggestions | Dated charges, categories and existing settings support recurring-bill inference. |
| Insight narration | Computed financial facts support explanatory text. |
| PDF identification and summary | Document text or scanned-page images support classification and summary. |
| Statement extraction | Statement pages support structured transactions for review. |

Document search is a separate visible entry and remains unavailable through the subscription provider.

### Configuration and execution

- Extend existing settings, providers, assistant, background jobs and PDF workflows. Preserve public API and MCP contracts.
- Store connection identity, model identity and supported reasoning choice per feature. Do not infer the connection from a model-name prefix.
- Group dropdown choices by connection and identify subscription or separately billed API usage. Identically named models from different connections remain distinct.
- Discover models where supported. Allow manually specified custom-endpoint models when discovery is unavailable, subject to compatibility verification before use. Do not infer capabilities solely from display names.
- Disable incompatible choices with reasons. Keep an unavailable saved choice visible rather than replacing it.
- Require explicit reasoning selection where configurable. Do not silently use Provider default or retain an unsupported level after model changes. Models without reasoning controls need no level.
- Start features unconfigured. Do not copy global settings or use defaults as a fallback. Partial setup is supported, subject to consent and feature controls.
- Manual, rule and background entry points share the corresponding feature configuration. Assistant-triggered statement extraction uses the extraction selection; its surrounding conversation uses the chat selection.
- Keep existing feature-specific controls and global background pause. A model choice does not override them.
- PDF summary and extraction remain separate stages. Check image capability for scans, validate structured data, and retain import review and reconciliation. Extraction cannot directly commit balances.
- Tooltips explain relative task complexity without promising quality or exact savings. No presets or automatic model selection.

### Connection and recovery

| Observed state | Display and action |
|---|---|
| Not connected | Connect ChatGPT or Add API key |
| Authentication expired/revoked | Reconnect ChatGPT or Update API key |
| Connected | Provider/account and last successful check |
| Service unreachable | Retry connection check; preserve credentials |
| Quota exhausted | Pause affected work; show reset when reported |
| Selected model unavailable | Choose another model on affected features |

- Authentication, service reachability, quota and model availability are distinct. Credentials alone do not prove usable generation.
- Check authentication on page entry. Show current failure separately from the last successful check.
- Offer Test model with synthetic data and explicit subscription/API usage disclosure. No financial data is needed for testing.
- Device login supports cancel, expiry and Start again. Reconnect preserves model selections and consent. Credentials stay out of responses, logs and artifacts.
- After recovery, resume only unfinished background work whose consent, feature configuration and pause controls allow execution. Preserve completed batches and stable operation identity.
- Failed chat requests require explicit retry. Check persisted results before repeating uncertain financial writes.
- Never automatically switch model, connection or billing source. No automatic extra-usage purchase. Unknown quota/cost remains unknown.

### UI and rollout

- Implement layout C using Sure's design-system components, accessible controls and responsive behaviour. The reviewed mockup is throwaway code.
- The mockup's Provider default reasoning option was rejected and must not ship.
- Preserve owner-only subscription access, family permissions, session/CSRF checks, audits and destructive-action confirmation.
- Inspect actual PR/merge state before selecting the implementation branch. Existing PR readiness remains user-owned.
- Deploy with AI sharing off. After verification, Yash chooses models and enables sharing from the finished page. Do not enable it on his behalf.

## Testing Decisions

The following testing boundaries are approved:

1. Primary boundary: existing Rails system/integration tests configure features through authenticated settings and trigger normal actions or jobs. Stub external provider transport and assert requested connection/model/reasoning and observable results.
2. Narrow adapter boundary: existing protocol tests cover device login, cancellation, authentication errors, capability handling, reasoning forwarding, quota signals, interruption and stable operation identity.

Test external behaviour, not internal method choreography or simple configuration getters. Reuse existing Minitest/Mocha settings, provider, assistant, deferred-job, approval and execution coverage, the text/scanned PDF fixtures and reconciliation tests, and Node adapter tests.

Required evidence:

- Every feature and entry point uses its exact configuration, including mixed providers and duplicate model names across connections.
- Unconfigured and incompatible selections never fall back to global defaults or another provider. Unsupported reasoning fails visibly.
- Settings distinguish authentication from generation. Model tests use synthetic data and disclose usage.
- Reconnect, cancellation, expiry, service failure and quota handling preserve settings and present the appropriate action.
- Background recovery rechecks eligibility and preserves completed work; chat does not automatically replay and financial writes are not blindly repeated.
- Owner/family isolation, unauthorised settings access, CSRF and consent-off paths remain enforced; API/MCP behaviour remains compatible.
- PDF stages route independently. Validate scans, dates, amounts, currencies, duplicates and balance discrepancies. Extraction alone cannot change balances.
- Run required full Rails tests, applicable system tests, Ruby/ERB lint, Biome, Brakeman, adapter checks and green CI.
- Use isolated synthetic end-to-end scenarios for verification. Keep production sharing off and do not send production financial data during acceptance checks. Real financial acceptance awaits owner activation.

## Out of Scope

Presets, automatic routing/fallback, silent model-choice migration, extra-usage purchases, shared subscription access, bank connections, new financial tools, document search implementation, replacement import/reconciliation flows, and enabling sharing on the owner's behalf. Not every model is assumed to support every feature.

## Further Notes

All five product decisions were confirmed through Wayfinder. This specification consolidates those decisions; it is not evidence of implementation or deployment. Testing boundaries were approved with the implementation request.

The previous local tracker and prototype were under temporary storage. Their availability must not be assumed. This specification is retained in the project repository and linked from Atlas. It has not been published as a GitHub issue.
