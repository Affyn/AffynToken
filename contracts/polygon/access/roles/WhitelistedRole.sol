pragma solidity ^0.5.0;

import "../../GSN/Context.sol";
import "../Roles.sol";
import "./WhitelistAdminRole.sol";

/**
 * @title WhitelistedRole
 * @dev Whitelisted accounts have been approved by a WhitelistAdmin to perform certain actions (e.g. participate in a
 * crowdsale). This role is special in that the only accounts that can add it are WhitelistAdmins (who can also remove
 * it), and not Whitelisteds themselves.
 */
contract WhitelistedRole is Context, WhitelistAdminRole {
    using Roles for Roles.Role;

    event WhitelistedAdded(address indexed account);
    event WhitelistedRemoved(address indexed account);

    Roles.Role private _whitelisteds;

    modifier onlyWhitelisted() {
        require(isWhitelisted(_msgSender()), "WhitelistedRole: caller does not have the Whitelisted role");
        _;
    }

    function isWhitelisted(address account) public view returns (bool) {
        return _whitelisteds.has(account);
    }

    function addWhitelisted(address account) public onlyWhitelistAdmin {
        _addWhitelisted(account);
    }

    function removeWhitelisted(address account) public onlyWhitelistAdmin {
        _removeWhitelisted(account);
    }

    function renounceWhitelisted() public {
        _removeWhitelisted(_msgSender());
    }

    function _addWhitelisted(address account) internal {
        _whitelisteds.add(account);
        emit WhitelistedAdded(account);
    }

    function _removeWhitelisted(address account) internal {
        _whitelisteds.remove(account);
        emit WhitelistedRemoved(account);
    }
}

contract PrebuyerRole is Context, WhitelistAdminRole {
    using Roles for Roles.Role;

    event PrebuyerAdded(address indexed account);
    event PrebuyerRemoved(address indexed account);

    Roles.Role private _Prebuyers;

    modifier onlyPrebuyer() {
        require(isPrebuyer(_msgSender()), "PrebuyerRole: caller does not have the Prebuyer role");
        _;
    }

    function isPrebuyer(address account) public view returns (bool) {
        return _Prebuyers.has(account);
    }

    function addPrebuyer(address account) public onlyWhitelistAdmin {
        _addPrebuyer(account);
    }

    function removePrebuyer(address account) public onlyWhitelistAdmin {
        _removePrebuyer(account);
    }

    function renouncePrebuyer() public {
        _removePrebuyer(_msgSender());
    }

    function _addPrebuyer(address account) internal {
        _Prebuyers.add(account);
        emit PrebuyerAdded(account);
    }

    function _removePrebuyer(address account) internal {
        _Prebuyers.remove(account);
        emit PrebuyerRemoved(account);
    }
}