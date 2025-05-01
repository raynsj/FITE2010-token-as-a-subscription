// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EncryptionSystem.sol";

/**
 * @title VotingSystem
 * @dev Handles governance votes for subscription accounts
 */
contract VotingSystem is EncryptionSystem {
    struct Proposal {
        address proposer;
        address userToKick;
        uint256 yesVotes;
        uint256 noVotes;
        uint256 endTime;
        mapping(address => bool) hasVoted;
    }
    
    mapping(uint256 => mapping(uint256 => mapping(uint256 => Proposal))) public proposals;
    mapping(uint256 => mapping(uint256 => uint256)) public proposalCounts;
    mapping(address => uint256) public lastProposalTime;
    
    event ProposalCreated(
        uint256 serviceId,
        uint256 accountId,
        uint256 proposalId,
        address proposer,
        address userToKick
    );
    event VoteCast(
        uint256 serviceId,
        uint256 accountId,
        uint256 proposalId,
        address voter,
        bool vote
    );
    event UserKicked(
        uint256 serviceId,
        uint256 accountId,
        address kickedUser
    );
    
    error VotingPeriodEnded();
    error AlreadyVoted();
    error NotMember();

    function proposeToKickUser(
        uint256 serviceId,
        uint256 accountId,
        address userToKick
    ) external virtual {
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        require(account.isMember[msg.sender], "Not a member");
        require(account.isMember[userToKick], "User not in this account");
        require(userToKick != msg.sender, "Cannot propose yourself");

        require(
            block.timestamp > lastProposalTime[msg.sender] + 12 hours,
            "Wait before proposing again"
        );

        lastProposalTime[msg.sender] = block.timestamp;
        
        uint256 proposalId = ++proposalCounts[serviceId][accountId];
        Proposal storage proposal = proposals[serviceId][accountId][proposalId];
        
        proposal.proposer = msg.sender;
        proposal.userToKick = userToKick;
        proposal.endTime = block.timestamp + 1 days;
        
        emit ProposalCreated(serviceId, accountId, proposalId, msg.sender, userToKick);
    }

    function voteOnProposal(
        uint256 serviceId,
        uint256 accountId,
        uint256 proposalId,
        bool vote
    ) external virtual{
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        Proposal storage proposal = proposals[serviceId][accountId][proposalId];
        
        if (!account.isMember[msg.sender]) revert NotMember();
        if (block.timestamp > proposal.endTime) revert VotingPeriodEnded();
        if (proposal.hasVoted[msg.sender]) revert AlreadyVoted();
        if (msg.sender == proposal.userToKick) revert NotMember();

        proposal.hasVoted[msg.sender] = true;
        if (vote) {
            proposal.yesVotes += 1;
        } else {
            proposal.noVotes += 1;
        }
        
        emit VoteCast(serviceId, accountId, proposalId, msg.sender, vote);
    }

    function executeProposal(
        uint256 serviceId,
        uint256 accountId,
        uint256 proposalId
    ) external {
        SubscriptionAccount storage account = subscriptionAccounts[serviceId][accountId];
        Proposal storage proposal = proposals[serviceId][accountId][proposalId];
        
        require(block.timestamp > proposal.endTime, "Voting ongoing");
        require(account.isMember[proposal.userToKick], "Already kicked");
        require(account.members.length >= 2, "Not enough members to execute proposal");

        uint256 totalMembers = account.members.length - 1; // Exclude userToKick
        uint256 requiredVotes = (totalMembers / 2) + 1;
        
        if (proposal.yesVotes >= requiredVotes) {
            for (uint256 i = 0; i < account.members.length; i++) {
                if (account.members[i] == proposal.userToKick) {
                    account.members[i] = account.members[account.members.length - 1];
                    account.members.pop();
                    break;
                }
            }
            
            account.isMember[proposal.userToKick] = false;
            _removeEncryptedCredentials(serviceId, accountId, proposal.userToKick);
            delete userSubscriptions[proposal.userToKick][serviceId];
            
            emit UserKicked(serviceId, accountId, proposal.userToKick);
        }
    }
    
    function getProposalCount(uint256 serviceId, uint256 accountId) 
        external 
        view 
        returns (uint256) 
    {
        return proposalCounts[serviceId][accountId];
    }

    function getProposal(uint256 serviceId, uint256 accountId, uint256 proposalId)
        external
        view
        returns (
            address proposer,
            address userToKick,
            uint256 yesVotes,
            uint256 noVotes,
            uint256 endTime
        )
    {
        Proposal storage proposal = proposals[serviceId][accountId][proposalId];

        return (
            proposal.proposer,
            proposal.userToKick,
            proposal.yesVotes,
            proposal.noVotes,
            proposal.endTime
        );
    }
}