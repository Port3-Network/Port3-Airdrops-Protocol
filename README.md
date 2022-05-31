## Port3 Airdrops Protocol

This protocol is the first Airdrop DAO Tool of Port3. It implement an airdrops module that support ETH and ERC20 tokens, and within an third party token incentive layer. This protocol should be track as and parse when Port3 is going to aggregate onchain data.

### Fee 

> This protocol can be configured to charge fees 

* `setFeeRate(feeRate)`，e.g setup as 100, it's going to charge 1% of total amount from airdrop sender
* `setFeeReceiver(address)`, setup fee receiver, default is contract owner

### Rewards on airdrop

* `setRewardTokens([aToken, bToken])` Third party tokens reward list
* `configRewardRate(rewardToken, forSender, forReceiver)` Third party tokens reward rate for sepcify token 
* `addReward(rewardToken, amount)` Anyone can call this to deposit reward pool
* `withdrawReward(rewardToken, amount)` Only call by owner, should be call when migrate contracts

### multi airdrop

* `disperseEther(address[] recipients, uint256[] memory values)` Airdrop to receipients
* `disperseToken(IERC20 token, address[] memory recipients, uint256[] memory values)`  Airdrop token to receipients

