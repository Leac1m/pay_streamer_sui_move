# Sui Move Stream Payment-Based Payroll System

## Overview

The Sui Move Stream Payment-Based Payroll System is a decentralized application that allows users to send micro-payments at specified time intervals to other users. This module is designed to facilitate payroll systems, enabling seamless and automated payment streams.

## Features

- **Micro-Payments**: Send small payments over time to another user.
- **Payment Management**: Create, start, pause, resume, and cancel payments.
- **Access Control**: Utilize capabilities (`PayerCap` and `PayeeCap`) for secure access management.
- **Fee Management**: Set and update fee rates for transactions.
- **Token Whitelisting**: Admins can add new coin types to the whitelist for use in payments.

## Getting Started

### Prerequisites

To run this codebase, you need to have the following installed on your machine:

- [Sui](https://sui.io/) - The Sui blockchain framework.
- A compatible development environment for Sui Move.

### Installation

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/yourusername/sui-move-pay-streamer.git
   cd sui-move-pay-streamer
   ```

2. **Set Up Your Environment**:
   Follow the Sui documentation to set up your local environment and ensure you have the necessary dependencies installed.

3. **Compile the Code**:
   Use the Sui CLI to compile the Move modules:
   ```bash
   sui move build
   ```

4. **Run Tests**:
   Ensure everything is working correctly by running the unit tests:
   ```bash
   sui move test
   ```

## Core Structures

1. **Payments**:
   - A shared object that maintains information such as fee rates, supported tokens, and the balance of fees collected.
   - Dynamically links to active `Payment` structs.

2. **Payment**:
   - Represents a payment created by a payer, storing the balance to be streamed and time-related variables to track the streaming progress.

3. **PayerCap**:
   - An access control structure for the payer, granting permissions to manage payments.

4. **PayeeCap**:
   - An access control structure for the recipient, allowing them to withdraw funds.

5. **AdminCap**:
   - Grants administrative privileges to modify the `Payments` object, including changing fee rates, withdrawing fee balances, and adding new coins to the whitelist.

## Core Functions

1. **create_payment<COIN-TYPE>**:
   - Creates a `Payment` struct.
   - **Inputs**: `Coin`, `duration` (streaming duration), `payments`.
   - **Note**: The `Coin` must cover the balance to stream plus the fee (default is 0.3%).

2. **start_payment<COIN-TYPE>**:
   - Starts a `Payment` and sends `PayeeCap` to the recipient's address.
   - **Inputs**: `Payment`, `Recipient address`, `&Clock`, `&mut Payments`.
   - **Output**: Returns `PayerCap`.

3. **pause_payment<COIN-TYPE>**:
   - Pauses an active `Payment`.
   - **Permission**: User with `PayerCap`.

4. **resume_payment<COIN-TYPE>**:
   - Resumes a paused `Payment`. Fails if the `Payment` status is not `PAUSED`.
   - **Permission**: User with `PayerCap`.

5. **cancel_payment<COIN-TYPE>**:
   - Cancels a `Payment`. Fails if the `Payment` status is already `CANCELLED`.
   - **Returns**: "Unstreamed" `Coin<COIN-TYPE>`.
   - **Permission**: User with `PayerCap`.

6. **withdraw_payment<COIN-TYPE>**:
   - Withdraws streamed coins from a `Payment`.
   - Can be called multiple times while keeping track of the total withdrawn amount.
   - **Returns**: "Streamed" `Coin<COIN-TYPE>`.
   - **Permission**: User with `PayeeCap`.

7. **set_fee_percent<COIN-TYPE>**:
   - Changes the current fee rates.
   - **Permission**: User with `AdminCap`.

8. **admin_withdraw<COIN-TYPE>**:
   - Withdraws from the fee balance.
   - **Permission**: User with `AdminCap`.

## Unit Tests

The codebase includes unit tests to ensure the functionality of the payment system. You can run the tests using the following command:

```bash
sui move test
```
