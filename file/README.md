# Gas Sponsored Relayer - Phase 2

An enhanced Clarity smart contract system for sponsored transaction relaying on the Stacks blockchain with improved security, fee management, and additional functionality.

## Overview

The Gas Sponsored Relayer allows sponsors to pay for users' transaction fees, enabling gasless transactions for end users. Phase 2 introduces significant improvements including bug fixes, security enhancements, and a comprehensive fee management system.

## Key Features

### Core Functionality
- **Sponsored Transactions**: Sponsors can pay gas fees for users
- **Signature Verification**: Cryptographic verification of user intent
- **Nonce Management**: Prevents replay attacks
- **Transaction Expiry**: Time-limited transactions for security
- **Balance Management**: Sponsor deposit/withdrawal system

### New in Phase 2
- **Enhanced Security**: Contract whitelisting and improved access controls
- **Fee Management**: Dynamic fee structure with the fee-manager contract
- **Event Logging**: Comprehensive transaction event tracking
- **Refund System**: Automatic refunds for expired transactions
- **Better Error Handling**: Comprehensive error constants and validation

## Contracts

### 1. Relayer Contract (`relayer.clar`)

The main contract handling sponsored transactions.

#### Key Functions

**Public Functions:**
- `submit-sponsored-call`: Submit a sponsored transaction with signature verification
- `mark-paid`: Mark a transaction as paid (sponsor only)
- `refund-expired`: Refund expired transactions
- `deposit-sponsor-balance`: Deposit STX for sponsoring
- `withdraw-sponsor-balance`: Withdraw unused sponsor balance
- `add-allowed-contract`: Add contract to whitelist (admin only)
- `remove-allowed-contract`: Remove contract from whitelist (admin only)

**Read-Only Functions:**
- `get-sponsored-info`: Get transaction details
- `get-user-nonce`: Get user's current nonce
- `get-sponsor-balance`: Get sponsor's available balance
- `is-contract-allowed`: Check if contract is whitelisted
- `get-transaction-event`: Get event details

### 2. Fee Manager Contract (`fee-manager.clar`)

Manages dynamic fee structures for the relayer system.

#### Key Functions

**Public Functions:**
- `set-contract-fee`: Configure fees for specific contracts
- `toggle-contract-fee`: Enable/disable fees for contracts
- `calculate-fee`: Calculate fee for a transaction
- `collect-fee`: Record fee collection

**Read-Only Functions:**
- `get-contract-fee`: Get fee configuration
- `preview-fee`: Preview fee calculation
- `get-total-fees-collected`: Get total fees collected
- `get-contract-stats`: Get analytics for a contract

## Security Improvements

### Bug Fixes from Phase 1
1. **Fixed Signature Verification**: Proper preimage construction using `to-consensus-buff?`
2. **Fixed Buffer Size**: Changed from `buff 34` to `buff 32` for SHA256 hashes
3. **Fixed String Types**: Changed from `buff 34` to `string-ascii 128` for contract names

### Security Enhancements
1. **Contract Whitelisting**: Only approved contracts can be called
2. **Access Controls**: Proper authorization checks
3. **Balance Management**: Prevents overspending by sponsors
4. **Transaction Expiry**: Time-limited transactions
5. **Reentrancy Protection**: Balance updates before transfers
6. **Input Validation**: Comprehensive parameter validation

## Usage Examples

### 1. Setting up a Sponsor

```clarity
;; Deposit STX for sponsoring
(contract-call? .relayer deposit-sponsor-balance u10000000) ;; 10 STX

;; Add allowed contract (admin only)
(contract-call? .relayer add-allowed-contract "my-dapp-contract")
```

### 2. Submitting a Sponsored Transaction

```clarity
;; User signs a message off-chain, then sponsor submits:
(contract-call? .relayer submit-sponsored-call
  'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM  ;; user
  "my-dapp-contract"                              ;; contract
  "transfer-tokens"                               ;; function
  u1000000                                        ;; amount
  u1                                              ;; nonce
  u1640995200                                     ;; expiry timestamp
  0x5f8b... )                                     ;; signature
```

### 3. Fee Management

```clarity
;; Set fee structure for a contract
(contract-call? .fee-manager set-contract-fee
  "my-dapp-contract"
  u100000      ;; base fee (0.1 STX)
  u250         ;; percentage fee (2.5%)
  u1000000 )   ;; max fee (1 STX)

;; Preview fee calculation
(contract-call? .fee-manager preview-fee
  "my-dapp-contract"
  u5000000)    ;; transaction amount
```

## Error Codes

### Relayer Contract
- `u100`: Invalid nonce or expired transaction
- `u101`: Signature verification failed
- `u102`: Transaction not found
- `u103`: Unauthorized access
- `u104`: Transaction already paid
- `u105`: Insufficient sponsor balance
- `u106`: Invalid amount
- `u107`: Sponsor not found

### Fee Manager Contract
- `u200`: Unauthorized access
- `u201`: Invalid fee configuration
- `u202`: Contract not found
- `u203`: Invalid percentage (exceeds maximum)

## Development

### Prerequisites
- Clarinet >= 1.7.0
- Stacks CLI

### Setup
```bash
# Install dependencies
clarinet install

# Check contracts
clarinet check

# Run tests
clarinet test

# Deploy to testnet
clarinet deploy --testnet
```

### Testing
```bash
# Run unit tests
clarinet test tests/relayer-test.ts

# Run integration tests
clarinet test tests/integration-test.ts

# Test with console
clarinet console
```

## Deployment

### Testnet Deployment
```bash
clarinet deploy --testnet
```

### Mainnet Deployment
```bash
clarinet deploy --mainnet
```

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   User DApp     │    │   Sponsor API   │    │  Fee Manager    │
│                 │    │                 │    │                 │
│ - Sign txn      │    │ - Submit calls  │    │ - Fee calc      │
│ - Get nonce     │    │ - Manage balance│    │ - Fee tracking  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │  Relayer        │
                    │  Contract       │
                    │                 │
                    │ - Verify sigs   │
                    │ - Track nonces  │
                    │ - Manage funds  │
                    │ - Event logging │
                    └─────────────────┘
```

## Future Enhancements

- [ ] Multi-signature sponsor approvals
- [ ] Batch transaction processing
- [ ] Cross-chain relaying support
- [ ] Advanced analytics dashboard
- [ ] Automatic fee adjustment based on network conditions

## License

MIT License - see LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## Support

For issues and questions:
- Create an issue on GitHub
- Join our Discord community
- Check the documentation wiki
