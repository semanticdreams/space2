# SDK Examples

This page curates copyable Space SDK examples without duplicating their READMEs. Use these examples as starting points, then follow the linked SDK tutorials, guides, and reference pages for the surrounding contracts.

## Snake Space App Template

The [Snake example](https://github.com/semanticdreams/space2/tree/main/examples/snake) is the current app template for a small, hostable Space application.

It demonstrates:

- default `assets/lua/main.fnl` entrypoint
- hostable `create(host) -> runtime` path
- pure app-owned game logic
- widget-based presentation
- app-owned `host.scene` handles
- focused Fennel tests
- reusable bundle workflow

Related SDK pages:

- [Your First Space App](/sdk/tutorials/your-first-space-app)
- [App Layout Guide](/sdk/guides/app-layout)
- [App Module Contract](/sdk/reference/app-module-contract)
