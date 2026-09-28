# wallet-core

## Canonical Import

```fennel
(local wallet-core (require :wallet-core))
```

## Source Files

- `src/lua_wallet_core.cpp`

## What It Provides

`wallet-core` exposes the native Trust Wallet Core binding for mnemonic validation/generation, HD wallet handles, coin type constants, JSON signing, and JSON-signing support checks.

## API Summary

- `HDWallet({ :mnemonic mnemonic :passphrase passphrase })` creates an HD wallet handle. `mnemonic` is required; `passphrase` defaults to empty string.
- `HDWallet:mnemonic()` returns the wallet mnemonic.
- `HDWallet:address-for-coin(coin-type)` returns the address for a Trust Wallet coin type.
- `HDWallet:sign-json(coin-type json)` signs a JSON payload using the derived private key for the coin.
- `HDWallet:drop()` releases the native wallet; `is-closed()` reports whether the handle is closed.
- `mnemonic-valid(mnemonic)` validates a mnemonic.
- `generate-mnemonic({ :strength n :passphrase passphrase })` creates a mnemonic using the requested strength.
- `sign-json({ :json json :coin coin-type :key private-key-hex })` signs JSON with an explicit private key.
- `supports-json(coin-type)` reports whether Trust Wallet Core supports JSON signing for the coin.
- `coin-types` includes `bitcoin`, `ethereum`, `arbitrum`, `arbitrumnova`, and `solana`.

## Examples

```fennel
(local wallet-core (require :wallet-core))

(local mnemonic (wallet-core.generate-mnemonic {:strength 128 :passphrase ""}))
(local hd (wallet-core.HDWallet {:mnemonic mnemonic :passphrase ""}))
(local address (hd:address-for-coin (. wallet-core.coin-types :arbitrumnova)))
(print address)
(hd:drop)
```

## Errors and Platform Notes

`HDWallet` requires a non-empty valid mnemonic and raises `wallet-core.HDWallet invalid mnemonic` when Trust Wallet Core rejects it. Closed HD wallet handles raise `wallet-core.HDWallet is closed: <action>`. JSON signing requires a supported coin and valid key/material; unsupported coins raise `wallet-core.AnySigner does not support JSON for coin`.

## Related Modules

- [`wallet`](/sdk/modules/wallet) for higher-level Arbitrum Nova wallet helpers.
- [`json`](/sdk/modules/json) for preparing JSON payloads to sign.

## Aliases and Search Terms

Search terms: wallet-core, Trust Wallet Core, HDWallet, mnemonic, coin types, signer, private key, JSON signing.
