pragma solidity 0.6.12;

interface MMFarmingPool {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function userInfo(uint256, address)
        external
        view
        returns (uint256 amount, uint256 rewardDebt);

    function pendingMM(uint256 _pid, address _user)
        external
        view
        returns (uint256);
}

interface MMVault {
    function token() external view returns (address);

    function getRatio() external view returns (uint256);

    function deposit(uint256) external;

    function withdraw(uint256) external;

    function withdrawAll() external;

    function earn() external;

    function balance() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address _user) external view returns (uint256);
}
