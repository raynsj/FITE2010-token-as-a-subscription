const hre = require("hardhat");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const crypto = require("crypto");

// Helper functions for encryption/decryption
function generateKeyPair() {
  return crypto.generateKeyPairSync("rsa", {
    modulusLength: 2048,
    publicKeyEncoding: {
      type: "spki",
      format: "pem",
    },
    privateKeyEncoding: {
      type: "pkcs8",
      format: "pem",
    },
  });
}

function encryptWithPublicKey(publicKey, data) {
  const encryptedData = crypto.publicEncrypt(
    {
      key: publicKey,
      padding: crypto.constants.RSA_PKCS1_OAEP_PADDING,
    },
    Buffer.from(data)
  );
  return encryptedData;
}

function decryptWithPrivateKey(privateKey, encryptedData) {
  // Convert to Buffer if we received a hex string or Uint8Array
  if (typeof encryptedData === "string") {
    // Strip 0x prefix (if present) and convert from hex
    const hex = encryptedData.startsWith("0x")
      ? encryptedData.slice(2)
      : encryptedData;
    encryptedData = Buffer.from(hex, "hex");
  } else if (
    encryptedData instanceof Uint8Array &&
    !(encryptedData instanceof Buffer)
  ) {
    encryptedData = Buffer.from(encryptedData);
  } else if (Array.isArray(encryptedData)) {
    // Handle array of numbers returned from blockchain
    encryptedData = Buffer.from(encryptedData.map((n) => Number(n)));
  }

  try {
    const decryptedData = crypto.privateDecrypt(
      {
        key: privateKey,
        padding: crypto.constants.RSA_PKCS1_OAEP_PADDING,
      },
      encryptedData
    );
    return decryptedData.toString();
  } catch (error) {
    console.error("Decryption error:", error.message);
    console.error("Encrypted data type:", typeof encryptedData);
    console.error("Encrypted data length:", encryptedData.length);
    throw error;
  }
}

describe("SharedSubscriptionToken", function () {
  let sharedSubscriptionToken;
  let subscriptionVoting;
  let subscriptionServiceProvider;
  let owner, user1, user2, user3, user4, user5, user6;
  const serviceId1 = 1; // Netflix
  const serviceId2 = 2; // Spotify
  const tokenPrice = hre.ethers.parseEther("0.01"); // 0.01 ETH per token
  const serviceCost = hre.ethers.parseEther("10"); // 10 ETH for service

  // Store key pairs for testing
  const keyPairs = {};

  beforeEach(async function () {
    [owner, user1, user2, user3, user4, user5, user6] =
      await hre.ethers.getSigners();

    // Deploy the service provider contract
    const SubscriptionServiceProvider = await hre.ethers.getContractFactory(
      "SubscriptionServiceProvider",
      owner
    );
    subscriptionServiceProvider = await SubscriptionServiceProvider.deploy();
    await subscriptionServiceProvider.waitForDeployment();

    // Deploy the main subscription token contract
    const SharedSubscriptionToken = await hre.ethers.getContractFactory(
      "SharedSubscriptionToken",
      owner
    );
    sharedSubscriptionToken = await SharedSubscriptionToken.deploy();
    await sharedSubscriptionToken.waitForDeployment();

    // Deploy the voting contract with the main contract address
    const SubscriptionVoting = await hre.ethers.getContractFactory(
      "SubscriptionVoting",
      owner
    );
    subscriptionVoting = await SubscriptionVoting.deploy(
      await sharedSubscriptionToken.getAddress()
    );
    await subscriptionVoting.waitForDeployment();

    // Set the voting contract address in the main contract
    await sharedSubscriptionToken
      .connect(owner)
      .setVotingContractAddress(await subscriptionVoting.getAddress());

    // Set the service provider address in the main contract
    await sharedSubscriptionToken
      .connect(owner)
      .setServiceProviderAddress(
        await subscriptionServiceProvider.getAddress()
      );

    // Set the token contract address in the service provider contract
    await subscriptionServiceProvider
      .connect(owner)
      .setTokenContractAddress(await sharedSubscriptionToken.getAddress());

    // Add services to the service provider
    await subscriptionServiceProvider
      .connect(owner)
      .addService(
        serviceId1,
        "NFLX",
        serviceCost,
        "https://api.netflix.example.com"
      );
    await subscriptionServiceProvider
      .connect(owner)
      .addService(
        serviceId2,
        "SPTFY",
        serviceCost,
        "https://api.spotify.example.com"
      );
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

    // Then subscribe (need to include payment for service provider)
    await sharedSubscriptionToken
      .connect(user1)
      .subscribe(serviceId1, { value: serviceCost });

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

    // Check if service provider registered subscription
    const isSubscribedInProvider =
      await subscriptionServiceProvider.isSubscribed(serviceId1, user1.address);
    expect(isSubscribedInProvider).to.be.true;
  });

  it("Should create new subscription account when first user subscribes", async function () {
    // Buy tokens and subscribe
    await sharedSubscriptionToken
      .connect(user1)
      .buyTokens(1, { value: tokenPrice });
    await sharedSubscriptionToken
      .connect(user1)
      .subscribe(serviceId1, { value: serviceCost });

    // Get user's subscription details
    const [exists, accountId] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user1.address,
        serviceId1
      );

    expect(exists).to.be.true;
    expect(accountId).to.equal(1); // First account should have ID 1

    // Get subscription count
    const subscriptionCount = await sharedSubscriptionToken.subscriptionCounts(
      serviceId1
    );
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

      // First user needs to pay for service
      if (i === 0) {
        await sharedSubscriptionToken
          .connect(user)
          .subscribe(serviceId1, { value: serviceCost });
      } else {
        // Subsequent users only need to spend token
        await sharedSubscriptionToken.connect(user).subscribe(serviceId1);
      }
    }

    // Check all users are part of the same subscription account
    const [exists1, accountId1] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user1.address,
        serviceId1
      );
    const [exists2, accountId2] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user2.address,
        serviceId1
      );
    const [exists3, accountId3] =
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

      // First and fourth users need to pay for service (for their respective accounts)
      if (i === 0 || i === 3) {
        await sharedSubscriptionToken
          .connect(user)
          .subscribe(serviceId1, { value: serviceCost });
      } else {
        // Other users only need to spend token
        await sharedSubscriptionToken.connect(user).subscribe(serviceId1);
      }
    }

    // Get account IDs
    const [exists1, accountId1] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user1.address,
        serviceId1
      );
    const [exists4, accountId4] =
      await sharedSubscriptionToken.getUserSubscriptionDetails(
        user4.address,
        serviceId1
      );

    // Fourth user should be in a different account
    expect(accountId1).to.not.equal(accountId4);

    // Check subscription count
    const subscriptionCount = await sharedSubscriptionToken.subscriptionCounts(
      serviceId1
    );
    expect(subscriptionCount).to.equal(2); // Should have created 2 accounts
  });

  it("Should calculate cost per member correctly", async function () {
    // First add 3 users to a subscription
    for (let i = 0; i < 3; i++) {
      const user = [user1, user2, user3][i];
      await sharedSubscriptionToken
        .connect(user)
        .buyTokens(1, { value: tokenPrice });

      // First user needs to pay for service
      if (i === 0) {
        await sharedSubscriptionToken
          .connect(user)
          .subscribe(serviceId1, { value: serviceCost });
      } else {
        // Subsequent users only need to spend token
        await sharedSubscriptionToken.connect(user).subscribe(serviceId1);
      }
    }

    // Get the account ID they're all part of
    const [exists, accountId] =
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
    const serviceDetails = await subscriptionServiceProvider.getServiceDetails(
      serviceId1
    );
    const cost = serviceDetails[1]; // cost is the second item in the tuple

    // Fix: Account for integer division rounding in Solidity
    // When 10 ether is divided by 3, and then multiplied by 3 again,
    // there might be a rounding error of 1 wei due to integer division
    const costPerMember = event.args[3];
    const totalCostAfterDivision = costPerMember * BigInt(3);

    console.log("Original service cost:", cost.toString());
    console.log("Cost per member:", costPerMember.toString());
    console.log("Cost per member * 3:", totalCostAfterDivision.toString());

    // Check the difference is very small (due to integer division rounding)
    const difference = cost - totalCostAfterDivision;
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
    await sharedSubscriptionToken
      .connect(user1)
      .subscribe(serviceId1, { value: serviceCost });

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

    // Need to update subscription status
    await sharedSubscriptionToken
      .connect(owner)
      .updateSubscriptionStatus(user1.address, serviceId1);

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
    await sharedSubscriptionToken
      .connect(user1)
      .subscribe(serviceId1, { value: serviceCost });

    // Advance time close to expiration
    await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24 * 25]); // Advance 25 days
    await hre.ethers.provider.send("evm_mine");

    // Renew subscription
    await sharedSubscriptionToken
      .connect(user1)
      .renewSubscription(serviceId1, { value: serviceCost });

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

  // New test suite for public key encryption system
  describe("Public Key Encryption System", function () {
    beforeEach(async function () {
      // Generate key pairs for test users
      for (const user of [user1, user2, user3]) {
        keyPairs[user.address] = generateKeyPair();
      }

      // Users buy tokens and subscribe
      for (let i = 0; i < 3; i++) {
        const user = [user1, user2, user3][i];
        await sharedSubscriptionToken
          .connect(user)
          .buyTokens(1, { value: tokenPrice });

        // First user needs to pay for service
        if (i === 0) {
          await sharedSubscriptionToken
            .connect(user)
            .subscribe(serviceId1, { value: serviceCost });
        } else {
          // Subsequent users only need to spend token
          await sharedSubscriptionToken.connect(user).subscribe(serviceId1);
        }

        // Ensure all users are registered in the service provider
        if (i > 0) {
          await subscriptionServiceProvider
            .connect(owner)
            .manuallyRegisterSubscriber(serviceId1, user.address);
        }
      }
    });

    it("Should allow users to register public keys", async function () {
      // User1 registers their public key
      await sharedSubscriptionToken
        .connect(user1)
        .registerPublicKey(keyPairs[user1.address].publicKey);

      // Verify the public key was stored correctly
      const storedPublicKey = await sharedSubscriptionToken.getPublicKey(
        user1.address
      );
      expect(storedPublicKey).to.equal(keyPairs[user1.address].publicKey);
    });

    it("Should allow owner to store encrypted credentials for users", async function () {
      // User1 registers their public key
      await sharedSubscriptionToken
        .connect(user1)
        .registerPublicKey(keyPairs[user1.address].publicKey);

      // Service credentials to share
      const serviceCredentials = {
        username: "netflix_user123",
        password: "securePassword!456",
      };

      // Owner encrypts credentials with user's public key
      const credentialsString = JSON.stringify(serviceCredentials);
      const encryptedData = encryptWithPublicKey(
        keyPairs[user1.address].publicKey,
        credentialsString
      );

      // Owner stores the encrypted credentials on-chain
      await sharedSubscriptionToken
        .connect(owner)
        .storeEncryptedCredentials(user1.address, serviceId1, encryptedData);

      // User retrieves their encrypted credentials
      const retrievedData = await sharedSubscriptionToken
        .connect(user1)
        .getEncryptedCredentials(serviceId1);

      // Decrypt retrieved data
      const decryptedData = decryptWithPrivateKey(
        keyPairs[user1.address].privateKey,
        retrievedData
      );

      // Verify decrypted data matches original credentials
      const decryptedCredentials = JSON.parse(decryptedData);
      expect(decryptedCredentials.username).to.equal(
        serviceCredentials.username
      );
      expect(decryptedCredentials.password).to.equal(
        serviceCredentials.password
      );
    });

    it("Should store different credentials for each user", async function () {
      // All users register their public keys
      for (const user of [user1, user2, user3]) {
        await sharedSubscriptionToken
          .connect(user)
          .registerPublicKey(keyPairs[user.address].publicKey);
      }

      // Define custom profiles for each user
      const profiles = {
        [user1.address]: { username: "netflix_main", profile: "Profile 1" },
        [user2.address]: { username: "netflix_main", profile: "Profile 2" },
        [user3.address]: { username: "netflix_main", profile: "Profile 3" },
      };

      // Shared password
      const sharedPassword = "AccountPassword123!";

      // Owner stores customized credentials for each user
      for (const user of [user1, user2, user3]) {
        const userData = {
          ...profiles[user.address],
          password: sharedPassword,
        };

        const credentialsString = JSON.stringify(userData);
        const encryptedData = encryptWithPublicKey(
          keyPairs[user.address].publicKey,
          credentialsString
        );

        await sharedSubscriptionToken
          .connect(owner)
          .storeEncryptedCredentials(user.address, serviceId1, encryptedData);
      }

      // Each user retrieves and decrypts their credentials
      for (const user of [user1, user2, user3]) {
        const retrievedData = await sharedSubscriptionToken
          .connect(user)
          .getEncryptedCredentials(serviceId1);

        const decryptedData = decryptWithPrivateKey(
          keyPairs[user.address].privateKey,
          retrievedData
        );

        const decryptedCredentials = JSON.parse(decryptedData);

        // Verify the profile-specific information is correct
        expect(decryptedCredentials.username).to.equal(
          profiles[user.address].username
        );
        expect(decryptedCredentials.profile).to.equal(
          profiles[user.address].profile
        );
        expect(decryptedCredentials.password).to.equal(sharedPassword);
      }
    });

    it("Should prevent accessing credentials after subscription expires", async function () {
      // User registers public key
      await sharedSubscriptionToken
        .connect(user1)
        .registerPublicKey(keyPairs[user1.address].publicKey);

      // Owner stores credentials
      const credentials = { username: "test_user", password: "test_password" };
      const encryptedData = encryptWithPublicKey(
        keyPairs[user1.address].publicKey,
        JSON.stringify(credentials)
      );

      await sharedSubscriptionToken
        .connect(owner)
        .storeEncryptedCredentials(user1.address, serviceId1, encryptedData);

      // Fast-forward time beyond subscription period
      await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 24 * 31]); // 31 days
      await hre.ethers.provider.send("evm_mine");

      // Update subscription status
      await sharedSubscriptionToken
        .connect(owner)
        .updateSubscriptionStatus(user1.address, serviceId1);

      // Attempt to retrieve credentials (should fail)
      await expect(
        sharedSubscriptionToken
          .connect(user1)
          .getEncryptedCredentials(serviceId1)
      ).to.be.revertedWith("Subscription has expired");
    });

    it("Should not allow owner to store credentials for user without public key", async function () {
      // User subscribes but doesn't register public key

      // Owner tries to store credentials
      const dummyData = Buffer.from("test data");

      await expect(
        sharedSubscriptionToken
          .connect(owner)
          .storeEncryptedCredentials(user1.address, serviceId1, dummyData)
      ).to.be.revertedWith("User has not registered a public key");
    });

    it("Should not allow non-owner to store credentials for others", async function () {
      // User1 registers public key
      await sharedSubscriptionToken
        .connect(user1)
        .registerPublicKey(keyPairs[user1.address].publicKey);

      // User2 tries to store credentials for User1 (should fail)
      const dummyData = Buffer.from("test data");

      await expect(
        sharedSubscriptionToken
          .connect(user2)
          .storeEncryptedCredentials(user1.address, serviceId1, dummyData)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  // Updated Voting System tests for the new contract structure
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

        // First user needs to pay for service
        if (i === 0) {
          await sharedSubscriptionToken
            .connect(user)
            .subscribe(serviceId1, { value: serviceCost });
        } else {
          // Subsequent users only need to spend token
          await sharedSubscriptionToken.connect(user).subscribe(serviceId1);
        }
      }
    });

    it("Should allow creating a proposal to kick a user", async function () {
      // Get the account ID for User1
      const [exists, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user1.address,
          serviceId1
        );

      // User1 proposes to kick User5
      await subscriptionVoting
        .connect(user1)
        .proposeToKickUser(serviceId1, accountId, user5.address);

      // Get the proposal count
      const proposalCount = await subscriptionVoting.proposalCount();
      expect(proposalCount).to.equal(1);

      // Get proposal details using the getter function
      const proposal = await subscriptionVoting.getProposal(1);

      // Verify the proposal details
      expect(proposal[0]).to.equal(user1.address); // proposer
      expect(proposal[1]).to.equal(user5.address); // userToKick
      expect(proposal[2]).to.equal(serviceId1); // serviceId
      expect(proposal[3]).to.equal(accountId); // accountId
    });

    it("Should execute successful kick proposal", async function () {
      // Get the account ID for User1
      const [exists, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user1.address,
          serviceId1
        );

      // User1 proposes to kick User5
      await subscriptionVoting
        .connect(user1)
        .proposeToKickUser(serviceId1, accountId, user5.address);

      // Other users vote "yes" to kick User5
      await subscriptionVoting.connect(user2).voteOnProposal(1, true);
      await subscriptionVoting.connect(user3).voteOnProposal(1, true);
      await subscriptionVoting.connect(user4).voteOnProposal(1, true);

      // Fast-forward time by 25 hours (beyond the voting period of 24 hours)
      await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 25]);
      await hre.ethers.provider.send("evm_mine");

      // Execute the proposal
      await subscriptionVoting.connect(user4).executeProposal(1);

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

      // Verify that User5's subscription was canceled in the service provider
      const isSubscribedInProvider =
        await subscriptionServiceProvider.isSubscribed(
          serviceId1,
          user5.address
        );
      expect(isSubscribedInProvider).to.be.false;
    });

    it("Should prevent double voting", async function () {
      // Get the account ID for User1
      const [exists, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user1.address,
          serviceId1
        );

      // User1 proposes to kick User5
      await subscriptionVoting
        .connect(user1)
        .proposeToKickUser(serviceId1, accountId, user5.address);

      // User2 votes "yes"
      await subscriptionVoting.connect(user2).voteOnProposal(1, true);

      // Attempt to vote again as User2 (should fail)
      await expect(
        subscriptionVoting.connect(user2).voteOnProposal(1, true)
      ).to.be.revertedWith("Already voted");
    });

    it("Should not allow a non-member to propose or vote", async function () {
      // Get the account ID for User1
      const [exists, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user1.address,
          serviceId1
        );

      // Attempt to propose as a non-member (User6)
      await expect(
        subscriptionVoting
          .connect(user6)
          .proposeToKickUser(serviceId1, accountId, user5.address)
      ).to.be.revertedWith("Not a member");

      // Have a valid user create a proposal first
      await subscriptionVoting
        .connect(user1)
        .proposeToKickUser(serviceId1, accountId, user5.address);

      // Attempt to vote as a non-member (User6)
      await expect(
        subscriptionVoting.connect(user6).voteOnProposal(1, true)
      ).to.be.revertedWith("Not a member");
    });

    it("Should not allow a user to propose themselves for removal", async function () {
      // Get the account ID for User3
      const [exists, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user3.address,
          serviceId1
        );

      // Attempt to propose themselves for removal
      await expect(
        subscriptionVoting
          .connect(user3)
          .proposeToKickUser(serviceId1, accountId, user3.address)
      ).to.be.revertedWith("Cannot propose yourself");
    });

    it("Should not allow voting after the voting period has ended", async function () {
      // Get the account ID for User4
      const [exists, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user4.address,
          serviceId1
        );

      // User4 proposes to kick User3
      await subscriptionVoting
        .connect(user4)
        .proposeToKickUser(serviceId1, accountId, user3.address);

      // Fast-forward time by more than the voting period (25 hours)
      await hre.ethers.provider.send("evm_increaseTime", [60 * 60 * 25]);
      await hre.ethers.provider.send("evm_mine");

      // Attempt to vote after the voting period has ended (should fail)
      await expect(
        subscriptionVoting.connect(user2).voteOnProposal(1, true)
      ).to.be.revertedWith("Voting period ended");
    });
  });

  // New tests for subscription service provider
  describe("SubscriptionServiceProvider", function () {
    beforeEach(async function () {
      // User1 buys tokens and subscribes
      await sharedSubscriptionToken
        .connect(user1)
        .buyTokens(1, { value: tokenPrice });
      await sharedSubscriptionToken
        .connect(user1)
        .subscribe(serviceId1, { value: serviceCost });
    });

    it("Should process payments correctly", async function () {
      // Check that the payment was received by the service provider
      const providerBalance = await hre.ethers.provider.getBalance(
        await subscriptionServiceProvider.getAddress()
      );
      expect(providerBalance).to.equal(serviceCost);
    });

    it("Should allow service provider to withdraw funds", async function () {
      const initialPaymentReceiverBalance =
        await hre.ethers.provider.getBalance(owner.address);

      // Withdraw funds from service provider
      const tx = await subscriptionServiceProvider
        .connect(owner)
        .withdrawFunds();
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;

      // Check balances after withdrawal
      const finalProviderBalance = await hre.ethers.provider.getBalance(
        await subscriptionServiceProvider.getAddress()
      );
      const finalPaymentReceiverBalance = await hre.ethers.provider.getBalance(
        owner.address
      );

      expect(finalProviderBalance).to.equal(0);
      expect(finalPaymentReceiverBalance).to.be.closeTo(
        initialPaymentReceiverBalance + serviceCost - gasUsed,
        hre.ethers.parseEther("0.0001") // Allow for small gas calculation differences
      );
    });

    it("Should allow updating service costs", async function () {
      const newCost = hre.ethers.parseEther("15"); // 15 ETH

      // Update the cost
      await subscriptionServiceProvider
        .connect(owner)
        .updateServiceCost(serviceId1, newCost);

      // Get the updated service details
      const serviceDetails =
        await subscriptionServiceProvider.getServiceDetails(serviceId1);
      const updatedCost = serviceDetails[1]; // cost is the second item in the tuple

      expect(updatedCost).to.equal(newCost);
    });

    it("Should allow setting a different payment receiver", async function () {
      // Set user6 as the payment receiver
      await subscriptionServiceProvider
        .connect(owner)
        .setPaymentReceiver(user6.address);

      // Verify the payment receiver was updated
      const newPaymentReceiver =
        await subscriptionServiceProvider.paymentReceiver();
      expect(newPaymentReceiver).to.equal(user6.address);

      // Subscribe with a new user to generate payments
      await sharedSubscriptionToken
        .connect(user2)
        .buyTokens(1, { value: tokenPrice });

      const initialUser6Balance = await hre.ethers.provider.getBalance(
        user6.address
      );

      // User2 subscribes to serviceId2, which will send payment to the provider
      await sharedSubscriptionToken
        .connect(user2)
        .subscribe(serviceId2, { value: serviceCost });

      // Now withdraw funds to user6
      await subscriptionServiceProvider.connect(owner).withdrawFunds();

      // Check the final balance - there should be the sum of serviceCosts in the balance now
      const finalUser6Balance = await hre.ethers.provider.getBalance(
        user6.address
      );

      // Check that the total service cost (20 ETH) was transferred
      expect(finalUser6Balance - initialUser6Balance).to.equal(
        serviceCost * BigInt(2)
      );
    });

    it("Should handle API credentials management", async function () {
      // Generate key pair for test user
      keyPairs[user1.address] = generateKeyPair();

      // User1 registers their public key
      await sharedSubscriptionToken
        .connect(user1)
        .registerPublicKey(keyPairs[user1.address].publicKey);

      // Mock API credentials with endpoint information
      const apiCredentials = {
        username: "user123",
        password: "pass456",
        apiKey: "sk_live_testKey1234567890",
        endpoint: "https://api.netflix.example.com/v1/stream",
      };

      // Encrypt credentials
      const credentialsString = JSON.stringify(apiCredentials);
      const encryptedData = encryptWithPublicKey(
        keyPairs[user1.address].publicKey,
        credentialsString
      );

      // Store credentials
      await sharedSubscriptionToken
        .connect(owner)
        .storeEncryptedCredentials(user1.address, serviceId1, encryptedData);

      // Retrieve credentials
      const retrievedData = await sharedSubscriptionToken
        .connect(user1)
        .getEncryptedCredentials(serviceId1);

      // Decrypt the credentials
      const decryptedData = decryptWithPrivateKey(
        keyPairs[user1.address].privateKey,
        retrievedData
      );

      // Verify credentials were correctly stored and retrieved
      const decryptedCredentials = JSON.parse(decryptedData);
      expect(decryptedCredentials.username).to.equal(apiCredentials.username);
      expect(decryptedCredentials.password).to.equal(apiCredentials.password);
      expect(decryptedCredentials.apiKey).to.equal(apiCredentials.apiKey);
      expect(decryptedCredentials.endpoint).to.equal(apiCredentials.endpoint);
    });
  });

  // Security tests for reentrancy
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

  // Contract integration tests
  describe("Contract Integration", function () {
    it("Should only allow voting contract to kick users", async function () {
      // Setup users
      for (let i = 0; i < 3; i++) {
        const user = [user1, user2, user3][i];
        await sharedSubscriptionToken
          .connect(user)
          .buyTokens(1, { value: tokenPrice });

        // First user needs to pay for service
        if (i === 0) {
          await sharedSubscriptionToken
            .connect(user)
            .subscribe(serviceId1, { value: serviceCost });
        } else {
          // Subsequent users only need to spend token
          await sharedSubscriptionToken.connect(user).subscribe(serviceId1);
        }
      }

      // Get account ID
      const [exists, accountId] =
        await sharedSubscriptionToken.getUserSubscriptionDetails(
          user1.address,
          serviceId1
        );

      // Try to kick a user directly (should fail)
      await expect(
        sharedSubscriptionToken
          .connect(owner)
          .kickUser(serviceId1, accountId, user3.address)
      ).to.be.revertedWith("Only voting contract can call this function");
    });

    it("Should ensure service provider only accepts calls from token contract", async function () {
      // Try to directly cancel a subscription through the service provider (should fail)
      await expect(
        subscriptionServiceProvider
          .connect(owner)
          .cancelSubscription(user1.address, serviceId1)
      ).to.be.reverted; // Will revert with the Unauthorized error
    });
  });
});
