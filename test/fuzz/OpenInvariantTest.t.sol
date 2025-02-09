// Have our invariant aka properties always hold
//Our invariants
//1. The total supply of DSC should be less than the total value of collateral
//2. Getter view funcions should nerver revert <- evergreen invariant

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelpConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,,weth,wbtc,) = config.activeNetworkConfig();
        targetContract(address(dsce));
    }

    function invariant_protocalMustHaveMoreValueThanTotalSupply() public view {
        //get the value of all the collateral in the protocol
        //compare it to all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getAmountFromUsd(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getAmountFromUsd(wbtc, totalBtcDeposited);

        console.log("WETH Value:", wethValue);
        console.log("BTC Value:", wbtcValue);
        console.log("Total Supply:", totalSupply);

        assert(totalSupply <= (wethValue + wbtcValue));
    }
}