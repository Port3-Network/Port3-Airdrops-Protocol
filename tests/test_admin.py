import brownie
from brownie import LuckyMoney


def test_admin_functions(gov, geek, luckyMoney, wbtc, luckyMoneyInit):
    luckyMoney.setFeeRate(100, {"from": gov})
    luckyMoney.setFeeReceiver(geek, {"from": gov})
    luckyMoney.setRefundAmount("1 ether", {"from": gov})
    luckyMoney.setOwner(geek, {"from": gov})

    assert luckyMoney.feeRate() == 100
    assert luckyMoney.feeReceiver() == geek
    assert luckyMoney.refundAmount() == "1 ether"
    assert luckyMoney.owner() == geek

    with brownie.reverts("priviledged action"):
        luckyMoney.setFeeRate(100, {"from": gov})
        luckyMoney.setFeeReceiver(geek, {"from": gov})
        luckyMoney.setRefundAmount("1 ether", {"from": gov})
        luckyMoney.setOwner(geek, {"from": gov})
        luckyMoney.setRewardTokens([wbtc], {"from": gov})
        luckyMoney.configRewardRate(wbtc, "0.01 ether", "0.001 ether", {"from": gov})
        luckyMoney.withdrawReward(wbtc, 0, {"from": gov})

    luckyMoney.setOwner(gov, {"from": geek})
