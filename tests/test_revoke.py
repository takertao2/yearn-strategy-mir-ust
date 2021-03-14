import pytest


def test_revoke_strategy_from_vault(token, vault, strategy, amount, gov):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": gov})
    vault.deposit(amount, {"from": gov})
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=4 * 1e-3) == amount

    vault.revokeStrategy(strategy.address, {"from": gov})
    strategy.harvest()
    assert pytest.approx(token.balanceOf(vault.address), rel=4 * 1e-3) == amount


def test_revoke_strategy_from_strategy(token, vault, strategy, amount, gov):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": gov})
    vault.deposit(amount, {"from": gov})
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=4 * 1e-3) == amount

    strategy.setEmergencyExit()
    strategy.harvest()
    assert pytest.approx(token.balanceOf(vault.address), rel=4 * 1e-3) == amount
