// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {MMFarmingPool, MMVault} from "../interfaces/MM.sol";
import {IUniswapV2Router02, IUniswapV2Pair} from "../interfaces/Uniswap.sol";

import {Babylonian} from "./Libraries.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    event DepoistedOnMMFarmingPool(uint256 amount);
    event Debug(uint256 want, uint256 debt);

    address public constant unirouter =
        address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public constant mmVault =
        address(0x374513251ef47DB34047f07998e31740496c6FaA);
    address public constant mmFarmingPool =
        address(0xf8873a6080e8dbF41ADa900498DE0951074af577);
    uint256 public constant mmFarmingPoolId = 6;

    address public constant mm =
        address(0xa283aA7CfBB27EF0cfBcb2493dD9F4330E0fd304);
    address public constant mir =
        address(0x09a3EcAFa817268f77BE1283176B946C4ff2E608);
    address public constant ust =
        address(0xa47c8bf37f92aBed4A126BDA807A7b7498661acD);

    uint256 public minMMToSwap = 10; // min $MM to swap during adjustPosition()
    address[] private pathToSwap;

    constructor(address _vault) public BaseStrategy(_vault) {
        want.safeApprove(mmVault, uint256(-1));
        IERC20(mmVault).safeApprove(mmFarmingPool, uint256(-1));
        IERC20(mm).safeApprove(unirouter, uint256(-1));
        IERC20(ust).safeApprove(unirouter, uint256(-1));
        IERC20(mir).safeApprove(unirouter, uint256(-1));
    }

    function setMinMMToSwap(uint256 _minMMToSwap) external onlyAuthorized {
        minMMToSwap = _minMMToSwap;
    }

    function setPathToSwap(address[] calldata _path) external onlyAuthorized {
        pathToSwap = _path;
    }

    function name() external view override returns (string memory) {
        return "StrategyMM-MIR-USTLP";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        (uint256 _mToken, ) =
            MMFarmingPool(mmFarmingPool).userInfo(
                mmFarmingPoolId,
                address(this)
            );
        uint256 _mmVault = IERC20(mmVault).balanceOf(address(this));
        return
            _convertMTokenToWant(_mToken.add(_mmVault)).add(
                want.balanceOf(address(this))
            );
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // Pay debt if any
        if (_debtOutstanding > 0) {
            (uint256 _amountFreed, uint256 _reportLoss) =
                liquidatePosition(_debtOutstanding);
            _debtPayment = _amountFreed > _debtOutstanding
                ? _debtOutstanding
                : _amountFreed;
            _loss = _reportLoss;
        }

        // Claim profit
        _profit = claimMM();
        return (_profit, _loss, _debtPayment);
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
            return;
        }

        uint256 _before = IERC20(mmVault).balanceOf(address(this));
        uint256 _after = _before;
        uint256 _want = want.balanceOf(address(this));

        emit Debug(_want, _debtOutstanding);

        if (_want > _debtOutstanding) {
            _want = _want.sub(_debtOutstanding);

            MMVault(mmVault).deposit(_want);

            _after = IERC20(mmVault).balanceOf(address(this));
            require(_after > _before, "!mismatchDepositIntoMushrooms");
        } else if (_debtOutstanding > _want) {
            return;
        }

        emit DepoistedOnMMFarmingPool(_after);

        if (_after > 0) {
            MMFarmingPool(mmFarmingPool).deposit(mmFarmingPoolId, _after);
            emit DepoistedOnMMFarmingPool(_after);
        }
    }

    function claimMM() internal returns (uint256) {
        uint256 _pendingMM =
            MMFarmingPool(mmFarmingPool).pendingMM(
                mmFarmingPoolId,
                address(this)
            );
        if (_pendingMM > minMMToSwap) {
            MMFarmingPool(mmFarmingPool).withdraw(mmFarmingPoolId, 0);
        }
        return _disposeOfMM();
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        bool liquidateAll =
            _amountNeeded >= estimatedTotalAssets() ? true : false;

        if (liquidateAll) {
            (uint256 _mToken, ) =
                MMFarmingPool(mmFarmingPool).userInfo(
                    mmFarmingPoolId,
                    address(this)
                );
            MMFarmingPool(mmFarmingPool).withdraw(mmFarmingPoolId, _mToken);
            MMVault(mmVault).withdraw(IERC20(mmVault).balanceOf(address(this)));
            _liquidatedAmount = IERC20(want).balanceOf(address(this));
            return (
                _liquidatedAmount,
                _liquidatedAmount < vault.strategies(address(this)).totalDebt
                    ? vault.strategies(address(this)).totalDebt.sub(
                        _liquidatedAmount
                    )
                    : 0
            );
        } else {
            uint256 _before = IERC20(want).balanceOf(address(this));
            if (_before < _amountNeeded) {
                uint256 _gap = _amountNeeded.sub(_before);
                uint256 _mShare =
                    _gap.mul(1e18).div(MMVault(mmVault).getRatio());

                uint256 _mmVault = IERC20(mmVault).balanceOf(address(this));
                if (_mmVault < _mShare) {
                    uint256 _mvGap = _mShare.sub(_mmVault);
                    (uint256 _mToken, ) =
                        MMFarmingPool(mmFarmingPool).userInfo(
                            mmFarmingPoolId,
                            address(this)
                        );
                    require(
                        _mToken >= _mvGap,
                        "!insufficientMTokenInMasterChef"
                    );
                    MMFarmingPool(mmFarmingPool).withdraw(
                        mmFarmingPoolId,
                        _mvGap
                    );
                }
                MMVault(mmVault).withdraw(_mShare);
                uint256 _after = IERC20(want).balanceOf(address(this));
                require(_after > _before, "!mismatchMushroomsVaultWithdraw");

                return (
                    _after,
                    _amountNeeded > _after ? _amountNeeded.sub(_after) : 0
                );
            } else {
                return (_amountNeeded, _loss);
            }
        }
    }

    function harvestTrigger(uint256 callCost)
        public
        view
        override
        returns (bool)
    {
        StrategyParams memory params = vault.strategies(address(this));

        // Should not trigger if Strategy is not activated
        if (params.activation == 0) return false;

        // Should not trigger if we haven't waited long enough since previous harvest
        if (block.timestamp.sub(params.lastReport) < minReportDelay)
            return false;

        // Should trigger if hasn't been called in a while
        if (block.timestamp.sub(params.lastReport) >= maxReportDelay)
            return true;

        // If some amount is owed, pay it back
        // NOTE: Since debt is based on deposits, it makes sense to guard against large
        //       changes to the value from triggering a harvest directly through user
        //       behavior. This should ensure reasonable resistance to manipulation
        //       from user-initiated withdrawals as the outstanding debt fluctuates.
        uint256 outstanding = vault.debtOutstanding();
        if (outstanding > debtThreshold) return true;

        // Check for profits and losses
        uint256 total = estimatedTotalAssets();
        // Trigger if we have a loss to report
        if (total.add(debtThreshold) < params.totalDebt) return true;

        uint256 profit = 0;
        if (total > params.totalDebt) profit = total.sub(params.totalDebt); // We've earned a profit!

        // Otherwise, only trigger if it "makes sense" economically (gas cost
        // is <N% of value moved)
        uint256 credit = vault.creditAvailable();
        return (profitFactor.mul(callCost) < credit.add(profit));
    }

    function prepareMigration(address _newStrategy) internal override {
        (uint256 _mToken, ) =
            MMFarmingPool(mmFarmingPool).userInfo(
                mmFarmingPoolId,
                address(this)
            );
        MMFarmingPool(mmFarmingPool).withdraw(mmFarmingPoolId, _mToken);

        uint256 _mmVault = IERC20(mmVault).balanceOf(address(this));
        if (_mmVault > 0) {
            IERC20(mmVault).safeTransfer(_newStrategy, _mmVault);
        }

        uint256 _mm = IERC20(mm).balanceOf(address(this));
        if (_mm > 0) {
            IERC20(mm).safeTransfer(_newStrategy, _mm);
        }
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](1);
        protected[0] = mmVault;
        return protected;
    }

    function _convertMTokenToWant(uint256 _shares)
        internal
        view
        returns (uint256)
    {
        uint256 _mTokenTotal = IERC20(mmVault).totalSupply();
        if (_mTokenTotal == 0) {
            return 0;
        }
        uint256 _wantInVault = MMVault(mmVault).balance();
        return (_wantInVault.mul(_shares)).div(_mTokenTotal);
    }

    function _disposeOfMM() internal returns (uint256) {
        uint256 mmBalance = IERC20(mm).balanceOf(address(this));

        if (mmBalance < minMMToSwap) {
            return 0;
        }

        uint256 _wantProfit;
        IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(unirouter);
        uniswapV2Router.swapExactTokensForTokens(
            mmBalance,
            uint256(1),
            pathToSwap,
            address(this),
            now + 180
        ); // swap MM to UST

        uint256 ustAmount = IERC20(ust).balanceOf(address(this));

        (uint256 res0, uint256 reserveIn, ) =
            IUniswapV2Pair(address(want)).getReserves();

        address[] memory path = new address[](2);
        path[0] = ust;
        path[1] = mir;

        uint256[] memory amounts;

        uint256 amountToSwap = calculateSwapInAmount(reserveIn, ustAmount);

        amounts = uniswapV2Router.swapExactTokensForTokens(
            amountToSwap,
            0,
            path,
            address(this),
            now + 180
        );

        (uint256 amountA, uint256 amountB, uint256 LP) =
            uniswapV2Router.addLiquidity(
                ust,
                mir,
                ustAmount - amountToSwap,
                amounts[1],
                1,
                1,
                address(this),
                now + 60
            );

        emit Debug(123, LP);

        return LP;
    }

    function calculateSwapInAmount(uint256 reserveIn, uint256 userIn)
        public
        pure
        returns (uint256)
    {
        return
            Babylonian
                .sqrt(
                reserveIn.mul(userIn.mul(3988000) + reserveIn.mul(3988009))
            )
                .sub(reserveIn.mul(1997)) / 1994;
    }
}