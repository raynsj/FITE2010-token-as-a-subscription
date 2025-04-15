const hre = require("hardhat");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SharedSubscriptionToken", function () {
  let sharedSubscriptionToken;
  let owner, user1, user2, user3, user4, user5, user6;
  const serviceId1 = 1; // Netflix
  const serviceId2 = 2; // Spotify
  const tokenPrice = hre.ethers.parseEther("0.01"); // 0.01 ETH per token

  beforeEach(async function () {
    [owner, user1, user2, user3, user4, user5, user6] =
      await hre.ethers.getSigners();

    const SharedSubscriptionToken = await hre.ethers.getContractFactory(
      "SharedSubscriptionToken",
      owner
    );
    sharedSubscriptionToken = await SharedSubscriptionToken.deploy();
    await sharedSubscriptionToken.waitForDeployment();

    // Add services as admin
    await sharedSubscriptionToken.connect(owner).addService(serviceId1, "NFLX");
    await sharedSubscriptionToken
      .connect(owner)
      .addService(serviceId2, "SPTFY");
  });

  it("Should allow users to buy tokens", async function () {
    const tokenAmount = 5;
    const initialBalance = await sharedSubscriptionToken.balanceOf(
      user1.address
    );
    console.log("Initial token balance:", initialBalance);

    // Buy tokens
    await sharedSubscriptionToken
      .connect(user1)
      .buyTokens(tokenAmount, { value: tokenPrice * BigInt(tokenAmount) });

    // Check token balance increased
    const finalBalance = await sharedSubscriptionToken.balanceOf(user1.address);
    console.log("Final token balance:", finalBalance);
    expect(finalBalance).to.equal(initialBalance + BigInt(tokenAmount));
  });

  it("Should allow users to subscribe to a service", async function () {
    // First buy tokens
    await sharedSubscriptionToken
      .connect(user1)
      .buyTokens(1, { value: tokenPrice });

    // Then subscribe
    await sharedSubscriptionToken.connect(user1).subscribe(serviceId1);

    // Check if subscription is active
    const isActive = await sharedSubscriptionToken.isSubscriptionActive(
      user1.address,
      serviceId1
    );
    console.log("Subscription active status:", isActive);
    expect(isActive).to.be.true;

    // Check if token was spent
    const balance = await sharedSubscriptionToken.balanceOf(user1.address);
    expect(balance).to.equal(0);
  });

  it("Should create new subscription account when first user subscribes", async function () {
    // Buy tokens and subscribe
    await sharedSubscriptionToken
      .connect(user1)
      .buyTokens(1, { value: tokenPrice });
    await sharedSubscriptionToken.connect(user1).subscribe(serviceId1);

    // Get user's subscription details
    const [exists, accountId] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user1.address,
        serviceId1
      );

    expect(exists).to.be.true;
    expect(accountId).to.equal(1); // First account should have ID 1

    // Get service details to check subscription count
    const [_, __, ___, subscriptionCount] =
      await sharedSubscriptionToken.getServiceDetails(serviceId1);
    expect(subscriptionCount).to.equal(1);
  });

  it("Should add users to existing subscription accounts when space available", async function () {
    // Setup: Multiple users subscribe
    const subscriberCount = 3;
    for (let i = 0; i < subscriberCount; i++) {
      const user = [user1, user2, user3][i];
      await sharedSubscriptionToken
        .connect(user)
        .buyTokens(1, { value: tokenPrice });
      await sharedSubscriptionToken.connect(user).subscribe(serviceId1);
    }

    // Check all users are part of the same subscription account
    const [_, accountId1] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user1.address,
        serviceId1
      );
    const [__, accountId2] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user2.address,
        serviceId1
      );
    const [___, accountId3] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user3.address,
        serviceId1
      );

    // All should be in the same account as they fit within maxUsersPerSubscription (which is 5 by default)
    expect(accountId1).to.equal(accountId2);
    expect(accountId2).to.equal(accountId3);

    // Get members of the subscription account
    const members = await sharedSubscriptionToken.getSubscriptionMembers(
      serviceId1,
      accountId1
    );
    expect(members.length).to.equal(subscriberCount);
    expect(members).to.include(user1.address);
    expect(members).to.include(user2.address);
    expect(members).to.include(user3.address);
  });

  it("Should create new subscription account when existing ones are full", async function () {
    // First set max users per subscription to 3 for testing
    await sharedSubscriptionToken
      .connect(owner)
      .updateMaxUsersPerSubscription(3);

    // Subscribe with 4 users (should create 2 accounts)
    for (let i = 0; i < 4; i++) {
      const user = [user1, user2, user3, user4][i];
      await sharedSubscriptionToken
        .connect(user)
        .buyTokens(1, { value: tokenPrice });
      await sharedSubscriptionToken.connect(user).subscribe(serviceId1);
    }

    // Get account IDs
    const [_, accountId1] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user1.address,
        serviceId1
      );
    const [__, accountId4] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user4.address,
        serviceId1
      );

    // Fourth user should be in a different account
    expect(accountId1).to.not.equal(accountId4);

    // Get service details to check subscription count
    const [___, ____, _____, subscriptionCount] =
      await sharedSubscriptionToken.getServiceDetails(serviceId1);
    expect(subscriptionCount).to.equal(2); // Should have created 2 accounts
  });

  it("Should calculate cost per member correctly", async function () {
    // First add 3 users to a subscription
    for (let i = 0; i < 3; i++) {
      const user = [user1, user2, user3][i];
      await sharedSubscriptionToken
        .connect(user)
        .buyTokens(1, { value: tokenPrice });
      await sharedSubscriptionToken.connect(user).subscribe(serviceId1);
    }

    // Get the account ID they're all part of
    const [_, accountId] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user1.address,
        serviceId1
      );

    // Calculate cost per member and capture event
    const tx = await sharedSubscriptionToken
      .connect(owner)
      .calculateCostPerMember(serviceId1, accountId);
    const receipt = await tx.wait();

    // Fixed event parsing for newer ethers.js versions
    const eventInterface =
      sharedSubscriptionToken.interface.getEvent("SubscriptionUpdate");
    const topicHash = eventInterface.topicHash;

    // Find the log with matching topic hash and parse it
    const log = receipt.logs.find((x) => x.topics[0] === topicHash);
    const event = sharedSubscriptionToken.interface.parseLog({
      data: log.data,
      topics: log.topics,
    });

    // Get service cost
    const [__, serviceCost] = await sharedSubscriptionToken.getServiceDetails(
      serviceId1
    );

    // Fix: Account for integer division rounding in Solidity
    // When 10 ether is divided by 3, and then multiplied by 3 again,
    // there might be a rounding error of 1 wei due to integer division
    const costPerMember = event.args[3];
    const totalCostAfterDivision = costPerMember * BigInt(3);

    console.log("Original service cost:", serviceCost.toString());
    console.log("Cost per member:", costPerMember.toString());
    console.log("Cost per member * 3:", totalCostAfterDivision.toString());

    // Check the difference is very small (due to integer division rounding)
    const difference = serviceCost - totalCostAfterDivision;
    expect(difference).to.be.lessThanOrEqual(BigInt(3)); // Difference should be at most 3 wei (1 wei per member)

    // Check other event parameters
    expect(event.args[0]).to.equal(serviceId1); // serviceId
    expect(event.args[1]).to.equal(accountId); // accountId
    expect(event.args[2]).to.equal(3); // numMembers
  });

  it("Should expire subscriptions after the designated time", async function () {
    // Setup: Buy tokens and subscribe
    await sharedSubscriptionToken
      .connect(user1)
      .buyTokens(1, { value: tokenPrice });
    await sharedSubscriptionToken.connect(user1).subscribe(serviceId1);

    console.log(
      "Initial subscription status:",
      await sharedSubscriptionToken.isSubscriptionActive(
        user1.address,
        serviceId1
      )
    );

    // Artificially advance time
    await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24 * 31]); // Advance 31 days
    await hre.ethers.provider.send("evm_mine");

    // Check and expire subscriptions
    // await sharedSubscriptionToken.checkAndExpireSubscriptions();

    // Instead of manually calling checkAndExpireSubscriptions, call a function that
    // uses the modifier
    // For example, try to get encrypted credentials which should trigger the expiration checlk

    // Verify subscription is expired
    const isActive = await sharedSubscriptionToken.isSubscriptionActive(
      user1.address,
      serviceId1
    );
    console.log("Final subscription status:", isActive);
    expect(isActive).to.be.false;
  });

  it("Should allow users to renew their subscriptions", async function () {
    // Setup: Buy tokens and subscribe
    await sharedSubscriptionToken
      .connect(user1)
      .buyTokens(2, { value: tokenPrice * BigInt(2) });
    await sharedSubscriptionToken.connect(user1).subscribe(serviceId1);

    // Advance time close to expiration
    await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24 * 25]); // Advance 25 days
    await hre.ethers.provider.send("evm_mine");

    // Renew subscription
    await sharedSubscriptionToken.connect(user1).renewSubscription(serviceId1);

    // Advance another 10 days (would expire without renewal)
    await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24 * 10]);
    await hre.ethers.provider.send("evm_mine");

    // Check if still active after what would have been the original expiration
    const isActive = await sharedSubscriptionToken.isSubscriptionActive(
      user1.address,
      serviceId1
    );
    expect(isActive).to.be.true;
  });

  it("Should allow storing and retrieving encrypted credentials", async function () {
    // Setup: Buy tokens and subscribe
    await sharedSubscriptionToken
      .connect(user1)
      .buyTokens(1, { value: tokenPrice });
    await sharedSubscriptionToken.connect(user1).subscribe(serviceId1);

    // Mock encrypted credentials (in real app this would be encrypted with user's public key)
    const mockEncryptedData = ethers.encodeBytes32String(
      "encryptedCredentials"
    );

    // Store credentials
    await sharedSubscriptionToken
      .connect(user1)
      .storeEncryptedCredentials(serviceId1, mockEncryptedData);

    // Retrieve credentials
    const retrievedData = await sharedSubscriptionToken
      .connect(user1)
      .getEncryptedCredentials(serviceId1);

    expect(retrievedData).to.equal(mockEncryptedData);
  });

  it("Should allow admin to set base credentials for subscription accounts", async function () {
    // Setup: User subscribes to create an account
    await sharedSubscriptionToken
      .connect(user1)
      .buyTokens(1, { value: tokenPrice });
    await sharedSubscriptionToken.connect(user1).subscribe(serviceId1);

    // Get account ID
    const [_, accountId] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user1.address,
        serviceId1
      );

    // Admin sets base credentials
    const mockUsername = "service_username";
    const mockPassword = "encrypted_password";

    await sharedSubscriptionToken
      .connect(owner)
      .setBaseCredentials(serviceId1, accountId, mockUsername, mockPassword);
  });

  it("Should not allow non-admin to set base credentials", async function () {
    // Setup: User subscribes to create an account
    await sharedSubscriptionToken
      .connect(user1)
      .buyTokens(1, { value: tokenPrice });
    await sharedSubscriptionToken.connect(user1).subscribe(serviceId1);

    // Get account ID
    const [_, accountId] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user1.address,
        serviceId1
      );

    // Non-admin tries to set base credentials
    await expect(
      sharedSubscriptionToken
        .connect(user2)
        .setBaseCredentials(serviceId1, accountId, "username", "password")
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("Should allow admin to withdraw funds", async function () {
    // First, ensure there are funds in the contract
    await sharedSubscriptionToken
      .connect(user1)
      .buyTokens(10, { value: tokenPrice * BigInt(10) });

    const initialContractBalance = await hre.ethers.provider.getBalance(
      await sharedSubscriptionToken.getAddress()
    );
    const initialOwnerBalance = await hre.ethers.provider.getBalance(
      owner.address
    );
    console.log("Initial contract balance:", initialContractBalance);

    // Withdraw funds
    const tx = await sharedSubscriptionToken.connect(owner).withdrawFunds();
    const receipt = await tx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    // Check if funds were transferred to owner
    const finalContractBalance = await hre.ethers.provider.getBalance(
      await sharedSubscriptionToken.getAddress()
    );
    const finalOwnerBalance = await hre.ethers.provider.getBalance(
      owner.address
    );

    expect(finalContractBalance).to.equal(0);
    expect(finalOwnerBalance).to.be.closeTo(
      initialOwnerBalance + initialContractBalance - gasUsed,
      hre.ethers.parseEther("0.0001") // Allow for small gas calculation differences
    );
  });

  //Jayden added
  describe("Voting System", function () {
    beforeEach(async function () {
      // Setup: Allow up to 5 users in a single subscription account
      await sharedSubscriptionToken
        .connect(owner)
        .updateMaxUsersPerSubscription(5);

      // User1, User2, User3, User4, and User5 buy tokens and subscribe to the same service
      for (let i = 0; i < 5; i++) {
        const user = [user1, user2, user3, user4, user5][i];
        await sharedSubscriptionToken
          .connect(user)
          .buyTokens(1, { value: tokenPrice });
        await sharedSubscriptionToken.connect(user).subscribe(serviceId1);
      }
    });

    it("Should allow creating a proposal to kick a user", async function () {
      // Get the account ID for User1
      const [_, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user1.address,
          serviceId1
        );

      // User1 proposes to kick User5
      await sharedSubscriptionToken
        .connect(user1)
        .proposeToKickUser(serviceId1, accountId, user5.address);

      // Get the proposal count
      const proposalCount = await sharedSubscriptionToken.getProposalCount(
        serviceId1,
        accountId
      );

      // Get proposal details using the getter function
      const proposal = await sharedSubscriptionToken.getProposal(
        serviceId1,
        accountId,
        proposalCount
      );

      // Verify the proposal details
      expect(proposal.proposer).to.equal(user1.address);
      expect(proposal.userToKick).to.equal(user5.address);
    });

    it("Should execute successful kick proposal", async function () {
      // Get the account ID for User1
      const [_, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user1.address,
          serviceId1
        );

      // User1 proposes to kick User5
      await sharedSubscriptionToken
        .connect(user1)
        .proposeToKickUser(serviceId1, accountId, user5.address);

      // Other users vote "yes" to kick User5
      await sharedSubscriptionToken
        .connect(user2)
        .voteOnProposal(serviceId1, accountId, 1, true);
      await sharedSubscriptionToken
        .connect(user3)
        .voteOnProposal(serviceId1, accountId, 1, true);
      await sharedSubscriptionToken
        .connect(user4)
        .voteOnProposal(serviceId1, accountId, 1, true);

      // Fast-forward time by 25 hours (beyond the voting period of 24 hours)
      await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 25]);
      await hre.ethers.provider.send("evm_mine");

      // Execute the proposal
      await sharedSubscriptionToken
        .connect(user4)
        .executeProposal(serviceId1, accountId, 1);

      // Verify that User5 was removed from the subscription
      const isMember = await sharedSubscriptionToken.isSubscriptionActive(
        user5.address,
        serviceId1
      );
      expect(isMember).to.be.false;

      // Verify that User5 is no longer in the membership list
      const members = await sharedSubscriptionToken.getSubscriptionMembers(
        serviceId1,
        accountId
      );
      expect(members).to.not.include(user5.address);
    });

    it("Should prevent double voting", async function () {
      // Get the account ID for User1
      const [_, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user1.address,
          serviceId1
        );

      // User1 proposes to kick User5
      await sharedSubscriptionToken
        .connect(user1)
        .proposeToKickUser(serviceId1, accountId, user5.address);

      // User2 votes "yes"
      await sharedSubscriptionToken
        .connect(user2)
        .voteOnProposal(serviceId1, accountId, 1, true);

      // Attempt to vote again as User2 (should fail)
      await expect(
        sharedSubscriptionToken
          .connect(user2)
          .voteOnProposal(serviceId1, accountId, 1, true)
      ).to.be.revertedWithCustomError(sharedSubscriptionToken, "AlreadyVoted");
    });

    it("Should not allow a non-member to propose or vote", async function () {
      // Get the account ID for User6 (who is not a member)
      const [_, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user1.address,
          serviceId1
        );

      // Attempt to propose as a non-member (User6)
      await expect(
        sharedSubscriptionToken
          .connect(user6)
          .proposeToKickUser(serviceId1, accountId, user5.address)
      ).to.be.revertedWith("Not a member");

      // Attempt to vote as a non-member (User6)
      await expect(
        sharedSubscriptionToken
          .connect(user6)
          .voteOnProposal(serviceId1, accountId, 0, true)
      ).to.be.revertedWithCustomError(sharedSubscriptionToken, "NotMember");
    });

    it("Should not allow a user to propose themselves for removal", async function () {
      // Get the account ID for User3
      const [_, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user3.address,
          serviceId1
        );

      // Attempt to propose themselves for removal
      await expect(
        sharedSubscriptionToken
          .connect(user3)
          .proposeToKickUser(serviceId1, accountId, user3.address)
      ).to.be.revertedWith("Cannot propose yourself");
    });

    it("Should not allow voting after the voting period has ended", async function () {
      // Get the account ID for User4
      const [_, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user4.address,
          serviceId1
        );

      // User4 proposes to kick User3
      await sharedSubscriptionToken
        .connect(user4)
        .proposeToKickUser(serviceId1, accountId, user3.address);

      // Fast-forward time by more than the voting period (25 hours)
      await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 25]);
      await hre.ethers.provider.send("evm_mine");

      // Attempt to vote after the voting period has ended (should fail)
      await expect(
        sharedSubscriptionToken
          .connect(user2)
          .voteOnProposal(serviceId1, accountId, 0, true)
      ).to.be.revertedWithCustomError(
        sharedSubscriptionToken,
        "VotingPeriodEnded"
      );
    });
  });

  // new tests for security

  describe("Security: Reentrancy", function () {
    let attackerContract;

    beforeEach(async function () {
      // Deploy the attacker contract
      const ReentrancyAttack = await hre.ethers.getContractFactory(
        "ReentrancyAttack"
      );
      attackerContract = await ReentrancyAttack.connect(owner).deploy(
        await sharedSubscriptionToken.getAddress()
      );
      await attackerContract.waitForDeployment();
    });

    it("Should prevent reentrancy on buyTokens", async function () {
      // Attack amount - we'll send this to the attacker contract
      const attackAmount = tokenPrice * BigInt(5);

      // Launch the attack
      await attackerContract.connect(owner).attack({ value: attackAmount });

      // Get the attack count (how many times the reentrancy was attempted)
      const attackCount = await attackerContract.attackCount();
      console.log("Attack count (reentrant calls):", attackCount);

      // If buyTokens is not vulnerable to reentrancy, there should be only
      // one successful call and no stolen tokens
      const stolenTokens = await attackerContract.stolenTokens();
      console.log("Stolen tokens:", stolenTokens);

      // The attacker should only receive tokens for the initial legitimate call
      expect(stolenTokens).to.equal(1);

      // If the contract properly handles reentrancy, the attackCount could be 0 or 1
      // 0 if no ETH is sent back to the attacker during buyTokens
      // 1 if ETH is sent but reentrancy is prevented
      expect(attackCount).to.be.lessThanOrEqual(1);
    });
  });

  describe("Proposal Cooldown", function () {
    let sharedSubscriptionToken, owner, user1, user2, user3;
    const serviceId1 = 1;
    const tokenPrice = hre.ethers.parseEther("0.01");

    beforeEach(async function () {
      [owner, user1, user2, user3] = await hre.ethers.getSigners();

      const SharedSubscriptionToken = await hre.ethers.getContractFactory(
        "SharedSubscriptionToken",
        owner
      );
      sharedSubscriptionToken = await SharedSubscriptionToken.deploy();
      await sharedSubscriptionToken.waitForDeployment();

      await sharedSubscriptionToken
        .connect(owner)
        .addService(serviceId1, "NFLX");

      // All users buy tokens and subscribe
      for (let user of [user1, user2, user3]) {
        await sharedSubscriptionToken
          .connect(user)
          .buyTokens(1, { value: tokenPrice });
        await sharedSubscriptionToken.connect(user).subscribe(serviceId1);
      }
    });

    it("Should not allow user to create two proposals within 12 hours", async function () {
      // Get accountId for user1
      const [_, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user1.address,
          serviceId1
        );

      // User1 proposes to kick user2
      await sharedSubscriptionToken
        .connect(user1)
        .proposeToKickUser(serviceId1, accountId, user2.address);

      // Try to propose again immediately
      await expect(
        sharedSubscriptionToken
          .connect(user1)
          .proposeToKickUser(serviceId1, accountId, user3.address)
      ).to.be.revertedWith("Wait before proposing again");

      // Fast-forward time by 12 hours
      await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 12]);
      await hre.ethers.provider.send("evm_mine");

      // Now user1 can propose again
      await sharedSubscriptionToken
        .connect(user1)
        .proposeToKickUser(serviceId1, accountId, user3.address);
    });
  });
});
