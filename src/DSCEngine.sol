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
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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

contract DSCEngine is ReentrancyGuard {
    ///////////////
    // Errors //
    //////////////
    error DSCEngine__NeedsMoreThanZero();
    error ESCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error ESCEngine__NotAllowedToekn();
    error ESCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 heatlthFactor);
    error ESCEngine__MintferFailed();

    /////////////////////
    // State Variables //
    ////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; //TokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited; //UserToTokenToBDeposited
    mapping(address user => uint256) private s_DscMinted; //UserToDscMinted
    address[] private s_collateralTokens;

    DecentralizedStableCoin private i_dsc;

    /////////////////////
    // Events //////////
    ////////////////////

    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event CollateralRedeemd(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

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
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddress,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert ESCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////
    // External functions //
    ////////////////////////

    /*
    *@param tokenCollateralAddress The address of thet token to deposit *as collateral
    *@param amountCollateral The amount of the token to deposit as *collateral
    *param amountDscToMint The amount of decentralized stablecoint to mint
    *@notice this function will deposit your collateral and mint you *DSC in one transaction
    */

    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }
    /*
     *@notice CEI
     *@param tokenCollateralAddress The address of thet token to deposit *as collateral
     *@param amountCollateral The amount of the token to deposit as *collateral
     */

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert ESCEngine__TransferFailed();
        }
    }
    /*
    *@param tokenCollateralAddress The collateral address to redeem
    *@param amountCollateral The amount of collateral to redeem
    *@param amountDscToBurn The amount of dsc to burn
    *This function burns DSC and redeems collateral in one transaction
    */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //redeemCollateral has checked the health factor
    }
    //In order to redeem collateral
    //1. health factor must be above 1 AFTER collateral pulled out
    //DRY: Don't repeat yourself.
    //Follow CET: Checks, Effects, Interactions

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemd(msg.sender,, amountCollateral, tokenCollateralAddress);
        bool success = IERC20(tokenCollateralAddress).transfer(
            msg.sender,
            amountCollateral
        );
        if (!success) {
            revert ESCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     *@notice follows CEI
     *@param amountDscToMint The amount of decentralized stablecoint to min
     *@notice they must have more collateral value than the minium threshold
     *
     */

    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        // if they minted too much?
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert ESCEngine__MintferFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount){
        s_DscMinted[msg.sender] -= amount;
        bool success = i_dsc.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert ESCEngine__MintferFailed();
        }
        //This conditional is hypothitically unreachable
        if (!success) {
            revert ESCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
        _revertIfHealthFactorIsBroken(msg.sender); //bakcup, this should not be triggered.
    }

    function liquidate() external {}

    function getHealthFactor() external view {}

    /////////////////////////////////////////
    // Private and Internal view functions //
    ////////////////////////////////////////

    function _getAccountInformation(
        address user
    )
        internal
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */

    function _heatlthFactor(address user) internal view returns (uint256) {
        // calculate the health factor
        (uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        uint256 collateralAdjustedThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedThreshold * PRECISION) / totalDscMinted;
        //return (collateralValueInUsd / totalDscMinted); 
    }
    // if the health factor <1, revert
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _heatlthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /////////////////////////////////////////
    // Public and External view functions //
    ////////////////////////////////////////
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        //loop through all the collateral tokens and get the value of the collateral, and map it to the price, to get USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; //value from chainlink is 1000*10^8, so we need to multiply by 10^10 to get the correct value, assuming ETH = 1000 USD
    }
}
