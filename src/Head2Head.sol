// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IHead2HeadOracle } from "./IHead2HeadOracle.sol";

/**
 * @title Head2Head
 * @notice This contract enables the creation and management of lots for bets,
 *         funds storage, lot resolution, and facilitates the distribution of
 *         winnings and refunds to users.
 */
contract Head2Head is
    Ownable,
    ReentrancyGuard,
    Pausable
{
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // ===================== Custom Errors ===================== //
    error InvalidFeePercentage();
    error Head2HeadOracleCannotBeZero();
    error CollateralTokenCannotBeZero();
    error TokenACannotBeEmpty();
    error StartTimestampInPast();
    error SizeMustBePositive();
    error DurationMustBePositive();
    error DurationTooLong();
    error InvalidCollateralToken();
    error NotInvitedToPrivateLot();
    error TooLateToJoinLot();
    error TransferError();
    error LotAlreadyResolved();
    error InvalidLotId();
    error NoUsersBeingInvited();
    error NotPrivateLot();
    error NotPermittedToInvite();
    error AlreadyWithdrawn();
    error TokensCannotBeEmpty();
    error TokensCannotBeIdentical();
    error TooEarly();
    error NotPartOfLot();
    error CannotJoinOnBothSides();
    error InvalidTokenID();
    error CannotJoinLotAInChallenge();
    error MultipleUsersNotAllowedInChallenge();
    error LotSizeMustBeEqual();

    // ===================== Structs ===================== //

    struct Lot {
        // ------------------------------------------------- //
        // Immutable attributes of the lot, set at creation. //
        // ------------------------------------------------- //
        string tokenA;
        mapping(string => bool) tokenBChoices;
        address collateralToken;
        uint256 startTimestamp;
        uint256 duration;
        address creator;
        bool isPrivate;
        bool isChallenge;
        bool isBasketOfAssets;

        // ------------------------------ //
        // Mutable attributes of the lot. //
        // ------------------------------ //
        string tokenB;
        // NOTE: The pool deposit and claim amounts are stored as uint128 to ensure that the
        //       math performed in withdrawClaim and withdrawRefund cannot overflow.
        mapping(address => uint128) userDepositPoolA;
        mapping(address => uint128) userDepositPoolB;
        uint128 totalDepositPoolA;
        uint128 totalDepositPoolB;
        // only invited can join if private
        mapping(address => bool) invited;
        // refunds should only be processed once per address
        mapping(address => bool) refunded;
        // resolveLot should only be called once
        bool resolved;
        // claims should only be processed once per address
        mapping(address => bool) claimed;
        uint128 totalClaimPoolA;
        uint128 totalClaimPoolB;
    }

    // Contains only the non-mapping state from a lot.
    struct LotData {
        string tokenA;
        address collateralToken;
        uint256 startTimestamp;
        uint256 duration;
        address creator;
        bool isPrivate;
        bool isChallenge;
        bool isBasketOfAssets;
        string tokenB;
        uint128 totalDepositPoolA;
        uint128 totalDepositPoolB;
        bool resolved;
        uint128 totalClaimPoolA;
        uint128 totalClaimPoolB;
    }

    // ===================== Events ===================== //

    event LotCreated(
        uint256 indexed lotId,
        string tokenA,
        string[] tokenBChoices,
        address collateralToken,
        uint256 startTimestamp,
        uint256 duration,
        uint256 size,
        address indexed creator,
        bool isPrivate,
        bool isChallenge
    );

    event Invited(
        uint256 indexed lotId,
        address from,
        address[] to
    );

    event LotJoined(
        uint256 indexed lotId,
        string token,
        address indexed user,
        uint256 size
    );

    event LotResolved(
        uint256 indexed lotId,
        uint256 size,
        string winningToken,
        uint256 startPriceTokenA,
        uint256 startPriceTokenB,
        uint256 resolvePriceTokenA,
        uint256 resolvePriceTokenB
    );

    event ClaimWithdrawn(
        uint256 indexed lotId,
        address indexed user,
        uint256 amount
    );

    event RefundWithdrawn(
        uint256 indexed lotId,
        address indexed user,
        uint256 amount
    );

    event FeeWithdrawn(
        address collateralToken,
        uint256 amount
    );

    // ===================== Constants ===================== //

    uint256 public constant MAX_FEE_PERCENTAGE = 20;

    uint256 public constant MAX_LOT_DURATION = 365*24*60*60;

    // ===================== Storage ===================== //

    IHead2HeadOracle public head2HeadOracle;

    uint256 public feePercentage;

    uint256 public lastLotId;

    // collateralToken -> tokenFeeCollected
    mapping(address => uint256) public totalFees;

    // lotId -> lot
    mapping(uint256 => Lot) private _lots;

    // collateralToken -> isValid
    mapping(address => bool) public validCollateralTokens;

    // ===================== Constructor ===================== //

    /**
     * @notice Constructor of the contract.
     *
     * @param _head2HeadOracle The address of the price feed contract.
     * @param _collateralTokens The array of addresses of the collateral token contract.
     * @param _feePercentage The fee percentage charged by the contract for its services.
     */
    constructor(
        IHead2HeadOracle _head2HeadOracle,
        address[] memory _collateralTokens,
        uint256 _feePercentage
    )
    {
        if(_feePercentage > MAX_FEE_PERCENTAGE){
            revert InvalidFeePercentage();
        }

        head2HeadOracle = _head2HeadOracle;

        for (uint256 i; i < _collateralTokens.length; i++) {
            if(_collateralTokens[i] == address(0)){
                revert CollateralTokenCannotBeZero();
            }
            validCollateralTokens[_collateralTokens[i]] = true;
        }
        feePercentage = _feePercentage;
    }

    // ===================== Owner External Functions ===================== //

    /**
     * @notice Sets the collateral tokens accepted for placing bets.
     *
     * @param _collateralTokens The array of addresses of the collateral tokens contract.
     * @param _isValid Whether the collateral tokens should be valid.
     */
    function setIsValidCollateralToken(
        address[] calldata _collateralTokens,
        bool _isValid
    ) external onlyOwner whenNotPaused {
        for (uint256 i; i < _collateralTokens.length; i++) {
            validCollateralTokens[_collateralTokens[i]] = _isValid;
        }
    }

    /**
     * @notice Sets the price feed oracle address.
     *
     * @param _head2HeadOracle The address of the price feed oracle contract.
     */
    function setHead2HeadOracle(IHead2HeadOracle _head2HeadOracle) external onlyOwner whenNotPaused {
        if(address(_head2HeadOracle) == address(0)){
            revert Head2HeadOracleCannotBeZero();
        }
        head2HeadOracle = _head2HeadOracle;
    }

    /**
     * @notice Withdraws the fee accrued in the contract.
     * @param _collateralToken The address of the collateral token contract.
     */
    function withdrawFee(address _collateralToken) external onlyOwner nonReentrant whenNotPaused {
        uint256 feeAmount = totalFees[_collateralToken];
        totalFees[_collateralToken] = 0;

        if(feeAmount > 0){
            IERC20(_collateralToken).safeTransfer(
                _msgSender(),
                feeAmount
            );
        }

        emit FeeWithdrawn(_collateralToken, feeAmount);
    }

    /**
     * @notice Sets the percentage of fee taken by the platform for each lot.
     * @param _feePercentage The percentage that the platform will take as fee
     */
    function setFeePercentage(
        uint256 _feePercentage
    ) external onlyOwner whenNotPaused {
        if(_feePercentage > MAX_FEE_PERCENTAGE){
            revert InvalidFeePercentage();
        }

        feePercentage = _feePercentage;
    }

    function pauseContract() external onlyOwner {
        _pause();
    }

    function unpauseContract() external onlyOwner {
        _unpause();
    }

    // ===================== Other External Functions ===================== //

    /**
     * @notice Creates a new lot for betting.
     *
     * @param _tokenA The token to be used as the primary token for betting.
     * @param _tokenBChoices The array of choices/options for the second token in the betting lot.
     * @param _size The size of the bet or deposit for the lot.
     * @param _collateralToken The collateral token that will be used as deposit for the lot.
     * @param _startTimestamp The starting timestamp for the lot.
     * @param _duration The duration of the lot.
     * @param _isPrivate Boolean indicating if the lot is private (restricted to invited
     *                   participants only).
     * @param _isChallenge Boolean indicating if the lot is a challenge.
     */
    function createLot(
        string calldata _tokenA,
        string[] calldata _tokenBChoices,
        uint256 _size,
        address _collateralToken,
        uint256 _startTimestamp,
        uint256 _duration,
        bool _isPrivate,
        bool _isChallenge
    ) external nonReentrant whenNotPaused {
        address creator = _msgSender();

        if(_size <= 0){
            revert SizeMustBePositive();
        }
        if(_startTimestamp <= block.timestamp){
            revert StartTimestampInPast();
        }
        if(_duration >= MAX_LOT_DURATION){
            revert DurationTooLong();
        }
        if(_duration <= 0){
            revert DurationMustBePositive();
        }
        if(!validCollateralTokens[_collateralToken]){
            revert InvalidCollateralToken();
        }
        if(_compareStrings(_tokenA, "")){
            revert TokenACannotBeEmpty();
        }

        // Set the immutable attributes of the lot.
        Lot storage lot = _lots[++lastLotId];
        lot.tokenA = _tokenA;
        lot.collateralToken = _collateralToken;
        lot.startTimestamp = _startTimestamp;
        lot.duration = _duration;
        lot.creator = creator;
        lot.isPrivate = _isPrivate;
        lot.isChallenge = _isChallenge;
        for (uint256 i; i < _tokenBChoices.length; i++) {
            if(_compareStrings(_tokenBChoices[i], "")){
                revert TokensCannotBeEmpty();
            }
            if(_compareStrings(_tokenA, _tokenBChoices[i])){
                revert TokensCannotBeIdentical();
            }

            lot.tokenBChoices[_tokenBChoices[i]] = true;
        }

        // It is a "basket of assets" lot if no tokenBChoices are given.
        // The user who joins the lot can choose any token as tokenB.
        if (_tokenBChoices.length == 0) {
            lot.isBasketOfAssets = true;
        }

        // For private lots, mark lot creator as invited.
        if (lot.isPrivate) {
            lot.invited[creator] = true;
        }

        // Execute the creator's deposit to the lot.
        _depositToPoolA(lot, creator, _size);

        emit LotCreated(
            lastLotId,
            lot.tokenA,
            _tokenBChoices,
            lot.collateralToken,
            lot.startTimestamp,
            lot.duration,
            lot.totalDepositPoolA,
            lot.creator,
            lot.isPrivate,
            lot.isChallenge
        );
    }

    /**
     * @notice Invites additional addresses to a private lot.
     *
     * @param _lotId The ID of the lot to invite participants to.
     * @param _addresses An array of addresses to be invited.
     */
    function invite(
        uint256 _lotId,
        address[] calldata _addresses
    ) external whenNotPaused {
        Lot storage lot = _getLot(_lotId);
        address user = _msgSender();

        if(!lot.isPrivate){
            revert NotPrivateLot();
        }
        if(!lot.invited[user]){
            revert NotPermittedToInvite();
        }
        if(_addresses.length <= 0){
            revert NoUsersBeingInvited();
        }

        for (uint256 i; i < _addresses.length; i++) {
            lot.invited[_addresses[i]] = true;
        }

        emit Invited(_lotId, user, _addresses);
    }

    /**
     * @notice Withdraws refund from one or multiple lots.
     *
     * @param _lotIds An array of lot IDs from which the user wants to withdraw the refund.
     */
    function withdrawRefund(
        uint256[] calldata _lotIds
    ) external nonReentrant whenNotPaused {
        address user = _msgSender();

        for (uint256 i; i < _lotIds.length; i++) {
            uint256 lotId = _lotIds[i];
            Lot storage lot = _getLot(lotId);
            if(block.timestamp < lot.startTimestamp){
                revert TooEarly();
            }

            if(lot.userDepositPoolA[user] <= 0 && lot.userDepositPoolB[user] <= 0){
                revert NotPartOfLot();
            }
            if(lot.refunded[user]){
                revert AlreadyWithdrawn();
            }

            uint256 refundAmount;
            uint256 size = _getSize(lot);

            if (size < lot.totalDepositPoolA) {
                refundAmount = (
                    (uint256(lot.totalDepositPoolA) - size) *
                    uint256(lot.userDepositPoolA[user])) /
                    uint256(lot.totalDepositPoolA
                );
            } else if (size < lot.totalDepositPoolB) {
                refundAmount = (
                    (uint256(lot.totalDepositPoolB) - size) *
                    uint256(lot.userDepositPoolB[user])) /
                    uint256(lot.totalDepositPoolB
                );
            }

            // Update state.
            lot.refunded[user] = true;

            // Execute transfer.
            if(refundAmount > 0){
                IERC20(lot.collateralToken).safeTransfer(
                    user,
                    refundAmount
                );
            }

            emit RefundWithdrawn(lotId, user, refundAmount);
        }
    }

    /**
     * @notice Withdraws claim from one or multiple lots.
     *
     * @param _lotIds An array of lot IDs from which the user wants to withdraw their claim.
     */
    function withdrawClaim(
        uint256[] calldata _lotIds
    ) external nonReentrant whenNotPaused {
        address user = _msgSender();

        for (uint256 i; i < _lotIds.length; i++) {
            uint256 lotId = _lotIds[i];
            Lot storage lot = _getLot(lotId);

            if(lot.claimed[user]){
                revert AlreadyWithdrawn();
            }
            if(lot.userDepositPoolA[user] <= 0 && lot.userDepositPoolB[user] <= 0){
                revert NotPartOfLot();
            }
            if (!lot.resolved) {
                _resolveLot(lotId, lot);
            }

            uint256 claimAmount;

            if (lot.userDepositPoolA[user] > 0) {
                claimAmount = (
                    uint256(lot.totalClaimPoolA) *
                    uint256(lot.userDepositPoolA[user]) /
                    uint256(lot.totalDepositPoolA)
                );
            } else {
                claimAmount = (
                    uint256(lot.totalClaimPoolB) *
                    uint256(lot.userDepositPoolB[user]) /
                    uint256(lot.totalDepositPoolB)
                );
            }

            // Update state.
            lot.claimed[user] = true;

            // Execute transfer.
            if(claimAmount > 0){
                IERC20(lot.collateralToken).safeTransfer(
                    user,
                    claimAmount
                );
            }

            emit ClaimWithdrawn(lotId, user, claimAmount);
        }
    }

    /**
     * @notice Joins a lot by depositing tokens.
     *
     * @param _lotId The ID of the lot the user wants to join.
     * @param _token The token the user wants to bet on.
     * @param _size The size (amount) of collateral tokens the user wants to deposit.
     */
    function joinLot(
        uint256 _lotId,
        string calldata _token,
        uint256 _size
    ) external nonReentrant whenNotPaused {
        Lot storage lot = _getLot(_lotId);
        address user = _msgSender();
        if(lot.isPrivate && !lot.invited[user]){
            revert NotInvitedToPrivateLot();
        }
        if(block.timestamp >= lot.startTimestamp){
            revert TooLateToJoinLot();
        }
        if(_size <= 0){
            revert SizeMustBePositive();
        }

        if (_compareStrings(_token, lot.tokenA)) {
            if(lot.userDepositPoolB[user] > 0){
                revert CannotJoinOnBothSides();
            }
            if(lot.isChallenge){
                revert CannotJoinLotAInChallenge();
            }
            _depositToPoolA(lot, user, _size);
        } else {
            if (bytes(lot.tokenB).length == 0) {
                if(!lot.tokenBChoices[_token] && !lot.isBasketOfAssets){
                    revert InvalidTokenID();
                }
                lot.tokenB = _token;
            }
            else {
                if(!_compareStrings(_token, lot.tokenB)){
                    revert InvalidTokenID();
                }
            }
            if(lot.userDepositPoolA[user] > 0){
                revert CannotJoinOnBothSides();
            }
            if(lot.isChallenge && lot.totalDepositPoolB > 0){
                revert MultipleUsersNotAllowedInChallenge();
            }
            if(lot.isChallenge && lot.totalDepositPoolA != _size){
                revert LotSizeMustBeEqual();
            }
            _depositToPoolB(lot, user, _size);
        }

        emit LotJoined(_lotId, _token, user, _size);
    }

    /**
     * @notice Resolves a lot by retrieving historical prices and calculating the result.
     *
     * @param _lotId The ID of the lot to be resolved.
     */
    function resolveLot(uint256 _lotId) external nonReentrant whenNotPaused {
        Lot storage lot = _getLot(_lotId);

        if(lot.resolved){
            revert LotAlreadyResolved();
        }

        _resolveLot(_lotId, lot);
    }

    /**
     * @notice Get information about a lot. Reverts if no lot exists with the given ID.
     *
     * @param _lotId The ID of the lot to get information about.
     */
    function getLot(
        uint256 _lotId
    ) external view returns (LotData memory) {
        Lot storage lot = _getLot(_lotId);
        return LotData({
            tokenA: lot.tokenA,
            collateralToken: lot.collateralToken,
            startTimestamp: lot.startTimestamp,
            duration: lot.duration,
            creator: lot.creator,
            isPrivate: lot.isPrivate,
            isChallenge: lot.isChallenge,
            isBasketOfAssets: lot.isBasketOfAssets,
            tokenB: lot.tokenB,
            totalDepositPoolA: lot.totalDepositPoolA,
            totalDepositPoolB: lot.totalDepositPoolB,
            resolved: lot.resolved,
            totalClaimPoolA: lot.totalClaimPoolA,
            totalClaimPoolB: lot.totalClaimPoolB
        });
    }

    /**
     * @notice Check if a lot accepts a certain token as tokenB.
     *
     * @param _lotId The ID of the lot to get information about.
     * @param _tokenB The The dentifier of the token to check for acceptance as tokenB.
     */
    function isAllowedTokenBChoice(
        uint256 _lotId,
        string calldata _tokenB
    ) external view returns (bool) {
        Lot storage lot = _getLot(_lotId);
        return lot.tokenBChoices[_tokenB];
    }

    /**
     * @notice Get the deposits made by a specific user for a given lot.
     *
     * @param _lotId The ID of the lot to retrieve deposit information for.
     * @param user The address of the user whose deposits are being queried.
     * @return (uint128, uint128) tuple containing two values: the user's
     *          deposits in pool A and pool B of the specified lot.
    */
    function getUserDeposits(
        uint256 _lotId,
        address user
    ) external view returns (uint128, uint128) {
        Lot storage lot = _getLot(_lotId);
        return (lot.userDepositPoolA[user], lot.userDepositPoolB[user]);
    }

    /**
    * @notice Check if a user is invited to participate in a specific lot.
    *
    * @param _lotId The ID of the lot to check for user invitation.
    * @param user The address of the user whose invitation status is being queried.
    * @return A boolean value indicating whether the user is invited to the specified lot.
    */
    function getIsInvited(
        uint256 _lotId,
        address user
    ) external view returns (bool) {
        Lot storage lot = _getLot(_lotId);
        return lot.invited[user];
    }

    /**
    * @notice Check if a user has withdrawn a refund for a specific lot.
    *
    * @param _lotId The ID of the lot to check for user refund status.
    * @param user The address of the user whose refund status is being queried.
    * @return A boolean value indicating whether the user has received a refund for the specified lot.
    */
    function getHasRefunded(
        uint256 _lotId,
        address user
    ) external view returns (bool) {
        Lot storage lot = _getLot(_lotId);
        return lot.refunded[user];
    }

    /**
    * @notice Check if a user has claimed rewards for a specific lot.
    *
    * @param _lotId The ID of the lot to check for user reward claiming status.
    * @param user The address of the user whose reward claiming status is being queried.
    * @return A boolean value indicating whether the user has claimed rewards for the specified lot.
    */
    function getHasClaimed(
        uint256 _lotId,
        address user
    ) external view returns (bool) {
        Lot storage lot = _getLot(_lotId);
        return lot.claimed[user];
    }

    // ===================== Public Functions ===================== //

    /**
    * @notice Prevents renouncing ownership.
    *
    * This function is designed to prevent the renouncement of ownership.
    * Ownership changes should be handled carefully and in accordance with
    * the contract's governance rules.
    * Renouncing ownership is disabled for enhanced security.
    */
    function renounceOwnership() public view override onlyOwner {
        revert("renounceOwnership is disabled");
    }

    /**
    * @notice Check if a lot with the given ID exists.
    *
    * @param _lotId The ID of the lot to check for existence.
    * @return A boolean value indicating whether a lot with the specified ID exists.
    */
    function exists(uint256 _lotId) public view returns (bool) {
        return _lotId != 0 && _lotId <= lastLotId;
    }

    // ===================== Internal Functions ===================== //

    /**
    * @notice Resolve the outcome of a lot and determines user rewards.
    *
    * @dev This internal function calculates the outcome of a lot based on historical price data.
    * It determines the winning token and determines user rewards accordingly.
    *
    * @param _lotId The ID of the lot to be resolved.
    * @param lot The storage reference to the lot being resolved.
    */
    function _resolveLot(uint256 _lotId, Lot storage lot) internal {
        uint256 endTimestamp = lot.startTimestamp + lot.duration;
        if(block.timestamp < endTimestamp){
            revert TooEarly();
        }

        uint256 size = _getSize(lot);

        uint256 startPriceTokenA;
        uint256 startPriceTokenB;
        uint256 resolvePriceTokenA;
        uint256 resolvePriceTokenB;

        string memory winningToken;

        uint256 feeAmountPerSide = (size * feePercentage) / 100;

        if (!head2HeadOracle.isInvalid(lot.tokenA)) {
            startPriceTokenA = head2HeadOracle.getHistoricalPrice(lot.tokenA, lot.startTimestamp);
            resolvePriceTokenA = head2HeadOracle.getHistoricalPrice(lot.tokenA, endTimestamp);
        }
        if (!head2HeadOracle.isInvalid(lot.tokenB)) {
            startPriceTokenB = head2HeadOracle.getHistoricalPrice(lot.tokenB, lot.startTimestamp);
            resolvePriceTokenB = head2HeadOracle.getHistoricalPrice(lot.tokenB, endTimestamp);
        }

        uint256 d1 = resolvePriceTokenA * startPriceTokenB;
        uint256 d2 = resolvePriceTokenB * startPriceTokenA;

        // If token A is invalid or if token B had a greater increase in price...
        if (startPriceTokenA == 0 || d2 > d1) {
            lot.totalClaimPoolB = (2 * (size - feeAmountPerSide)).toUint128();
            winningToken = lot.tokenB;
        }
        // If token B is invalid or if token A had a greater increase in price...
        else if (startPriceTokenB == 0 || d1 > d2) {
            lot.totalClaimPoolA = (2 * (size - feeAmountPerSide)).toUint128();
            winningToken = lot.tokenA;
        }
        // Otherwise, in the case of a tie...
        else {
            uint128 claim = (size - feeAmountPerSide).toUint128();
            lot.totalClaimPoolA = claim;
            lot.totalClaimPoolB = claim;
        }

        // Accumulate protocol fee.
        totalFees[lot.collateralToken] += 2 * feeAmountPerSide;

        lot.resolved = true;

        emit LotResolved(
            _lotId,
            size,
            winningToken,
            startPriceTokenA,
            startPriceTokenB,
            resolvePriceTokenA,
            resolvePriceTokenB
        );
    }

    /**
    * @notice Deposit tokens into Pool A of a lot for a specific user.
    *
    * @dev This internal function handles the deposit of tokens from a user into Pool A of a lot.
    * It calculates the deposited size and updates the user's and the lot's deposit balances accordingly.
    *
    * @param _lot The storage reference to the lot where the deposit is made.
    * @param _user The address of the user making the deposit.
    * @param _size The amount of tokens to deposit into Pool A.
    */
    function _depositToPoolA(
        Lot storage _lot,
        address _user,
        uint256 _size
    ) internal {
        uint128 initialSize = IERC20(_lot.collateralToken).balanceOf(address(this)).toUint128();

        IERC20(_lot.collateralToken).safeTransferFrom(
            _user,
            address(this),
            _size
        );

        uint128 finalSize = IERC20(_lot.collateralToken).balanceOf(address(this)).toUint128();
        uint128 size = finalSize - initialSize;
        if(size <= 0){
            revert TransferError();
        }

        _lot.userDepositPoolA[_user] += size;
        _lot.totalDepositPoolA += size;
    }

    /**
    * @notice Deposit tokens into Pool B of a lot for a specific user.
    *
    * @dev This internal function handles the deposit of tokens from a user into Pool B of a lot.
    * It calculates the deposited size and updates the user's and the lot's deposit balances accordingly.
    *
    * @param _lot The storage reference to the lot where the deposit is made.
    * @param _user The address of the user making the deposit.
    * @param _size The amount of tokens to deposit into Pool B.
    */
    function _depositToPoolB(
        Lot storage _lot,
        address _user,
        uint256 _size
    ) internal {
        uint128 initialSize = IERC20(_lot.collateralToken).balanceOf(address(this)).toUint128();

        IERC20(_lot.collateralToken).safeTransferFrom(
            _user,
            address(this),
            _size
        );

        uint128 finalSize = IERC20(_lot.collateralToken).balanceOf(address(this)).toUint128();
        uint128 size = finalSize - initialSize;
        if(size <= 0){
            revert TransferError();
        }

        _lot.userDepositPoolB[_user] += size;
        _lot.totalDepositPoolB += size;
    }

    /**
    * @dev Get a storage pointer to a specific lot and ensure the lot exists, reverting if it doesn't.
    *
    * @param lotId The ID of the lot to retrieve a storage pointer to.
    * @return A reference to the storage location of the specified lot.
    */
    function _getLot(
        uint256 lotId
    )
        internal
        view
        returns (Lot storage)
    {
        if(!exists(lotId)){
            revert InvalidLotId();
        }

        return _lots[lotId];
    }

    /**
     * @dev Internal function to calculate the size of a lot.
     *
     * @param lot The reference to the Lot storage struct.
     *
     * @return size The size of the lot, which is the minimum value between `totalDepositPoolA`
     *              and `totalDepositPoolB`.
     */
    function _getSize(Lot storage lot) internal view returns (uint256) {
        return uint256(_min128(lot.totalDepositPoolA, lot.totalDepositPoolB));
    }

    /**
     * @dev Internal function to compare two strings for equality.
     *
     * @param a The first string to compare.
     * @param b The second string to compare.
     *
     * @return isEqual True if the strings are equal, false otherwise.
     */
    function _compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return bytes(a).length == bytes(b).length && keccak256(bytes(a)) == keccak256(bytes(b));
    }

    /**
     * @dev Internal function to find the minimum value between two uint128 numbers.
     *
     * @param x The first uint128 number.
     * @param y The second uint128 number.
     *
     * @return min The minimum value between `x` and `y`.
     */
    function _min128(uint128 x, uint128 y) internal pure returns (uint128) {
        return x > y ? y : x;
    }
}
