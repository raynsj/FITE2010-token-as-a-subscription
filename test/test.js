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

    // Find the SubscriptionUpdate event
    const event = receipt.events.find((e) => e.event === "SubscriptionUpdate");

    // Get service cost
    const [__, serviceCost] = await sharedSubscriptionToken.getServiceDetails(
      serviceId1
    );

    // Check cost division
    expect(event.args.serviceId).to.equal(serviceId1);
    expect(event.args.accountId).to.equal(accountId);
    expect(event.args.numMembers).to.equal(3);
    expect(event.args.costPerMember * BigInt(3)).to.equal(serviceCost);
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
    await sharedSubscriptionToken.checkAndExpireSubscriptions();

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
});
