import brownie
from brownie import Contract
from brownie import chain
import pytest
from brownie import chain


def test_operation(accounts, token, vault, strategy, strategist, amount):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": accounts[0]})
    vault.deposit(amount, {"from": accounts[0]})
    assert token.balanceOf(vault.address) == amount

    # harvest
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=1e-5) == amount

    # tend()
    strategy.tend()

    # withdrawal
    vault.withdraw({"from": accounts[0]})
    assert pytest.approx(token.balanceOf(accounts[0]), rel=1e-5) == amount


def test_emergency_exit(accounts, token, vault, strategy, strategist, amount):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": accounts[0]})
    vault.deposit(amount, {"from": accounts[0]})
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=1e-5) == amount

    # set emergency and exit
    strategy.setEmergencyExit()
    strategy.harvest()

    assert strategy.estimatedTotalAssets() < amount


def test_profitable_harvest(
    accounts,
    token,
    vault,
    strategy,
    strategist,
    amount,
    underlying_vault_strategy,
    underlying_vault_strategy_strategist,
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": accounts[0]})
    vault.deposit(amount, {"from": accounts[0]})
    assert token.balanceOf(vault.address) == amount

    # harvest
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=1e-5) == amount

    chain.sleep(3600 * 24 * 30)
    # Fist harvest the underlying strategy
    underlying_vault_strategy.harvest({"from": underlying_vault_strategy_strategist})
    strategy.harvest()

    assert pytest.approx(strategy.estimatedTotalAssets(), rel=1e-5) == amount

    assert token.balanceOf(vault.address) > 0


def test_change_debt(gov, token, vault, strategy, strategist, amount):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": gov})
    vault.deposit(amount, {"from": gov})
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    strategy.harvest()
    half = int(amount / 2)

    assert pytest.approx(strategy.estimatedTotalAssets(), rel=1e-5) == half

    vault.updateStrategyDebtRatio(strategy.address, 10_000, {"from": gov})
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=1e-5) == amount

    # In order to pass this tests, you will need to implement prepareReturn.
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=1e-5) == half


def test_sweep(gov, vault, strategy, token, amount, weth, weth_amout):
    # Strategy want token doesn't work
    token.transfer(strategy, amount, {"from": gov})
    assert token.address == strategy.want()
    assert token.balanceOf(strategy) > 0
    with brownie.reverts("!want"):
        strategy.sweep(token, {"from": gov})

    # Vault share token doesn't work
    with brownie.reverts("!shares"):
        strategy.sweep(vault.address, {"from": gov})

    # Protected token doesn't work
    with brownie.reverts("!protected"):
        strategy.sweep("0x374513251ef47DB34047f07998e31740496c6FaA", {"from": gov})

    weth.transfer(strategy, weth_amout, {"from": gov})
    assert weth.address != strategy.want()
    assert weth.balanceOf(gov) == 0
    strategy.sweep(weth, {"from": gov})
    assert weth.balanceOf(gov) == weth_amout


def test_triggers(
    gov,
    vault,
    strategy,
    token,
    amount,
    weth,
    weth_amout,
    underlying_vault_strategy,
    underlying_vault_strategy_strategist,
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": gov})
    vault.deposit(amount, {"from": gov})
    strategy.harvest()

    strategy.setDebtThreshold(10 ** (token.decimals() - 2))
    strategy.setMaxReportDelay(3600 * 24 * 60)

    chain.sleep(1)
    underlying_vault_strategy.harvest({"from": underlying_vault_strategy_strategist})

    assert False == strategy.harvestTrigger("0.01 ether")
    chain.sleep(3600 * 24 * 30)
    underlying_vault_strategy.harvest({"from": underlying_vault_strategy_strategist})

    assert False == strategy.harvestTrigger("0.01 ether")
    assert True == strategy.harvestTrigger("0.001 ether")


def test_report_apy(
    gov,
    vault,
    strategy,
    token,
    amount,
    weth,
    weth_amout,
    underlying_vault_strategy,
    underlying_vault_strategy_strategist,
):
    token.approve(vault.address, amount, {"from": gov})
    vault.deposit(amount, {"from": gov})

    for x in range(0, 4):
        chain.sleep(3600 * 24 * 7)
        underlying_vault_strategy.harvest(
            {"from": underlying_vault_strategy_strategist}
        )
        strategy.harvest({"from": gov})

    amountAfter = vault.totalDebt() + token.balanceOf(vault)

    print(
        f"APR calculated over a month without componding: { (((amountAfter - amount) / amount * 100 * 12))}"
    )
    print(
        f"APR calculated over a month, with  componding: { (1 + ((amountAfter - amount) / amount)) ** 12 * 100}"
    )
