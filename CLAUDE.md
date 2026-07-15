# ScopeFinder — contributor & assistant guidelines

## STRICT: never leak targets or engagement data (this is a public repo)

ScopeFinder is an **open-source, public repository**. Nothing that identifies a
real test target, client, or engagement may ever enter this repo — not in code,
comments, commit messages, docs, examples, fixtures, or test data.

**Prohibited anywhere in the repo (code, comments, commits, PRs, docs):**
- Real hostnames, domains, subdomains, or URLs of any target you tested against
  (e.g. a real `*.company.com`, a specific `admin-graph.<company>.com`, a live
  `api.<company>.net`, etc.).
- Any client, company, program, or engagement name.
- IPs, endpoints, credentials, tokens, API keys, or captured response bodies from
  a real target.
- Screenshots, sample specs/SDLs, or output files harvested from a real target.
- Statements like "verified/tested against <real target>" in commit messages or
  code comments — describe the behavior, not the target.

**Always use neutral placeholders instead:** `example.com`, `api.example.com`,
`https://target.example`, `127.0.0.1`, `10.0.0.1`, RFC 5737 ranges. Keep test
targets, scratch data, and validation notes **outside** this repo entirely.

When writing a commit message or comment, describe *what changed and why* in the
abstract (the class of behavior, the detection logic, the request pattern) —
never the specific live host it was checked on.

If you are ever unsure whether something is sensitive, leave it out.
