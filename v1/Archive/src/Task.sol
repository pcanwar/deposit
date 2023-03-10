// SPDX-License-Identifier: UNLICENSED

/*
- User is able to:
     deposit a token, 
     withdraw a token, 
     emergency withdraw all tokens, 
     show list of his tokens with their balances
- Be able to 
    transfer his deposited tokens for another user on the portifolio smart contract
- Bonus: add support for EIP-2612 compliant tokens for single transaction deposits
*/

/*
    * I assume that only the owner is able to withdraw,
      so no one has a permission to withdraw it for him to the owner wallet...  
    * I think it is better to reset the set of the token addresses when a user withdraw all their tokens
     so in this code I just looped to remove them one by one. Not opt
*/

pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

interface ITask {
    function balances(address, address) external view returns (uint256);

    function deposit(address, uint256) external;

    function withdraw(address, uint256) external;

    function withdrawAll(address, uint256) external;
}

error UnrecognizedTokenAddress();
error FailedTransaction();

contract Task is Ownable {
    mapping(address => mapping(address => uint256)) private _balances;
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _set;

    event Deposit(
        address indexed tokenContractAdress,
        address indexed spender,
        uint256 _amount
    );

    event Withdraw(address indexed tokenContractAdress, uint256 _amount);
    event WithdrawAll(address[] indexed tokenContractAdress, uint256[] _amount);

    modifier zeroAddress(address _contract) {
        require(_contract != address(0), "The address is the zero address");
        _;
    }

    function add(address _address) private returns (bool) {
        return _set.add(_address);
    }

    function remove(address _address) private returns (bool) {
        return _set.remove(_address);
    }

    function getAll() public view returns (bytes32[] memory) {
        // not used for removed
        return _set._inner._values;
    }

    function contains(address _address) public view returns (bool) {
        return _set.contains(_address);
    }

    function length() public view returns (uint256) {
        return _set.length();
    }

    /**
     * - index is to a way to find the token address in a set
     *
     */
    function balanceAt(uint256 index) public view returns (uint256) {
        address tokenAddress = _set.at(index);
        require(contains(tokenAddress), "Invalid index");
        return _balances[_set.at(index)][owner()];
    }

    /**
     * - _address is the token address
     *
     */
    function balanceAt(address _address) public view returns (uint256) {
        require(_address != address(0), "Address zero is not a valid owner");
        return _balances[_address][owner()];
    }

    /*
      retrun the address of an index 
    */
    function at(uint256 index) public view returns (address) {
        address tokenAddress = _set.at(index);
        require(tokenAddress != address(0), "Invalid index");
        return tokenAddress;
    }

    /*
    return two lists one tokens address and
    sencond of their balances
    */
    function balanceOf()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        address _owner = owner();
        address[] memory res = new address[](_set.length());
        uint256[] memory bal = new uint256[](_set.length());

        for (uint256 i = 0; i < _set.length(); i++) {
            // address _add = at(i);
            res[i] = at(i);
            bal[i] = _balances[res[i]][_owner];
        }
        return (res, bal);
    }

    function deposit(
        address _tokenAdress,
        address spender,
        uint256 _amount
    ) external zeroAddress(_tokenAdress) zeroAddress(spender) returns (bool) {
        require(
            IERC20(_tokenAdress).allowance(spender, address(this)) >= _amount,
            "Insufficient Allowance"
        );
        address _owner = owner();
        require(_amount > 0, "amount needs to be greater than 0");
        bool isAdded = add(_tokenAdress);

        if (!isAdded) {
            // _balances[_tokenAdress][_owner] = _amount;
            _balances[_tokenAdress][_owner] += _amount;
        } else {
            _balances[_tokenAdress][_owner] = _amount;
        }

        bool res = IERC20(_tokenAdress).transferFrom(
            spender,
            address(this),
            _amount
        );
        if (!res) FailedTransaction;
        emit Deposit(_tokenAdress, spender, _amount);
        return res;
    }

    function withdraw(address _tokenAdress)
        external
        onlyOwner
        zeroAddress(_tokenAdress)
        returns (bool)
    {
        bool isContains = contains(_tokenAdress);
        if (!isContains) revert UnrecognizedTokenAddress();
        uint256 _amount = _balances[_tokenAdress][msg.sender];
        require(_amount > 0, "NO Balance"); // second layer check
        _balances[_tokenAdress][msg.sender] -= _amount;
        remove(_tokenAdress);
        bool res = IERC20(_tokenAdress).transfer(msg.sender, _amount);
        if (!res) FailedTransaction;
        emit Withdraw(_tokenAdress, _amount);
        return res;
    }

    function withdraw(address _tokenAdress, uint256 _amount)
        external
        onlyOwner
        zeroAddress(_tokenAdress)
        returns (bool)
    {
        uint256 bal = _balances[_tokenAdress][msg.sender];
        require(
            _amount > 0 && bal >= _amount,
            "Transfer amount exceeds balance"
        );
        bool isContains = contains(_tokenAdress);
        if (!isContains) revert UnrecognizedTokenAddress();
        _balances[_tokenAdress][msg.sender] -= _amount;
        if (_balances[_tokenAdress][msg.sender] == 0) {
            remove(_tokenAdress);
        }
        bool res = IERC20(_tokenAdress).transfer(msg.sender, _amount);
        if (!res) FailedTransaction;
        emit Withdraw(_tokenAdress, _amount);
        return res;
    }

    function withdrawAll() external onlyOwner returns (bool res) {
        address _owner = owner();
        address[] memory _tokenAddress = new address[](_set.length());
        uint256[] memory _amount = new uint256[](_set.length());
        uint256 len = length();
        uint256 i;
        if (len <= 0) {
            return false;
        }
        for (i = 0; i < len; ++i) {
            _tokenAddress[i] = at(i);
            _amount[i] = _balances[_tokenAddress[i]][_owner];
            _balances[_tokenAddress[i]][_owner] -= _amount[i];
            res = IERC20(_tokenAddress[i]).transfer(_owner, _amount[i]);
            if (!res) FailedTransaction;
        }
        // here the set can be rest or add a func to start over
        for (i = 0; i < len; ++i) {
            remove(_tokenAddress[i]);
        }
    }

    function deposits(
        address _tokenAdress,
        address _owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bool) {
        address owner = owner();
        require(value > 0, "amount needs to be greater than 0");
        IERC20Permit(_tokenAdress).permit(
            _owner,
            spender,
            value,
            deadline,
            v,
            r,
            s
        );
        bool isAdded = add(_tokenAdress);
        bool res = IERC20(_tokenAdress).transferFrom(
            owner,
            address(this),
            value
        );
        if (!res) FailedTransaction;
        if (!isAdded) {
            _balances[_tokenAdress][owner] += value;
        } else {
            _balances[_tokenAdress][owner] = value;
        }

        emit Deposit(_tokenAdress, owner, value);
        return res;
    }
}
