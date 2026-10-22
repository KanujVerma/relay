# Codex GitHub PR review policy, 2026-10-22

This is a review workflow, not a claim that Codex is enabled on Relay.

## Manual request
1. Open a reviewable PR with passing local/CI checks.
2. Ensure Relay is connected to Codex Code Review in the user's Codex settings.
3. Add a top-level PR comment with `@codex review`. For one focused pass, use `@codex review for OAuth safety and billing boundary regressions`.
4. Confirm the bot acknowledged and actually submitted a GitHub review. **Comment submitted is not proof the bot reviewed.**
5. Fix high-priority findings, run exact-head checks and seek follow-up only as necessary. Never merge with unresolved severe issues or failed critical checks.

Automatic reviews are configured in Codex settings for the repo and personal preferences, not in Relay code. Manual review requests reduce repeated work on every small push.

## Repository Code Review Rules
Root AGENTS.md contains high-signal rules: correct OAuth grant and callback validation; no unapproved billed API; no tokens/private recordings in Git/CI; no invented personal experiences; correct stream completion, follow-up cancellation and bounded output. Formatting is handled by offline CI, not by review prompts.

## Usage reality
Free **Codex approval auto-review safety checks** are a different feature from **GitHub PR code review**. PR reviews have tracked Code Review usage and can have plan limits or credit settings. Do not promise they are usage-free or automatically purchase credits. They do not consume GitHub Actions runner minutes unless you separately invoke Actions.

## If no bot reacts
Check repository connection, enabled code reviews, GitHub permissions, an open PR and plan usage. Record the blocker rather than claiming the review ran. An independent human/manual review remains necessary.

## Official references
- https://learn.chatgpt.com/docs/third-party/github
- https://learn.chatgpt.com/docs/pricing
- https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan
