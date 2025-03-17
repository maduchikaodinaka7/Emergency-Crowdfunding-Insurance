# Emergency Crowdfunding Insurance

A decentralized emergency crowdfunding insurance platform built on Stacks blockchain that enables rapid disaster response through community-pooled funds.

## Overview

This smart contract implements a decentralized insurance pool where users can:
- Contribute STX tokens to a shared emergency fund
- Create verified claims for emergencies
- Process rapid payouts to beneficiaries in need

## Features

- **Pooled Contributions**: Users can contribute a minimum of 1 STX to the insurance pool
- **Claim Management**: Contract owner can create verified claims for emergencies
- **Secure Payouts**: Only authorized beneficiaries can claim their allocated funds
- **Balance Tracking**: Real-time tracking of total pool and individual contributions
- **Access Controls**: Role-based permissions for different contract functions

## Smart Contract Functions

### Public Functions

- `contribute()`: Contribute the minimum required amount to the insurance pool
- `create-claim(amount)`: Create a new claim for a specified amount (contract owner only)  
- `claim-payout(beneficiary)`: Process payout for an approved claim

### Read-Only Functions

- `get-pool-balance()`: Get total balance of the insurance pool
- `get-contribution(contributor)`: Get contribution amount for a specific address
- `get-claim(beneficiary)`: Get claim details for a beneficiary

## Testing

The contract includes comprehensive test coverage for all major functions:
- Contribution validation
- Claim creation authorization
- Payout processing
- Balance tracking

## Technical Details

- Built on Clarity smart contract language
- Uses Stacks blockchain for settlement
- Implements role-based access control
- Includes error handling for common edge cases

## Error Codes

- `ERR-NOT-AUTHORIZED (u100)`: Unauthorized access attempt
- `ERR-INSUFFICIENT-FUNDS (u101)`: Insufficient pool balance
- `ERR-ALREADY-CLAIMED (u102)`: Duplicate claim attempt

## Development

### Prerequisites
- Clarinet
- Node.js
- Vitest for testing

### Running Tests
```bash
npm test
