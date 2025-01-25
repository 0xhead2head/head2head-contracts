// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

interface IHead2HeadOracle {
    function getHistoricalPrice(
        string calldata _token,
        uint256 queryTimestamp
    ) external view returns (uint256);

    function getPrice(string calldata _token) external view returns (uint256);

    function isInvalid(string calldata _token) external view returns (bool);
}
