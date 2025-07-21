# Naoris Governance & Token Contracts

## Overview

This repository contains two primary smart contracts designed to power decentralized ecosystems:

1. **Governance.sol** — A full-featured governance framework for DAOs and decentralized protocols.
2. **Naoris.sol** — An upgradeable, permissioned ERC20 token with capped supply, pausable functionality, and permit-based approvals.

Both contracts are built using **Solidity 0.8.22** and integrate **OpenZeppelin** libraries to ensure modularity, upgradeability, and robust access control.

---

## Smart Contracts

### 1. Governance Smart Contract

The Governance contract enables on-chain proposal creation, vote delegation (global or per proposal), weighted voting using an external staking contract, and timelocked execution of successful proposals.

#### Features

- **Flexible proposal creation** with optional IPFS metadata.
- **Multi-choice voting** options for community decisions.
- **Delegation mechanisms**:
  - Global delegation for all proposals.
  - Per-proposal delegation for finer control.
- **Staking-based vote weight** using an external contract.
- **Timelock execution** for passed proposals.
- **Role-restricted proposal creation** (e.g., by multisig or admin).


### 2. Naoris Token Contract

A robust and secure ERC20 token implementation designed to serve as the core utility/governance token of the protocol. It supports upgradeability, permit-based approvals (EIP-2612), capped total supply, pausability, and strict admin role control.

#### Features

- **Upgradeable** via UUPS proxy pattern.
- **ERC20Permit** support for gasless approvals.
- **Capped supply** — maximum total supply enforced.
- **Pausable** — transfer functionality can be paused in emergencies.
- **AccessControl** — role-based administration and minting control.
- **Admin safeguards** — protections to prevent accidental admin lockout.



For any queries, kindly contact at a.gupta@naoris.com
