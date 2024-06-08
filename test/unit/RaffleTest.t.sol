//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {VRFCoordinatorV2Mock} from "../mocks/VRFCoordinatorV2Mock.sol";
import {CreateSubscription} from "../../script/Interactions.s.sol";
// import {WETH} from "forge-std/WETH.sol";

contract Raffletest is StdCheats, Test {

    // Events
    event EnteredRaffle(address indexed player);

    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    // WETH private _weth;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
        deal(PLAYER, STARTING_USER_BALANCE);
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,
            
        ) = helperConfig.activeNetworkConfig();
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }



    //////////////////////////
    // enter raffle
    //////////////////////////
    function testRaffleRevertsWhenYouDontPayEnough() public {
        //Arrange
        vm.prank(PLAYER);
        //Act/ Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughETHSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecord = raffle.getPlayer(0);
        assert(playerRecord == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    // function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
    //      // Arrange
    //     vm.prank(PLAYER);
    //     raffle.enterRaffle{value: entranceFee}();
    //     vm.warp(block.timestamp + interval + 1);
    //     vm.roll(block.number + 1);
    //     raffle.performUpkeep("");

    //     // Act / Assert
    //     vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
    //     vm.prank(PLAYER);
    //     raffle.enterRaffle{value: entranceFee}();
    // }

    /////////////////
    // checkUpKeep
    /////////////////
    function testCheckUpKeepReturnsFalseIfIthasNoBalance() public {
        // arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //Act
        (bool upKeppNeeded, ) = raffle.checkUpkeep("");

        //assert
        assert(!upKeppNeeded);
    }

    function checkUpkeepReturnsFalseIfRaffleNotOpen() public {
        //arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        //act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //assert
        assert(upkeepNeeded == false);
    }

    // testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed
    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //assert
        assert(upkeepNeeded);
    }


    ///////////////////////
    // performUpkeep
    ///////////////////////
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //Act / Assert
        // It doesn't revert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        //Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        //Act/Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEnteredAndTimePassed {
        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); //emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[0];

        //assert
        Raffle.RaffleState rState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1);
    }

    ////////////////////////
    // fulfillRandomWords //
    ////////////////////////

    modifier skipFork() {
        if(block.chainid != 31337) {
            return;
        }
        _;
    }
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEnteredAndTimePassed skipFork {
        // Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendMoney() public raffleEnteredAndTimePassed skipFork {
        // Arrange
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for(uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimestamp = raffle.getLastTimestamp();

        //pretend to chainlink vrf to get randfom number and pick winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        //Assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLengthOfPlayers() == 0);
        assert(previousTimestamp < raffle.getLastTimestamp());
        console.log(raffle.getRecentWinner().balance);
        console.log(prize);
        assert(raffle.getRecentWinner().balance == STARTING_USER_BALANCE + prize - entranceFee);
    }
}