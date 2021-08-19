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

        it("Check users and function isMember(...)", async () => {
            expect(await multisig.isMember(deployer), "Should be member").to.be.true;
            expect(await multisig.isMember(member2), "Should be member").to.be.true;
            expect(await multisig.isMember(member5), "Should be member").to.be.true;
            expect(await multisig.isMember(user6), "Should not be member").to.be.false;
            await expectRevert(
                multisig.isMember(constants.ZERO_ADDRESS),
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
            const FIRST_APP_ID = 0;
            expect(
                await multisig.submitApp.call(
                    user6,
                    new BN(1000),
                    time.duration.days(new BN(3)),
                    { from: member2 }
                )
            )
            .to.be.bignumber.equal(new BN(FIRST_APP_ID));
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
                    appID: new BN(FIRST_APP_ID),
                    endTime:
                        new BN(
                            +(await time.latest()) +
                            +(time.duration.days(new BN(3)))
                        )
                }
            );
            // Multiple submissions
            const APP_ID = 1;
            expect(
                await multisig.submitApp.call(
                    user6,
                    new BN(1000),
                    time.duration.days(new BN(3)),
                    { from: member2 }
                )
            )
            .to.be.bignumber.equal(new BN(APP_ID));
        });

        it("Add and revoke confirm for an application and getConfirms()", async () => {
            await token.mint(multisig.address, new BN(100000), { from: deployer });
            await multisig.submitApp(
                member3,
                new BN(1000),
                time.duration.days(new BN(3)),
                { from: member4 }
            );
            const FIRST_APP_ID = 0;
            const SECOND_CONFIRM = 2;

            // Confirm
            await expectRevert(
                multisig.confirmApp(+(new BN(FIRST_APP_ID)) + +1, { from: member3 }),
                "Unknown application ID"
            );
            expectEvent(
                await multisig.confirmApp(new BN(FIRST_APP_ID), { from: member3 }),
                "AppConfirmed",
                {
                    sender: member3,
                    appID: new BN(FIRST_APP_ID),
                    numConfirms: new BN(SECOND_CONFIRM)
                }
            );
            await expectRevert(
                multisig.confirmApp.call(new BN(FIRST_APP_ID), { from: member3 }),
                "You have already confirmed the application"
            );
            expect(await multisig.getConfirms(new BN(FIRST_APP_ID), { from: member2 }))
            .to.be.bignumber.equal(new BN(2));
            // Revoke confirm
            await expectRevert(
                multisig.revokeConfirmation(new BN(FIRST_APP_ID), { from: member2 }),
                "You have not confirmed the application yet"
            );
            expectEvent(
                await multisig.revokeConfirmation(new BN(FIRST_APP_ID), { from: member3 }),
                "ConfirmRevoked",
                {
                    sender: member3,
                    appID: new BN(FIRST_APP_ID),
                    numConfirms: new BN(+SECOND_CONFIRM - +1)
                }
            );
            expect(await multisig.getConfirms(new BN(FIRST_APP_ID), { from: member2 }))
            .to.be.bignumber.equal(new BN(1));
            // The second application adding and confirm it
            await multisig.submitApp(
                member4,
                new BN(100),
                time.duration.days(new BN(2)),
                { from: member2 }
            );
            await multisig.confirmApp(new BN(+FIRST_APP_ID + +1), { from: member3 });
            expect(await multisig.getConfirms(new BN(+FIRST_APP_ID + +1), { from: member2 }))
            .to.be.bignumber.equal(new BN(2));
        });

        it("Accept an application and transfer tokens", async () => {
            await token.mint(multisig.address, new BN(100000), { from: deployer });
            await multisig.submitApp(
                member3,
                new BN(1000),
                time.duration.days(new BN(3)),
                { from: member4 }
            );
            const FIRST_APP_ID = 0;

            await multisig.confirmApp(new BN(FIRST_APP_ID), { from: member3 });
            expectEvent(
                await multisig.confirmApp(new BN(FIRST_APP_ID), { from: deployer }),
                "AppConfirmed",
                {
                    sender: deployer,
                    appID: new BN(FIRST_APP_ID),
                    numConfirms: new BN(3)
                }
            );
            // Transfer check
            expect(await token.balanceOf(multisig.address)).to.be.bignumber.equal(new BN(99000));
            expect(await token.balanceOf(member3)).to.be.bignumber.equal(new BN(1000));

            await expectRevert(
                multisig.confirmApp(new BN(FIRST_APP_ID), { from: member2 }),
                "This application has already been applied"
            );

            // emit AppAccepted() checking
            await multisig.submitApp(
                member3,
                new BN(1000),
                time.duration.days(new BN(3)),
                { from: member4 }
            );
            const SECOND_APP_ID = +FIRST_APP_ID + +1;
            await multisig.confirmApp(new BN(SECOND_APP_ID), { from: member3 });
            expectEvent(
                await multisig.confirmApp(new BN(SECOND_APP_ID), { from: deployer }),
                "AppAccepted",
                { appID: new BN(SECOND_APP_ID) }
            );
        });

        it("The application is out of time cheking", async () => {
            await token.mint(multisig.address, new BN(100000), { from: deployer });
            await multisig.submitApp(
                member3,
                new BN(1000),
                time.duration.days(new BN(1)),
                { from: member4 }
            );
            const FIRST_APP_ID = 0;
            time.increase(time.duration.days(new BN(2)));
            await expectRevert(
                multisig.confirmApp(new BN(FIRST_APP_ID), { from: member3 }),
                "This application is out of time"
            );
        });

        it("Cancel an application", async () => {
            await token.mint(multisig.address, new BN(100000), { from: deployer });

            // From function revokeConfirmation()
            await multisig.submitApp(
                member3,
                new BN(1000),
                time.duration.days(new BN(1)),
                { from: member4 }
            );
            const FIRST_APP_ID = 0;
            await multisig.confirmApp(new BN(FIRST_APP_ID), { from: member3 });
            await multisig.revokeConfirmation(new BN(FIRST_APP_ID), { from: member4 });
            expectEvent(
                await multisig.revokeConfirmation(new BN(FIRST_APP_ID), { from: member3 }),
                "AppCanceled",
                { appID: new BN(FIRST_APP_ID) }
            );

            // Cancellation due to lack of tokens
            await multisig.submitApp(
                member3,
                new BN(99500),
                time.duration.days(new BN(1)),
                { from: member4 }
            );
            const SECOND_APP_ID = 1;
            await multisig.submitApp(
                member3,
                new BN(1000),
                time.duration.days(new BN(1)),
                { from: member4 }
            );
            const THIRD_ADD_ID = 2;
            // The second application accept
            await multisig.confirmApp(new BN(SECOND_APP_ID), { from: member3 });
            await multisig.confirmApp(new BN(SECOND_APP_ID), { from: member2 });
            // The third application try to accept, but lack of tokens
            expect(await token.balanceOf(multisig.address)).to.be.bignumber.equal(new BN(500));
            await multisig.confirmApp(new BN(THIRD_ADD_ID), { from: member3 });
            expectEvent(
                await multisig.confirmApp(new BN(THIRD_ADD_ID), { from: member2 }),
                "AppCanceled",
                { appID: new BN(THIRD_ADD_ID) }
            );

            // Try confirm the application when it was canceled
            await expectRevert(
                multisig.confirmApp(new BN(THIRD_ADD_ID), { from: deployer }),
                "This application has been canceled"
            );
        });

        it("Function isConfirmedBy(...) check", async () => {
            await token.mint(multisig.address, new BN(100000), { from: deployer });
            await multisig.submitApp(
                member3,
                new BN(1000),
                time.duration.days(new BN(1)),
                { from: member4 }
            );
            const FIRST_APP_ID = 0;
            await multisig.confirmApp(new BN(FIRST_APP_ID), { from: member3 });
            expect(await multisig.isConfirmedBy(member4, new BN(FIRST_APP_ID), { from: deployer })).to.be.true;
            await expectRevert(
                multisig.isConfirmedBy(constants.ZERO_ADDRESS, new BN(FIRST_APP_ID), { from: deployer }),
                "Zero address"
            );
            expect(await multisig.isConfirmedBy(member3, new BN(FIRST_APP_ID), { from: deployer })).to.be.true;
            expect(await multisig.isConfirmedBy(member2, new BN(FIRST_APP_ID), { from: deployer })).to.be.false;
        });

        it("Function getAppInfo(...) check", async () => {
            await token.mint(multisig.address, new BN(100000), { from: deployer });
            await multisig.submitApp(
                member3,
                new BN(1000),
                time.duration.days(new BN(1)),
                { from: member4 }
            );
            let tempTime = await time.latest();
            const FIRST_APP_ID = 0;
            const CONFIRMS = 1;
            let tempAppInfo = await multisig.getAppInfo(new BN(FIRST_APP_ID));
            expect(
                tempAppInfo[0] == member3 &&
                tempAppInfo[1] == 1000 &&
                tempAppInfo[2] == CONFIRMS &&
                tempAppInfo[3] == false &&
                (tempAppInfo[4]).toString() == (new BN(+(tempTime) + +(time.duration.days(new BN(1))))).toString()
            ).to.be.true;
        });
    });
});
