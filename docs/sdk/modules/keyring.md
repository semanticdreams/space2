# keyring

## Canonical Import

```fennel
(local keyring (require :keyring))
```

## Source Files

- `src/lua_keyring.cpp`
- `src/engine.cpp`

## What It Provides

`keyring` stores, retrieves, and deletes secrets through the host platform keyring service.

## API Summary

- `set-password(service account secret)` stores a secret and returns a boolean.
- `get-password(service account)` returns the secret string or `nil` when no secret is found.
- `delete-password(service account)` deletes a stored secret and returns a boolean.

## Examples

```fennel
(local keyring (require :keyring))

(when (keyring.set-password "space-demo" "alice" "secret")
  (print (or (keyring.get-password "space-demo" "alice") "missing"))
  (keyring.delete-password "space-demo" "alice"))
```

## Errors and Platform Notes

The module is installed by the engine host because it needs a `Keyring` handle. Actual storage behavior and prompts depend on the OS keyring backend and user session.

## Related Modules

- [`engine`](/sdk/modules/engine) for host lifecycle.
- [`wallet`](/sdk/modules/wallet) for wallet-oriented credential flows.

## Aliases and Search Terms

Search terms: secrets, credentials, password store, OS keychain, secure storage.
