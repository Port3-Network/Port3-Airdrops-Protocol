import brownie, time
from brownie import chain, accounts, LuckyMoney
import eth_keys
from hexbytes import HexBytes
from eth_account._utils.signing import sign_message_hash


ZERO = "0x0000000000000000000000000000000000000000"
priv_key = "0x416b8a7d9290502f5661da81f0cf43893e3d19cb9aea3c426cfb36e8186e9c09"
addr = "0x14b0Ed2a7C4cC60DD8F676AE44D0831d3c9b2a9E"

def test_sign(gov, john, wick, victory, geek, luckyMoney, luckyMoneyInit):
    creator = accounts.add(priv_key)
    gov.transfer(creator, "10 ether")
    b_creator = creator.balance()
    b_john = john.balance()
    b_wick = wick.balance()
    b_gov = gov.balance()

    expire = chain.time() + 200000
    # 1 ether for luckyMoney
    # 0.001 ether (0.1%) for fee
    # 0.001 ether for refund
    tx = luckyMoney.create(expire, 1, ZERO, "1 ether", 4, {"from": creator, "value": "1.002 ether"})
    luckyMoneyId = tx.return_value;

    def submit(collector):
        # logic modified from https://github.com/eth-brownie/brownie/blob/af0be999c348cbba83c9f331da6a3dde96d0e007/brownie/network/account.py#L911
        # brownie use length of str
        # but we need to use fix length for bytes32
        msg = luckyMoney.getEthSignedMessageHash(luckyMoneyId, collector)
        eth_private_key = eth_keys.keys.PrivateKey(HexBytes(priv_key))
        (v, r, s, eth_signature_bytes) = sign_message_hash(eth_private_key, msg)

        # web3签名
        # from eth_account.messages import encode_defunct
        # msg = encode_defunct(hexstr=str(luckyMoney.getMessageHash(luckyMoneyId, collector)))
        # eth_signature_bytes = web3.eth.account.sign_message(msg, priv_key).signature

        luckyMoney.submit(luckyMoneyId, eth_signature_bytes, {"from": collector})

    submit(john)
    submit(wick)
    with brownie.reverts("luckyMoney not fully collected or expired"):
        luckyMoney.distribute(luckyMoneyId)

    # if luckyMoney being fully collected, anyone could distribute even it hasn't expired
    chain.snapshot()
    submit(victory)
    submit(geek)
    luckyMoney.distribute(luckyMoneyId, {"from": wick})
    chain.revert()

    chain.sleep(210000)
    chain.mine(1)
    luckyMoney.distribute(luckyMoneyId, {"from": wick})
    assert b_creator - creator.balance() == "0.502 ether"
    assert john.balance() - b_john == "0.25 ether"
    # extra 0.001 ether is refund
    assert wick.balance() - b_wick == "0.251 ether"
    # fee receiver
    assert gov.balance() - b_gov == "0.001 ether"
