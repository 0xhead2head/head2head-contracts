// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { IHead2HeadOracle } from "../src/IHead2HeadOracle.sol";
import { Head2Head } from "../src/Head2Head.sol";
import { Head2HeadOracle } from "../src/Head2HeadOracle.sol";

contract TestHead2Head is Test {
    Head2Head public head2head;
    MockERC20 public token;
    Head2HeadOracle public head2HeadOracle;

    address admin = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address user3 = address(0x4);

    address collateralTokenAddress;

    uint256 timeStamp = 1e7;

    uint256 btcPrice1 = 20000 * 10**10;
    uint256 btcPrice2 = 22000 * 10**10;

    uint256 ethPrice1 = 2000 * 10**10;
    uint256 ethPrice2 = 2000 * 10**10;


    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000000;
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    string public constant token1 = "BTC";
    string public constant token2 = "ETH";

    function setUp() public {
        uint256[] memory initialPriceArray = new uint256[](2);
        initialPriceArray[0] = btcPrice1;
        initialPriceArray[1] = ethPrice1;
        uint256[] memory finalPriceArray = new uint256[](2);
        finalPriceArray[0] = btcPrice2;
        finalPriceArray[1] = ethPrice2;
        uint256[] memory equalPriceArray = new uint256[](2);
        equalPriceArray[0] = btcPrice2;
        equalPriceArray[1] = ethPrice2;

        string[] memory tokenArray = new string[](2);
        tokenArray[0] = token1;
        tokenArray[1] = token2;

        vm.startPrank(admin);
        head2HeadOracle = new Head2HeadOracle();
        token = new MockERC20();
        collateralTokenAddress = address(token);
        address[] memory collateralTokenArray = new address[](1);
        collateralTokenArray[0] = collateralTokenAddress;
        head2head = new Head2Head(
            head2HeadOracle,               // _head2HeadOracle
            collateralTokenArray,    // _collateralTokens
            5                       // _feePercentage
        );

        head2HeadOracle.grantRole(ORACLE_ROLE, admin);

        vm.warp(timeStamp + 240);
        head2HeadOracle.store(timeStamp, tokenArray, initialPriceArray);
        head2HeadOracle.store(timeStamp + 120, tokenArray, finalPriceArray);
        head2HeadOracle.store(timeStamp + 240, tokenArray, equalPriceArray);
        vm.warp(timeStamp - 120);

        token.transfer(user1, 100e18);
        token.transfer(user2, 100e18);
        token.transfer(user3, 100e18);

        vm.stopPrank();

        vm.startPrank(user1);
        token.approve(address(head2head), 100e18);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(head2head), 100e18);
        vm.stopPrank();

        vm.startPrank(user3);
        token.approve(address(head2head), 100e18);
        vm.stopPrank();
    }

    function testSetFeePercentage() public {
        vm.startPrank(admin);

        // Set and get fee percentage.
        head2head.setFeePercentage(15);
        assertEq(head2head.feePercentage(), 15);

        // Revert if fee percentage exceeds maximum.
        vm.expectRevert(Head2Head.InvalidFeePercentage.selector);
        head2head.setFeePercentage(30);

        vm.stopPrank();

        vm.startPrank(user1);

        // Revert if non-owner tries to set fee percentage.
        vm.expectRevert("Ownable: caller is not the owner");
        head2head.setFeePercentage(5);

        vm.stopPrank();
    }

    function testHead2Head() public {
        string[] memory token1Array = new string[](1);
        string[] memory token2Array = new string[](1);
        token1Array[0] = token1;
        token2Array[0] = token2;

        uint256[] memory lotIdArray = new uint256[](1);

        vm.startPrank(user1);
        head2head.createLot(token1, token2Array, 1e18, collateralTokenAddress, timeStamp, 120, false, false);
        head2head.createLot(token2, token1Array, 1e18, collateralTokenAddress, timeStamp, 120, false, false);
        vm.expectRevert(Head2Head.CannotJoinOnBothSides.selector);
        head2head.joinLot(1, token2, 1e18);
        vm.stopPrank();

        vm.startPrank(user2);
        head2head.joinLot(1, token2, 1e18);
        vm.stopPrank();

        vm.startPrank(user3);
        head2head.joinLot(1, token2, 1e18);
        head2head.joinLot(2, token1, 1e18);
        vm.expectRevert(Head2Head.TooEarly.selector);
        head2head.resolveLot(1);
        vm.warp(timeStamp + 120);
        head2head.resolveLot(1);
        head2head.resolveLot(2);
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 prev_balance = token.balanceOf(user1);
        lotIdArray[0] = 1;
        head2head.withdrawClaim(lotIdArray);
        assertEq(token.balanceOf(user1) - prev_balance, 19e17);
        vm.stopPrank();

        vm.startPrank(user2);
        prev_balance = token.balanceOf(user2);
        lotIdArray[0] = 1;
        head2head.withdrawRefund(lotIdArray);
        assertEq(token.balanceOf(user2) - prev_balance, 5e17);
        vm.stopPrank();

        vm.startPrank(user3);
        prev_balance = token.balanceOf(user3);
        lotIdArray[0] = 1;
        head2head.withdrawRefund(lotIdArray);
        lotIdArray[0] = 2;
        head2head.withdrawClaim(lotIdArray);
        assertEq(token.balanceOf(user3) - prev_balance, 24e17);
        vm.stopPrank();
    }

    function testPause() public {
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        head2head.pauseContract();
        vm.expectRevert("Ownable: caller is not the owner");
        head2head.unpauseContract();
        vm.stopPrank();

        string[] memory token1Array = new string[](1);
        string[] memory token2Array = new string[](1);
        token1Array[0] = token1;
        token2Array[0] = token2;

        vm.startPrank(admin);
        head2head.pauseContract();
        assertEq(head2head.paused(), true);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("Pausable: paused");
        head2head.createLot(token1, token2Array, 1e18, collateralTokenAddress, timeStamp, 120, false, false);
        vm.stopPrank();

        vm.startPrank(admin);
        head2head.unpauseContract();
        assertEq(head2head.paused(), false);
        vm.stopPrank();
    }

    function testDrawLot() public {
        string[] memory token1Array = new string[](1);
        string[] memory token2Array = new string[](1);
        token1Array[0] = token1;
        token2Array[0] = token2;

        uint256[] memory lotIdArray = new uint256[](1);

        vm.startPrank(user1);
        head2head.createLot(token1, token2Array, 1e18, collateralTokenAddress, timeStamp + 120, 120, false, false);
        vm.stopPrank();

        vm.startPrank(user2);
        head2head.joinLot(1, token2, 1e18);

        vm.warp(timeStamp + 240);
        head2head.resolveLot(1);
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 prev_balance = token.balanceOf(user1);
        lotIdArray[0] = 1;
        head2head.withdrawClaim(lotIdArray);
        assertEq(token.balanceOf(user1) - prev_balance, 9.5e17);
        vm.stopPrank();

        vm.startPrank(user2);
        prev_balance = token.balanceOf(user2);
        lotIdArray[0] = 1;
        head2head.withdrawClaim(lotIdArray);
        assertEq(token.balanceOf(user2) - prev_balance, 9.5e17);
        vm.stopPrank();

        // Expect 5% of the total pooled funds to be received as fees.
        assertEq(head2head.totalFees(collateralTokenAddress), 1e17);
    }

    function testTokenBChoices() public {
        string[] memory tokenChoiceArray = new string[](2);
        tokenChoiceArray[0] = token2;
        tokenChoiceArray[1] = "XXX";

        vm.startPrank(user1);
        head2head.createLot(token1, tokenChoiceArray, 1e18, collateralTokenAddress, timeStamp, 120, false, false);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(Head2Head.InvalidTokenID.selector);
        head2head.joinLot(1, "YYY", 1e18);
        head2head.joinLot(1, token2, 1e18);
        vm.expectRevert(Head2Head.InvalidTokenID.selector);
        head2head.joinLot(1, "XXX", 1e18);
        vm.stopPrank();
    }

    function testPrivateLot() public {
        string[] memory token2Array = new string[](1);
        token2Array[0] = token2;

        vm.startPrank(user1);
        head2head.createLot(token1, token2Array, 1e18, collateralTokenAddress, timeStamp, 120, true, false);
        address[] memory invitedArray = new address[](1);
        invitedArray[0] = user3;
        head2head.invite(1, invitedArray);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(Head2Head.NotInvitedToPrivateLot.selector);
        head2head.joinLot(1, token2, 1e18);
        vm.stopPrank();

        vm.startPrank(user3);
        head2head.joinLot(1, token2, 1e18);
        vm.stopPrank();
    }

    function testChallengeLot() public {
        string[] memory token2Array = new string[](1);
        token2Array[0] = token2;

        vm.startPrank(user1);
        head2head.createLot(token1, token2Array, 1e18, collateralTokenAddress, timeStamp, 120, false, true);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(Head2Head.CannotJoinLotAInChallenge.selector);
        head2head.joinLot(1, token1, 1e18);
        vm.expectRevert(Head2Head.LotSizeMustBeEqual.selector);
        head2head.joinLot(1, token2, 2e18);
        head2head.joinLot(1, token2, 1e18);
        vm.stopPrank();

        vm.startPrank(user3);
        vm.expectRevert(Head2Head.MultipleUsersNotAllowedInChallenge.selector);
        head2head.joinLot(1, token2, 1e18);
        vm.stopPrank();
    }

    function testExpiredLot() public {
        string[] memory token2Array = new string[](1);
        token2Array[0] = token2;

        uint256[] memory lotIdArray = new uint256[](1);

        vm.startPrank(user1);
        head2head.createLot(token1, token2Array, 1e18, collateralTokenAddress, timeStamp, 120, false, false);
        vm.stopPrank();

        vm.startPrank(user2);
        head2head.joinLot(1, token1, 1e18);
        vm.stopPrank();

        vm.warp(timeStamp + 120);

        vm.startPrank(user1);
        uint256 prev_balance = token.balanceOf(user1);
        lotIdArray[0] = 1;
        head2head.withdrawRefund(lotIdArray);
        assertEq(token.balanceOf(user1) - prev_balance, 10e17);
        vm.stopPrank();

        vm.startPrank(user2);
        prev_balance = token.balanceOf(user2);
        lotIdArray[0] = 1;
        head2head.withdrawRefund(lotIdArray);
        assertEq(token.balanceOf(user2) - prev_balance, 10e17);
        vm.stopPrank();
    }

    function testHead2HeadFunctions() public {
        string[] memory token2Array = new string[](1);
        token2Array[0] = token2;

        vm.startPrank(admin);
        MockERC20 collateralToken = new MockERC20();
        address[] memory tokenArray = new address[](2);
        tokenArray[0] = address(token);
        tokenArray[1] = address(collateralToken);
        head2head.setIsValidCollateralToken(tokenArray, true);
        vm.stopPrank();

        vm.startPrank(user1);
        head2head.createLot(token1, token2Array, 1e18, collateralTokenAddress, timeStamp, 120, false, false);
        vm.stopPrank();

        vm.startPrank(user2);
        head2head.joinLot(1, token2, 1e18);
        vm.stopPrank();

        vm.startPrank(user3);
        head2head.joinLot(1, token2, 1e18);
        vm.warp(timeStamp + 120);
        head2head.resolveLot(1);
        vm.stopPrank();

        vm.expectRevert("Ownable: caller is not the owner");
        head2head.withdrawFee(collateralTokenAddress);

        vm.expectRevert("Ownable: caller is not the owner");
        head2head.setHead2HeadOracle(IHead2HeadOracle(address(0x5)));

        MockERC20 newToken = new MockERC20();
        vm.expectRevert("Ownable: caller is not the owner");
        address[] memory tokenArray2 = new address[](1);
        tokenArray2[0] = address(newToken);
        head2head.setIsValidCollateralToken(tokenArray2, true);

        vm.startPrank(admin);
        uint256 initialAdminBalance = token.balanceOf(admin);

        vm.expectRevert(Head2Head.Head2HeadOracleCannotBeZero.selector);
        head2head.setHead2HeadOracle(IHead2HeadOracle(address(0x0)));

        head2head.setHead2HeadOracle(IHead2HeadOracle(address(0x5)));
        head2head.withdrawFee(collateralTokenAddress);
        assertEq(token.balanceOf(admin), initialAdminBalance + 1e17);
        assertEq(address(head2head.head2HeadOracle()), address(0x5));
        vm.stopPrank();
    }

    function testInvalidCreateHead2Head() public {
        string[] memory token2Array = new string[](1);
        string[] memory token1ArrayInvalid = new string[](2);
        token2Array[0] = token2;
        token1ArrayInvalid[0] = token2;
        token1ArrayInvalid[1] = token1;

        vm.warp(timeStamp - 60);

        vm.startPrank(user1);
        vm.expectRevert(Head2Head.TokenACannotBeEmpty.selector);
        head2head.createLot("", token2Array, 1e18,  collateralTokenAddress,timeStamp, 120, false, false);

        vm.expectRevert(Head2Head.StartTimestampInPast.selector);
        head2head.createLot(token1, token2Array, 1e18,  collateralTokenAddress,timeStamp - 120, 120, false, false);

        vm.expectRevert(Head2Head.SizeMustBePositive.selector);
        head2head.createLot(token1, token2Array, 0, collateralTokenAddress, timeStamp, 120, false, false);

        vm.expectRevert(Head2Head.DurationMustBePositive.selector);
        head2head.createLot(token1, token2Array, 1e18,  collateralTokenAddress,timeStamp, 0, false, false);

        vm.expectRevert(Head2Head.DurationTooLong.selector);
        head2head.createLot(token1, token2Array, 1e18,  collateralTokenAddress,timeStamp, 365*24*60*60, false, false);

        vm.expectRevert(Head2Head.TokensCannotBeIdentical.selector);
        head2head.createLot(token1, token1ArrayInvalid, 1e18, collateralTokenAddress, timeStamp, 120, false, false);

        vm.stopPrank();
    }

    function testInvalidJoinHead2Head() public {
        string[] memory token2Array = new string[](1);
        token2Array[0] = token2;

        vm.startPrank(user1);
        head2head.createLot(token1, token2Array, 1e18, collateralTokenAddress, timeStamp, 120, false, false);

        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(Head2Head.InvalidLotId.selector);
        head2head.joinLot(100, token2, 1e18);
        vm.expectRevert(Head2Head.SizeMustBePositive.selector);
        head2head.joinLot(1, token2, 0);

        vm.warp(timeStamp);
        vm.expectRevert(Head2Head.TooLateToJoinLot.selector);
        head2head.joinLot(1, token2, 1e18);
        vm.warp(timeStamp-120);

        vm.expectRevert(Head2Head.InvalidTokenID.selector);
        head2head.joinLot(1, "randomtoken", 1e18);

        head2head.joinLot(1, token2, 1e18);

        vm.expectRevert(Head2Head.CannotJoinOnBothSides.selector);
        head2head.joinLot(1, token1, 1e18);
        vm.expectRevert(Head2Head.InvalidTokenID.selector);
        head2head.joinLot(1, "randomtoken", 1e18);

        vm.stopPrank();
    }

    function testInvalidResolveLot() public {
        string[] memory token2Array = new string[](1);
        token2Array[0] = token2;

        vm.startPrank(user1);
        head2head.createLot(token1, token2Array, 1e18, collateralTokenAddress, timeStamp, 120, false, false);

        vm.stopPrank();

        vm.startPrank(user2);
        head2head.joinLot(1, token2, 1e18);
        vm.stopPrank();

        vm.startPrank(user3);
        vm.expectRevert(Head2Head.InvalidLotId.selector);
        head2head.resolveLot(3);

        vm.expectRevert(Head2Head.TooEarly.selector);
        head2head.resolveLot(1);

        vm.warp(timeStamp + 120);
        head2head.resolveLot(1);
        vm.expectRevert(Head2Head.LotAlreadyResolved.selector);
        head2head.resolveLot(1);

        vm.stopPrank();
    }

    function testInvalidWithdrawRefund() public {
        string[] memory token2Array = new string[](1);
        token2Array[0] = token2;
        uint256[] memory lotIds = new uint256[](1);
        lotIds[0] = 1;
        uint256[] memory invalidLotIds = new uint256[](3);
        invalidLotIds[0] = 1;
        invalidLotIds[1] = 2;
        invalidLotIds[2] = 3;

        vm.startPrank(user1);
        head2head.createLot(token1, token2Array, 2e18, collateralTokenAddress, timeStamp, 120, false, false);
        vm.stopPrank();

        vm.startPrank(user2);
        head2head.joinLot(1, token2, 1e18);
        vm.stopPrank();

        vm.startPrank(user1);

        vm.warp(timeStamp - 60);
        vm.expectRevert(Head2Head.TooEarly.selector);
        head2head.withdrawRefund(lotIds);

        vm.warp(timeStamp);

        vm.expectRevert(Head2Head.InvalidLotId.selector);
        head2head.withdrawRefund(invalidLotIds);

        uint256 prev_balance = token.balanceOf(user1);
        head2head.withdrawRefund(lotIds);
        assertEq(token.balanceOf(user1) - prev_balance, 1e18);

        vm.expectRevert(Head2Head.AlreadyWithdrawn.selector);
        head2head.withdrawRefund(lotIds);

        vm.stopPrank();

        vm.startPrank(user3);

        vm.expectRevert(Head2Head.NotPartOfLot.selector);
        head2head.withdrawRefund(lotIds);

        vm.stopPrank();
    }

    function testInvalidWithdrawClaim() public {
        string[] memory token2Array = new string[](1);
        token2Array[0] = token2;
        uint256[] memory lotIds = new uint256[](1);
        lotIds[0] = 1;
        uint256[] memory invalidLotIds = new uint256[](3);
        invalidLotIds[0] = 1;
        invalidLotIds[1] = 2;
        invalidLotIds[2] = 3;

        vm.startPrank(user1);
        head2head.createLot(token1, token2Array, 2e18, collateralTokenAddress, timeStamp, 120, false, false);
        vm.stopPrank();

        vm.startPrank(user2);
        head2head.joinLot(1, token2, 1e18);
        vm.stopPrank();

        vm.startPrank(user1);

        vm.warp(timeStamp);
        vm.expectRevert(Head2Head.TooEarly.selector);
        head2head.withdrawClaim(lotIds);

        vm.warp(timeStamp + 120);

        vm.expectRevert(Head2Head.InvalidLotId.selector);
        head2head.withdrawClaim(invalidLotIds);

        uint256 prev_balance = token.balanceOf(user1);
        head2head.withdrawClaim(lotIds);
        assertEq(token.balanceOf(user1) - prev_balance, 19e17);

        vm.expectRevert(Head2Head.AlreadyWithdrawn.selector);
        head2head.withdrawClaim(lotIds);

        vm.stopPrank();

        vm.startPrank(user3);

        vm.expectRevert(Head2Head.NotPartOfLot.selector);
        head2head.withdrawClaim(lotIds);

        vm.stopPrank();
    }

    function testInvalidCollateralToken() public {
        string[] memory token2Array = new string[](1);
        MockERC20 newToken = new MockERC20();

        vm.startPrank(user1);
        vm.expectRevert(Head2Head.InvalidCollateralToken.selector);
        head2head.createLot(token1, token2Array, 1e18, address(newToken), timeStamp, 120, false, false);
        vm.stopPrank();
    }

    function testInvalidTokens() public {
        string memory invalidTokenString = "randomInvalid";
        string memory invalidTokenString2 = "randomInvalid2";
        string[] memory invalidTokenArray = new string[](1);
        string[] memory invalidTokenArray2 = new string[](1);
        string[] memory token2Array = new string[](1);
        invalidTokenArray[0] = invalidTokenString;
        token2Array[0] = token2;
        invalidTokenArray2[0] = invalidTokenString2;

        uint256[] memory lotIdArray = new uint256[](1);

        vm.startPrank(user1);
        head2head.createLot(invalidTokenString, token2Array, 1e18, collateralTokenAddress, timeStamp, 120, false, false);
        head2head.createLot(token1, invalidTokenArray, 1e18, collateralTokenAddress, timeStamp, 120, false, false);
        head2head.createLot(invalidTokenString, invalidTokenArray2, 1e18, collateralTokenAddress, timeStamp, 120, false, false);

        vm.stopPrank();

        vm.startPrank(user2);
        head2head.joinLot(1, token2, 1e18);
        head2head.joinLot(2, invalidTokenString, 1e18);
        head2head.joinLot(3, invalidTokenString2, 1e18);
        vm.stopPrank();

        vm.startPrank(admin);
        vm.warp(timeStamp + 120);
        vm.expectRevert(Head2HeadOracle.PriceNotAvailable.selector);
        head2head.resolveLot(1);
        head2HeadOracle.setInvalid(invalidTokenArray, true);
        head2HeadOracle.setInvalid(invalidTokenArray2, true);
        head2head.resolveLot(1);

        head2head.resolveLot(2);
        head2head.resolveLot(3);

        uint256 prev_balance = token.balanceOf(admin);
        head2head.withdrawFee(collateralTokenAddress);
        assertEq(token.balanceOf(admin) - prev_balance, 3e17);

        vm.stopPrank();

        vm.startPrank(user2);
        prev_balance = token.balanceOf(user2);
        lotIdArray[0] = 1;
        head2head.withdrawClaim(lotIdArray);
        assertEq(token.balanceOf(user2) - prev_balance, 19e17);

        prev_balance = token.balanceOf(user2);
        lotIdArray[0] = 2;
        head2head.withdrawClaim(lotIdArray);
        assertEq(token.balanceOf(user2) - prev_balance, 0);

        prev_balance = token.balanceOf(user2);
        lotIdArray[0] = 3;
        head2head.withdrawClaim(lotIdArray);
        assertEq(token.balanceOf(user2) - prev_balance, 19e17);

        vm.stopPrank();

        vm.startPrank(user1);
        prev_balance = token.balanceOf(user1);
        lotIdArray[0] = 1;
        head2head.withdrawClaim(lotIdArray);
        assertEq(token.balanceOf(user1) - prev_balance, 0);

        prev_balance = token.balanceOf(user1);
        lotIdArray[0] = 2;
        head2head.withdrawClaim(lotIdArray);
        assertEq(token.balanceOf(user1) - prev_balance, 19e17);

        prev_balance = token.balanceOf(user1);
        lotIdArray[0] = 3;
        head2head.withdrawClaim(lotIdArray);
        assertEq(token.balanceOf(user1) - prev_balance, 0);

        vm.stopPrank();
    }

    function testInvite_RevertIf_LotIsNotPrivate() public {
        string[] memory token2Array = new string[](1);
        token2Array[0] = token2;

        vm.startPrank(user1);
        head2head.createLot(token1, token2Array, 1e18, collateralTokenAddress, timeStamp, 120, false, false);
        address[] memory invitedArray = new address[](1);
        invitedArray[0] = user3;
        vm.expectRevert(Head2Head.NotPrivateLot.selector);
        head2head.invite(1, invitedArray);
        vm.stopPrank();
    }

    function testInvite_RevertIf_SenderNotInvited() public {
        string[] memory token2Array = new string[](1);
        token2Array[0] = token2;

        vm.prank(user1);
        head2head.createLot(token1, token2Array, 1e18, collateralTokenAddress, timeStamp, 120, true, false);

        address[] memory invitedArray = new address[](1);
        invitedArray[0] = user3;
        vm.prank(user2);
        vm.expectRevert(Head2Head.NotPermittedToInvite.selector);
        head2head.invite(1, invitedArray);
    }

    function testRenounceOwnership() public {
        vm.startPrank(admin);
        vm.expectRevert("renounceOwnership is disabled");
        head2head.renounceOwnership();
        vm.stopPrank();
    }
}
