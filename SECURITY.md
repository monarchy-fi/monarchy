# Security

Monarchy is a testnet build for the Ascend x Elysium Builder Competition and has not been audited. Don't use it with real funds yet.

## Reporting a vulnerability

Please report security issues privately through GitHub's [private vulnerability reporting](https://github.com/monarchy-fi/monarchy/security/advisories/new) rather than in a public issue. Include the contract, the steps to reproduce and the impact you expect. We'll acknowledge the report and keep you updated while we fix it.

## Scope

- `contracts/src`: Lodestar, LodestarFactory, AscendSwapper, Exile, Sandfall and their libraries
- The deployment scripts in `contracts/script`

Mocks under `contracts/src/mocks` and the website are out of scope for security reports, though bug reports are welcome as issues.

## Design guarantees

See the security model in the [README](README.md#security-model) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
