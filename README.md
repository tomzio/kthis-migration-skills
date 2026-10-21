# kthis-migration-skills

Agent skills for migrating legacy **KTHIS / eHealth** HIS features (Eclipse RCP + SWT, Java 6 / GBK) to **WebHIS** (React 18 + antd 4 + dva frontend / Spring Boot 2.7 + MyBatis backend).

The migration is split into two stages, one skill each:

| Skill | Stage | Produces |
| --- | --- | --- |
| [`kthis-migration-plan`](./skills/kthis-migration-plan/SKILL.md) | 1. Design docs | `docs/migration/` per-screen / per-tab design volumes |
| [`kthis-migration`](./skills/kthis-migration/SKILL.md) | 2. Implementation | Backend `webhis-<mod>-*` endpoints + frontend `src/pages/<mod>/` pages, dialogs, models, i18n |

## Install

```bash
# Both skills
npx skills add tomzio/kthis-migration-skills

# Only the design-doc skill
npx skills add tomzio/kthis-migration-skills --skill kthis-migration-plan

# Only the implementation skill
npx skills add tomzio/kthis-migration-skills --skill kthis-migration
```

Works with OpenCode, Claude Code, Codex, Cursor and the other agents supported by the [`skills`](https://github.com/vercel-labs/skills) CLI.

## Upgrade

```bash
# Upgrade both skills to the latest commit on `main`
npx skills update kthis-migration kthis-migration-plan

# Add -g for a global install
npx skills update kthis-migration kthis-migration-plan -g

# If `update` misses newly added files, re-add (overwrites)
npx skills add tomzio/kthis-migration-skills -p -y
```

[skills.sh](https://skills.sh/tomzio/kthis-migration-skills) has no manual publish step: it re-reads this repo's default branch (content is cached, so it may lag). To refresh it, push to `main`, or run `npx skills add tomzio/kthis-migration-skills` once.

## Notes

- The legacy repository is the single source of truth for business logic; the skills only map it layer by layer onto the new stack.
- Local repository paths are read from the target project's `.agents/paths.env` (per-developer, gitignored); nothing is hard-coded to a machine.
- Both skills are project-agnostic workflow guides: you supply the module name, screen, and paths each run.
