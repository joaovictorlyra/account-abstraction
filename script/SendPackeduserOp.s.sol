// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SendPackedUserOp is Script {
    using MessageHashUtils for bytes32;

    function run() public {
        HelperConfig helperConfig = new HelperConfig();
        address dest = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d; // Arbitrum Sepolia usdc address
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(IERC20.approve.selector, 0xC76DA0866C529c1822BA4673dB6D360378AA134E, 1e18);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory userOp = generateSignedUserOperarion(
            executeCallData, helperConfig.getConfig(), 0xDd9F940558FC1E78d0cBb262a11FBA5927799063
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;

        vm.startBroadcast();
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(helperConfig.getConfig().account));
        vm.stopBroadcast();
    }

    function generateSignedUserOperarion(
        bytes memory callData,
        HelperConfig.NetworkConfig memory config,
        address minimalAccount
    ) public view returns (PackedUserOperation memory) {
        // 1. Generate the unsigned data
        uint256 nonce = vm.getNonce(minimalAccount) - 1;
        PackedUserOperation memory userOp = _generateUnsignedUserOperation(callData, minimalAccount, nonce);
        // 2. Get the userOp hash
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(userOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        //3. sign it
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        if (block.chainid == 31337) {
            (v, r, s) = vm.sign(ANVIL_DEFAULT_KEY, digest);
        } else {
            (v, r, s) = vm.sign(config.account, digest);
        }
        userOp.signature = abi.encodePacked(r, s, v); // look at the the  order
        return userOp;
    }

    function _generateUnsignedUserOperation(bytes memory callData, address sender, uint256 nonce)
        internal
        pure
        returns (PackedUserOperation memory)
    {
        uint128 verificationGasLimit = 16777216;
        uint128 callGasLimit = verificationGasLimit;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;
        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: hex"",
            callData: callData,
            accountGasLimits: bytes32(uint256(uint128(verificationGasLimit)) << 128 | uint256(uint128(callGasLimit))),
            preVerificationGas: verificationGasLimit,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | maxFeePerGas),
            paymasterAndData: hex"",
            signature: hex""
        });
    }
}
