// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";
import {Setup} from "script/Deploy.s.sol";
import {Account} from "src/Account.sol";
import {Events} from "src/Events.sol";
import {Factory} from "src/Factory.sol";
import {Settings} from "src/Settings.sol";
import {IAccount} from "src/interfaces/IAccount.sol";
import {IERC20} from "src/interfaces/token/IERC20.sol";
import {AccountExposed} from "test/utils/AccountExposed.sol";
import {ConsolidatedEvents} from "test/utils/ConsolidatedEvents.sol";
import {IAddressResolver} from "test/utils/interfaces/IAddressResolver.sol";
import {ISynth} from "test/utils/interfaces/ISynth.sol";
import {IFuturesMarketManager} from
    "src/interfaces/synthetix/IFuturesMarketManager.sol";
import {IPerpsV2MarketConsolidated} from "src/interfaces/IAccount.sol";
import {IPerpsV2ExchangeRate} from
    "src/interfaces/synthetix/IPerpsV2ExchangeRate.sol";

import {
    ADDRESS_RESOLVER,
    AMOUNT,
    BLOCK_NUMBER,
    DESIRED_FILL_PRICE,
    FUTURES_MARKET_MANAGER,
    GELATO,
    OPS,
    PERPS_V2_EXCHANGE_RATE,
    PROXY_SUSD,
    sETHPERP,
    SYSTEM_STATUS,
    UNISWAP_PERMIT2,
    UNISWAP_UNIVERSAL_ROUTER
} from "test/utils/Constants.sol";

contract OrderFlowFeeTest is Test, ConsolidatedEvents {
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // main contracts
    Factory private factory;
    Events private events;
    Account private account;
    Settings private settings;

    // helper contracts for testing
    IERC20 private sUSD;
    AccountExposed private accountExposed;

    // helper variables for testing
    uint256 private currentEthPriceInUSD;

    // constants
    uint256 private constant INITIAL_ORDER_FLOW_FEE = 5; // 0.005%

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        // define Setup contract used for deployments
        Setup setup = new Setup();

        // deploy system contracts
        (factory, events, settings,) = setup.deploySystem({
            _deployer: address(0),
            _owner: address(this),
            _addressResolver: ADDRESS_RESOLVER,
            _gelato: GELATO,
            _ops: OPS,
            _universalRouter: UNISWAP_UNIVERSAL_ROUTER,
            _permit2: UNISWAP_PERMIT2
        });

        // deploy an Account contract
        account = Account(payable(factory.newAccount()));

        // define helper contracts
        IAddressResolver addressResolver = IAddressResolver(ADDRESS_RESOLVER);
        sUSD = IERC20(addressResolver.getAddress(PROXY_SUSD));
        address futuresMarketManager =
            addressResolver.getAddress(FUTURES_MARKET_MANAGER);
        address systemStatus = addressResolver.getAddress(SYSTEM_STATUS);
        address perpsV2ExchangeRate =
            addressResolver.getAddress(PERPS_V2_EXCHANGE_RATE);

        // deploy AccountExposed contract for exposing internal account functions
        IAccount.AccountConstructorParams memory params = IAccount
            .AccountConstructorParams(
            address(factory),
            address(events),
            address(sUSD),
            perpsV2ExchangeRate,
            futuresMarketManager,
            systemStatus,
            GELATO,
            OPS,
            address(settings),
            UNISWAP_UNIVERSAL_ROUTER,
            UNISWAP_PERMIT2
        );
        accountExposed = new AccountExposed(params);

        // get current ETH price in USD
        (currentEthPriceInUSD,) = accountExposed.expose_sUSDRate(
            IPerpsV2MarketConsolidated(
                accountExposed.expose_getPerpsV2Market(sETHPERP)
            )
        );

        // call approve() on an ERC20 to grant an infinite allowance to the SM account contract
        sUSD.approve(address(account), type(uint256).max);

        // set the order flow fee to a non-zero value
        settings.setOrderFlowFee(INITIAL_ORDER_FLOW_FEE);

        fundAccount(AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// Verifies that Order Flow Fee is correctly calculated
    /// For this test, it is assumed that there is enough account margin to cover fee
    function test_calculateOrderFlowFee(uint256 fee) public {
        vm.assume(fee < settings.MAX_ORDER_FLOW_FEE());

        settings.setOrderFlowFee(fee);

        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Keep account margin to cover for orderFlowFee
        int256 marginDelta = int256(AMOUNT) / 5;
        int256 sizeDelta = 1 ether;

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);

        uint256 imposedOrderFlowFee =
            account.getExpectedOrderFlowFee(market, sizeDelta);

        // Current marketRate is 1880.505 sUSD per 1 ETH
        uint256 currentMarketRate = 1_880_505_000_000_000_000_000;

        if (fee == 0) {
            assertEq(imposedOrderFlowFee, 0);
        } else {
            // Size is 1 ETH, so fee should be the orderflowfee value of 1 ETH in sUSD
            uint256 orderFlowFeeMath = currentMarketRate
                * settings.orderFlowFee() / settings.MAX_ORDER_FLOW_FEE();
            assertEq(orderFlowFeeMath, imposedOrderFlowFee);
        }
    }

    /// Verifies that OrderFlowFee is correctly sent from account margin to treasury
    /// when there is enough funds in account margin to cover orderFlowFee
    function test_imposeOrderFlowFee_account_margin() public {
        uint256 treasuryPreBalance = sUSD.balanceOf(settings.TREASURY());

        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Keep account margin to cover for orderFlowFee
        int256 marginDelta = int256(AMOUNT) / 5;
        int256 sizeDelta = 1;

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);

        uint256 treasuryPostBalance = sUSD.balanceOf(settings.TREASURY());

        /// inital funding - sETHPERP margin = 8000 ether
        uint256 accountMarginBeforeFee = AMOUNT - uint256(marginDelta);

        uint256 imposedOrderFlowFee =
            account.getExpectedOrderFlowFee(market, sizeDelta);

        // Assert that fee was correctly sent from account margin
        assertEq(
            accountMarginBeforeFee - imposedOrderFlowFee, account.freeMargin()
        );
        // Assert that fee was correctly sent to treasury address
        assertEq(treasuryPostBalance - treasuryPreBalance, imposedOrderFlowFee);
    }

    /// Verifies that OrderFlowFee is correctly sent from account margin to treasury with a
    /// delayed order when there is enough funds in account margin to cover orderFlowFee
    function test_imposeOrderFlowFee_account_margin_delayed() public {
        uint256 treasuryPreBalance = sUSD.balanceOf(settings.TREASURY());

        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Keep account margin to cover for orderFlowFee
        int256 marginDelta = int256(AMOUNT) / 5;
        int256 sizeDelta = 34_500_000_000_000_000;
        uint256 desiredFillPrice = 3_787_625_873_186_525_010_951;
        uint256 desiredTimeDelta = 0;

        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_DELAYED_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] =
            abi.encode(market, sizeDelta, desiredTimeDelta, desiredFillPrice);
        account.execute(commands, inputs);

        uint256 treasuryPostBalance = sUSD.balanceOf(settings.TREASURY());

        /// inital funding - sETHPERP margin = 8000 ether
        uint256 accountMarginBeforeFee = AMOUNT - uint256(marginDelta);

        uint256 imposedOrderFlowFee =
            account.getExpectedOrderFlowFee(market, sizeDelta, desiredFillPrice);

        // Assert that fee was correctly sent from account margin
        assertEq(
            accountMarginBeforeFee - imposedOrderFlowFee, account.freeMargin()
        );
        // Assert that fee was correctly sent to treasury address
        assertEq(treasuryPostBalance - treasuryPreBalance, imposedOrderFlowFee);
    }

    /// Verifies that OrderFlowFee is correctly sent from market margin to treasury
    /// when there is no funds in account margin to cover orderFlowFee in account margin
    function test_imposeOrderFlowFee_market_margin() public {
        uint256 treasuryPreBalance = sUSD.balanceOf(settings.TREASURY());

        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Deposit all margin so that account has no margin to cover orderFlowFee
        int256 marginDelta = int256(AMOUNT);
        int256 sizeDelta = 1;

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);

        uint256 treasuryPostBalance = sUSD.balanceOf(settings.TREASURY());

        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition(sETHPERP);

        uint256 imposedOrderFlowFee =
            account.getExpectedOrderFlowFee(market, position.size);

        // Assert that fee was correctly sent from market margin
        assertEq(uint256(position.margin), AMOUNT - imposedOrderFlowFee - 563);
        // Assert that fee was correctly sent to treasury address
        assertEq(treasuryPostBalance - treasuryPreBalance, imposedOrderFlowFee);
    }

    /// Verifies that OrderFlowFee is correctly sent from market margin to treasury
    /// when there is no funds in account margin to cover orderFlowFee in account margin
    /// with a pending order to confirm locked margin is not used in this case
    function test_imposeOrderFlowFee_market_margin_with_pending_order()
        public
    {
        uint256 treasuryPreBalance = sUSD.balanceOf(settings.TREASURY());

        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        uint256 conditionalOrderMarginDelta = 10_000;
        uint256 conditionalOrdersizeDelta = 1;

        // Place a conditional order
        assertEq(account.committedMargin(), 0);

        placeConditionalOrder({
            marketKey: sETHPERP,
            marginDelta: int256(conditionalOrderMarginDelta),
            sizeDelta: int256(conditionalOrdersizeDelta),
            targetPrice: currentEthPriceInUSD,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: false
        });

        assertEq(account.committedMargin(), conditionalOrderMarginDelta);

        /// Deposit all remaining margin so that account has no margin to cover orderFlowFee
        int256 marginDelta =
            int256(AMOUNT) - int256(conditionalOrderMarginDelta);
        int256 sizeDelta = 1;

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);

        // Assert that locked account margin was not used to cover fee
        assertEq(account.committedMargin(), conditionalOrderMarginDelta);

        uint256 treasuryPostBalance = sUSD.balanceOf(settings.TREASURY());

        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition(sETHPERP);

        uint256 imposedOrderFlowFee =
            account.getExpectedOrderFlowFee(market, position.size);

        // Assert that fee was correctly sent from market margin
        assertEq(
            uint256(position.margin),
            uint256(marginDelta) - imposedOrderFlowFee - 563
        );
        // Assert that fee was correctly sent to treasury address
        assertEq(treasuryPostBalance - treasuryPreBalance, imposedOrderFlowFee);
    }

    /// Verifies that OrderFlowFee is correctly sent from both market margin and account margin
    /// when there is not enough funds to cover orderFlowFee in account margin
    function test_imposeOrderFlowFee_both_margin() public {
        uint256 treasuryPreBalance = sUSD.balanceOf(settings.TREASURY());

        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// orderFlowFee is 94025250000000000 in the following configuration
        /// Leave 50000000000 in account (not enough to cover fees)
        int256 marginDelta = int256(AMOUNT) - 50_000_000_000;
        int256 sizeDelta = 1 ether;

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);

        uint256 treasuryPostBalance = sUSD.balanceOf(settings.TREASURY());

        IPerpsV2MarketConsolidated.Position memory position =
            account.getPosition(sETHPERP);

        uint256 imposedOrderFlowFee =
            account.getExpectedOrderFlowFee(market, sizeDelta);

        // Account margin is emptied
        assertEq(account.freeMargin(), 0);

        // Market margin is reduced by the missing amount to cover fee
        // uint256(marginDelta) - 563537402924844194061 is the effective position margin when there is no orderflowfee
        assertEq(
            uint256(position.margin),
            uint256(marginDelta) - 563_537_402_924_844_194_061
                - imposedOrderFlowFee + 50_000_000_000
        );

        // Assert that fee was correctly sent to treasury address
        assertEq(treasuryPostBalance - treasuryPreBalance, imposedOrderFlowFee);
    }

    /// Verifies that transaction reverts if there is insufficient margin to cover for orderFlowFee without exceeding positions limits
    /// @dev Synthetix makes transaction reverts if the resulting position is too large, outside the max leverage, or is liquidating.
    function test_imposeOrderFlowFee_market_margin_failed() public {
        // Set orderflow fee high to easily test that transaction fails if neither account or market has sufficient margin to cover for fees
        uint256 testOrderFlowFee = 50_000; // 50%
        settings.setOrderFlowFee(testOrderFlowFee);

        uint256 treasuryPreBalance = sUSD.balanceOf(settings.TREASURY());

        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Deposit all available account margin into market margin
        int256 marginDelta = int256(AMOUNT);
        int256 sizeDelta = 10 ether;

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        // Deposit market margin
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(market, marginDelta);
        account.execute(commands, inputs);

        // Execute Atomic Order
        IAccount.Command[] memory commandsAtomic = new IAccount.Command[](2);
        commandsAtomic[0] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputsAtomic = new bytes[](2);
        inputsAtomic[0] = abi.encode(market, sizeDelta, desiredFillPrice);

        // Current configuration should have insufficient margin to cover for orderflow fee and revert
        // because there is not enough margin for the position delta.
        vm.expectRevert("Insufficient margin");

        account.execute(commandsAtomic, inputsAtomic);

        uint256 treasuryPostBalance = sUSD.balanceOf(settings.TREASURY());

        // Assert that no overflowfee was distributed
        assertEq(treasuryPreBalance, treasuryPostBalance);
    }

    /// Verifies that transaction does not revert and charges a fee if there is sufficient margin to cover for orderFlowFee
    /// @dev Synthetix makes transaction reverts if the resulting position is too large, outside the max leverage, or is liquidating.
    function test_imposeOrderFlowFee_on_valid_close() public {
        uint256 treasuryPreBalance = sUSD.balanceOf(settings.TREASURY());

        /// @dev Ensures first trade doesn't charge a fee
        uint256 testOrderFlowFee = 0; // 0%
        settings.setOrderFlowFee(testOrderFlowFee);

        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Deposit all margin so that account has no margin to cover orderFlowFee
        int256 marginDelta = int256(AMOUNT); // 10_000 dollars
        int256 sizeDelta = 5 ether; // ~ Estimated notional $9,396.3052993
        // Leverage is .94x

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);

        // Margin after fees charged: ~ $7182.31

        // Set orderflow fee high to easily test that transaction fails if neither account or market has sufficient margin to cover for fees
        testOrderFlowFee = 10_000; // 10%
        settings.setOrderFlowFee(testOrderFlowFee);

        // Fee is 90% of notional = $936 fee
        // Margin would be 7182.31 - 936 = 6246.31
        // Remaining leverage is 1.5x
        // Resulting in valid fee charge

        // define close position order
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CLOSE_POSITION;
        bytes[] memory inputs = new bytes[](1);
        desiredFillPrice -= 1 ether;
        inputs[0] = abi.encode(market, desiredFillPrice);

        // close position
        account.execute(commands, inputs);

        // Assert position is closed
        IPerpsV2MarketConsolidated.Position memory position = 
            account.getPosition(sETHPERP);
        assertEq(0, position.size);

        uint256 treasuryPostBalance = sUSD.balanceOf(settings.TREASURY());

        // Assert treasury balance is now greater than before
        assertLt(treasuryPreBalance, treasuryPostBalance);
    }

    /// Verifies that transaction does not revert and does not charge a fee if Synthetix trade reverts (due to max leverage etc..)
    /// @dev Synthetix makes transaction reverts if the resulting position is too large, outside the max leverage, or is liquidating.
    function test_imposeOrderFlowFee_market_revert_bypass() public {
        uint256 treasuryPreBalance = sUSD.balanceOf(settings.TREASURY());

        /// @dev Ensures first trade doesn't charge a fee
        uint256 testOrderFlowFee = 0; // 0%
        settings.setOrderFlowFee(testOrderFlowFee);

        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Deposit all margin so that account has no margin to cover orderFlowFee
        int256 marginDelta = int256(AMOUNT); // 10_000 dollars
        int256 sizeDelta = 5 ether; // ~ Estimated notional $9,396.3052993
        // Leverage is .94x

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);

        // Margin after fees charged: ~ $7182.31

        // Set orderflow fee high to easily test that transaction fails if neither account or market has sufficient margin to cover for fees
        testOrderFlowFee = 75_000; // 75%
        settings.setOrderFlowFee(testOrderFlowFee);

        // Fee is 75% of notional = $7,047 fee
        // Margin would be $7182.31 - $7,047 = $135.31
        // Resulting in 69x leverage

        // define close position order
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERPS_V2_CLOSE_POSITION;
        bytes[] memory inputs = new bytes[](1);
        desiredFillPrice -= 1 ether;
        inputs[0] = abi.encode(market, desiredFillPrice);

        // close position
        account.execute(commands, inputs);

        // Assert position is closed
        IPerpsV2MarketConsolidated.Position memory position = 
            account.getPosition(sETHPERP);
        assertEq(0, position.size);

        uint256 treasuryPostBalance = sUSD.balanceOf(settings.TREASURY());

        // Assert that no overflowfee was distributed
        assertEq(treasuryPreBalance, treasuryPostBalance);
    }

    /// Verifies that the correct Event is emitted with correct fee value
    function test_imposeOrderFlowFee_event() public {
        // create a long position in the ETH market
        address market = getMarketAddressFromKey(sETHPERP);

        /// Keep account margin to cover for orderFlowFee
        int256 marginDelta = int256(AMOUNT) / 5;
        int256 sizeDelta = 1 ether;

        (uint256 desiredFillPrice,) =
            IPerpsV2MarketConsolidated(market).assetPrice();

        vm.expectEmit(true, true, true, true);
        // orderFlowFee is 94025250000000000 in this configuration
        emit OrderFlowFeeImposed(address(account), 94_025_250_000_000_000);

        submitAtomicOrder(sETHPERP, marginDelta, sizeDelta, desiredFillPrice);
    }

    // Verifies atomic order flow fee calculation across different scenarios
    function test_orderFlowFee(
        int256 marginDelta,
        int256 sizeDelta,
        uint256 desiredFillPrice
    ) public {
        // if margin delta is too big, expect revert
        // if size delta is too big, expect revert
        // if desired fill price is out of range, idk
        // if above assertions hold, then calculate order flow fee
        // assert that the order flow fee is correct
        // assert that the order flow fee is correctly deducted from the account margin
        // assert that the order flow fee is correctly sent to the treasury
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function mintSUSD(address to, uint256 amount) private {
        address issuer = IAddressResolver(ADDRESS_RESOLVER).getAddress("Issuer");
        ISynth synthsUSD =
            ISynth(IAddressResolver(ADDRESS_RESOLVER).getAddress("SynthsUSD"));
        vm.prank(issuer);
        synthsUSD.issue(to, amount);
    }

    function fundAccount(uint256 amount) private {
        vm.deal(address(account), 1 ether);
        mintSUSD(address(this), amount);
        modifyAccountMargin({amount: int256(amount)});
    }

    function getMarketAddressFromKey(bytes32 key)
        private
        view
        returns (address market)
    {
        market = address(
            IPerpsV2MarketConsolidated(
                IFuturesMarketManager(
                    IAddressResolver(ADDRESS_RESOLVER).getAddress(
                        "FuturesMarketManager"
                    )
                ).marketForKey(key)
            )
        );
    }

    function abs(int256 x) private pure returns (uint256 z) {
        assembly {
            let mask := sub(0, shr(255, x))
            z := xor(mask, add(mask, x))
        }
    }

    /*//////////////////////////////////////////////////////////////
                           COMMAND SHORTCUTS
    //////////////////////////////////////////////////////////////*/

    function modifyAccountMargin(int256 amount) private {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(amount);
        account.execute(commands, inputs);
    }

    function submitAtomicOrder(
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 desiredFillPrice
    ) private {
        address market = getMarketAddressFromKey(marketKey);
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
        commands[1] = IAccount.Command.PERPS_V2_SUBMIT_ATOMIC_ORDER;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(market, marginDelta);
        inputs[1] = abi.encode(market, sizeDelta, desiredFillPrice);
        account.execute(commands, inputs);
    }

    function placeConditionalOrder(
        bytes32 marketKey,
        int256 marginDelta,
        int256 sizeDelta,
        uint256 targetPrice,
        IAccount.ConditionalOrderTypes conditionalOrderType,
        uint256 desiredFillPrice,
        bool reduceOnly
    ) private returns (uint256 conditionalOrderId) {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.GELATO_PLACE_CONDITIONAL_ORDER;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            marketKey,
            marginDelta,
            sizeDelta,
            targetPrice,
            conditionalOrderType,
            desiredFillPrice,
            reduceOnly
        );
        account.execute(commands, inputs);
        conditionalOrderId = account.conditionalOrderId() - 1;
    }
}
