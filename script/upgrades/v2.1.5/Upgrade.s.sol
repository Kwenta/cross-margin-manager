// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Script} from "lib/forge-std/src/Script.sol";

import {IAddressResolver} from "script/utils/interfaces/IAddressResolver.sol";

import {Account} from "src/Account.sol";
import {Events} from "src/Events.sol";
import {Settings} from "src/Settings.sol";
import {IAccount} from "src/interfaces/IAccount.sol";

import {
    OPTIMISM_GELATO,
    OPTIMISM_OPS,
    FUTURES_MARKET_MANAGER,
    OPTIMISM_FACTORY,
    OPTIMISM_SYNTHETIX_ADDRESS_RESOLVER,
    OPTIMISM_UNISWAP_PERMIT2,
    OPTIMISM_UNISWAP_UNIVERSAL_ROUTER,
    OPTIMISM_SETTINGS,
    OPTIMISM_EVENTS,
    PERPS_V2_EXCHANGE_RATE,
    PROXY_SUSD,
    SYSTEM_STATUS,
    OPTIMISM_PDAO,
    OPTIMISM_DEPLOYER,
    OPTIMISM_USDC,
    OPTIMISM_DAI,
    OPTIMISM_USDT,
    OPTIMISM_LUSD
} from "script/utils/parameters/OptimismParameters.sol";

import {
    OPTIMISM_SEPOLIA_DEPLOYER,
    OPTIMISM_SEPOLIA_SYNTHETIX_ADDRESS_RESOLVER,
    OPTIMISM_SEPOLIA_GELATO,
    OPTIMISM_SEPOLIA_OPS,
    OPTIMISM_SEPOLIA_FACTORY,
    OPTIMISM_SEPOLIA_UNISWAP_UNIVERSAL_ROUTER,
    OPTIMISM_SEPOLIA_UNISWAP_PERMIT2
} from "script/utils/parameters/OptimismSepoliaParameters.sol";

/// @title Script to upgrade the Account implementation v2.1.4 -> v2.1.5
/// @author JaredBorders (jaredborders@pm.me)

/// @dev steps to deploy and verify on Optimism:
/// (1) load the variables in the .env file via `source .env`
/// (2) run `forge script script/upgrades/v2.1.5/Upgrade.s.sol:UpgradeAccountOptimism --rpc-url $ARCHIVE_NODE_URL_L2 --broadcast --verify -vvvv`
/// (3) Smart Margin Account Factory owner (i.e. Kwenta pDAO) will need to call `upgradeAccountImplementation` on the Factory with the address of the new Account implementation
contract UpgradeAccountOptimism is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        upgrade();

        vm.stopBroadcast();
    }

    function upgrade() public returns (address implementation) {
        IAddressResolver addressResolver =
            IAddressResolver(OPTIMISM_SYNTHETIX_ADDRESS_RESOLVER);

        address marginAsset = addressResolver.getAddress({name: PROXY_SUSD});
        address perpsV2ExchangeRate =
            addressResolver.getAddress({name: PERPS_V2_EXCHANGE_RATE});
        address futuresMarketManager =
            addressResolver.getAddress({name: FUTURES_MARKET_MANAGER});
        address systemStatus = addressResolver.getAddress({name: SYSTEM_STATUS});

        IAccount.AccountConstructorParams memory params = IAccount
            .AccountConstructorParams({
            factory: OPTIMISM_FACTORY,
            events: OPTIMISM_EVENTS,
            marginAsset: marginAsset,
            perpsV2ExchangeRate: perpsV2ExchangeRate,
            futuresMarketManager: futuresMarketManager,
            systemStatus: systemStatus,
            gelato: OPTIMISM_GELATO,
            ops: OPTIMISM_OPS,
            settings: OPTIMISM_SETTINGS,
            universalRouter: OPTIMISM_UNISWAP_UNIVERSAL_ROUTER,
            permit2: OPTIMISM_UNISWAP_PERMIT2
        });

        implementation = address(new Account(params));
    }
}
