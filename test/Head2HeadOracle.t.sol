// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { Head2HeadOracle } from "../src/Head2HeadOracle.sol";

contract TestHead2HeadOracle is Test {
    Head2HeadOracle public head2HeadOracle;
    address admin = address(0x1);
    address user = address(0x2);
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000000;
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    string public constant token1 = "bitcoin";
    string public constant token2 = "ethereum";

    uint256 timeStamp = 1e7;

    uint256 btcPrice1 = 20000 * 10**10;
    uint256 btcPrice2 = 22000 * 10**10;

    uint256 ethPrice1 = 2000 * 10**10;
    uint256 ethPrice2 = 2000 * 10**10;

    function setUp() public {
        vm.startPrank(admin);
        head2HeadOracle = new Head2HeadOracle();
        head2HeadOracle.grantRole(ORACLE_ROLE, admin);
        vm.stopPrank();
    }

    function testAdmin() public {
        assertTrue(head2HeadOracle.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    function testOracle() public {
        assertTrue(head2HeadOracle.hasRole(ORACLE_ROLE, admin));
    }

    function testStore() public {
        uint256[] memory initialPriceArray = new uint256[](2);
        initialPriceArray[0] = btcPrice1;
        initialPriceArray[1] = ethPrice1;

        uint256[] memory finalPriceArray = new uint256[](2);
        finalPriceArray[0] = btcPrice2;
        finalPriceArray[1] = ethPrice2;

        string[] memory tokenArray = new string[](2);
        tokenArray[0] = token1;
        tokenArray[1] = token2;

        vm.warp(timeStamp + 120);
        vm.prank(admin);
        head2HeadOracle.store(timeStamp, tokenArray, initialPriceArray);
        vm.prank(admin);
        head2HeadOracle.store(timeStamp + 120, tokenArray, finalPriceArray);

        uint256 nearestTimeStamp1 = _getNearestMinuteTimestamp(timeStamp);
        uint256 nearestTimeStamp2 = _getNearestMinuteTimestamp(timeStamp + 120);

        assertEq(head2HeadOracle.price(token1, nearestTimeStamp1), btcPrice1);
        assertEq(head2HeadOracle.price(token1, nearestTimeStamp2), btcPrice2);

        assertEq(head2HeadOracle.price(token2, nearestTimeStamp1), ethPrice1);
        assertEq(head2HeadOracle.price(token2, nearestTimeStamp2), ethPrice2);
    }

    function testGetHistoricalPrice() public {
        uint256[] memory initialPriceArray = new uint256[](2);
        initialPriceArray[0] = btcPrice1;
        initialPriceArray[1] = ethPrice1;

        uint256[] memory finalPriceArray = new uint256[](2);
        finalPriceArray[0] = btcPrice2;
        finalPriceArray[1] = ethPrice2;

        string[] memory tokenArray = new string[](2);
        tokenArray[0] = token1;
        tokenArray[1] = token2;

        vm.warp(timeStamp + 120);
        vm.startPrank(admin);
        head2HeadOracle.store(timeStamp, tokenArray, initialPriceArray);
        head2HeadOracle.store(timeStamp + 120, tokenArray, finalPriceArray);
        vm.stopPrank();

        assertEq(head2HeadOracle.getHistoricalPrice(token1, timeStamp), btcPrice1);
        assertEq(head2HeadOracle.getHistoricalPrice(token1, timeStamp + 120), btcPrice2);
    }

    function testGetPrice() public {
        uint256[] memory initialPriceArray = new uint256[](2);
        initialPriceArray[0] = btcPrice1;
        initialPriceArray[1] = ethPrice1;

        uint256[] memory finalPriceArray = new uint256[](2);
        finalPriceArray[0] = btcPrice2;
        finalPriceArray[1] = ethPrice2;

        string[] memory tokenArray = new string[](2);
        tokenArray[0] = token1;
        tokenArray[1] = token2;

        vm.warp(timeStamp);
        vm.prank(admin);
        head2HeadOracle.store(timeStamp, tokenArray, initialPriceArray);
        assertEq(head2HeadOracle.getPrice(token1), btcPrice1);
        assertEq(head2HeadOracle.getPrice(token2), ethPrice1);

        vm.warp(timeStamp + 120);
        vm.prank(admin);
        head2HeadOracle.store(timeStamp + 120, tokenArray, finalPriceArray);
        assertEq(head2HeadOracle.getPrice(token1), btcPrice2);
        assertEq(head2HeadOracle.getPrice(token2), ethPrice2);
    }

    function testStoreReverts() public {
        uint256[] memory initialPriceArray = new uint256[](2);
        initialPriceArray[0] = btcPrice1;
        initialPriceArray[1] = ethPrice1;

        uint256[] memory finalPriceArray = new uint256[](2);
        finalPriceArray[0] = btcPrice2;
        finalPriceArray[1] = ethPrice2;

        uint256[] memory invalidPriceArray = new uint256[](4);
        invalidPriceArray[0] = btcPrice2;
        invalidPriceArray[1] = ethPrice2;
        invalidPriceArray[2] = ethPrice1;
        invalidPriceArray[3] = btcPrice1;

        string[] memory tokenArray = new string[](2);
        tokenArray[0] = token1;
        tokenArray[1] = token2;

        string[] memory invalidTokenArray = new string[](4);
        invalidTokenArray[0] = token1;
        invalidTokenArray[1] = token2;
        invalidTokenArray[2] = "token3";
        invalidTokenArray[3] = "token4";

        vm.startPrank(admin);

        vm.expectRevert(Head2HeadOracle.InvalidTimestamp.selector);
        head2HeadOracle.store(timeStamp, tokenArray, initialPriceArray);

        vm.warp(timeStamp);

        vm.expectRevert(Head2HeadOracle.UnevenArrays.selector);
        head2HeadOracle.store(timeStamp, tokenArray, invalidPriceArray);

        vm.expectRevert(Head2HeadOracle.UnevenArrays.selector);
        head2HeadOracle.store(timeStamp, invalidTokenArray, initialPriceArray);

        vm.stopPrank();
        vm.startPrank(user);

        vm.expectRevert("AccessControl: account 0x0000000000000000000000000000000000000002 is missing role 0x68e79a7bf1e0bc45d0a330c573bc367f9cf464fd326078812f301165fbda4ef1");
        head2HeadOracle.store(timeStamp, tokenArray, initialPriceArray);

        vm.stopPrank();
    }

    function testGetHistoricalPriceRevert() public {
        vm.warp(timeStamp);
        vm.expectRevert(Head2HeadOracle.PriceNotAvailable.selector);
        head2HeadOracle.getPrice(token1);

        vm.expectRevert(Head2HeadOracle.PriceNotAvailable.selector);
        head2HeadOracle.getHistoricalPrice(token1, timeStamp);
    }

    function testInvalid() public {
        string[] memory invalidTokensArray = new string[](4);
        invalidTokensArray[0] = "invalid1";
        invalidTokensArray[1] = "invalid2";
        invalidTokensArray[2] = "invalid3";
        invalidTokensArray[3] = "invalid4";

        vm.startPrank(user);
        vm.expectRevert("AccessControl: account 0x0000000000000000000000000000000000000002 is missing role 0x68e79a7bf1e0bc45d0a330c573bc367f9cf464fd326078812f301165fbda4ef1");
        head2HeadOracle.setInvalid(invalidTokensArray, true);
        for(uint256 i = 0; i < invalidTokensArray.length; i++){
            assertEq(head2HeadOracle.isInvalid(invalidTokensArray[i]), false);
        }
        vm.stopPrank();

        vm.startPrank(admin);
        head2HeadOracle.setInvalid(invalidTokensArray, true);
        for(uint256 i = 0; i < invalidTokensArray.length; i++){
            assertEq(head2HeadOracle.isInvalid(invalidTokensArray[i]), true);
        }
        vm.stopPrank();
    }

    function testRenounceRole() public {
        vm.startPrank(admin);
        vm.expectRevert("renounceRole is disabled");
        head2HeadOracle.renounceRole(DEFAULT_ADMIN_ROLE, admin);
        vm.stopPrank();
    }

    function _getNearestMinuteTimestamp(uint256 _timestamp) internal pure returns(uint256) {
        return (_timestamp - (_timestamp % 60));
    }
}
