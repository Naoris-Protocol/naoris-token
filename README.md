# naoris-token
# Governance Smart Contract

**Overview**
A Governance smart contract written in Solidity, designed to power on-chain governance for DAOs, councils, and decentralized protocols. This contract supports proposal creation, vote delegation, multi-choice voting, and staking-based governance weight.

---

## Features

This Governance contract offers a full-featured on-chain governance framework. It allows for:

- **Flexible proposal creation** with optional IPFS document linking.
- **Multi-choice voting**, allowing voters to select from several options.
- **Delegation support**:
  - **Global delegation**: delegate all future votes.
  - **Per-proposal delegation**: delegate only for a specific proposal.
- **Configurable parameters**:
  - Voting delay
  - Voting period
  - Execution delay (timelock)
  - Maximum delegators limit
- **Staking-based governance weight** via an external staking contract.

---

