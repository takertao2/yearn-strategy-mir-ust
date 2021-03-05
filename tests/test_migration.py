# TODO: Add tests that show proper migration of the strategy to a newer one
#       Use another copy of the strategy to simulate the migration
#       Show that nothing is lost!
import pytest


def test_migration(token, vault, strategy, amount, Strategy, strategist, gov):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": gov})
    vault.deposit(amount, {"from": gov})
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=4 * 1e-3) == amount

    # migrate to a new strategy
    new_strategy = strategist.deploy(Strategy, vault)
    strategy.migrate(new_strategy.address, {"from": gov})
    assert pytest.approx(new_strategy.estimatedTotalAssets(), rel=4 * 1e-3) == amount
