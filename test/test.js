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
    const NUM_MEMBERS = 5, THRESHOLD = 3;

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
    });

    describe("Constructor", () => {
        beforeEach(async () => {
            // Create a snapshot
            const snapshot = await timeMachine.takeSnapshot();
            snapshotId = snapshot["result"];
        });

        afterEach(async () => await timeMachine.revertToSnapshot(snapshotId));

        it("Token address", async () => {
            await expectRevert(
                SimpleMultisig.new(constants.ZERO_ADDRESS, members, { from: deployer }),
                "Token zero address"
            );
        });

        it("Members amount", async () => {
            let tempMembers = [];
            await expectRevert(
                SimpleMultisig.new(token.address, tempMembers, { from: deployer }),
                "Must be 5 members"
            );
            tempMembers.push(deployer);
            await expectRevert(
                SimpleMultisig.new(token.address, tempMembers, { from: deployer }),
                "Must be 5 members"
            );
            tempMembers.push(member2, member3, member4, member5, user6);
            await expectRevert(
                SimpleMultisig.new(token.address, tempMembers, { from: deployer }),
                "Must be 5 members"
            );
        });

        it("Duplications among members and member zero address checks", async () => {
            let tempMembers = [];
            tempMembers.push(deployer, deployer, member3, constants.ZERO_ADDRESS, member5);
            await expectRevert(
                SimpleMultisig.new(token.address, tempMembers, { from: deployer }),
                "Members must not repeat themselves or/and member can not be zero address"
            );
            tempMembers[4] = constants.ZERO_ADDRESS;
            await expectRevert(
                SimpleMultisig.new(token.address, tempMembers, { from: deployer }),
                "Members must not repeat themselves or/and member can not be zero address"
            );
        });

        it("Check users and function isSuchMember()", async () => {
            expect(await multisig.isSuchMember(deployer), "Should be member").to.be.true;
            expect(await multisig.isSuchMember(member2), "Should be member").to.be.true;
            expect(await multisig.isSuchMember(member5), "Should be member").to.be.true;
            expect(await multisig.isSuchMember(user6), "Should not be member").to.be.false;
            await expectRevert(
                multisig.isSuchMember(constants.ZERO_ADDRESS),
                "Zero address"
            );
        });
    });

    describe("Main test", () => {
        beforeEach(async () => {
            // Create a snapshot
            const snapshot = await timeMachine.takeSnapshot();
            snapshotId = snapshot["result"];
        });

        afterEach(async () => await timeMachine.revertToSnapshot(snapshotId));

        it("Transfer to token and function getBalance() test", async () => {
            let x = new BN(100000);
            await token.mint(user6, x, { from: deployer });
            expect(await token.balanceOf(user6)).to.be.bignumber.equal(x);
            let x2 = new BN(10000);
            await token.transfer(multisig.address, x2, { from: user6 });
            expect(await token.balanceOf(multisig.address)).to.be.bignumber.equal(x2);
            expect(await multisig.getBalance()).to.be.bignumber.equal(x2);
            expect(await token.balanceOf(user6)).to.be.bignumber.equal(new BN(90000));
        });

        it("Function for submit an application", async () => {
            await token.mint(multisig.address, new BN(100000), { from: deployer });

            /**
             *  Requires
             */
            await expectRevert(
                multisig.submitApp(
                    user6,
                    new BN(100),
                    time.duration.days(new BN(3)),
                    { from: user6 }
                ),
                "Only a member can use this function"
            );
            await expectRevert(
                multisig.submitApp(
                    user6,
                    0,
                    time.duration.days(new BN(3)),
                    { from: member2 }
                ),
                "The amount of token must be greater than zero"
            );
            await expectRevert(
                multisig.submitApp(
                    constants.ZERO_ADDRESS,
                    new BN(100),
                    time.duration.days(new BN(3)),
                    { from: member2 }
                ),
                "Zero recipient address"
            );
            await expectRevert(
                multisig.submitApp(
                    multisig.address,
                    new BN(100),
                    time.duration.days(new BN(3)),
                    { from: member2 }
                ),
                "The recipient's address matches the contract address"
            );
            await expectRevert(
                multisig.submitApp(
                    member2,
                    new BN(100),
                    time.duration.days(new BN(3)),
                    { from: member2 }
                ),
                "The recipient's address matches the sender's address"
            );
            await expectRevert(
                multisig.submitApp(
                    user6,
                    new BN(100001), // = 0.0000000000001000001
                    time.duration.days(new BN(3)),
                    { from: member2 }
                ),
                "Not enough tokens"
            );
            await expectRevert(
                multisig.submitApp(
                    user6,
                    new BN(100),
                    0,
                    { from: member2 }
                ),
                "Zero duration of the application"
            );

            /**
             *  Function
             */
            const firstAppID = 0;
            expect(
                await multisig.submitApp.call(
                    user6,
                    new BN(1000),
                    time.duration.days(new BN(3)),
                    { from: member2 }
                )
            )
            .to.be.bignumber.equal(new BN(firstAppID));
            expectEvent(
                await multisig.submitApp(
                    user6,
                    new BN(1000),
                    time.duration.days(new BN(3)),
                    { from: member2 }
                ),
                "AppSubmitted",
                {
                    sender: member2,
                    recipient: user6,
                    amount: new BN(1000),
                    appID: new BN(firstAppID),
                    endTime:
                        new BN(
                            +(await time.latest()) +
                            +(time.duration.days(new BN(3)))
                        )
                }
            );
        });
    });
});
