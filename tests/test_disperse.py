import brownie
from brownie import LuckyMoney

ZERO = "0x0000000000000000000000000000000000000000"

def test_disperse(gov, john, wick, geek, luckyMoney, luckyMoneyInit):
    gov.transfer(geek, "20 ether")

    bal_john = john.balance()
    bal_wick = wick.balance()
    bal_geek = geek.balance()
    bal_gov = gov.balance()


    recipients = []
    values = []
    for i in range(1000):
        recipients.append(john)
        values.append("0.01 ether")
    value = "10.01 ether"
    luckyMoney.disperseEther(recipients, values, {'from': geek, 'value': value})

    assert john.balance() - bal_john == "10 ether"

    # luckyMoney.disperseEther([john, wick], ["1 ether", "2 ether"], {'from': geek, 'value': "3.003 ether"})
    # assert john.balance() - bal_john == "1 ether"
    # assert wick.balance() - bal_wick == "2 ether"
    # # fee receiver, 0.1%
    # assert gov.balance() - bal_gov == "0.003 ether"
    # assert bal_geek - geek.balance() == "3.003 ether"

    with brownie.reverts("incorrect amount of eth transferred"):
        luckyMoney.disperseEther([john, wick], ["3 ether", "7 ether"], {'from': gov, 'value': "5 ether"})


def test_disperse_token(gov, john, wick, geek, wbtc, luckyMoney, luckyMoneyInit):
    wbtc.transfer(geek, "10 ether", {"from": gov})
    wbtc.approve(luckyMoney, 2**256-1, {"from": geek})

    bal_john = wbtc.balanceOf(john)
    bal_wick = wbtc.balanceOf(wick)
    bal_geek = wbtc.balanceOf(geek)
    bal_gov = wbtc.balanceOf(gov)

    luckyMoney.disperseToken(wbtc, [john, wick], ["1 ether", "2 ether"], {"from": geek})
    assert wbtc.balanceOf(john) - bal_john == "1 ether"
    assert wbtc.balanceOf(wick) - bal_wick == "2 ether"
    # fee receiver, 0.1%
    assert wbtc.balanceOf(gov) - bal_gov == "0.003 ether"
    assert bal_geek - wbtc.balanceOf(geek) == "3.003 ether"

    with brownie.reverts():
        luckyMoney.disperseToken(wbtc, [john, wick], ["5 ether", "6 ether"], {'from': geek})

# disperse same token and reward, edge case test
def test_disperse_with_reward(gov, john, wick, geek, luckyMoney, wbtc, luckyMoneyInit):
    gov.transfer(geek, "10 ether")
    wbtc.transfer(geek, "10 ether", {"from": gov})
    wbtc.approve(luckyMoney, 2**256-1, {"from": gov})
    wbtc.approve(luckyMoney, 2**256-1, {"from": geek})
    # Reward config
    luckyMoney.setRewardTokens([wbtc], {"from": gov})
    luckyMoney.configRewardRate(wbtc, "0.01 ether", "0.001 ether", {"from": gov})

    bal_john = wbtc.balanceOf(john)
    bal_wick = wbtc.balanceOf(wick)
    bal_geek = wbtc.balanceOf(geek)
    bal_gov = wbtc.balanceOf(gov)
    bal_contract = wbtc.balanceOf(luckyMoney)

    luckyMoney.addReward(wbtc, "1 ether", {"from": gov})
    luckyMoney.disperseToken(wbtc, [john, wick], ["1 ether", "2 ether"], {"from": geek})
    luckyMoney.withdrawReward(wbtc, "0.988 ether", {"from": gov})

    # receiver got 0.001 wbtc as reward
    assert wbtc.balanceOf(john) - bal_john == "1.001 ether"
    assert wbtc.balanceOf(wick) - bal_wick == "2.001 ether"
    # addReward with 0.012 (1 - 0.01 - 0.001*2) wbtc - fee receiver 0.1%
    assert bal_gov - wbtc.balanceOf(gov) == "0.009 ether"
    # dipserse 3 wbtc + pay 0.1% fee - 0.01 wbtc reward
    assert bal_geek - wbtc.balanceOf(geek) == "2.993 ether"

    # anyone can add reward
    luckyMoney.addReward(wbtc, "1 ether", {"from": geek})

    with brownie.reverts():
        luckyMoney.addReward(wbtc, "1000 ether", {"from": geek})

    with brownie.reverts("remain reward not enough to withdraw"):
        luckyMoney.withdrawReward(wbtc, "10 ether", {"from": gov})
        luckyMoney.withdrawReward(ZERO, "0.1 ether", {"from": gov})
