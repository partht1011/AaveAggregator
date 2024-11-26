import { Address } from './../typechain-types/@openzeppelin/contracts/utils/Address';
import { expect } from "chai"
import { IERC20, IPool } from 'typechain-types';
import { AaveAggregator } from '../typechain-types/contracts/AaveAggregator';
import { ethers, network } from 'hardhat';
async function timeTravel(seconds: number) {
    await ethers.provider.send("evm_increaseTime", [seconds]);
    await ethers.provider.send("evm_mine");
}
describe("AaveAggregator", function () {
    const ADDRESS_AAVE_POOL = '0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2';
    const ADDRESS_DAI = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
    const knownDAIHolder = "0xD1668fB5F690C59Ab4B0CAbAd0f8C1617895052B";

    let daiHolder: any, user1: any, user2: any;
    let aavePool: IPool;
    let dai: IERC20;
    let aggregator: AaveAggregator;
    before(async () => {

        [, user1, user2] = await ethers.getSigners();
        aavePool = await ethers.getContractAt('IPool', ADDRESS_AAVE_POOL);
        dai = await ethers.getContractAt('IERC20', ADDRESS_DAI);

        const aggregatorFactory = await ethers.getContractFactory('AaveAggregator');
        aggregator = await aggregatorFactory.deploy(ADDRESS_AAVE_POOL, ADDRESS_DAI);

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [knownDAIHolder],
        });

        daiHolder = await ethers.getSigner(knownDAIHolder);
        const amount = ethers.parseEther("1000"); // Amount of DAI to transfer
        await dai.connect(daiHolder).transfer(user1, amount);
        await dai.connect(daiHolder).transfer(user2, amount);

        await network.provider.request({
            method: "hardhat_stopImpersonatingAccount",
            params: [knownDAIHolder],
        });

    })
    it("check user1 and user2 have sufficient amount of DAI", async () => {
        expect(await dai.balanceOf(user1)).to.be.equal(ethers.parseEther("1000"));
        expect(await dai.balanceOf(user2)).to.be.equal(ethers.parseEther("1000"));
    });

    it("deposit amount must be more than 0", async () => {
        await dai.connect(user1).approve(await aggregator.getAddress(), ethers.parseEther('100'))
        await expect(aggregator.connect(user1).deposit(0)).to.be.revertedWith("Invalid deposit amount")

        console.log("   User1 amount: ", ethers.formatEther(await dai.balanceOf(user1)));
        console.log("   User2 amount: ", ethers.formatEther(await dai.balanceOf(user2)));
    })

    it("user1 and user2 deposit DAI to the pool", async () => {
        await dai.connect(user1).approve(await aggregator.getAddress(), ethers.parseEther('100'))
        await aggregator.connect(user1).deposit(ethers.parseEther('100'))

        await timeTravel(60 * 60 * 24 * 10)

        await dai.connect(user2).approve(await aggregator.getAddress(), ethers.parseEther('100'))
        await aggregator.connect(user2).deposit(ethers.parseEther('100'))

        const user1Share = await aggregator.getShare(user1)
        const user2Share = await aggregator.getShare(user2)

        console.log("   User1 amount: ", ethers.formatEther(await dai.balanceOf(user1)));
        console.log("   User2 amount: ", ethers.formatEther(await dai.balanceOf(user2)));

        expect(user1Share).to.be.gt(user2Share)
    })

    it("user1 and user2 withdraw DAI from the pool", async () => {
        await timeTravel(60 * 60 * 24 * 365)

        const user1Share = await aggregator.getShare(user1)
        await aggregator.connect(user1).withdraw(user1Share)

        const user2Share = await aggregator.getShare(user2)
        await aggregator.connect(user2).withdraw(user2Share)

        const user1Amount = await dai.balanceOf(user1);
        const user2Amount = await dai.balanceOf(user2);

        console.log("   User1 amount: ", ethers.formatEther(user1Amount));
        console.log("   User2 amount: ", ethers.formatEther(user2Amount));

        expect(user1Amount).to.be.gt(user2Amount)
    })
});