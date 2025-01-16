// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*
*@title DSCEngine
*@author Patrick Collins
*
*The system is designed to be as minimal as possible, and have the tokens *maintain a 1toekn ==$1 peg.
*This stablecoin has the propertise:
* - Exogenous Collateral
* - Dollar Pegged
* - Algorithmic Stable
*
*It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
*
*The ESC system should alwasys be "overcollateralized". At no point, should the value of all collateral <= the baback value of all the DSC.
*@notice This contract is core of the DSC System. It handles all the *logic for mining and redeeming DSC, as well as depositing & withdrawing *collateral.
*@notical This contract is VERY lossely based on the MakerDAO DSS (DAI) system.
*/

contract ESCEngine is ReentrancyGuard {
    ///////////////
    // Errors //
    //////////////
    error DSCEngine__NeedsMoreThanZero();
    error ESCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error ESCEngine__NotAllowedToekn();
    error ESCEngine__TransferFailed();

    /////////////////////
    // State Variables //
    ////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; //TokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; //UserToTokenToBDeposited

    DecentralizedStableCoin private i_dsc;

    /////////////////////
    // Events //////////
    ////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    ///////////////
    // Modifiers //
    //////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert ESCEngine__NotAllowedToekn();
        }
        _;
    }

    ///////////////
    // functions //
    //////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert ESCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////
    // External functions //
    ////////////////////////

    function depositCollateralAndMintDsc() external {}
    /*
    *@notice CEI
    *@param tokenCollateralAddress The address of thet token to deposit *as collateral
    *@param amountCollateral The amount of the token to deposit as *collateral
    */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert ESCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function reddemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
