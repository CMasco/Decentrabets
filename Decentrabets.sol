pragma solidity ^0.4.24;

//import "github.com/oraclize/ethereum-api/oraclizeAPI_0.5.sol";

//Chris Bergamasco
//Michael Ferrara
import "installed_contracts/oraclize-api/contracts/usingOraclize.sol";

contract Decentrabets is usingOraclize {

  //Logging the Orcalize Query
  event LogNewOraclizeQuery(string description);

  address public owner; //address of owner
  //model of a Match
  struct Match{
    uint id; //id of match
    string team1;
    string team2;
    uint256 t1_pool; //pool for team1 bets
    uint256 t2_pool; //pool for team2 bets
    uint256 betPool; //total pool of bets
    uint256 house;
    bool betsOpen; //Betting Open or Closed
    string winner; //Winning Team
    address[] bettorAddress; // Addresses of all the bettors
    mapping(address => Bet) bets; //all the bets made on this match
    string game;
  }

  struct Bet {
    uint matchID; //matchID
    string team;
    uint256 amount;
  }

  struct OraclizeQueries{
      //uint id;
      string result;
  }

  mapping(address => bool) public bettors; //Not used anymore?
  address[] public emptyAddress;  //empty address array to initialize for Matches
  mapping(uint => Match) public matches;  //mapping of all the matches created
  mapping(uint => string) public InputToResult;  //Pairs up the callback result with the Query ID as its Key
  mapping(bytes32 => uint) internal QueryIDtoMatchID;  //pairs up the query ID with its corresponding Match ID



  string public jsonData;
  string public testWinner;

  //string public testString = "json(https://api.pandascore.co/dota2/matches.json?filter[id]=52364&token=tU9uGM46ds_tXnE6FkW3u9g43EV1HsfuXOBPVNkmPHOBzMDK13Q).0.winner.name";

  string public firstQuery ="json(https://api.pandascore.co/";
  string public secondQuery ="/matches.json?filter[id]=";
  string public thirdQuery ="&token=tU9uGM46ds_tXnE6FkW3u9g43EV1HsfuXOBPVNkmPHOBzMDK13Q).0.winner.name";

  //constructor
  constructor() public payable {
    owner = msg.sender;
    OAR = OraclizeAddrResolverI(0x6f485c8bf6fc43ea212e93bbf8ce046c7f1cb475);
    oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);  //set the proof for Oraclize callback
  }

  function fetchMatchResults(uint _matchID) payable onlyOwner {
    string memory query = strConcat(firstQuery, matches[_matchID].game, secondQuery,uint2str(_matchID), thirdQuery); //Oraclize Query with  game and matchID as parameters
    bytes32 queryId = oraclize_query("URL", query);
    QueryIDtoMatchID[queryId] = _matchID;   //MatchID is paired to its key --> QueryID
    LogNewOraclizeQuery("Oraclize query was sent, standing by for the answer.");
}

//Callback function gives us the result of the oraclize query that was called above
  function __callback(bytes32 _oracleID, string result, bytes proof){
    if(msg.sender != oraclize_cbAddress()) revert();
    require(QueryIDtoMatchID[_oracleID] != 0);  //Require the oraclize Query  to have been called and  its ID stored
    uint Input = QueryIDtoMatchID[_oracleID];
    InputToResult[Input] = result;        //Store the result of the callback function
    pickWinner(QueryIDtoMatchID[_oracleID], InputToResult[Input]);      //PickWinner function will take the result of the query and update the winner in the corresponding Match struct
}

  function startMatch(string t1, string t2, uint matchID, string game) onlyOwner {
  matches[matchID] = Match(matchID, t1, t2, 0, 0, 0, 0, true, "none", emptyAddress, game);  //Intialize a Match
}

  function startBet(string _choice, uint _id) payable public {

  require(msg.value >= 0.01 ether);
  require( compareStrings(_choice, matches[_id].team1) == true || compareStrings(_choice, matches[_id].team2) == true);
  require(matches[_id].id != 0);
  require(matches[_id].betsOpen == true); //Requirements include bet being more than 0.01 ether, the team thats bet on to be part of the current matchID
                                          //ID is not 0 and betting is still open

  matches[_id].bettorAddress.push(msg.sender);    //Push bettors address into address array in match struct

  uint256 _amount = msg.value;
  uint256 _house = (_amount * 5) / 100;

  _amount = _amount - _house;
  matches[_id].house += _house;

  string memory _teamPicked;      //Intialize team that was picked to an empty sting
  _teamPicked = "none";

  //Compare the strings of the team that the bettor has chosen with the teams that are in the current match
  if(compareStrings(_choice,matches[_id].team1) == true){
    _teamPicked = matches[_id].team1;
    matches[_id].t1_pool += _amount;
  } else if(compareStrings(_choice,matches[_id].team2) == true){
    _teamPicked = matches[_id].team2;
    matches[_id].t2_pool += _amount;
  }
  matches[_id].betPool += _amount;
  //Place the Bet (object) with the amount bet, team picked and match ID
  matches[_id].bets[msg.sender] = Bet(
    _id,
    _teamPicked,
    _amount
    );
}

function compareStrings (string a, string b) view returns (bool){
     return keccak256(a) == keccak256(b);     //Used to compare the match winner and the bettors choice to determine if the they won
}

function endBetting(uint _matchID) onlyOwner {
  require(matches[_matchID].id != 0);
  require(matches[_matchID].betsOpen == true);
  matches[_matchID].betsOpen = false;     //Closes betting on the match
}

function pickWinner(uint _matchID, string result) {
  require(matches[_matchID].id != 0);
  require(matches[_matchID].betsOpen == false);
  if(msg.sender != oraclize_cbAddress()) revert();
  matches[_matchID].winner = result;      //Stores the correct winner to the match. Function is called automatically during __callback function
}

function calculateResults(uint _matchID) payable onlyOwner {

  uint numberOfBettors = matches[_matchID].bettorAddress.length;    //Get the number of bets placed on the match
  for(uint i = 0; i < numberOfBettors; i++){

  address currentBettor = matches[_matchID].bettorAddress[i];     //address of  bettor that is in loop
  uint256 bettedAmount = matches[_matchID].bets[currentBettor].amount;  //pull the amount bet by current bettor
  uint256 team1Odds = matches[_matchID].t2_pool / matches[_matchID].t1_pool; //calculate the odds for team1
  uint256 team2Odds = matches[_matchID].t1_pool / matches[_matchID].t2_pool;  //calculate the odds for team2
  uint256 winningAmount = 0;    //Initialize winning amount to 0

  owner.transfer(matches[_matchID].house);
  if(compareStrings(matches[_matchID].winner,matches[_matchID].team1) == true && compareStrings(matches[_matchID].bets[currentBettor].team, matches[_matchID].team1) == true){
      winningAmount = team1Odds * bettedAmount + bettedAmount;   //Winning amount is based on the teams odds and the amount bet
      currentBettor.transfer(winningAmount);     // transfer winnings to the bettor
  } else if (compareStrings(matches[_matchID].winner,matches[_matchID].team2) == true && compareStrings(matches[_matchID].bets[currentBettor].team, matches[_matchID].team2) == true) {
      winningAmount = team2Odds * bettedAmount + bettedAmount;  //Winning amount is based on the teams odds and the amount bet
      currentBettor.transfer(winningAmount);    // transfer winnings to the bettor
  }
 }
}


modifier onlyOwner {
  require(owner == msg.sender);
  _;
}
}

