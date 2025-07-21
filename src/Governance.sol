// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @notice Interface to external staking contract
interface IStaking {
    /// @notice getUserTotalGovernanceWeight function executes core protocol logic.
    /// @dev Detailed description of getUserTotalGovernanceWeight.
    /// @param user Description of user.
    /// @return uint256 Description of return value.
    function getUserTotalGovernanceWeight(address user) external view returns (uint256);
}

/// @title Governance Contract
/// @notice Implements proposal creation, voting with delegation, and parameter configuration for a decentralized protocol
/// @dev Interacts with an external staking contract to determine voting weight
contract Governance is Ownable2Step {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    error InvalidAddress();
    error OnlyMultisig();
    error ProposalNotExists();
    error AlreadyVoted();
    error VotingNotActive();
    error InvalidOption();
    error DelegatorCannotVote();
    error NoGovernanceWeight();
    error AlreadyDelegated();
    error NoDelegationToRevoke();
    error CannotDelegateSelf();
    error AtLeastTwoOptionsRequired();
    error VotingAlreadyStarted();
    error VotingAlreadyEnded();
    error InvalidProposalStatus();
    error TimelockNotOver();
    error VotingOngoing();
    error ExtensionLimitReached();
    error MaximumDelegatorsLimitReached();
    error ProposalAlreadyDefeated();
    error OptionsLimitExceeded();
    error ProposalNotSucceeded();

    IStaking public stakingContract;
    address public multiSig;

    uint256 public voteDelay = 1 days;
    uint256 public voteDuration = 7 days;
    uint256 public timelockDuration = 1 days;
    uint8 constant MAX_EXTENSION_COUNTER = 3;
    uint8 public maxDelegatorsLimit = 5;
    uint256 constant MAX_PROPOSAL_OPTIONS = 4; 

    enum ProposalStatus { Pending, Active, Cancelled, Succeeded, Defeated, Tie }
    enum ProposalType { Standard, Treasury, Protocol }

    struct ProposalDetails {
        uint256 id;
        uint256 createdAt;
        uint256 voteStart;
        uint256 voteEnd;
        uint256 timelockEnd;
        uint8 minimumVotes;
        ProposalType proposalType;
        ProposalStatus status;
        bool votingStarted;
        uint256 winningOption;
        uint256 highestWeight;
        uint256 castedVotes;
        string description;
        string ipfsCID;
        string[] options;
    }

    uint256 public proposalCount;
    mapping(uint256 => ProposalDetails) private proposals;
    EnumerableSet.UintSet private activeProposals;
    EnumerableSet.UintSet private cancelledProposals;
    uint256 public totalExecutedProposals;
    uint256 public totalSucceededProposals;
    uint256 public totalDefeatedProposals;

    mapping(uint256 => mapping(uint256 => uint256)) private optionWeights;
    mapping(uint256 => mapping(address => uint256)) private voterChoice;
    mapping(uint256 => mapping(address => bool)) private hasVoted;
    mapping(address => EnumerableSet.UintSet) private userVotes;
    mapping(uint256 => address[]) private proposalVoters;
    mapping(uint256 => bool) private cancelledProposalDataRemoved;

    mapping(uint256 => mapping(address => address)) public proposalDelegation;
    mapping(address => address) public globalDelegation;
    mapping(address => EnumerableSet.AddressSet) private globalDelegators;
    mapping(uint256 => mapping(address => EnumerableSet.AddressSet)) private proposalDelegators;
    mapping(address => uint256) public userConsecutiveVotes;
    mapping(address => uint8) public totalDelegators;
    mapping(uint256 => uint256) private proposalWinningOption;
    mapping(uint256 => uint256) private proposalHighestWeight;
    mapping(uint256 => uint8) private extensionCount;
    
    event MultisigOwnershipTransferred(address previousMultisig, address newMultiSig, uint256 time);
    event ProposalCreated(uint256 indexed id, ProposalType proposalType, address proposer, uint256 createdAt, string description, string ipfsCID, string[] options);
    event ProposalCancelled(uint256 indexed id, address cancelledBy, uint256 timestamp);
    event ProposalExecuted(uint256 indexed id, ProposalStatus status, uint256 timestamp);
    event VoteCast(address indexed voter, uint256 indexed proposalId, uint256 optionIndex, uint256 weight, uint256 timestamp);
    event Delegation(address indexed delegator, address indexed delegatee, uint256 timestamp);
    event DelegationRevoked(address indexed delegator, address indexed delegatee, uint256 timestamp);
    event ProposalUpdated(uint256 indexed id, string newDescription, string ipfsCID, string[] options, uint256 timestamp);
    event VotingExtended(uint256 indexed id, uint256 additionalTime, uint256 newVoteEnd, uint256 newTimelockEnd, uint256 timestamp);
    event VotingParamsUpdated(uint256 delay, uint256 duration, uint256 timelock, uint256 timestamp);
    event CancelledProposalDataRemoved(address voter, uint256 proposalId);

    
    /// @notice Initializes the contract with staking contract and multisig addresses
    /// @param _stakingContract Address of staking contract used to calculate governance weight
    /// @param _multiSig Initial multisig controller
    constructor(address _stakingContract, address initialOwner, address _multiSig) Ownable(initialOwner) {
        if (_stakingContract == address(0) || _multiSig == address(0)) revert InvalidAddress();
        stakingContract = IStaking(_stakingContract);
        multiSig = _multiSig;
    }

    modifier onlyMultisig {
        if (msg.sender != multiSig) revert OnlyMultisig();
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        if (proposalId == 0 || proposalId > proposalCount) revert ProposalNotExists();
        _;
    }
    
    /// @notice Transfers multisig ownership to a new address
    /// @param _multiSig New multisig address
    /// @notice changeMultisig function executes core protocol logic.
    /// @dev Detailed description of changeMultisig.
    /// @param _multiSig Description of _multiSig.
    function changeMultisig(address _multiSig) external onlyOwner{
        if(_multiSig == address(0)) revert InvalidAddress();
        address previousMultiSig = multiSig;
        multiSig = _multiSig;
        emit MultisigOwnershipTransferred(previousMultiSig, _multiSig, block.timestamp);
    }
    
    /// @notice Creates a new governance proposal
    /// @param proposalType Type of the proposal
    /// @param description Description of the proposal
    /// @param ipfsCID The cid of proposal document uploaded on ipfs
    /// @param options The string array having proposal options
    /// @param minimumVotes The minimum number of votes required in a proposal
    function createProposal(
        ProposalType proposalType,
        string memory description,
        string memory ipfsCID,
        string[] memory options,
        uint8 minimumVotes
    ) external onlyMultisig {
        if (options.length < 2) revert AtLeastTwoOptionsRequired();

        if(options.length > MAX_PROPOSAL_OPTIONS) revert OptionsLimitExceeded();

        uint256 id = ++proposalCount;
        ProposalDetails storage p = proposals[id];
        p.id = id;
        p.proposalType = proposalType;
        p.description = description;
        p.ipfsCID = ipfsCID;
        p.createdAt = block.timestamp;
        p.voteStart = block.timestamp + voteDelay;
        p.voteEnd = p.voteStart + voteDuration;
        p.timelockEnd = p.voteEnd + timelockDuration;
        p.options= options;
        p.status = ProposalStatus.Pending;
        p.minimumVotes = minimumVotes;

        emit ProposalCreated(id, proposalType, msg.sender, block.timestamp, description, ipfsCID, options);
    }
    
    /// @notice Casts a vote on a proposal
    /// @param proposalId ID of the proposal
    /// @param optionIndex Index of the option to vote for
    function castVote(uint256 proposalId, uint256 optionIndex) external proposalExists(proposalId)  {
        ProposalDetails storage p = proposals[proposalId];

        if (p.status == ProposalStatus.Cancelled || p.status == ProposalStatus.Defeated) {
            revert InvalidProposalStatus();
        }

        if (block.timestamp < p.voteStart || block.timestamp >= p.voteEnd) {
            revert VotingNotActive();
        }

        if (optionIndex >= p.options.length) {
            revert InvalidOption();
        }

        if (!p.votingStarted) {
            p.votingStarted = true;
            p.status = ProposalStatus.Active;
            activeProposals.add(proposalId);
        }

        address voter = msg.sender;

        if (hasVoted[proposalId][voter]) revert AlreadyVoted();

        if (proposalDelegation[proposalId][voter] != address(0) || globalDelegation[voter] != address(0)) {
            revert DelegatorCannotVote();
        }
        
        uint256 totalWeight = getUserTotalGovernanceWeight(voter);
         
        // Mark delegatee as voted
        hasVoted[proposalId][voter] = true;
        userVotes[voter].add(proposalId);
        proposalVoters[proposalId].push(voter);

        if (totalWeight > 0){
            p.castedVotes++;
            if(hasVoted[proposalId - 1][voter]){
                userConsecutiveVotes[voter]++;
            }
        }
        EnumerableSet.AddressSet storage delegatorsSet = proposalDelegators[proposalId][voter];
        uint256 delegatorsCount = EnumerableSet.length(delegatorsSet);

        for (uint256 i; i < delegatorsCount; ++i) {
            address delegator = EnumerableSet.at(delegatorsSet, i);

            if (!hasVoted[proposalId][delegator]) {
                uint256 delegatorWeight = getUserTotalGovernanceWeight(delegator);
                if (delegatorWeight > 0) {
                    hasVoted[proposalId][delegator] = true;
                    userVotes[delegator].add(proposalId);
                    proposalVoters[proposalId].push(delegator);
                    voterChoice[proposalId][delegator] = optionIndex;
                    totalWeight += delegatorWeight;
                    p.castedVotes++;
                }
            }
        }

        optionWeights[proposalId][optionIndex] += totalWeight;
        voterChoice[proposalId][voter] = optionIndex;

        uint256 updatedWeight = optionWeights[proposalId][optionIndex];
        if (updatedWeight > proposalHighestWeight[proposalId]) {
            proposalHighestWeight[proposalId] = updatedWeight;
            proposalWinningOption[proposalId] = optionIndex;
        }

        emit VoteCast(voter, proposalId, optionIndex, totalWeight, block.timestamp);
    }
    
    /// @notice Cancels a proposal before voting starts or mid voting
    /// @param proposalId ID of the proposal
    /// @notice cancelProposal function executes core protocol logic.
    /// @dev Detailed description of cancelProposal.
    /// @param proposalId Description of proposalId.
    function cancelProposal(uint256 proposalId) external onlyMultisig proposalExists(proposalId)  {
        ProposalDetails storage p = proposals[proposalId];
        if (block.timestamp >= p.voteEnd) revert VotingAlreadyEnded();
        if (p.status == ProposalStatus.Cancelled || p.status == ProposalStatus.Defeated || p.status == ProposalStatus.Succeeded)
            revert InvalidProposalStatus();

        p.status = ProposalStatus.Cancelled;

        activeProposals.remove(proposalId);
        cancelledProposals.add(proposalId);

        emit ProposalCancelled(proposalId, msg.sender, block.timestamp);
    }

    /// @notice Removes vote-related data for a cancelled proposal.
    /// @dev This function can only be called by the contract owner(admin) to remove voting data 
    /// for a user who has already voted in a proposal that was subsequently cancelled.
    /// @param voter The address of the voter whose vote data is to be removed.
    /// @param proposalId The ID of the cancelled proposal for which data is being cleaned.
    function removeCancelledProposalData(address voter, uint256 proposalId) external onlyOwner {
        ProposalDetails storage p = proposals[proposalId];
        if(p.status != ProposalStatus.Cancelled) revert InvalidProposalStatus();
        require(!cancelledProposalDataRemoved[proposalId], "Data already cleaned");
        hasVoted[proposalId][voter] = false;
        delete voterChoice[proposalId][voter];
        userVotes[voter].remove(proposalId);
        cancelledProposalDataRemoved[proposalId] = true;
        emit CancelledProposalDataRemoved(voter, proposalId);
    }


    /// @notice getProposalVoters function executes core protocol logic.
    /// @dev Detailed description of getProposalVoters.
    /// @param proposalId Description of proposalId.
    /// @return memory Description of return value.
    function getProposalVoters(uint256 proposalId) external view returns(address[] memory) {
        return proposalVoters[proposalId]; 
    }

    /// @notice executeProposal function executes core protocol logic.
    /// @dev Detailed description of executeProposal.
    /// @param proposalId Description of proposalId.
    function executeProposal(uint256 proposalId) external proposalExists(proposalId) onlyMultisig {
        ProposalDetails storage p = proposals[proposalId];
        if (block.timestamp < p.timelockEnd) revert TimelockNotOver();
        if (p.status != ProposalStatus.Active) revert InvalidProposalStatus();

        if (p.castedVotes < p.minimumVotes)  {
            p.status = ProposalStatus.Defeated;
            totalExecutedProposals++;
            totalDefeatedProposals++;
            activeProposals.remove(proposalId);
            emit ProposalExecuted(proposalId, p.status, block.timestamp);
            return;
        }

        uint256 highestWeight;
        uint256 optionsLength = p.options.length;
        uint256[] memory tempTiedOptions = new uint256[](optionsLength);
        uint256 tieCount;

        for (uint256 i; i < optionsLength; i++) {
            uint256 weight = optionWeights[proposalId][i];

            if (weight > highestWeight) {
                highestWeight = weight;
                tieCount = 1;
                tempTiedOptions[0] = i;
            } else if (weight == highestWeight) {
                tempTiedOptions[tieCount] = i;
                tieCount++;
            }
        }

        activeProposals.remove(proposalId);
        totalExecutedProposals++;

        if (tieCount > 1) {
            p.status = ProposalStatus.Tie;
            emit ProposalExecuted(proposalId, p.status, block.timestamp);
            return;
        } else {
            p.status = ProposalStatus.Succeeded;
            p.winningOption = tempTiedOptions[0];
            p.highestWeight = highestWeight;
            totalSucceededProposals++;
            emit ProposalExecuted(proposalId, p.status, block.timestamp);
        }
    }
    
    /// @notice Allows a user to delegate their vote to another address
    /// @param proposalId The proposal for which votes are delegated
    /// @param to Address to delegate to
    /// @notice delegateVoteForProposal function executes core protocol logic.
    /// @dev Detailed description of delegateVoteForProposal.
    /// @param proposalId Description of proposalId.
    /// @param to Description of to.
    function delegateVoteForProposal(uint256 proposalId, address to) external proposalExists(proposalId)  {
        _delegate(msg.sender, to, proposalId, false);
    }

    /// @notice delegateVoteGlobally function executes core protocol logic.
    /// @dev Detailed description of delegateVoteGlobally.
    /// @param to Description of to.
    function delegateVoteGlobally(address to) external  {
        _delegate(msg.sender, to, 0, true);
    }

    /// @notice _delegate function executes core protocol logic.
    /// @dev Detailed description of _delegate.
    /// @param delegator Description of delegator.
    /// @param delegatee Description of delegatee.
    /// @param proposalId Description of proposalId.
    /// @param isGlobal Description of isGlobal.
    function _delegate(address delegator, address delegatee, uint256 proposalId, bool isGlobal) internal  {
        if(totalDelegators[delegatee] > maxDelegatorsLimit) revert MaximumDelegatorsLimitReached();
        if (delegatee == address(0)) revert InvalidAddress();
        if (delegator == delegatee) revert CannotDelegateSelf();

        if (isGlobal) {
            if (globalDelegation[delegator] != address(0)) revert AlreadyDelegated();
            globalDelegation[delegator] = delegatee;
            globalDelegators[delegatee].add(delegator);
        } else {
            if (proposalDelegation[proposalId][delegator] != address(0)) revert AlreadyDelegated();
            if (hasVoted[proposalId][delegator]) revert AlreadyVoted(); 
            proposalDelegation[proposalId][delegator] = delegatee;
            proposalDelegators[proposalId][delegatee].add(delegator);
        }

        totalDelegators[delegatee]++;

        emit Delegation(delegator, delegatee, uint32(block.timestamp));
    }

    /// @notice revokeProposalDelegation function executes core protocol logic.
    /// @dev Detailed description of revokeProposalDelegation.
    /// @param proposalId Description of proposalId.
    function revokeProposalDelegation(uint256 proposalId) external proposalExists(proposalId)  {
        _revokeDelegation(msg.sender, proposalId, false);
    }
    
    /// @notice revokeGlobalDelegation function executes core protocol logic.
    /// @dev Detailed description of revokeGlobalDelegation.      
    function revokeGlobalDelegation() external  {
        _revokeDelegation(msg.sender, 0, true);
    }

    /// @notice _revokeDelegation function executes core protocol logic.
    /// @dev Detailed description of _revokeDelegation.
    /// @param delegator Description of delegator.
    /// @param proposalId Description of proposalId.
    /// @param isGlobal Description of isGlobal.
    function _revokeDelegation(address delegator, uint256 proposalId, bool isGlobal) internal  {
        address currentDelegatee;

        if (isGlobal) {
            currentDelegatee = globalDelegation[delegator];
            if (currentDelegatee == address(0)) revert NoDelegationToRevoke();
            delete globalDelegation[delegator];

            // Remove delegator from globalDelegators set of delegatee
            globalDelegators[currentDelegatee].remove(delegator);
        } else {
            currentDelegatee = proposalDelegation[proposalId][delegator];
            if (currentDelegatee == address(0)) revert NoDelegationToRevoke();
            delete proposalDelegation[proposalId][delegator];

            // Remove delegator from proposalDelegators set of delegatee
            proposalDelegators[proposalId][currentDelegatee].remove(delegator);
        }

        totalDelegators[currentDelegatee]--;

        emit DelegationRevoked(delegator, currentDelegatee, uint32(block.timestamp));
    }

    /// @notice updateProposalDetails function executes core protocol logic.
    /// @dev Detailed description of updateProposalDetails.
    /// @param id Description of id.
    /// @param proposalType Description of proposalType.
    /// @param description Description of proposal.
    /// @param ipfsCID The URL of proposal document uploaded on IPFS
    /// @param options Description of options.
    function updateProposalDetails(
        uint256 id,
        ProposalType proposalType,
        string memory description,
        string memory ipfsCID,
        string[] memory options
    ) external onlyMultisig proposalExists(id)  {
        ProposalDetails storage p = proposals[id];
        if (block.timestamp >= p.voteStart) revert VotingAlreadyStarted();
        if (p.status != ProposalStatus.Pending) revert InvalidProposalStatus();
        if(options.length > MAX_PROPOSAL_OPTIONS) revert OptionsLimitExceeded();

        p.proposalType = proposalType;
        p.description = description;
        p.ipfsCID = ipfsCID;
        p.options = options;

        emit ProposalUpdated(id, description, ipfsCID, options, block.timestamp);
    }

    /// @notice extendVoting function executes core protocol logic.
    /// @dev Detailed description of extendVoting.
    /// @param id Description of id.
    /// @param additionalTime Description of additionalTime.
    function extendVoting(uint256 id, uint32 additionalTime) external onlyMultisig proposalExists(id) {
        ProposalDetails storage p = proposals[id];
        if(extensionCount[id] >= MAX_EXTENSION_COUNTER) revert ExtensionLimitReached();
        if (block.timestamp >= p.voteEnd) revert VotingAlreadyEnded();
        
        if (p.status != ProposalStatus.Pending && p.status != ProposalStatus.Active) revert InvalidProposalStatus();

        p.voteEnd += additionalTime;
        p.timelockEnd += additionalTime;
        extensionCount[id]++;

        emit VotingExtended(id, additionalTime, p.voteEnd, p.timelockEnd, block.timestamp);
    }

    /// @notice updateVotingParams function updates voting parameters.
    /// @dev Detailed description of updateVotingParams.
    /// @param _delay Description of _delay.
    /// @param _duration Description of _duration.
    /// @param _timelock Description of _timelock.
    function updateVotingParams(uint32 _delay, uint32 _duration, uint32 _timelock) external onlyMultisig {
        voteDelay = _delay;
        voteDuration = _duration;
        timelockDuration = _timelock;

        emit VotingParamsUpdated(_delay, _duration, _timelock, uint32(block.timestamp));
    }

    function updateTotalDelegatorsLimit(uint8 _limit) external onlyOwner {
        maxDelegatorsLimit = _limit;
    }
    
    function getEffectiveDelegatee(uint256 proposalId, address voter) public view returns (address) {
        address proposalLevel = proposalDelegation[proposalId][voter];
        if (proposalLevel != address(0)) return proposalLevel;
        return globalDelegation[voter];
    }

    function renounceOwnership() public view override onlyOwner {
        revert("Renouncing ownership is disabled.");
    }

    /// @notice getProposalBasicInfo function executes core protocol logic.
    /// @dev Detailed description of getProposalBasicInfo.
    /// @param id Description of id.
    function getProposalBasicInfo(uint256 id) 
        public view returns (
            ProposalType,
            string memory,
            string memory,
            uint256,   
            uint256,  
            uint256,   
            ProposalStatus,
            uint256,
            uint256,
            uint256,
            uint256
        ) {
        ProposalDetails storage p = proposals[id];
        return (
            p.proposalType, 
            p.description, 
            p.ipfsCID, 
            p.voteStart, 
            p.voteEnd, 
            p.timelockEnd, 
            p.status,
            p.highestWeight,
            p.winningOption,
            p.minimumVotes,
            p.castedVotes
        );
    }

    /// @notice getVoterChoice function executes core protocol logic.
    /// @dev Detailed description of getVoterChoice.
    /// @param proposalId Description of proposalId.
    /// @param user Description of user.
    /// @return uint256 Description of return value.
    function getVoterChoice(uint256 proposalId, address user) external view proposalExists(proposalId) returns (uint256) {
        require(hasVoted[proposalId][user], "User not voted");
        return voterChoice[proposalId][user];
    }

    /// @notice getActiveProposals function executes core protocol logic.
    /// @dev Detailed description of getActiveProposals.
    /// @return memory Description of return value.
    function getActiveProposals() external view returns (uint256[] memory) {
        return activeProposals.values();
    }

    /// @notice getCancelledProposals function executes core protocol logic.
    /// @dev Detailed description of getCancelledProposals.
    /// @return memory Description of return value.
    function getCancelledProposals() external view returns (uint256[] memory) {
        return cancelledProposals.values();
    }

    /// @notice getProposalOptions function executes core protocol logic.
    /// @dev Detailed description of getProposalOptions.
    /// @param proposalId Description of proposalId.
    /// @return memory Description of return value.
    function getProposalOptions(uint256 proposalId) external view proposalExists(proposalId) returns (string[] memory) {
        return proposals[proposalId].options;
    }

    /// @notice getWinningOption function executes core protocol logic.
    /// @dev Detailed description of getWinningOption.
    /// @param proposalId Description of proposalId.
    /// @return uint256 Description of return value.
    /// @return memory Description of return value.
    /// @return uint256 Description of return value.
    function getWinningOption(uint256 proposalId) external view proposalExists(proposalId) returns (uint256, string memory, uint256) {
        ProposalDetails memory p = proposals[proposalId];
        if (block.timestamp <= p.timelockEnd) revert TimelockNotOver();
        if(p.status != ProposalStatus.Succeeded) revert ProposalNotSucceeded();

        uint256 winningIndex = proposalWinningOption[proposalId];
        uint256 highestWeight = proposalHighestWeight[proposalId];

       return (winningIndex, p.options[winningIndex], highestWeight);
    }

    /// @notice getOptionWeight function executes core protocol logic.
    /// @dev Detailed description of getOptionWeight.
    /// @param proposalId Description of proposalId.
    /// @param optionIndex Description of optionIndex.
    /// @return uint256 Description of return value.
    function getOptionWeight(uint256 proposalId, uint256 optionIndex) external view proposalExists(proposalId) returns (uint256) {
        return optionWeights[proposalId][optionIndex];
    }

    /// @notice hasUserVoted function executes core protocol logic.
    /// @dev Detailed description of hasUserVoted.
    /// @param proposalId Description of proposalId.
    /// @param user Description of user.
    /// @return bool Description of return value.
    function hasUserVoted(uint256 proposalId, address user) external view proposalExists(proposalId) returns (bool) {
        return hasVoted[proposalId][user];
    }

    /// @notice getTotalExecutedProposals function executes core protocol logic.
    /// @dev Detailed description of getTotalExecutedProposals.
    /// @return uint256 Description of return value.
    function getTotalExecutedProposals() external view returns (uint256) {
        return totalExecutedProposals;
    }

    /// @notice getDelegatedVoteCount function executes core protocol logic.
    /// @dev Detailed description of getDelegatedVoteCount.
    /// @param delegatee Description of delegatee.
    /// @param proposalId Description of proposalId.
    /// @return uint256 Description of return value.
    function getDelegatedVoteCount(address delegatee, uint256 proposalId) external view returns (uint256) {
        uint256 proposalCount_ = proposalId == 0 ? 0 : proposalDelegators[proposalId][delegatee].length();
        uint256 globalCount = globalDelegators[delegatee].length();
        return proposalCount_ + globalCount;
    }

    /// @notice getUserVotes function executes core protocol logic.
    /// @dev Detailed description of getUserVotes.
    /// @param user Description of user.
    /// @return memory Description of return value.
    function getUserVotes(address user) external view returns (uint256[] memory) {
        return userVotes[user].values();
    }

    /// @notice getUserConsecutiveVotes function executes core protocol logic.
    /// @dev Detailed description of getUserConsecutiveVotes.
    /// @param user Description of user.
    /// @return uint8 Description of return value.
    function getUserConsecutiveVotes(address user) external view returns (uint256) {
        return userConsecutiveVotes[user];
    }

    /// @notice getUserTotalGovernanceWeight function executes core protocol logic.
    /// @dev Detailed description of getUserTotalGovernanceWeight.
    /// @param user Description of user.
    /// @return uint256 Description of return value.
    function getUserTotalGovernanceWeight(address user) public view returns(uint256) {
        uint256 totalWeight = stakingContract.getUserTotalGovernanceWeight(user);
        return totalWeight;
    }

    /// @notice hasGlobalDelegation function executes core protocol logic.
    /// @dev Detailed description of hasGlobalDelegation.
    /// @param user Description of user.
    /// @return bool Description of return value.
    function hasGlobalDelegation(address user) external view returns (bool) {
        return globalDelegation[user] != address(0);
    }

    /// @notice getProposalDelegators function executes core protocol logic.
    /// @dev Detailed description of getProposalDelegators.
    /// @param proposalId Description of proposalId.
    /// @param delegatee Description of delegatee.
    /// @return memory Description of return value.
    function getProposalDelegators(uint256 proposalId, address delegatee) external view returns (address[] memory) {
        EnumerableSet.AddressSet storage set = proposalDelegators[proposalId][delegatee];
        uint256 len = set.length();
        address[] memory result = new address[](len);
        for (uint256 i; i < len; i++) {
            result[i] = set.at(i);
        }
        return result;
    }
}
