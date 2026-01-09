// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {Transaction, MemoryTransactionHelper} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {NONCE_HOLDER_SYSTEM_CONTRACT, BOOTLOADER_FORMAL_ADDRESS} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Lifecycle of a type 113 (0x71) transaction
 *
 * Phase 1 Validation
 *  1. The user sends the transaction to the "zkSync API client" (sort of a "light node")
 *  2. The zkSync API client checks to see the nonce is unique by querying the NonceHolder system contract
 *  3. The zkSync API client calls validateTransaction, which MUST update the nonce
 *  4. The zkSync API client checks the nonce is updated
 *  5. The zkSync API client calls payForTransaction, or prepareForPaymaster &
 *     validateAndPayForPaymasterTransaction
 *  6. The zkSync API client verifies that the bootloader gets paid
 *
 * Phase 2 Execution
 *  7. The zkSync API client passes the validated transaction to the main node / sequencer (as of today, they are
 *     the same)
 *  8. The main node calls executeTransaction
 *  9. If a paymaster was used, the postTransaction is called
 */

contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__NotFromBootLoader();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier requireFromBootLoader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotFromBootLoader();
        }
    }

    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // ...who is the msg.sender when this is called?
    /**
    * @notice must increase the nonce
    * @notice must validate the transaction (check the owner signed the transaction)
    * @notice also check if we have enough balance to pay for the transaction
    */
    function validateTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction memory _transaction)
        external
        payable
        requireFromBootLoader()
        returns (bytes4 magic) 
        {
            // Call NonceHolder
            // increment the nonce
            // call(x,y,z) ->system contract call
            SystemContractsCaller.systemCallWithPropagatedRevert(
                uint32(gasleft()),
                address(NONCE_HOLDER_SYSTEM_CONTRACT),
                0,
                abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
                );

            // check for fee to pay
            uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
            if (totalRequiredBalance > address(this).balance) {
                revert ZkMinimalAccount__NotEnoughBalance();
            }

            // Check the signature
            bytes32 txHash = _transaction.encodeHash(); // Get the hash based on tx type (helper)
            
            // Note: The step MessageHashUtils.toEthSignedMessageHash(txHash) is NOT needed here
            // for zkSync AA transactions using the standard EIP-712 flow as _transaction.encodeHash()
            // already produces the EIP-712 compliant hash.
        
            address signer = ECDSA.recover(txHash, _transaction.signature); // Recover signer directly from txHash
            bool isValidSigner = signer == owner(); // Check if signer is the contract owner
            // return magic number
            bytes4 magic;
            if (isValidSigner) {
                magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC; // Magic value for success
            } else {
                magic = bytes4(0); // Magic value for failure (equivalent to false)
            }
            return magic;
        }

    function executeTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction memory _transaction)
        external
        payable {}

    // There is no point in providing possible signed hash in the `executeTransactionFromOutside` method,
    // since it typically should not be trusted.
    function executeTransactionFromOutside(Transaction memory _transaction) external payable {}

    function payForTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction memory _transaction)
        external
        payable {}

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction memory _transaction)
        external
        payable {}

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
}