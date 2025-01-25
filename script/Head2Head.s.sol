// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import { IHead2HeadOracle } from "../src/IHead2HeadOracle.sol";
import { Head2Head } from "../src/Head2Head.sol";

contract DeployHead2Head is Script {

    function run() external {
        address COLLATERAL_ADDRESS = vm.envAddress("COLLATERAL_ADDRESS");
        address PRICE_FEED_ADDRESS = vm.envAddress("PRICE_FEED_ADDRESS");
        uint256 FEE_PERCENTAGE = 5;

        address[] memory COLLATERAL_TOKENS = new address[](1);
        COLLATERAL_TOKENS[0] = COLLATERAL_ADDRESS;

        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new Head2Head(
            IHead2HeadOracle(PRICE_FEED_ADDRESS),
            COLLATERAL_TOKENS,
            FEE_PERCENTAGE
        );

        vm.stopBroadcast();
    }
}
