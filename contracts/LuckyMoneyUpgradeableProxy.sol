// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./proxy/TransparentUpgradeableProxy.sol";
import "./proxy/ProxyAdmin.sol";

contract LuckyMoneyUpgradeableProxy is TransparentUpgradeableProxy {

    constructor(address logic, address admin, bytes memory data) TransparentUpgradeableProxy(logic, admin, data) public {

    }

}
