# Fire Restriction Review Playbook

This playbook is for AI-assisted review of production fire-restriction data.
It exists to keep reviews repeatable: prefer parser/source improvements over
one-off human judgment, and make any manual acceptance explicit.

## Review Principles

- Separate system work from reviewer work. Tuning extraction, parsing,
  validation, source catalogs, and auto-review policy is system work. Calling
  `accept_observation` is reviewer work.
- Do not manually accept observations unless the user explicitly asks for
  manual review/approval. If the request is to "address more forests" or "tune
  parsing," build or adjust the system first.
- Treat `partial` and localized restrictions as high-risk. They should publish
  only when the product can clearly communicate affected area, dates, source,
  and campfire policy without implying a forest-wide rule.
- Low fire danger, "No Featured Alerts," or absence of a listed restriction is
  not enough by itself to publish `none`.
- Official source pages can be trusted only for what they explicitly state or
  for structure the extractor has captured and tested.
- Keep cost defaults conservative. Do not enable automatic polling, Sonnet
  escalation, or broad paid parsing unless requested.

## Standard Workflow

1. Start with a read-only production snapshot.

   ```sh
   bin/prod-console -e 'fire_counts'
   bin/prod-console -e 'review_candidates'
   bin/prod-console -e 'llm_costs'
   ```

2. Classify each unresolved forest.

   Use `review_forest("slug")` and `review_observation(id)` to decide whether
   the blocker is missing source coverage, extraction structure, parser
   confusion, validation strictness, auto-review policy, or true human judgment.

3. Compare production documents with live source pages only when the stored
   evidence is stale, ambiguous, or points to a linked source that is not in the
   catalog.

4. Prefer durable changes in this order:

   - Add a better official source to `config/fire_restriction_sources.yml`.
   - Improve extraction in `lib/bfp/fire_restrictions/extractors/`.
   - Improve parser guidance in `lib/bfp/llm/bedrock_parser_client.rb`.
   - Add deterministic normalization or source-specific overrides in
     `lib/bfp/fire_restrictions/source_parser.rb` only when the source has a
     stable structure.
   - Adjust validation or auto-review policy only with focused specs.

5. Add tests before production review actions.

   ```sh
   mise exec -- bundle exec standardrb
   mise exec -- bundle exec rake spec
   ```

6. Deploy only after tests pass and changes are committed/pushed.

   ```sh
   bin/prod-deploy --seed
   ```

7. Run targeted paid parsing, not broad polling, unless asked.

   ```sh
   ssh -i ~/.ssh/bfp-lightsail.pem ubuntu@34.223.75.206 \
     'cd /srv/bfp && docker compose -f compose.yaml -f compose.production.yaml run --rm -e LLM_PARSE_ENABLED=true web bundle exec rake "fire:poll[source-slug]"'
   ```

8. Let `auto_accepted` observations publish through code policy. For
   observations still in `needs_review`, report recommendations unless the user
   asked for manual approval.

## Manual Approval Boundary

Manual approval means running:

```sh
bin/prod-console -e 'accept_observation(123)'
```

Only do this when the user explicitly authorizes manual review or manual
approval. Before accepting manually, inspect:

- `review_observation(id)`
- source URL and source type
- evidence quotes and validation errors
- affected area and whether the status is forest-wide or localized
- effective dates, especially seasonal dates without a current year
- conflicts with other accepted observations for the same forest

If manual approval is used, the final update must say which observation IDs were
accepted manually and why.

## Common Blockers

- Alerts pages include boilerplate category labels such as "Fire Restriction"
  even when no active forest alert exists.
- Region Alerts often contain permanent fireworks/explosives prohibitions; those
  should not become seasonal campfire restrictions.
- Press release index pages tend to produce weak `none` candidates; do not rely
  on them ahead of official fire, fire info, alert detail, ArcGIS, or dispatch
  sources.
- `PUR: Seasonal Restrictions`, Phase A, `Fire Danger: LOW`, and `IFPL: I` can
  indicate an `advisory` posture when captured from a stable current-status
  source.
- Localized wilderness, corridor, watershed, campground, trail, or incident-area
  restrictions should remain `partial` and should not be summarized as
  forest-wide `none`.
- Date windows such as `06/01-09/30` need careful year handling. Do not publish
  based on stale inferred years.

## Reporting Template

Include:

- starting and ending unresolved counts
- code/system changes made
- tests run
- production deploy and smoke result
- paid parsing cost delta from `llm_costs`
- auto-accepted forests
- manually accepted observations, if any
- forests still unresolved and the next system change needed for each
