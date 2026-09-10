# Configure AI by feature

The owner-only preview adds an AI page in Settings. Configure each feature before enabling AI sharing. Existing global model settings are not copied into the feature selections.

Choose the feature in the left-hand list, select a model from the combined connection list, choose an explicit reasoning level if the model exposes one, and save. ChatGPT entries use the subscription's Codex allowance. API entries use separately billed API credentials. A model name can appear under multiple connections; the connection is part of your selection.

Eight features can be configured independently: chat and requested edits, categorisation, merchant detection, merchant enrichment, bill suggestions, insight narration, PDF summary and statement extraction. PDF processing may invoke both summary and extraction. Missing extraction configuration leaves completed summary work intact while extraction waits. Document search through ChatGPT remains unavailable.

## Connection checks

Opening AI settings checks authentication without sending financial data. A connected badge does not prove that a model can generate. Test saved model sends synthetic data and consumes subscription allowance or API usage.

Expired ChatGPT authentication offers reconnect. API credential errors link to credential settings. Service outages retain credentials and offer another connection check. Exhausted quota pauses affected work; reset information appears only when supplied by the provider. No failure automatically changes the model, connection or billing source.

For custom endpoints or models without known capabilities, use the manual verification disclosure. Supply the exact model identifier and the effort value documented by that provider, if any. Enable image verification for PDF use. Verification sends synthetic data and is tied to the endpoint and credentials. It does not guarantee accuracy on financial documents.

## Recovery and consent

Reconnect preserves consent and model selections. Eligible unfinished background work resumes after connection recovery, provided sharing is enabled, the feature is configured and background work is not paused. API quota failures without a known reset require a successful model test before queued work resumes; a model-list request alone does not prove generation quota is available.

Failed chat requests require an explicit retry. Existing financial permissions, action confirmation and import review still apply. Turning sharing off cancels queued subscription work while retaining login credentials. Previously transmitted requests cannot be recalled from a provider.

Production rollout leaves sharing off. The owner selects models and enables it from the finished page after verification.

## Capability sources

ChatGPT options use the connected account's Codex model catalogue. Claude API options use the [Models API capability metadata](https://platform.claude.com/docs/en/api/models). The OpenAI API model list does not provide the same capability shape, so a conservative explicit catalogue covers documented models from the [OpenAI model documentation](https://developers.openai.com/api/docs/models). Other models require synthetic verification. Official capability metadata is never applied to custom endpoints solely because their model names match.
