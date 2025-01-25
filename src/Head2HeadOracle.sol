// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";

import { IHead2HeadOracle } from "./IHead2HeadOracle.sol";

/**
 * @title Head2HeadOracle
 */
contract Head2HeadOracle is IHead2HeadOracle, AccessControl {

    // ===================== Custom Errors ===================== //
    error EmptyTokenIdsArray();
    error UnevenArrays();
    error InvalidTimestamp();
    error CannotRewritePrices();
    error CannotWriteZeroPrice();
    error PriceNotAvailable();

    event Stored(
        uint256 timestamp,
        string[] tokenIds,
        uint256[] prices
    );

    event SetInvalidity(
        string[] tokenIds,
        bool invalid
    );

    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    uint256 private constant _TIME_ACCURACY = 60;

    mapping(string => mapping(uint256 => uint256)) public price;

    mapping(string => bool) public invalid;

    /**
     * @notice Initializes the contract by setting up the access control and assigning the
     *         default admin role to the message sender.
     */
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /**
     * @notice Stores prices in the contract. This function is exclusively callable by the
     *         designated oracle script with the ORACLE_ROLE.
     * @param _timestamp The timestamp associated with the prices being stored.
     * @param _tokenIds An array of token identifiers corresponding to the prices being stored.
     * @param _prices An array of prices to be stored.
     * @dev The lengths of the _tokenIds and _prices arrays must be equal.
     * @dev The _timestamp is rounded to the nearest minute before storing the prices.
     */
    function store(
        uint256 _timestamp,
        string[] calldata _tokenIds,
        uint256[] calldata _prices
    ) external onlyRole(ORACLE_ROLE) {
        if(block.timestamp < _timestamp){
            revert InvalidTimestamp();
        }
        if(_tokenIds.length != _prices.length){
            revert UnevenArrays();
        }
        if(_tokenIds.length <= 0){
            revert EmptyTokenIdsArray();
        }

        uint256 nearestMinuteTimestamp = _getNearestMinuteTimestamp(_timestamp);

        for (uint256 i; i < _tokenIds.length; i++) {
            if(_prices[i] == 0){
                revert CannotWriteZeroPrice();
            }
            if(price[_tokenIds[i]][nearestMinuteTimestamp] != 0){
                revert CannotRewritePrices();
            }

            price[_tokenIds[i]][nearestMinuteTimestamp] = _prices[i];
        }

        emit Stored(_timestamp, _tokenIds, _prices);
    }

    /**
     * @notice Sets a token id as invalid or valid. This function is exclusively callable by the
     *         designated oracle script with the ORACLE_ROLE.
     * @param _tokenIds array of token ids.
     * @param _isInvalid bool representing validity of the token string.
     */
    function setInvalid(
        string[] calldata _tokenIds,
        bool _isInvalid
    ) external onlyRole(ORACLE_ROLE) {
        if(_tokenIds.length <= 0){
            revert EmptyTokenIdsArray();
        }

        for (uint256 i; i < _tokenIds.length; i++) {
            invalid[_tokenIds[i]] = _isInvalid;
        }

        emit SetInvalidity(_tokenIds, _isInvalid);
    }

    /**
     * @notice Retrieves the current price of a token.
     * @param _tokenId The identifier of the token for which the price is being retrieved.
     * @return the current price of the specified token.
     * @dev This function calls the getHistoricalPrice function with the current block timestamp.
     */
    function getPrice(string calldata _tokenId) external view returns (uint256) {
        return getHistoricalPrice(_tokenId, block.timestamp);
    }

    /**
     * @notice Retrieves the validity of a token id.
     * @param _tokenId The token id.
     */
    function isInvalid(string calldata _tokenId) external view returns (bool) {
        return invalid[_tokenId];
    }

    /**
    * @notice Prevents renouncing ownership.
    *
    * This function is designed to prevent the renouncement of ownership.
    * Ownership changes should be handled carefully and in accordance with
    * the contract's governance rules.
    * Renouncing ownership is disabled for enhanced security.
    */
    function renounceRole(bytes32 role, address account) public pure override {
        revert("renounceRole is disabled");
    }

    /**
     * @notice Retrieves the historical price of a token at a specific timestamp.
     * @param _tokenId The identifier of the token for which the price is being retrieved.
     * @param _timestamp The timestamp for which the historical price is being retrieved.
     * @return The historical price of the specified token at the given timestamp.
     * @dev The _timestamp is rounded down to the nearest minute to match the stored price timestamps.
     * @dev If no recent price is available within the query limit, the function reverts with an error message.
     */
    function getHistoricalPrice(
        string calldata _tokenId,
        uint256 _timestamp
    ) public view returns (uint256) {
        uint256 nearestMinuteTimestamp = _getNearestMinuteTimestamp(_timestamp);
        uint256 result = price[_tokenId][nearestMinuteTimestamp];

        if(result == 0){
            revert PriceNotAvailable();
        }

        return result;
    }

    /**
     * @notice Returns the nearest minute timestamp less than or equal to the provided timestamp.
     * @dev The function calculates the nearest minute timestamp by subtracting the remainder
     *      of the division between the provided timestamp and the _TIME_ACCURACY constant from
     *      the timestamp. This ensures that the returned timestamp aligns with the accuracy
     *      defined by _TIME_ACCURACY.
     *
     * @param _timestamp The timestamp for which the nearest minute timestamp is calculated.
     *
     * @return The nearest minute timestamp less than or equal to the provided timestamp.
     */
    function _getNearestMinuteTimestamp(uint256 _timestamp) internal pure returns (uint256) {
        return _timestamp - (_timestamp % _TIME_ACCURACY);
    }
}
