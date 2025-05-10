// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISharedSubscriptionToken {
    function isMemberOfAccount(address user, uint256 serviceId, uint256 accountId) external view returns (bool);
    function kickUser(uint256 serviceId, uint256 accountId, address userToKick) external;
    function getSubscriptionMembers(uint256 serviceId, uint256 accountId) external view returns (address[] memory);
}

/**
 * @title SubscriptionVoting
 * @dev A contract that handles voting functionality for SharedSubscriptionToken
 */
contract SubscriptionVoting {
    address public owner;
    ISharedSubscriptionToken public subscriptionToken;
    
    // Rate limiting for proposals
    mapping(address => uint256) public lastProposalTime;
    
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
    
    // Mapping: proposalId => Proposal
    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    
    // Events
    event ProposalCreated(
        uint256 proposalId,
        uint256 serviceId,
        uint256 accountId,
        address proposer,
        address userToKick
    );
    event VoteCast(
        uint256 proposalId,
        uint256 serviceId,
        uint256 accountId,
        address voter,
        bool vote
    );
    event ProposalExecuted(
        uint256 proposalId,
        uint256 serviceId,
        uint256 accountId,
        address kickedUser,
        bool successful
    );
    
    // Errors
    error VotingPeriodEnded();
    error AlreadyVoted();
    error NotMember();
    error ProposalAlreadyExecuted();
    
    constructor(address _subscriptionTokenAddress) {
        owner = msg.sender;
        subscriptionToken = ISharedSubscriptionToken(_subscriptionTokenAddress);
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }
    
    // Create a proposal to kick a user from a subscription account
    function proposeToKickUser(
        uint256 serviceId,
        uint256 accountId,
        address userToKick
    ) external returns (uint256) {
        // Check if caller is a member of the subscription account
        require(subscriptionToken.isMemberOfAccount(msg.sender, serviceId, accountId), "Not a member");
        require(subscriptionToken.isMemberOfAccount(userToKick, serviceId, accountId), "User not in this account");
        require(userToKick != msg.sender, "Cannot propose yourself");
        
        // Rate limiting: Ensure the user waits at least 12 hours between proposals
        require(
            block.timestamp > lastProposalTime[msg.sender] + 12 hours,
            "Wait before proposing again"
        );
        
        lastProposalTime[msg.sender] = block.timestamp;
        
        uint256 proposalId = ++proposalCount;
        Proposal storage proposal = proposals[proposalId];
        
        proposal.proposer = msg.sender;
        proposal.userToKick = userToKick;
        proposal.serviceId = serviceId;
        proposal.accountId = accountId;
        proposal.endTime = block.timestamp + 1 days;
        proposal.executed = false;
        
        emit ProposalCreated(proposalId, serviceId, accountId, msg.sender, userToKick);
        
        return proposalId;
    }
    
    // Vote on a proposal
    function voteOnProposal(
        uint256 proposalId,
        bool vote
    ) external {
        Proposal storage proposal = proposals[proposalId];
        
        require(block.timestamp <= proposal.endTime, "Voting period ended");
        require(!proposal.executed, "Proposal already executed");
        require(subscriptionToken.isMemberOfAccount(msg.sender, proposal.serviceId, proposal.accountId), "Not a member");
        require(msg.sender != proposal.userToKick, "Cannot vote on your own kick");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        
        proposal.hasVoted[msg.sender] = true;
        if (vote) {
            proposal.yesVotes += 1;
        } else {
            proposal.noVotes += 1;
        }
        
        emit VoteCast(proposalId, proposal.serviceId, proposal.accountId, msg.sender, vote);
    }
    
    // Execute a proposal after voting period ends
    function executeProposal(
        uint256 proposalId
    ) external {
        Proposal storage proposal = proposals[proposalId];
        
        if (block.timestamp <= proposal.endTime) revert VotingPeriodEnded();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        
        // Mark as executed to prevent re-execution
        proposal.executed = true;
        
        // Get total member count
        address[] memory members = subscriptionToken.getSubscriptionMembers(proposal.serviceId, proposal.accountId);
        require(members.length >= 2, "Not enough members to execute proposal");
        
        uint256 totalMembers = members.length - 1; // Exclude userToKick
        uint256 requiredVotes = (totalMembers / 2) + 1;
        
        bool successful = false;
        
        if (proposal.yesVotes >= requiredVotes) {
            // Verify user is still a member before kicking
            if (subscriptionToken.isMemberOfAccount(proposal.userToKick, proposal.serviceId, proposal.accountId)) {
                // Call the main contract to remove the user
                subscriptionToken.kickUser(proposal.serviceId, proposal.accountId, proposal.userToKick);
                successful = true;
            }
        }
        
        emit ProposalExecuted(proposalId, proposal.serviceId, proposal.accountId, proposal.userToKick, successful);
    }
    
    // Get proposal details
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
    
    // Check if a user has voted on a proposal
    function hasVoted(uint256 proposalId, address user) external view returns (bool) {
        return proposals[proposalId].hasVoted[user];
    }
    
    // Update subscription token address (in case of contract upgrades)
    function updateSubscriptionTokenAddress(address _newAddress) external onlyOwner {
        subscriptionToken = ISharedSubscriptionToken(_newAddress);
    }
}