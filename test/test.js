const hre = require("hardhat");
const { expect } = require("chai");

describe("SubscriptionToken", function () {
  let subscriptionToken;
  let owner, user1, user2, user3;
  const serviceId1 = 1; // Netflix
  const serviceId2 = 2; // Spotify
  const tokenPrice = hre.ethers.parseEther("0.01"); // 0.01 ETH per token

  beforeEach(async function () {
    [owner, user1, user2, user3] = await hre.ethers.getSigners();

    const SubscriptionToken = await hre.ethers.getContractFactory(
      "SubscriptionToken",
      owner
    );
    subscriptionToken = await SubscriptionToken.deploy();
    await subscriptionToken.waitForDeployment();

    // Add services as admin
    await subscriptionToken.connect(owner).addService(serviceId1);
    await subscriptionToken.connect(owner).addService(serviceId2);
  });

  it("Should allow users to buy tokens", async function () {
    const tokenAmount = 5;
    const initialBalance = await subscriptionToken.balanceOf(user1.address);
    console.log("Initial token balance:", initialBalance);

    // Buy tokens
    await subscriptionToken
      .connect(user1)
      .buyTokens(tokenAmount, { value: tokenPrice * BigInt(tokenAmount) });

    // Check token balance increased
    const finalBalance = await subscriptionToken.balanceOf(user1.address);
    console.log("Final token balance:", finalBalance);
    expect(finalBalance).to.equal(initialBalance + BigInt(tokenAmount));
  });

  it("Should allow users to activate subscriptions", async function () {
    // First buy tokens
    const tokenAmount = 1;
    await subscriptionToken
      .connect(user1)
      .buyTokens(tokenAmount, { value: tokenPrice * BigInt(tokenAmount) });

    // Then activate subscription
    await subscriptionToken
      .connect(user1)
      .activateSubscription(user1.address, serviceId1);

    // Check if subscription is active
    const isActive = await subscriptionToken.isSubscriptionActive(
      user1.address,
      serviceId1
    );
    console.log("Subscription active status:", isActive);
    expect(isActive).to.be.true;

    // Check if token was spent
    const balance = await subscriptionToken.balanceOf(user1.address);
    expect(balance).to.equal(0);
  });

  it("Should check and expire subscriptions after the designated time", async function () {
    // Setup: Buy tokens and activate subscription
    await subscriptionToken.connect(user1).buyTokens(1, { value: tokenPrice });
    await subscriptionToken
      .connect(user1)
      .activateSubscription(user1.address, serviceId1);

    console.log(
      "Initial subscription status:",
      await subscriptionToken.isSubscriptionActive(user1.address, serviceId1)
    );

    // Artificially advance time
    await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24 * 31]); // Advance 31 days
    await hre.ethers.provider.send("evm_mine");

    // Check and expire subscriptions
    await subscriptionToken.checkAndExpireSubscriptions();

    // Verify subscription is expired
    const isActive = await subscriptionToken.isSubscriptionActive(
      user1.address,
      serviceId1
    );
    console.log("Final subscription status:", isActive);
    expect(isActive).to.be.false;
  });

  it("Should allow users to request a new platform", async function () {
    const newPlatformId = 3; // Disney+

    // Request new platform
    await subscriptionToken
      .connect(user1)
      .requestNewPlatform(user1.address, newPlatformId);

    // Check if platform request was registered
    const requests = await subscriptionToken.checkSubscribers(newPlatformId);
    console.log("Platform requests:", requests);
    expect(requests).to.equal(1);
  });

  it("Should correctly count the number of subscribers for a platform", async function () {
    // Setup: Multiple users activate subscriptions for the same service
    await subscriptionToken.connect(user1).buyTokens(1, { value: tokenPrice });
    await subscriptionToken.connect(user2).buyTokens(1, { value: tokenPrice });

    await subscriptionToken
      .connect(user1)
      .activateSubscription(user1.address, serviceId1);
    await subscriptionToken
      .connect(user2)
      .activateSubscription(user2.address, serviceId1);

    // Check subscriber count
    const subscriberCount = await subscriptionToken.checkSubscribers(
      serviceId1
    );
    console.log("Subscriber count:", subscriberCount);
    expect(subscriberCount).to.equal(2);
  });

  it("Should correctly divide costs among subscribers", async function () {
    // Setup: Multiple users activate subscriptions for the same service
    await subscriptionToken.connect(user1).buyTokens(1, { value: tokenPrice });
    await subscriptionToken.connect(user2).buyTokens(1, { value: tokenPrice });
    await subscriptionToken.connect(user3).buyTokens(1, { value: tokenPrice });

    await subscriptionToken
      .connect(user1)
      .activateSubscription(user1.address, serviceId1);
    await subscriptionToken
      .connect(user2)
      .activateSubscription(user2.address, serviceId1);
    await subscriptionToken
      .connect(user3)
      .activateSubscription(user3.address, serviceId1);

    console.log(
      "Subscribers before division:",
      await subscriptionToken.checkSubscribers(serviceId1)
    );

    // Listen for the SubscriptionUpdate event
    const tx = await subscriptionToken.connect(owner).divideCost(serviceId1);
    const receipt = await tx.wait();

    // Find the SubscriptionUpdate event
    const event = receipt.events.find((e) => e.event === "SubscriptionUpdate");
    console.log("SubscriptionUpdate event:", event.args);

    // Verify event data
    expect(event.args.platformId).to.equal(serviceId1);
    expect(event.args.numSubscribers).to.equal(3);

    // Cost per subscriber should be the total cost divided by number of subscribers
    const totalCost = await subscriptionToken.getServiceCost(serviceId1);
    expect(event.args.costPerSubscriber * BigInt(3)).to.equal(totalCost);
  });

  it("Should allow admin to withdraw funds", async function () {
    // First, ensure there are funds in the contract
    await subscriptionToken
      .connect(user1)
      .buyTokens(10, { value: tokenPrice * BigInt(10) });

    const initialContractBalance = await hre.ethers.provider.getBalance(
      await subscriptionToken.getAddress()
    );
    const initialOwnerBalance = await hre.ethers.provider.getBalance(
      owner.address
    );
    console.log("Initial contract balance:", initialContractBalance);

    // Withdraw funds
    const tx = await subscriptionToken.connect(owner).withdrawFunds();
    const receipt = await tx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    // Check if funds were transferred to owner
    const finalContractBalance = await hre.ethers.provider.getBalance(
      await subscriptionToken.getAddress()
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

  it("Should not allow non-admin to add services or withdraw funds", async function () {
    // Try to add service as non-admin
    await expect(
      subscriptionToken.connect(user1).addService(3)
    ).to.be.revertedWith("Ownable: caller is not the owner");

    // Try to withdraw funds as non-admin
    await expect(
      subscriptionToken.connect(user1).withdrawFunds()
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("Should handle fallback functionality correctly", async function () {
    // Buy tokens first
    await subscriptionToken.connect(user1).buyTokens(1, { value: tokenPrice });

    // Test the fallback function
    await subscriptionToken
      .connect(user1)
      .fallbackFunction(user1.address, serviceId1);

    // Verify the subscription was activated via fallback mechanism
    const isActive = await subscriptionToken.isSubscriptionActive(
      user1.address,
      serviceId1
    );
    expect(isActive).to.be.true;
  });
});
