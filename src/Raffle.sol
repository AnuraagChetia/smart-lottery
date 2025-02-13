//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;

/// @title A sample Raffle Contract
/// @author Anuraag Chetia
/// @notice This contract is for creating a sample raffle contract
/// @dev This implements Chainlink VRF Version 2

import {VRFConsumerBaseV2Plus} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

contract Raffle is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    /** ERRORS */
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState,
        bool timeHasPassed
    );
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__RaffleNotOpen();
    error Raffle__TransferFailed();

    /** TYPE DECLARATION */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /** STATE VARIABLES */

    /** CHAINLINK VARIABLES */
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    /** Lottery Variables */
    uint256 immutable i_entranceFee;
    address payable private s_recentWinner;
    address payable[] private s_players;
    RaffleState private s_raffleState;
    uint256 private s_lastTimeStamp;
    uint256 immutable i_interval;

    /** EVENTS */
    event RaffleEntered(address indexed player);
    event RaffleWinnerDeclared(address indexed player);
    event RaffleUpkeepPerformed(uint256 indexed requestId);

    /** FUNCTIONS */
    //constructor
    constructor(
        uint256 subscriptionId,
        bytes32 gasLane, //keyHash
        uint256 interval,
        uint256 entranceFee,
        uint32 callbackGasLimit,
        address vrfCoordinatorV2
    ) VRFConsumerBaseV2Plus(vrfCoordinatorV2) {
        i_gasLane = gasLane;
        i_interval = interval;
        i_subscriptionId = subscriptionId;
        i_entranceFee = entranceFee;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    // enter raffle
    function enterRaffle() public payable {
        //player pays entry fee
        if (msg.value < i_entranceFee) revert Raffle__SendMoreToEnterRaffle();
        //if raffle not open
        if (s_raffleState != RaffleState.OPEN) revert Raffle__RaffleNotOpen();
        //add player to raffle
        s_players.push(payable(msg.sender));
        //emit an event
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev This is the function that the Chainlink nodes will call to see
     * if the lottery is ready to have a winner picked
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed between raffle runs
     * 2. The lottery is open
     * 3. The contract has ETH
     * 4. Implicity, your subscription has LINK
     * @param - ignored
     * @return upkeepNeeded - true if it's time to restart the lottery
     * @return - ignored
     */

    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        //check if enough time has passed
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_interval);
        //check if contract has balance
        bool hasBalance = address(this).balance > 0;
        // check if contract is open
        bool isOpen = s_raffleState == RaffleState.OPEN;
        //check if contract has players
        bool hasPlayers = s_players.length > 0;

        upkeepNeeded = timeHasPassed && hasBalance && hasPlayers && isOpen;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        // check to see if enough time has passed
        (bool upkeepNeeded, ) = checkUpkeep(""); // why is this needed ? so that no one can call performUpkeep directly
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState),
                bool((block.timestamp - s_lastTimeStamp) >= i_interval)
            );
        }

        //set raffle state to calculating
        s_raffleState = RaffleState.CALCULATING;

        //get a random number // will revert if subscription is not set and funded // computation money will still be lost
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_gasLane,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        //redundant emit as VrfCoordinatorV2_5Mock already emits this
        //but we are emitting this to test
        emit RaffleUpkeepPerformed(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] calldata randomWords
    ) internal override {
        //declare winner
        uint256 winnerIndex = randomWords[0] % s_players.length;
        s_recentWinner = s_players[winnerIndex];

        s_raffleState = RaffleState.OPEN; // Set Raffle state to OPEN
        s_players = new address payable[](0); // Reset to blank array
        emit RaffleWinnerDeclared(s_recentWinner);

        //transfer money to winner
        (bool success, ) = s_recentWinner.call{value: address(this).balance}(
            ""
        );
        if (!success) revert Raffle__TransferFailed();
    }

    /** GETTER FUNCTIONS */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getPlayerList() external view returns (address payable[] memory) {
        return s_players;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
