const Web3 = require("web3");
const web3 = new Web3(Web3.givenProvider || "ws://localhost:8545");
const { expect } = require("chai");
const timeMachine = require("ganache-time-traveler");
const {
    BN,           // Big Number support
    constants,    // Common constants, like the zero address and largest integers
    expectEvent,  // Assertions for emitted events
    expectRevert, // Assertions for transactions that should fail
    time
} = require("@openzeppelin/test-helpers");

const MockERC20 = artifacts.require("ERC20PresetMinterPauserMock");
const SimpleMultisig = artifacts.require("SimpleMultisig");

describe("Testset for Simple Multisig", () => {
    let deployer;
    let member2, member3, member4, member5, user6;
    let members = [];
    const NUM_MEMBERS = 5;

    let token;
    let multisig;
    let snapshotId;

    before(async () => {
        [
            deployer,
            member2,
            member3,
            member4,
            member5,
            user6
        ] = await web3.eth.getAccounts();
        members.push(deployer, member2, member3, member4, member5);

        token = await MockERC20.new("MyMockToken", "MMTKN", 18, { from: deployer });
        multisig = await SimpleMultisig.new(token.address, members, { from: deployer });
        //console.log(token.address, multisig.address);
    });

    describe("Main test", () => {
        beforeEach(async () => {
            // Create a snapshot
            const snapshot = await timeMachine.takeSnapshot();
            snapshotId = snapshot["result"];
        });

        afterEach(async () => await timeMachine.revertToSnapshot(snapshotId));

        it("Function isMember() test (check users)", async () => {
            expect(await multisig.isMember(deployer), "Should be member").to.be.true;
            expect(await multisig.isMember(member2), "Should be member").to.be.true;
            expect(await multisig.isMember(member5), "Should be member").to.be.true;
            expect(await multisig.isMember(user6), "Should not be member").to.be.false;
            await expectRevert(
                multisig.isMember(constants.ZERO_ADDRESS),
                "Zero address"
            );
        });

        it("Transfer to token and function getBalance() test", async () => {
            let x = new BN(100000);
            await token.mint(user6, x, { from: deployer });
            expect(await token.balanceOf(user6)).to.be.bignumber.equal(x);
            //expect(await token.balanceOf(user6)).to.be.bignumber.equal(new BN(100000));
            let x2 = new BN(5000);
            // ? await multisig.token.transfer(multisig.address, x2, { from: user6 });
            await token.transfer(multisig.address, x2, { from: user6 });
            await multisig.transferToThis(x2, { from: user6 });
            //expectEvent(receipt, "TokensTransferedToThis", { user6, x2 });
            expect(await token.balanceOf(multisig.address)).to.be.bignumber.equal(x2);
            expect(await multisig.getBalance()).to.be.bignumber.equal(x2);
            expect(await token.balanceOf(user6)).to.be.bignumber.equal(new BN(90000));
        });

        // it("Submit an application", async () => {
        //     const firstAppID = 0;
        //     expect(
        //         await multisig.submitApp(
        //             user6,
        //             new BN(100),
        //             time.duration.days(new BN(3)),
        //             { from: member2 }
        //         )
        //     )
        //     .to.equal(firstAppID);
        // });
    });
});
