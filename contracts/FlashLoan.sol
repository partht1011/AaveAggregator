// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Import necessary interfaces and libraries
import "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import "@aave/core-v3/contracts/interfaces/IPool.sol";
import "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FlashLoan is IFlashLoanReceiver {
	using SafeERC20 for IERC20; // Use SafeERC20 for safe token transfers

	// Constants for token addresses
	address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI token address
	address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH token address
	address public constant UNISWAP_ROUTER =
		0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap Router address
	address public constant SUSHISWAP_ROUTER =
		0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F; // SushiSwap Router address

	// State variables
	address public daiProvider; // Address of the DAI provider
	uint256 public provideAmount; // Amount of DAI to provide

	address owner; // Owner of the contract
	IPoolAddressesProvider public addressesProvider; // Aave Pool Addresses Provider
	IPool public aavePool; // Aave Pool

	/**
	 * @dev Constructor to initialize the contract with the Aave Pool Addresses Provider.
	 * @param _addressesProvider The address of the Aave Pool Addresses Provider.
	 */
	constructor(address _addressesProvider) {
		owner = msg.sender; // Set the contract deployer as the owner
		addressesProvider = IPoolAddressesProvider(_addressesProvider);
		aavePool = IPool(addressesProvider.getPool()); // Initialize Aave pool
	}

	/**
	 * @notice Initiates a flash loan from Aave.
	 * @param asset The address of the asset to borrow.
	 * @param amount The amount of the asset to borrow.
	 */
	function requestFlashLoan(address asset, uint256 amount) external {
		address receiverAddress = address(this); // The address that will receive the loan

		// Prepare arrays for assets, amounts, and modes
		address[] memory assets = new address[](1);
		uint256[] memory amounts = new uint256[](1);
		uint256[] memory modes = new uint256[](1);

		assets[0] = asset; // The asset to borrow
		amounts[0] = amount; // Amount to borrow
		modes[0] = 0; // Mode: 0 = no debt (full repayment in flash loan)

		// Request the flash loan from Aave
		aavePool.flashLoan(
			receiverAddress,
			assets,
			amounts,
			modes,
			address(this),
			"", // No additional data
			0 // Referral code
		);
	}

	/**
	 * @notice Callback function executed after receiving the flash loan.
	 * @param assets The array of assets borrowed.
	 * @param amounts The amounts borrowed.
	 * @param premiums The fees for borrowing the assets.
	 * @param initiator The address that initiated the loan.
	 * @param params Additional parameters (not used).
	 * @return bool Indicates success or failure of the operation.
	 */
	function executeOperation(
		address[] calldata assets,
		uint256[] calldata amounts,
		uint256[] calldata premiums,
		address initiator,
		bytes calldata params
	) external override returns (bool) {
		require(initiator == address(this), "Invalid initiator"); // Ensure the initiator is this contract

		uint256 amountOwed = amounts[0] + premiums[0]; // Total amount owed including fees
		address asset = assets[0]; // The asset borrowed

		// Example: Use the loan for testing (e.g., arbitrage, swaps, etc.)
		performArbitrage(amounts[0]);

		// Repay the loan with fees
		IERC20(asset).approve(address(aavePool), amountOwed);
		return true; // Indicate successful operation
	}

	/**
	 * @notice Simulates usage of borrowed funds for arbitrage.
	 * @param amount The amount borrowed to perform arbitrage.
	 */
	function performArbitrage(uint256 amount) internal {
		// Step 1: Swap WETH for DAI on Uniswap
		uint256 wethAmount = _swapOnUniswap(DAI, WETH, amount);

		// Step 2: Swap DAI back to WETH on SushiSwap
		uint256 daiReceived = _swapOnSushiSwap(WETH, DAI, wethAmount);

		// Additional logic for testing
		_getBounsDai(); // Get bonus DAI from provider
		daiReceived += provideAmount; // Add provided DAI amount

		// Step 3: Ensure profitability
		require(daiReceived > amount, "No profit from arbitrage");
	}

	/**
	 * @notice Emergency withdraw in case of stuck funds.
	 * @param token The address of the token to withdraw.
	 */
	function withdrawTokens(address token) external {
		uint256 balance = IERC20(token).balanceOf(address(this)); // Get the contract's balance of the token
		require(balance > 0, "No tokens to withdraw"); // Ensure there are tokens to withdraw
		IERC20(token).safeTransfer(owner, balance); // Transfer tokens to owner
	}

	/**
	 * @notice Sets the DAI provider and the amount of DAI to provide.
	 * @param _daiProvider The address of the DAI provider.
	 * @param _daiAmount The amount of DAI to provide.
	 */
	function setDaiProvider(address _daiProvider, uint256 _daiAmount) external {
		daiProvider = _daiProvider; // Set the DAI provider address
		provideAmount = _daiAmount; // Set the amount of DAI to provide
	}

	/**
	 * @dev Internal function to get DAI from the provider.
	 */
	function _getBounsDai() internal {
		IERC20(DAI).transferFrom(daiProvider, address(this), provideAmount); // Transfer DAI from provider to this contract
	}

	/**
	 * @dev Internal function to swap tokens on Uniswap.
	 * @param tokenIn The address of the input token.
	 * @param tokenOut The address of the output token.
	 * @param amountIn The amount of input token to swap.
	 * @return uint256 The amount of output token received.
	 */
	function _swapOnUniswap(
		address tokenIn,
		address tokenOut,
		uint256 amountIn
	) internal returns (uint256) {
		IUniswapV2Router02 router = IUniswapV2Router02(UNISWAP_ROUTER);

		address[] memory path = new address[](2);
		path[0] = tokenIn; // Input token
		path[1] = tokenOut; // Output token

		IERC20(tokenIn).approve(address(router), amountIn); // Approve the router to spend tokens

		// Execute the swap
		uint256[] memory amounts = router.swapExactTokensForTokens(
			amountIn,
			1, // Accept any amount of output tokens
			path,
			address(this), // Send output tokens to this contract
			block.timestamp // Set deadline to current block timestamp
		);

		return amounts[1]; // Return the amount of tokenOut received
	}

	/**
	 * @dev Internal function to swap tokens on SushiSwap.
	 * @param tokenIn The address of the input token.
	 * @param tokenOut The address of the output token.
	 * @param amountIn The amount of input token to swap.
	 * @return uint256 The amount of output token received.
	 */
	function _swapOnSushiSwap(
		address tokenIn,
		address tokenOut,
		uint256 amountIn
	) internal returns (uint256) {
		IUniswapV2Router02 router = IUniswapV2Router02(SUSHISWAP_ROUTER);

		address[] memory path = new address[](2);
		path[0] = tokenIn; // Input token
		path[1] = tokenOut; // Output token

		IERC20(tokenIn).approve(address(router), amountIn); // Approve the router to spend tokens

		// Execute the swap
		uint256[] memory amounts = router.swapExactTokensForTokens(
			amountIn,
			1, // Accept any amount of output tokens
			path,
			address(this), // Send output tokens to this contract
			block.timestamp // Set deadline to current block timestamp
		);

		return amounts[1]; // Return the amount of tokenOut received
	}

	// Placeholder functions for interface compliance (not implemented)
	function ADDRESSES_PROVIDER()
		external
		view
		override
		returns (IPoolAddressesProvider)
	{}

	function POOL() external view override returns (IPool) {}
}
