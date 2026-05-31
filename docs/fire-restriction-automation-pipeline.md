# Fire Restriction Automation Pipeline

This document describes the fully automated fire-season pipeline for BFP fire
restriction monitoring. It is written for review before and during production
operation.

The intended seasonal posture after Memorial Day is:

- fetch every active monitored source on a weekly production clock
- parse first-seen or changed source documents
- trust unchanged source hashes as a fresh verification of the previous parse
- use Haiku as the primary Bedrock parser
- escalate difficult parser cases to the configured Sonnet Bedrock model
- automatically publish only observations that pass deterministic validation and
  the auto-review policy
- leave ambiguous, stale, conflicting, localized, or weakly supported
  observations in `needs_review`

As of 2026-05-31, the repository supports Bedrock Haiku -> Sonnet escalation.
OpenAI `gpt-5.4` is documented by OpenAI as an API model, but BFP does not yet
have an OpenAI parser client. To use GPT-5.4 instead of, or before, Sonnet, add
the OpenAI provider described in "GPT-5.4 provider path" below.

## Production mode

Production automation is controlled by environment variables on the Lightsail
host in `/srv/bfp/.env`.

Fire-season weekly verification mode:

```sh
LLM_PROVIDER=bedrock
LLM_PARSE_ENABLED=true
LLM_ESCALATION_ENABLED=true
FIRE_AUTO_POLL_ENABLED=true
CLOCK_INTERVAL_SECONDS=604800
FIRE_POLL_BATCH_SIZE=150
BEDROCK_PRIMARY_MODEL_ID=global.anthropic.claude-haiku-4-5-20251001-v1:0
BEDROCK_ESCALATION_MODEL_ID=global.anthropic.claude-sonnet-4-5-20250929-v1:0
```

Meaning:

- `LLM_PARSE_ENABLED=true` allows HTML/PDF/NPS text sources to call the parser.
- `LLM_ESCALATION_ENABLED=true` allows a second parser call when Haiku returns a
  weak, invalid, ambiguous, or conflicting result.
- `FIRE_AUTO_POLL_ENABLED=true` lets the `clock` enqueue recurring fire jobs.
- `CLOCK_INTERVAL_SECONDS=604800` makes the production clock tick weekly.
- `FIRE_POLL_BATCH_SIZE=150` is large enough to cover the current active source
  catalog in one weekly run.

Unchanged successful fetches are not reparsed. The resolver keeps the previous
accepted observation current when the latest successful fetch for that source is
less than 30 days old and has the same content hash as the fetch that produced
the accepted observation.

Keep these values false outside fire season or when intentionally returning to
manual, no-cost mode:

```sh
LLM_PARSE_ENABLED=false
LLM_ESCALATION_ENABLED=false
FIRE_AUTO_POLL_ENABLED=false
```

## Runtime components

The production Docker Compose services are:

- `web`: public Roda/Bridgetown app served by Puma
- `postgres`: application database and Que job store
- `worker`: Que worker process
- `clock`: lightweight recurring scheduler
- `caddy`: public HTTPS reverse proxy

The job services are behind the Compose `jobs` profile. They do nothing unless
started explicitly:

```sh
docker compose -f compose.yaml -f compose.production.yaml --profile jobs up -d --build worker clock
```

The clock loop is in `jobs/clock.rb`. On each tick it reads
`FIRE_AUTO_POLL_ENABLED`. When true, it enqueues
`BFP::FireRestrictions::PollDueSourcesJob` with `FIRE_POLL_BATCH_SIZE`.

The worker entrypoint is `jobs/worker.rb`. It runs Que against
`jobs/fire_restriction_jobs.rb`.

## Data model

The core records are:

- `land_units`: monitored forests and parks
- `restriction_sources`: official or partner source definitions
- `source_fetches`: each fetch attempt, status, final URL, content hash, and
  source document link
- `source_documents`: deduplicated raw body and extracted text for fetched
  content
- `restriction_observations`: parser output and review status for one source
  fetch
- `restriction_statuses`: resolved public forestwide status for each land unit
- `restriction_areas`: named localized areas when the source supports them
- `localized_fire_use_rules`: localized parsed or curated fire-use rules

Source metadata lives in `config/fire_restriction_sources.yml`. The seeder
loads the catalog with:

```sh
bundle exec rake fire:sources:seed
```

Curated localized camping/backpacking fire-use rules live in
`config/fire_restriction_curated_rules.yml` and are seeded with:

```sh
bundle exec rake fire:localized:seed
```

`fire:seed` runs both.

## Weekly job flow

The automated weekly flow is:

1. `clock` wakes up.
2. If `FIRE_AUTO_POLL_ENABLED=true`, it enqueues `PollDueSourcesJob`.
3. `PollDueSourcesJob` selects active sources ordered by oldest
   `last_checked_at` first.
4. It filters with each source's `due?` method.
5. It enqueues `FetchSourceJob` for up to `FIRE_POLL_BATCH_SIZE` due sources.
6. Each `FetchSourceJob` fetches the source and persists a `source_fetch`.
7. If the fetch errored or produced no source document, parsing is skipped and
   the land unit is resolved from existing accepted observations.
8. If the fetch succeeded, parsing happens only when the fetched content changed
   or no previous observation exists for the source.
9. `ParseSourceFetchJob` extracts text, calls the parser, validates the result,
   applies auto-review policy, and persists an observation.
10. `Resolver` recomputes the public land-unit status from accepted or
    auto-accepted observations.

With a weekly clock, stable pages produce new fetch records but not new parser
observations. This keeps costs low while still proving that the accepted parse is
based on content that remains current.

## Fetch and extraction

The fetcher records:

- HTTP status or error class
- final URL
- fetched timestamp
- content hash
- whether the source content changed
- linked deduplicated `source_document`

When a server returns `304 Not Modified`, the fetch record reuses the latest
successful source document and content hash. This makes conditional HTTP checks
count as verified unchanged content without a new parser call.

Extractor selection is source/content based:

- ArcGIS feature layers use `ArcgisAdapter` and do not call an LLM.
- NPS alert API sources use the NPS alerts extractor.
- PDF content uses the PDF extractor.
- Everything else uses the HTML extractor.

Raw content stays in Postgres for now. Extracted text is normalized and saved on
the document so evidence quotes can be validated against the exact source text
the parser saw.

## Parser behavior

The parser converts official source text into the structured schema in
`BFP::LLM::ParserClient::SCHEMA`.

Top-level fields include:

- `status`
- `campfire_policy`
- `fire_danger_rating`
- `ifpl_level`
- `effective_start`
- `effective_end`
- `order_number`
- `affected_area`
- `summary`
- `evidence_quotes`
- `confidence`
- `needs_review_reasons`
- `localized_rules`

Allowed forestwide statuses:

- `unknown`
- `none`
- `advisory`
- `partial`
- `stage_1`
- `stage_2`
- `full`
- `closure`
- `year_round`

Allowed campfire policies:

- `unknown`
- `allowed`
- `developed_sites_only`
- `fire_pan_required`
- `prohibited`
- `propane_allowed`
- `stoves_only`

Parser rules intentionally bias toward caution:

- use only supplied source text
- do not infer from outside knowledge
- return `unknown` or null when unsupported
- evidence quotes must be exact spans from extracted text
- low fire danger alone does not mean `none`
- no featured alerts alone does not mean `none`
- active restrictions require explicit restriction, prohibition, order,
  closure, or Stage 1/Stage 2 evidence
- `none` requires explicit no-restrictions, lifted, rescinded, or equivalent
  evidence
- localized restrictions should be captured as localized rules and should not
  be implied to be forestwide

## Escalation

The primary Bedrock model is:

```text
global.anthropic.claude-haiku-4-5-20251001-v1:0
```

The configured Bedrock escalation model is:

```text
global.anthropic.claude-sonnet-4-5-20250929-v1:0
```

Escalation is attempted only when `LLM_ESCALATION_ENABLED=true`, the source is
not ArcGIS, and the primary parser did not fail at the transport/API layer.

Escalation triggers:

- primary confidence is below 0.7
- deterministic validation fails
- the primary returns `unknown` while the text contains restriction language
- the text appears to contain multiple overlapping orders
- the primary result conflicts with a recent accepted observation from another
  source for the same land unit

If escalation succeeds, its result replaces the primary result. If escalation
fails, the primary result is retained and validation/review policy continue from
there.

The repo-managed OpenTofu policy allows only the configured primary and
configured escalation Bedrock models and explicitly denies all other Bedrock
model invocations. Applying the OpenTofu change is required before production
Sonnet escalation can work.

## Automatic review

"Automatic review" means code policy marks a parsed observation as
`auto_accepted`. It does not mean the system calls the manual
`accept_observation` helper. Manual acceptance remains a human reviewer action.

The auto-review policy lives in `BFP::FireRestrictions::AutoReviewPolicy`.

Official source authorities eligible for normal auto-publish:

- `official_usfs`
- `official_nps`

Official source types eligible for normal auto-publish:

- `arcgis_feature_layer`
- `fs_alerts_page`
- `fs_alert_detail`
- `fs_fire_info_page`
- `fs_fire_page`
- `nps_alerts_api`
- `nps_conditions_page`
- `nps_fire_page`

Active statuses eligible for normal auto-publish:

- `advisory`
- `closure`
- `full`
- `stage_1`
- `stage_2`
- `year_round`

Normal auto-publish thresholds:

- active restrictive/advisory statuses need confidence at least 0.9
- `none` needs confidence at least 0.85 and explicit clear none/lifted/rescinded
  evidence
- source metadata `auto_publish: true` can auto-publish at confidence at least
  0.8 if there are no hard review reasons

Hard review reasons block auto-publish. These include:

- LLM parsing failed
- LLM parsing was disabled
- evidence quote mismatch
- missing status evidence
- incident-context source trying to set campfire policy
- scanned or empty PDF extraction problems
- conflicts with another accepted source
- expired restrictive end date
- multiple overlapping orders
- geographically limited or partial-area uncertainty

USFS alert pages get one special `none` path: the generated extractor summary
"No active forest fire restriction alerts were listed" can support `none` only
when the page does not look like a known broader IFPL/restriction index where
absence of an alert is too weak.

NPS alert summaries are stricter. "No fire-related NPS alerts were returned" is
not enough by itself for `none`; it can only provide context alongside explicit
park fire-ban or restriction text.

## Localized rules

Localized rules cover restrictions that apply to a wilderness, corridor,
campground, trail, watershed, incident area, or named area rather than the whole
land unit.

The parser can emit `localized_rules`. Each localized rule is validated
separately by `LocalizedRuleValidator`.

Parsed localized rules auto-publish only when:

- the source has metadata `localized_auto_publish: true`
- the localized rule passes strong validation

Otherwise, localized parsed rules stay in `needs_review`.

Curated localized rules are managed separately in
`config/fire_restriction_curated_rules.yml`. Static approximate geometries are
generated and labeled with provenance; they are not treated as legal boundaries.

## Public status resolution

The resolver runs after parsing or after manual review actions.

It considers accepted candidates for the land unit where:

- `review_status` is `accepted` or `auto_accepted`
- scope is nil or `forestwide`
- latest successful fetch for the observation source is less than 30 days old
- latest successful fetch has the same content hash as the fetch that produced
  the accepted observation

It chooses the best candidate by:

- source type precedence
- confidence
- recency

High-precedence examples:

- ArcGIS feature layer: 100
- USFS fire info page: 90
- USFS fire page: 88
- USFS alert detail: 85
- NPS alerts API: 84
- NPS conditions page: 82

If accepted candidates conflict on non-unknown status, the public status becomes
`unknown / needs_review` with conflict evidence. If no accepted candidate exists,
the public status also becomes `unknown / needs_review`.

This is why weekly verification matters. A stable source page can remain true
without being reparsed, but the source must still be successfully checked within
30 days. If the latest successful content hash differs from the accepted
observation's source fetch, the old accepted observation is no longer current
and the new parse/review result must carry the public status.

## Activation runbook

Use this sequence to turn on fire-season automation.

1. Deploy the current code.

```sh
bin/prod-deploy --migrate --seed
```

2. Apply the Bedrock IAM policy that allows both primary and escalation models.

```sh
cd infra/opentofu
tofu init
tofu plan
tofu apply
```

3. Confirm account-level Bedrock model access exists for both configured
   Anthropic models in AWS. IAM permissions are necessary but may not be enough
   if the AWS account has not enabled the model.

4. Write production environment values with Ansible. Include the Bedrock key
   outputs if the server does not already have current parser credentials.

```sh
ansible-playbook \
  -i infra/ansible/inventory.ini \
  infra/ansible/playbook.yml \
  -e bfp_llm_parse_enabled=true \
  -e bfp_llm_escalation_enabled=true \
  -e bfp_fire_auto_poll_enabled=true \
  -e bfp_clock_interval_seconds=604800 \
  -e bfp_fire_poll_batch_size=150 \
  -e bfp_aws_access_key_id="$(cd infra/opentofu && tofu output -raw bedrock_parser_access_key_id)" \
  -e bfp_aws_secret_access_key="$(cd infra/opentofu && tofu output -raw bedrock_parser_secret_access_key)"
```

5. Start the production job services.

```sh
ssh -i ~/.ssh/bfp-lightsail.pem ubuntu@34.223.75.206 \
  'cd /srv/bfp && docker compose -f compose.yaml -f compose.production.yaml --profile jobs up -d --build worker clock'
```

6. Confirm the intended services are running.

```sh
ssh -i ~/.ssh/bfp-lightsail.pem ubuntu@34.223.75.206 \
  'cd /srv/bfp && docker compose -f compose.yaml -f compose.production.yaml ps'
```

Expected fire-season services:

- `web`
- `caddy`
- `postgres`
- `worker`
- `clock`

7. Watch the first run.

```sh
ssh -i ~/.ssh/bfp-lightsail.pem ubuntu@34.223.75.206 \
  'cd /srv/bfp && docker compose -f compose.yaml -f compose.production.yaml logs --tail=200 clock worker'
```

8. Confirm new fetches, observations, review results, and costs.

```sh
bin/prod-console -e 'latest_fetches(20)'
bin/prod-console -e 'latest_observations(20)'
bin/prod-console -e 'review_candidates'
bin/prod-console -e 'llm_costs'
bin/prod-console -e 'fire_counts'
```

9. Run public smoke checks.

```sh
curl -sS https://bigfluffypuffy.org/health
curl -I -sS https://bigfluffypuffy.org/fire-restrictions
curl -sS https://bigfluffypuffy.org/api/fire-restrictions/forests
```

## Optional immediate catch-up run

After enabling the environment, the weekly clock may not tick immediately
depending on when the container starts. To force an immediate catch-up check:

```sh
ssh -i ~/.ssh/bfp-lightsail.pem ubuntu@34.223.75.206 \
  'cd /srv/bfp && docker compose -f compose.yaml -f compose.production.yaml run --rm \
    -e LLM_PARSE_ENABLED=true \
    -e LLM_ESCALATION_ENABLED=true \
    web bundle exec rake fire:poll_due'
```

If older `needs_review` observations become auto-publishable because the policy
changed, run the auto-accept sweep once:

```sh
ssh -i ~/.ssh/bfp-lightsail.pem ubuntu@34.223.75.206 \
  'cd /srv/bfp && docker compose -f compose.yaml -f compose.production.yaml run --rm web bundle exec rake fire:review:auto_accept'
```

The weekly parser does not need this sweep for new observations because
`SourceParser` applies the auto-review policy at creation time.

## Monitoring

Useful production checks:

```sh
bin/prod-console -e 'latest_fetches(20)'
bin/prod-console -e 'latest_observations(20)'
bin/prod-console -e 'review_candidates'
bin/prod-console -e 'review_queue'
bin/prod-console -e 'llm_costs'
bin/prod-console -e 'fire_counts'
bin/prod-console -e 'status("deschutes")'
```

Useful container checks:

```sh
ssh -i ~/.ssh/bfp-lightsail.pem ubuntu@34.223.75.206 \
  'cd /srv/bfp && docker compose -f compose.yaml -f compose.production.yaml ps'

ssh -i ~/.ssh/bfp-lightsail.pem ubuntu@34.223.75.206 \
  'cd /srv/bfp && docker compose -f compose.yaml -f compose.production.yaml logs --tail=200 worker'

ssh -i ~/.ssh/bfp-lightsail.pem ubuntu@34.223.75.206 \
  'cd /srv/bfp && docker compose -f compose.yaml -f compose.production.yaml logs --tail=200 clock'
```

Things to watch:

- last fetch timestamp should move after each weekly run
- observations should include parser model IDs
- `llm_costs` should show expected Haiku usage and limited Sonnet usage
- review queue should contain only genuinely ambiguous or unsafe cases
- public API forest count should match active land units
- public statuses should not all fall to `unknown` after 30 days

## Cost controls

The pipeline has several cost levers:

- `LLM_PARSE_ENABLED=false` turns off paid LLM parsing.
- `LLM_ESCALATION_ENABLED=false` disables Sonnet escalation.
- `FIRE_POLL_BATCH_SIZE` caps sources per clock tick.
- `CLOCK_INTERVAL_SECONDS` controls how often the clock enqueues work.
- `QUE_WORKER_COUNT` controls parser concurrency.

The Bedrock client stores token usage and estimated cost in observation raw
output. Inspect it with:

```sh
bin/prod-console -e 'llm_costs'
```

Escalation should be a minority of calls. If Sonnet usage is unexpectedly high,
inspect recent observations for common triggers:

```sh
bin/prod-console -e 'latest_observations(20)'
bin/prod-console -e 'review_candidates'
```

Common causes are weak extraction, multiple overlapping orders, broad alert
index pages, or source pages mixing permanent rules with seasonal restrictions.

## Rollback

To stop automation without changing code:

```sh
ssh -i ~/.ssh/bfp-lightsail.pem ubuntu@34.223.75.206 \
  'cd /srv/bfp && docker compose -f compose.yaml -f compose.production.yaml --profile jobs stop worker clock'
```

Then disable the flags in `/srv/bfp/.env` or through Ansible:

```sh
ansible-playbook \
  -i infra/ansible/inventory.ini \
  infra/ansible/playbook.yml \
  -e bfp_llm_parse_enabled=false \
  -e bfp_llm_escalation_enabled=false \
  -e bfp_fire_auto_poll_enabled=false
```

To keep no-cost freshness checks but avoid paid parsing:

```sh
LLM_PARSE_ENABLED=false
LLM_ESCALATION_ENABLED=false
FIRE_AUTO_POLL_ENABLED=true
```

This mode still fetches sources and resolves deterministic ArcGIS data, but
changed HTML/PDF/NPS text sources can remain `unknown / needs_review`.

## GPT-5.4 provider path

OpenAI documentation checked on 2026-05-31 lists `gpt-5.4` as an API model and
shows support for the Responses API, function calling, and structured outputs:

- https://developers.openai.com/api/docs/models/gpt-5.4
- https://developers.openai.com/api/docs/models

BFP currently does not call OpenAI APIs. `LLM_PROVIDER` supports `bedrock` and
`fake`; `ParserClient.build` returns `BedrockParserClient` in production unless
`LLM_PROVIDER=fake`.

To use GPT-5.4 as an escalation path, add a provider implementation:

1. Add an OpenAI client dependency or a small HTTP client wrapper.
2. Add `lib/bfp/llm/openai_parser_client.rb`.
3. Reuse `ParserClient::SCHEMA` for structured output.
4. Reuse the same parser system prompt and source prompt semantics.
5. Add environment variables:
   - `OPENAI_API_KEY`
   - `OPENAI_PRIMARY_MODEL_ID`
   - `OPENAI_ESCALATION_MODEL_ID`
6. Extend `ParserClient.build` to support `LLM_PROVIDER=openai`.
7. Add token usage and estimated cost fields compatible with `llm_costs`.
8. Add specs with fake OpenAI responses. Do not make live OpenAI calls in tests.
9. Decide whether GPT-5.4 replaces Sonnet or whether BFP needs a true provider
   cascade such as Haiku -> GPT-5.4 -> Sonnet.

Until that provider exists, the production-ready escalation path is Bedrock
Haiku -> Bedrock Sonnet.

## Manual review boundary

Automation is intentionally conservative. It should reduce the routine review
load, not erase the manual review boundary.

Manual reviewer actions are still required for:

- conflicts between accepted official sources
- expired dates that appear to need source interpretation
- partial or localized restrictions without strong geometry and evidence
- scanned PDFs or extraction failures
- weak `none` claims based only on absence of alerts
- source pages that mix permanent boilerplate with seasonal restrictions
- parser failures
- any case where the public status would imply a forestwide rule from a
  geographically limited source

Manual approval commands:

```sh
bin/prod-console -e 'review_observation(123)'
bin/prod-console -e 'accept_observation(123)'
bin/prod-console -e 'reject_observation(123, "reason")'
```

Do not use these commands as part of the automated weekly run. They are explicit
human review tools.
