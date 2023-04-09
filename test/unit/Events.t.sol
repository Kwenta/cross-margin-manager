// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {Events} from "../../src/Events.sol";
import {Factory} from "../../src/Factory.sol";
import {IAccount} from "../../src/interfaces/IAccount.sol";
import {IEvents} from "../../src/interfaces/IEvents.sol";
import {Setup} from "../../script/Deploy.s.sol";
import "../utils/Constants.sol";

contract EventsTest is Test, ConsolidatedEvents {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    Events private events;
    Factory private factory;
    address private account;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        Setup setup = new Setup();

        (factory, events,) = setup.deploySystem({
            _owner: address(this),
            _addressResolver: ADDRESS_RESOLVER,
            _gelato: GELATO,
            _ops: OPS
        });

        account = factory.newAccount();
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_FactorySett() public {
        assertEq(events.factory(), address(factory));
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_EmitDeposit_Event() public {
        vm.expectEmit(true, true, true, true);
        emit Deposit(USER, ACCOUNT, AMOUNT);
        vm.prank(account);
        events.emitDeposit({user: USER, account: ACCOUNT, amount: AMOUNT});
    }

    function test_EmitDeposit_OnlyAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(IEvents.OnlyAccounts.selector));
        events.emitDeposit({user: USER, account: ACCOUNT, amount: AMOUNT});
    }

    function test_EmitWithdraw_Event() public {
        vm.expectEmit(true, true, true, true);
        emit Withdraw(USER, ACCOUNT, AMOUNT);
        vm.prank(account);
        events.emitWithdraw({user: USER, account: ACCOUNT, amount: AMOUNT});
    }

    function test_EmitWithdraw_OnlyAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(IEvents.OnlyAccounts.selector));
        events.emitWithdraw({user: USER, account: ACCOUNT, amount: AMOUNT});
    }

    function test_EmitEthWithdraw_Event() public {
        vm.expectEmit(true, true, true, true);
        emit EthWithdraw(USER, ACCOUNT, AMOUNT);
        vm.prank(account);
        events.emitEthWithdraw({user: USER, account: ACCOUNT, amount: AMOUNT});
    }

    function test_EmitEthWithdraw_OnlyAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(IEvents.OnlyAccounts.selector));
        events.emitEthWithdraw({user: USER, account: ACCOUNT, amount: AMOUNT});
    }

    function test_EmitConditionalOrderPlaced_Event() public {
        uint256 id = 0;
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderPlaced(
            ACCOUNT,
            id,
            sETHPERP,
            MARGIN_DELTA,
            SIZE_DELTA,
            TARGET_PRICE,
            IAccount.ConditionalOrderTypes.LIMIT,
            DESIRED_FILL_PRICE,
            true
        );
        vm.prank(account);
        events.emitConditionalOrderPlaced({
            account: ACCOUNT,
            conditionalOrderId: id,
            marketKey: sETHPERP,
            marginDelta: MARGIN_DELTA,
            sizeDelta: SIZE_DELTA,
            targetPrice: TARGET_PRICE,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: true
        });
    }

    function test_EmitConditionalOrderPlaced_OnlyAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(IEvents.OnlyAccounts.selector));
        events.emitConditionalOrderPlaced({
            account: ACCOUNT,
            conditionalOrderId: 0,
            marketKey: sETHPERP,
            marginDelta: MARGIN_DELTA,
            sizeDelta: SIZE_DELTA,
            targetPrice: TARGET_PRICE,
            conditionalOrderType: IAccount.ConditionalOrderTypes.LIMIT,
            desiredFillPrice: DESIRED_FILL_PRICE,
            reduceOnly: true
        });
    }

    function test_EmitConditionalOrderCancelled_Event() public {
        uint256 id = 0;
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderCancelled(
            ACCOUNT,
            id,
            IAccount
                .ConditionalOrderCancelledReason
                .CONDITIONAL_ORDER_CANCELLED_BY_USER
        );
        vm.prank(account);
        events.emitConditionalOrderCancelled({
            account: ACCOUNT,
            conditionalOrderId: id,
            reason: IAccount
                .ConditionalOrderCancelledReason
                .CONDITIONAL_ORDER_CANCELLED_BY_USER
        });
    }

    function test_EmitConditionalOrderCancelled_OnlyAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(IEvents.OnlyAccounts.selector));
        events.emitConditionalOrderCancelled({
            account: ACCOUNT,
            conditionalOrderId: 0,
            reason: IAccount
                .ConditionalOrderCancelledReason
                .CONDITIONAL_ORDER_CANCELLED_BY_USER
        });
    }

    function test_EmitConditionalOrderFilled_Event() public {
        vm.expectEmit(true, true, true, true);
        emit ConditionalOrderFilled(ACCOUNT, 0, FILL_PRICE, GELATO_FEE);
        vm.prank(account);
        events.emitConditionalOrderFilled({
            account: ACCOUNT,
            conditionalOrderId: 0,
            fillPrice: FILL_PRICE,
            keeperFee: GELATO_FEE
        });
    }

    function test_EmitConditionalOrderFilled_OnlyAccounts() public {
        vm.expectRevert(abi.encodeWithSelector(IEvents.OnlyAccounts.selector));
        events.emitConditionalOrderFilled({
            account: ACCOUNT,
            conditionalOrderId: 0,
            fillPrice: FILL_PRICE,
            keeperFee: GELATO_FEE
        });
    }
}
