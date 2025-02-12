//SPDX-License-Identifier: MIT
// Handler is  going to narrow down he way we call function
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timeMintIsCalled;
    address[] public userWithCollateralDeposited;

    uint256 MAX_DEPOSITE_SIZE = type(uint96).max; //max of uint96 value

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    //call redeemCollateral when user has collateral

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSITE_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        //console.log("Deposit Collateral:", amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // there will be double push, but leave it as it now
        userWithCollateralDeposited.push(msg.sender);
    }

    // function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
    //     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    //     uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(msg.sender, address(collateral));

    //     amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
    //     if (amountCollateral == 0) {
    //         return;
    //     }
    //     vm.prank(msg.sender);
    //     dsce.redeemCollateral(address(collateral), amountCollateral);
    //     vm.stopPrank();
    // }

    //Deepseek version of redeemCollateral()
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        // 获取用户账户信息
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dsce.getAccountInformation(msg.sender);
        uint256 collateralAmount = dsce.getAmountFromUsd(collateral, totalCollateralValueInUsd);

        // 计算用户当前抵押品的价值
        uint256 userCollateralValue = dsce.getAccountCollateralValue(msg.sender);

        uint256 maxRedeemableValue;
        if (totalDscMinted == 0) {
            maxRedeemableValue = userCollateralValue; // 无债务可全额赎回
        } else {
            // 计算允许赎回的最大总价值
            maxRedeemableValue =
                totalCollateralValueInUsd / 2 > totalDscMinted ? totalCollateralValueInUsd / 2 - totalDscMinted : 0;
            // 不能超过当前抵押品的价值
            //maxRedeemableValue = min(maxRedeemableValue, userCollateralValue);
        }

        // 转换为抵押品数量
        uint256 maxRedeemableAmount;
        if (collateralAmount == 0) {
            maxRedeemableAmount = 0;
        } else {
            maxRedeemableAmount = (maxRedeemableValue * (10 ** collateralDecimals)) / collateralPrice;
        }

        // 确保不超过用户当前余额
        maxRedeemableAmount = min(maxRedeemableAmount, userCollateralBalance);
        amountCollateral = bound(amountCollateral, 0, maxRedeemableAmount);

        if (amountCollateral == 0) return;

        vm.startPrank(msg.sender);
        dsce.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(uint256 amountDscToMint, uint256 addressSeed) public {
        //amountDscToMint = bound(amountDscToMint, 1, MAX_DEPOSITE_SIZE);
        if (userWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = userWithCollateralDeposited[addressSeed % userWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }
        amountDscToMint = bound(amountDscToMint, 0, uint256(maxDscToMint));
        if (amountDscToMint == 0) {
            return;
        }
        vm.prank(sender);
        dsce.mintDsc(amountDscToMint);
        vm.stopPrank();
        timeMintIsCalled++;
    }

    //Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
