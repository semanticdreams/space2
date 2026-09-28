# wallet

## Canonical Import

```fennel
(local wallet (require :wallet))
```

## Source Files

- `assets/lua/wallet.fnl`

## What It Provides

`wallet` is a higher-level Fennel facade over `wallet-core` for mnemonic validation/generation, Arbitrum Nova wallet creation, and signing Arbitrum Nova transfer payloads.

## API Summary

- `validate-mnemonic(mnemonic)` returns whether the mnemonic is accepted by `wallet-core`.
- `generate-mnemonic([opts])` returns a generated mnemonic. Options include `strength` (default `128`) and `passphrase` (default empty string).
- `create-arbitrumnova([opts])` returns `{ :mnemonic mnemonic :address address }`. Options may provide `mnemonic`, `passphrase`, and `strength`; when no mnemonic is supplied, one is generated.
- `sign-arbitrumnova-transfer(opts)` signs a transfer with an active wallet table. Required wallet fields are `mnemonic` and `address`; required transaction fields include recipient (`to` or `to-address`), amount (`amount-eth` or `amount`), `nonce`/`nonce-hex`, `gas-price`/`gas-price-hex`, and `gas-limit`/`gas-limit-hex`. Optional `data`/`data-hex` is included when non-empty.

## Examples

```fennel
(local wallet (require :wallet))

(local account (wallet.create-arbitrumnova {:strength 128}))
(assert (wallet.validate-mnemonic account.mnemonic))
(print account.address)
```

## Errors and Platform Notes

This facade currently targets Arbitrum Nova helpers. It uses `wallet-core.HDWallet` internally and drops native wallet handles after deriving addresses or signing. `sign-arbitrumnova-transfer` asserts when required wallet or transaction fields are missing. Amount and hex/base64 transaction conversions are delegated to `wallet-tx-utils` before signing JSON through `wallet-core`.

## Related Modules

- [`wallet-core`](/sdk/modules/wallet-core) for lower-level Trust Wallet Core bindings.
- [`json`](/sdk/modules/json) for JSON serialization used by signing.

## Aliases and Search Terms

Search terms: wallet, mnemonic, Arbitrum Nova, transfer, sign transaction, HD wallet, Trust Wallet.
