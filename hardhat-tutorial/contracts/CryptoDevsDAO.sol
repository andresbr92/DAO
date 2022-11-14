// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

// We will add the Interfaces here
interface IFakeNFTMarketplace {
    // returns de price of the NFT in Wei
    function getPrice() external view returns (uint256);
    
    function available(uint256 _tokenId) external view returns(bool);

    function purchase(uint256 _tokenId) external payable;
}
interface ICryptoDevsNFT {
    function balanceOf(address owner) external view returns(uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns(uint256);
}

contract CryptoDevsDAO is Ownable {
    struct Proposal {
        // nftTokenId - the token of the NFT to purchase from FakeNFTMarketplace if the proposal passes
        uint256 nftTokenId;
        // deadline - The UNIX timestamp until which proposal is active. Proposal can be executed after the dealine has been exceeded
        uint256 deadline;
        // yayVotes - number of yay votes for this proposal
        uint256 yayVotes;
        // nayVotes - number of nay votes for this proposal
        uint256 nayVotes;
        // executed - whether or not this proposal has been executed yet. Cannot be executed before the deadline has been exceeded
        bool executed;
        // voters - a mappint of CryptoDevsNFT tokenIds to boolean indicating whether that NFT has already been used to cast a vote or not
        mapping(uint256 => bool) voters;
    }
    // mapping to store all the proposals
    mapping(uint256 => Proposal) public proposals;
    // number of proposals that have been created
    uint256 public numProposals;

    // initialize contracts variables ofr nftMarkeplace a& CryptoDevsNft
    IFakeNFTMarketplace nftMarketplace;
    ICryptoDevsNFT cryptoDevsNFT;

    // create a payable constructor wich initializes the contract instances for FakeNFTMarketplace and CryptoDevsNFT
    constructor(address _nftMarkeplace, address _cryptoDevsNFT) payable {
        nftMarketplace = IFakeNFTMarketplace(_nftMarkeplace);
        cryptoDevsNFT = ICryptoDevsNFT(_cryptoDevsNFT);
    }

    // create a modifier whick only allows a function to be called by someone who owns at least 1 cryptoDevsNFT
    modifier nftHolderOnly() {
        require(cryptoDevsNFT.balanceOf(msg.sender) > 0, "NOT_A_DAO_MENBER");
        _;
    }

    /// @dev createProposal allows a CryptoDevsNFT holder to create a new proposal in the DAO
    /// @param _nftTokenId - the tokenID of the NFT to be purchased from FakeNFTMarketplace if this proposal passes
    /// @return Returns the proposal index for the newly created proposal
    function createProposal(uint _nftTokenId) external nftHolderOnly returns(uint256) {
        require(nftMarketplace.available(_nftTokenId), "NFT_NOT_FOR_SALE");


        Proposal storage proposal = proposals[numProposals];
        proposal.nftTokenId = _nftTokenId;
        proposal.deadline = block.timestamp + 5 minutes;

        numProposals++;
        return numProposals - 1;
    }
    // create a modifier which only allows a function to be called if the given proposal's deadline has not been exceede yet
    modifier activeProposal(uint256 proposalIndex) {
        require(proposals[proposalIndex].deadline > block.timestamp, "DEADLINE_EXCEEDED");
        _;
    }
    // create a enum named Vote containing the possible options for a vote
    enum Vote {
        YAY, // YAY = 0
        NAY // NAY = 1
    }
    /// @dev voteOnProposal allows a CryptoDevsNFT holder to cast their vote on an active proposal
    /// @param proposalIndex - the index of the proposal to vote on in the proposals array
    /// @param vote - the type of vote they want to cast
    function voteOnProposal(uint256 proposalIndex, Vote vote) external nftHolderOnly activeProposal(proposalIndex) {

        Proposal storage proposal = proposals[proposalIndex];

        uint256 voterNFTBalance = cryptoDevsNFT.balanceOf(msg.sender);

        uint256 numVotes = 0;

        // calculate how many NFT are owned by the voter that haven't already been used for voting on this proposal
        for(uint256 i = 0; i < voterNFTBalance; i++) {
            uint256 tokenId = cryptoDevsNFT.tokenOfOwnerByIndex(msg.sender, i);
            if(proposal.voters[tokenId] == false) {
                numVotes++;
                proposal.voters[tokenId] = true;
            }
        }
        require(numVotes > 0, "ALREADY_VOTED");

        if(vote == Vote.YAY) {
            proposal.yayVotes += numVotes;
        } else {
            proposal.nayVotes += numVotes;
        }

    }
    // create a modifier which only allows a function to be called if the given proposal's deadline HAS been exceeded
    // and if the proposal has not yet been executed
    modifier inactiveProposalOnly(uint256 proposalIndex) {
        require(proposals[proposalIndex].deadline <= block.timestamp, "DEADLINE_NOT_EXCEEDED");
        require(proposals[proposalIndex].executed == false, "PROPOSAL_ALREADY_EXECUTED");
        _;
    }
    /// @dev executeProposal allows any CryptoDevsNFT holder to execute a proposal after it's deadline has been exceeded
    /// @param proposalIndex - the index of the proposal to execute in the proposals array
    function executeProposal(uint256 proposalIndex) external nftHolderOnly inactiveProposalOnly(proposalIndex) {
        Proposal storage proposal = proposals[proposalIndex];
        // if the proposal has more YAY votes than NAY votes, purchase the NFT from the FakeNFTMarketplace
        if(proposal.yayVotes > proposal.nayVotes) {
            uint256 nftPrice = nftMarketplace.getPrice();
            require(address(this).balance >= nftPrice, "NOT_ENOUGH_FUNDS");
            nftMarketplace.purchase{value: nftPrice}(proposal.nftTokenId);
        }
        proposal.executed = true;
    }
    /// @dev withdrawEther allows the contract owner (deployer) to withdraw the ETH from the contract
    function withdrawEther() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
    // The following two functions allow the contract to accept ETH deposits
    // directly from a wallet without calling a function
    receive() external payable {}

    fallback() external payable {}
}