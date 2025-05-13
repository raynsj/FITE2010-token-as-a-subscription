// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev Interface for interacting with the SharedSubscriptionToken contract
 */
interface ISharedSubscriptionToken {
    function isMemberOfAccount(address user, uint256 serviceId, uint256 accountId) external view returns (bool);
    function kickUser(uint256 serviceId, uint256 accountId, address userToKick) external;
    function getSubscriptionMembers(uint256 serviceId, uint256 accountId) external view returns (address[] memory);
}

/**
 * @title SubscriptionVoting
 * @dev A contract that handles decentralized governance for SharedSubscriptionToken
 * Members of a subscription can propose and vote on removing other members
 * This implementation uses a simple majority vote mechanism with time-based cooldowns
 */
contract SubscriptionVoting {
    // Contract owner address
    address public owner;
    
    // Reference to the main subscription token contract
    ISharedSubscriptionToken public subscriptionToken;
    
    // Rate limiting for proposals - maps user address to timestamp of their last proposal
    mapping(address => uint256) public lastProposalTime;
    
    /**
     * @dev Information about a proposal to kick a user
     * @param proposer Address that created the proposal
     * @param userToKick Address of the user to be potentially kicked
     * @param serviceId ID of the service
     * @param accountId ID of the subscription account
     * @param yesVotes Number of votes in favor of kicking
     * @param noVotes Number of votes against kicking
     * @param endTime Timestamp when voting ends
     * @param executed Whether the proposal has been executed
     * @param hasVoted Mapping of addresses to whether they've voted
     */
    struct Proposal {
        address proposer;
        address userToKick;
        uint256 serviceId;
        uint256 accountId;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 endTime;
        bool executed;
        mapping(address => bool) hasVoted;
    }
    
    // Mapping of proposal ID to proposal details
    mapping(uint256 => Proposal) public proposals;
    
    // Total number of proposals created
    uint256 public proposalCount;
    
    // ==================== EVENTS ====================
    
    // Emitted when a new proposal is created
    event ProposalCreated(
        uint256 proposalId,
        uint256 serviceId,
        uint256 accountId,
        address proposer,
        address userToKick
    );
    
    // Emitted when a vote is cast on a proposal
    event VoteCast(
        uint256 proposalId,
        uint256 serviceId,
        uint256 accountId,
        address voter,
        bool vote
    );
    
    // Emitted when a proposal is executed
    event ProposalExecuted(
        uint256 proposalId,
        uint256 serviceId,
        uint256 accountId,
        address kickedUser,
        bool successful
    );
    
    // ==================== ERRORS ====================
    
    // Error for when a vote is attempted after voting period is over
    error VotingPeriodEnded();
    
    // Error for when a user tries to vote twice
    error AlreadyVoted();
    
    // Error for when a non-member tries to participate
    error NotMember();
    
    // Error for when a proposal has already been executed
    error ProposalAlreadyExecuted();
    
    /**
     * @dev Constructor function
     * @param _subscriptionTokenAddress Address of the SharedSubscriptionToken contract
     */
    constructor(address _subscriptionTokenAddress) {
        owner = msg.sender;
        subscriptionToken = ISharedSubscriptionToken(_subscriptionTokenAddress);
    }
    
    /**
     * @dev Restricts function access to the contract owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }
    
    // ==================== PROPOSAL FUNCTIONS ====================
    
    /**
     * @dev Creates a proposal to kick a user from a subscription account
     * @param serviceId ID of the service
     * @param accountId ID of the subscription account
     * @param userToKick Address of the user to potentially kick
     * @return ID of the newly created proposal
     */
    function proposeToKickUser(
        uint256 serviceId,
        uint256 accountId,
        address userToKick
    ) external returns (uint256) {
        // Verify the caller is a member of the account
        require(subscriptionToken.isMemberOfAccount(msg.sender, serviceId, accountId), "Not a member");
        
        // Verify the user to kick is a member of the account
        require(subscriptionToken.isMemberOfAccount(userToKick, serviceId, accountId), "User not in this account");
        
        // Prevent users from proposing to kick themselves
        require(userToKick != msg.sender, "Cannot propose yourself");
        
        // Rate limiting: Ensure the user waits at least 12 hours between proposals
        require(
            block.timestamp > lastProposalTime[msg.sender] + 12 hours,
            "Wait before proposing again"
        );
        
        // Update the user's last proposal time
        lastProposalTime[msg.sender] = block.timestamp;
        
        // Create new proposal
        uint256 proposalId = ++proposalCount;
        Proposal storage proposal = proposals[proposalId];
        
        proposal.proposer = msg.sender;
        proposal.userToKick = userToKick;
        proposal.serviceId = serviceId;
        proposal.accountId = accountId;
        proposal.endTime = block.timestamp + 1 days; // Voting period of 1 day
        proposal.executed = false;
        
        emit ProposalCreated(proposalId, serviceId, accountId, msg.sender, userToKick);
        
        return proposalId;
    }
    
    /**
     * @dev Allows a member to vote on a proposal
     * @param proposalId ID of the proposal
     * @param vote True for yes (kick), False for no (don't kick)
     */
    function voteOnProposal(
        uint256 proposalId,
        bool vote
    ) external {
        Proposal storage proposal = proposals[proposalId];
        
        // Check if voting period is still active
        require(block.timestamp <= proposal.endTime, "Voting period ended");
        
        // Check if proposal has already been executed
        require(!proposal.executed, "Proposal already executed");
        
        // Verify voter is a member of the account
        require(subscriptionToken.isMemberOfAccount(msg.sender, proposal.serviceId, proposal.accountId), "Not a member");
        
        // The user to be kicked cannot vote on their own removal
        require(msg.sender != proposal.userToKick, "Cannot vote on your own kick");
        
        // Prevent double voting
        require(!proposal.hasVoted[msg.sender], "Already voted");
        
        // Record the vote
        proposal.hasVoted[msg.sender] = true;
        if (vote) {
            proposal.yesVotes += 1;
        } else {
            proposal.noVotes += 1;
        }
        
        emit VoteCast(proposalId, proposal.serviceId, proposal.accountId, msg.sender, vote);
    }
    
    /**
     * @dev Executes a proposal after the voting period ends
     * If the proposal passes (majority vote), the user is kicked from the subscription
     * @param proposalId ID of the proposal to execute
     */
    function executeProposal(
        uint256 proposalId
    ) external {
        Proposal storage proposal = proposals[proposalId];
        
        // Ensure voting period has ended
        if (block.timestamp <= proposal.endTime) revert VotingPeriodEnded();
        
        // Ensure proposal hasn't already been executed
        if (proposal.executed) revert ProposalAlreadyExecuted();
        
        // Mark as executed to prevent re-execution
        proposal.executed = true;
        
        // Get total member count
        address[] memory members = subscriptionToken.getSubscriptionMembers(proposal.serviceId, proposal.accountId);
        require(members.length >= 2, "Not enough members to execute proposal");
        
        // Calculate required votes for majority (excluding the user to kick)
        uint256 totalMembers = members.length - 1;
        uint256 requiredVotes = (totalMembers / 2) + 1;
        
        bool successful = false;
        
        // Check if proposal passed
        if (proposal.yesVotes >= requiredVotes) {
            // Verify user is still a member before kicking (they might have left already)
            if (subscriptionToken.isMemberOfAccount(proposal.userToKick, proposal.serviceId, proposal.accountId)) {
                // Call the main contract to remove the user
                subscriptionToken.kickUser(proposal.serviceId, proposal.accountId, proposal.userToKick);
                successful = true;
            }
        }
        
        emit ProposalExecuted(proposalId, proposal.serviceId, proposal.accountId, proposal.userToKick, successful);
    }
    
    // ==================== VIEW FUNCTIONS ====================
    
    /**
     * @dev Gets details about a proposal
     * @param proposalId ID of the proposal
     * @return proposer Address that created the proposal
     * @return userToKick Address of the user to be potentially kicked
     * @return serviceId ID of the service
     * @return accountId ID of the subscription account
     * @return yesVotes Number of votes in favor of kicking
     * @return noVotes Number of votes against kicking
     * @return endTime Timestamp when voting ends
     * @return executed Whether the proposal has been executed
     */
    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address proposer,
            address userToKick,
            uint256 serviceId,
            uint256 accountId,
            uint256 yesVotes,
            uint256 noVotes,
            uint256 endTime,
            bool executed
        )
    {
        Proposal storage proposal = proposals[proposalId];
        
        return (
            proposal.proposer,
            proposal.userToKick,
            proposal.serviceId,
            proposal.accountId,
            proposal.yesVotes,
            proposal.noVotes,
            proposal.endTime,
            proposal.executed
        );
    }
    
    /**
     * @dev Checks if a user has voted on a specific proposal
     * @param proposalId ID of the proposal
     * @param user Address of the user
     * @return Whether the user has voted
     */
    function hasVoted(uint256 proposalId, address user) external view returns (bool) {
        return proposals[proposalId].hasVoted[user];
    }
    
    // ==================== ADMIN FUNCTIONS ====================
    
    /**
     * @dev Updates the subscription token contract address
     * Useful in case of contract upgrades or migrations
     * @param _newAddress Address of the new subscription token contract
     */
    function updateSubscriptionTokenAddress(address _newAddress) external onlyOwner {
        subscriptionToken = ISharedSubscriptionToken(_newAddress);
    }
}