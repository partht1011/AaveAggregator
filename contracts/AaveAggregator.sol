// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Importing necessary OpenZeppelin contracts and Aave interfaces
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";

contract AaveAggregator {
	using SafeERC20 for IERC20;

	// State variables
	IPool public immutable aavePool; // Aave lending pool interface
	IERC20 public immutable dai; // DAI token interface

	uint256 public totalShare = 0; // Total shares of all users
	mapping(address => uint256) public userShare; // Shares per user

	/**
	 * @dev Constructor to initialize the Aave pool and DAI token.
	 * @param _aavePool Address of the Aave lending pool.
	 * @param _dai Address of the DAI token contract.
	 */
	constructor(IPool _aavePool, IERC20 _dai) {
		aavePool = _aavePool;
		dai = _dai;
	}

	/**
	 * @dev Deposit DAI into the Aave pool and mint shares for the user.
	 * @param amount The amount of DAI to deposit.
	 * @notice The caller must approve the contract to spend DAI before calling this function.
	 */
	function deposit(uint256 amount) external {
		require(amount > 0, "Invalid deposit amount");

		uint256 prevBalance = _balanceOf(); // Get previous aToken balance

		// Transfer DAI from the user to the contract
		dai.safeTransferFrom(msg.sender, address(this), amount);
		dai.approve(address(aavePool), amount); // Approve Aave to spend DAI

		// Supply DAI to the Aave pool
		aavePool.supply(address(dai), amount, address(this), 0);

		uint256 supplyAmount = _balanceOf() - prevBalance;

		// Calculate the user's share based on their contribution
		uint256 share = (totalShare == 0)
			? supplyAmount
			: (totalShare * supplyAmount) / prevBalance;

		// Update user's shares and total shares
		userShare[msg.sender] += share;
		totalShare += share;
	}
	/**
	 * @dev Withdraw a specified amount of shares from the user's balance.
	 * @param share The amount of shares to withdraw.
	 */
	function withdraw(uint256 share) external {
		_withdraw(share);
	}

	/**
	 * @dev Withdraw all shares from the user's balance.
	 */
	function withdrawAll() external {
		_withdraw(userShare[msg.sender]);
	}

	/**
	 * @notice Get the amount of share of user
	 * @param user The address of the user to get the amount of shares
	 * @return The amount of share of the give user.
	 */
	function getShare(address user) external view returns (uint256) {
		return userShare[user];
	}

	/**
	 * @dev Get the amount of DAI corresponding to a given share.
	 * @param share The number of shares to convert to DAI.
	 * @return The amount of DAI equivalent to the given shares.
	 */

	function getAmount(uint256 share) public view returns (uint256) {
		return (_balanceOf() * share) / totalShare; // Proportional amount based on shares
	}

	/**
	 * @dev Internal function to get the total balance of aTokens held by this contract.
	 * @return The balance of aTokens for the DAI reserve.
	 */
	function _balanceOf() internal view returns (uint256) {
		address aDaiAddress = aavePool
			.getReserveData(address(dai))
			.aTokenAddress; // Get aToken address
		return IERC20(aDaiAddress).balanceOf(address(this)); // Return balance of aTokens
	}

	/**
	 * @dev Internal function to handle the withdrawal of a specified amount of shares.
	 * @param share The amount of shares to withdraw.
	 */
	function _withdraw(uint256 share) internal {
		require(share > 0, "Nothing to withdraw");
		require(
			share <= userShare[msg.sender],
			"Withdraw amount exceeds balance"
		);

		uint256 amount = getAmount(share); // Get the amount of DAI to withdraw

		// Withdraw the underlying asset (DAI) from Aave
		dai.approve(msg.sender, amount);
		aavePool.withdraw(address(dai), amount, msg.sender);

		// Update user's shares and total shares
		userShare[msg.sender] -= share;
		totalShare -= share;
	}
}
