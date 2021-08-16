const Web3 = require("web3");
const web3 = new Web3(Web3.givenProvider || "ws://localhost:8545");
const { expect } = require("chai");
const BigNumber = require("bignumber.js");
const { constants, expectEvent, expectRevert, time } = require("@openzeppelin/test-helpers");
const timeMachine = require("ganache-time-traveler");

const MockERC20 = artifacts.require("ERC20PresetMinterPauserMock");
const SimpleMultisig = artifacts.require("SimpleMultisig");

BigNumber.config({ EXPONENTIAL_AT: 1e9 });

describe("Testset for token properties", () => {
    let deployer;
    let user2, user3, user4, user5;
    let members = [];
    const NUM_MEMBERS = 5;

    let token;
    let multisig;
    let snapshotId;

    before(async () => {
        [deployer, user2, user3, user4, user5] = await web3.eth.getAccounts();
        members.push(deployer, user2, user3, user4, user5);

        token = await MockERC20.new("MyMockToken", "MMTKN", 18, { from: deployer });
        multisig = await SimpleMultisig.new(token.address, members, { from: deployer });
    });

    describe("Adding application test", () => {
        beforeEach(async () => {
            // Create a snapshot
            const snapshot = await timeMachine.takeSnapshot();
            snapshotId = snapshot["result"];
        });

        afterEach(async () => await timeMachine.revertToSnapshot(snapshotId));

        it("Check users", async () => {
            expect(await multisig.isMember(deployer), "Must be member").to.be.true;
            expect(await multisig.isMember(user2), "Must be member").to.be.true;
            expect(await multisig.isMember(user5), "Must be member").to.be.true;
        });
    });
});
