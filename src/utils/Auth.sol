// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/// @notice Authorization mixin for Smart Margin Accounts
/// @author JaredBorders (jaredborders@pm.me)
/// @dev This contract is intended to be inherited by the Account contract
abstract contract Auth {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice max BPS; used for decimals calculations
    uint256 public constant MAX_BPS = 10_000;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice owner of the account
    address public owner;

    /// @notice mapping of delegate address
    mapping(address delegate => bool) public delegates;

    /// @notice mapping of delegate addresses to fees they impose on trades
    mapping(address delegate => uint256 fee) public delegateFees;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when an unauthorized caller attempts
    /// to access a caller restricted function
    error Unauthorized();

    /// @notice thrown when the delegate address is invalid
    /// @param delegateAddress: address of the delegate attempting to be added
    error InvalidDelegateAddress(address delegateAddress);

    /// @notice thrown when the delegate fee is invalid
    /// @param delegateFee: fee the delegate charges for executing trades
    error InvalidDelegateFee(uint256 delegateFee);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice emitted after ownership transfer
    /// @param caller: previous owner
    /// @param newOwner: new owner
    event OwnershipTransferred(
        address indexed caller, address indexed newOwner
    );

    /// @notice emitted after a delegate is added
    /// @param caller: owner of the account
    /// @param delegate: address of the delegate being added
    event DelegatedAccountAdded(
        address indexed caller, address indexed delegate
    );

    /// @notice emitted after a delegate is removed
    /// @param caller: owner of the account
    /// @param delegate: address of the delegate being removed
    event DelegatedAccountRemoved(
        address indexed caller, address indexed delegate
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @dev sets owner to _owner and not msg.sender
    /// @param _owner The address of the owner
    constructor(address _owner) {
        owner = _owner;

        emit OwnershipTransferred(address(0), _owner);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @return true if the caller is the owner
    function isOwner() public view virtual returns (bool) {
        return (msg.sender == owner);
    }

    /// @return true if the caller is the owner or a delegate
    function isAuth() public view virtual returns (bool) {
        return (msg.sender == owner || delegates[msg.sender]);
    }

    /*//////////////////////////////////////////////////////////////
                                SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfer ownership of the account
    /// @dev only owner can transfer ownership (not delegates)
    /// @param _newOwner The address of the new owner
    function transferOwnership(address _newOwner) public virtual {
        if (!isOwner()) revert Unauthorized();

        owner = _newOwner;

        emit OwnershipTransferred(msg.sender, _newOwner);
    }

    /// @notice Add a delegate to the account
    /// @dev only owner can add a delegate (not delegates)
    /// @param _delegate The address of the delegate
    /// @param _delegateFee The fee the delegate charges for executing trades
    function addDelegate(address _delegate, uint256 _delegateFee)
        public
        virtual
    {
        if (!isOwner()) revert Unauthorized();

        if (_delegate == address(0) || delegates[_delegate]) {
            revert InvalidDelegateAddress(_delegate);
        }

        if (_delegateFee > MAX_BPS) {
            revert InvalidDelegateFee(_delegateFee);
        }

        delegates[_delegate] = true;
        delegateFees[_delegate] = _delegateFee;

        emit DelegatedAccountAdded({caller: msg.sender, delegate: _delegate});
    }

    /// @notice Remove a delegate from the account
    /// @dev only owner can remove a delegate (not delegates)
    /// @param _delegate The address of the delegate
    function removeDelegate(address _delegate) public virtual {
        if (!isOwner()) revert Unauthorized();

        if (_delegate == address(0) || !delegates[_delegate]) {
            revert InvalidDelegateAddress(_delegate);
        }

        delete delegates[_delegate];
        delete delegateFees[_delegate];

        emit DelegatedAccountRemoved({caller: msg.sender, delegate: _delegate});
    }
}
