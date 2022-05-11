// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MinimalProxyable is Ownable {

    bool masterCopy;
    bool initialized;

    constructor() {
        masterCopy = true;
    }

    function initialize() public initOnce {
        // Note the Ownable constructor is never when we create minimal proxies
        _transferOwnership(msg.sender);
    }

    modifier initOnce {
        require(!masterCopy, "Cannot initialize implementation");
        require(!initialized, "Already initialized");
        initialized = true;
        _;
    }

}