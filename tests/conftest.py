import pytest
from brownie import config
from brownie import Contract
from brownie import chain
from datetime import datetime


@pytest.fixture(scope="function", autouse=True)
def shared_setup(fn_isolation):
    pass


@pytest.fixture
def gov(accounts):
    yield accounts[0]


@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts[4]


@pytest.fixture
def keeper(accounts):
    yield accounts[5]


@pytest.fixture
def token():
    token_address = (
        "0x87da823b6fc8eb8575a235a824690fda94674c88"  # Uniswap MIR/UST LP (UNI-V2)
    )
    yield Contract(token_address)


@pytest.fixture
def ust(accounts, uniswap):
    token_address = "0xa47c8bf37f92abed4a126bda807a7b7498661acd"
    ust = Contract(token_address)
    amount = 20_000 * (10 ** ust.decimals())
    reserve = accounts.at("0xa1d8d972560c2f8144af871db508f0b0b10a3fbf", force=True)
    ust.transfer(accounts[0], amount, {"from": reserve})
    ust.approve(uniswap, amount, {"from": accounts[0]})

    yield ust


@pytest.fixture
def mir(accounts, uniswap):
    token_address = "0x09a3ecafa817268f77be1283176b946c4ff2e608"
    mir = Contract(token_address)
    amount = 1000 * (10 ** mir.decimals())
    reserve = accounts.at("0xa1d8d972560c2f8144af871db508f0b0b10a3fbf", force=True)
    mir.transfer(accounts[0], amount, {"from": reserve})
    mir.approve(uniswap, amount, {"from": accounts[0]})

    yield mir


@pytest.fixture
def amount(accounts, token, mir, ust, uniswap):
    mir_price = uniswap.getAmountsOut(1 * 10 ** mir.decimals(), [mir, ust])[1]

    timestamp = chain.time() + 10
    amount = 1000
    amount_mir = amount * (10 ** mir.decimals())
    amount_ust = amount * mir_price  # mir and ust are 18 decimals

    uniswap.addLiquidity(
        mir,
        ust,
        amount_mir,
        amount_ust,
        1,
        1,
        accounts[0],
        timestamp,
        {"from": accounts[0]},
    )

    yield token.balanceOf(accounts[0])


@pytest.fixture
def uniswap():
    yield Contract("0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D")


@pytest.fixture
def weth():
    token_address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    yield Contract(token_address)


@pytest.fixture
def weth_amout(gov, weth):
    weth_amout = 10 ** weth.decimals()
    gov.transfer(weth, weth_amout)
    yield weth_amout


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault


@pytest.fixture
def strategy(strategist, keeper, vault, Strategy, gov):
    strategy = strategist.deploy(Strategy, vault)
    strategy.setKeeper(keeper)
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    strategy.setPathToSwap(
        [
            "0xa283aa7cfbb27ef0cfbcb2493dd9f4330e0fd304",
            "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
            "0xdac17f958d2ee523a2206206994597c13d831ec7",
            "0xa47c8bf37f92abed4a126bda807a7b7498661acd",
        ],
        {"from": strategist},
    )
    yield strategy


@pytest.fixture
def underlying_vault_strategy():
    yield Contract("0x0a625d31ebf6e8a93c54911075b00de881549b92")


@pytest.fixture
def underlying_vault_strategy_strategist(accounts, underlying_vault_strategy):
    yield accounts.at(underlying_vault_strategy.strategist(), force=True)
