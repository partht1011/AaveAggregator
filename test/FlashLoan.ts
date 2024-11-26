import { FlashLoan, IERC20, IPool } from 'typechain-types';
import { ethers, network } from 'hardhat';
async function timeTravel(seconds: number) {
    await ethers.provider.send("evm_increaseTime", [seconds]);
    await ethers.provider.send("evm_mine");
}
describe("FlashLoan", function () {
    const AAVE_POOL_ADDRESS_PROVIDER = '0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e';
    const ADDRESS_AAVE_POOL = '0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2';
    const ADDRESS_DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
    const knownDAIHolder = "0xD1668fB5F690C59Ab4B0CAbAd0f8C1617895052B";

    let owner: any, daiProvider: any, daiHolder: any;
    let flashLoan: FlashLoan;
    let dai: IERC20;
    before(async () => {
        [owner, daiProvider] = await ethers.getSigners();

        dai = await ethers.getContractAt('IERC20', ADDRESS_DAI);

        const flashLoanFactory = await ethers.getContractFactory('FlashLoan');
        flashLoan = await flashLoanFactory.deploy(AAVE_POOL_ADDRESS_PROVIDER);

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [knownDAIHolder],
        });

        daiHolder = await ethers.getSigner(knownDAIHolder);
        await dai.connect(daiHolder).transfer(ADDRESS_AAVE_POOL, ethers.parseEther("10000"));

        // Tricky for testing
        await dai.connect(daiHolder).transfer(daiProvider, ethers.parseEther("100"));

        await network.provider.request({
            method: "hardhat_stopImpersonatingAccount",
            params: [knownDAIHolder],
        });
    })

    it.only("should flash loan successfully", async () => {
        console.log("   DAI balance before flash loan: ", ethers.formatEther(await dai.balanceOf(owner)));

        await flashLoan.setDaiProvider(daiProvider, ethers.parseEther("0.2"));
        await dai.connect(daiProvider).approve(await flashLoan.getAddress(), ethers.parseEther("0.2"));

        await flashLoan.requestFlashLoan(dai, ethers.parseEther("10"));
    });

    it.only("check the profit via flash loan", async () => {
        await flashLoan.withdrawTokens(dai);
        console.log("   DAI balance after flash loan: ", ethers.formatEther(await dai.balanceOf(owner)));
    });
});