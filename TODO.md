# ScopeFinder — TODO

## graphql_probe module

- [ ] **Fork, package & extend graphql-cop** — fork `dolevf/graphql-cop` to `0xQRx/graphql-cop`:
      1. Add a `pyproject.toml` with a `graphql-cop` console-script entry point so it becomes
         `pipx install git+https://github.com/0xQRx/graphql-cop.git` installable (matches the
         waymore/xnLinkFinder/msftrecon pattern).
      2. Add a `--export-schema <path>` flag: graphql-cop already runs the introspection query
         for its "introspection enabled" check — when introspection is enabled, reuse that
         introspection JSON, build the schema with `graphql-core` (`build_client_schema`) and
         write SDL via `print_schema` to `<path>`. This folds the SDL export into the one tool
         so we don't also need gql-cli. Add `graphql-core` to the fork's deps.
      Until this fork exists the Dockerfile install line for graphql-cop will fail.

- [ ] **Clairvoyance (schema recovery when introspection is DISABLED)** — add
      [clairvoyance](https://github.com/nikitastupin/clairvoyance) to recover the GraphQL
      schema via field-suggestion brute-forcing + a wordlist when introspection is turned
      off. Deferred to keep the first version of `graphql_probe` lean. Adds a tool + wordlist
      dependency. Wire it into `graphql_probe` as a fallback path: run it only for confirmed
      endpoints whose graphql-cop report shows introspection disabled, output recovered SDL to
      `graphql/sdl/<host>.graphql`.
