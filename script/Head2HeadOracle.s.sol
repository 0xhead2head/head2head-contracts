// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import { Head2HeadOracle } from "../src/Head2HeadOracle.sol";

contract DeployHead2HeadOracle is Script {

    function run() external {
        bytes32 ORACLE_ROLE = keccak256("ORACLE_ROLE");
        address ORACLE_ADDRESS = vm.envAddress("ORACLE_ADDRESS");

        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Head2HeadOracle head2HeadOracle = new Head2HeadOracle();

        head2HeadOracle.grantRole(ORACLE_ROLE, ORACLE_ADDRESS);

        vm.stopBroadcast();
    }
}
