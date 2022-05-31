import pytest

from brownie import web3
from brownie.network import gas_price


@pytest.fixture
def gov(accounts):
    yield accounts[0]

@pytest.fixture
def john(accounts):
    yield accounts[1]

@pytest.fixture
def wick(accounts):
    yield accounts[2]

@pytest.fixture
def victory(accounts):
    yield accounts[3]

@pytest.fixture
def geek(accounts):
    yield accounts[4]

@pytest.fixture
def wbtc(gov, Token):
    yield gov.deploy(Token, "Wrapped BTC", "WBTC", 18, "21000000 ether")

@pytest.fixture
def luckyMoney(gov, LuckyMoney):
    gas_price('auto')
    yield gov.deploy(LuckyMoney)

@pytest.fixture
def luckyMoneyInit(gov, luckyMoney):
    gas_price('auto')
    luckyMoney.initialize(gov.address, gov.address, {'from': gov})
