// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @author Yurii
contract SimpleMultisig {
    /// Заявление на рассылку токенов
    struct Application {
        address sender;
        address recipient;
        uint256 amount;
        mapping(address => bool) confirms;
        uint8 numConfirms;
        bool success;
        bool valid;
        uint256 endTime;
    }

    IERC20 public token;

    uint8 private constant NUM_MEMBERS = 5;
    mapping(address => bool) private members;
    uint8 private constant THRESHOLD = 3;

    uint256 private numApps;
    mapping(uint256 => Application) private apps;

    event AppSubmitted(address sender, address recipient, uint256 amount, uint256 appId, uint256 endTime);

    event AppAccepted(uint256 appId);

    event AppCanceled(uint256 appId);

    event AppConfirmed(address sender, uint256 appId, uint8 numConfirms);

    event ConfirmWithdrawn(address sender, uint256 appId, uint8 numConfirms);

    constructor(IERC20 _token, address[] memory _members) {
        require(address(_token) != address(0), "Token zero address");
        require(_members.length == NUM_MEMBERS, "Must be 5 members");
        token = _token;
        for (uint256 i = 0; i < NUM_MEMBERS; ++i) {
            require(_members[i] != address(0), "Member zero address");
            members[_members[i]] = true;
        }
    }

    modifier onlyMember() {
        require(members[msg.sender], "Only a member can use this function");
        _;
    }

    modifier validAppId(uint256 _appId) {
        require(apps[_appId].numConfirms != 0, "Unknown application ID");
        _;
    }

    modifier validApp(uint256 _appId) {
        require(apps[_appId].valid, "This application is not valid");
        require(!apps[_appId].success, "This application has already been applied");
        require(block.timestamp <= apps[_appId].endTime, "This application is out of time");
        _;
    }

    /// @notice Подача заявления на рассылку токенов
    /// @param _duration Время жизни заявления в секундах
    function submitApp(
        address _recipient,
        uint256 _amount,
        uint8 _duration
    ) external onlyMember returns (uint256 newAppId) {
        require(_recipient != address(0), "Zero recipient address");
        require(_amount != 0, "The amount of token must be greater than zero");
        require(_amount <= token.balanceOf(address(this)), "Not enough tokens");
        require(_duration > 0, "Zero duration of the application");

        newAppId = numApps;
        Application storage a = apps[newAppId];
        a.sender = msg.sender;
        a.recipient = _recipient;
        a.amount = _amount;
        a.confirms[msg.sender] = true;
        a.numConfirms = 1;
        //a.success = false;
        a.valid = true;
        a.endTime = block.timestamp + _duration;
        ++numApps;
        emit AppSubmitted(msg.sender, _recipient, _amount, newAppId, a.endTime);
    }

    /// @notice Подтверждение заявления
    function confirmApp(uint256 _appId, bool _answerYes) external onlyMember validAppId(_appId) validApp(_appId) {
        Application storage a = apps[_appId];
        require(!a.confirms[msg.sender], "You have already confirmed the application");
        if (_answerYes) {
            a.confirms[msg.sender] = true;
            ++a.numConfirms;
            emit AppConfirmed(msg.sender, _appId, a.numConfirms);
        }
        if (a.numConfirms == THRESHOLD) acceptApp(_appId);
    }

    /// @notice Отзыв подтверждения заявления
    function withdrawConfirm(uint256 _appId) external onlyMember validAppId(_appId) validApp(_appId) {
        Application storage a = apps[_appId];
        require(a.confirms[msg.sender], "You have not confirmed the application yet");
        a.confirms[msg.sender] = false;
        --a.numConfirms;
        emit ConfirmWithdrawn(msg.sender, _appId, a.numConfirms);
        if (a.numConfirms == 0) cancelApp(_appId);
    }

    /// @notice Получение данных заявления
    function getAppInfo(uint256 _appId)
        external
        view
        validAppId(_appId)
        returns (
            address sender,
            address recipient,
            uint256 amount,
            uint8 numConfirms,
            bool success,
            bool valid,
            uint256 endTime
        )
    {
        Application storage a = apps[_appId];
        return (a.sender, a.recipient, a.amount, a.numConfirms, a.success, a.valid, a.endTime);
    }

    /// @notice Проверка: подтвердил ли адрес заявление
    function isConfirmedBy(address _addr, uint256 _appId) external view validAppId(_appId) returns (bool) {
        require(_addr != address(0), "Zero address");
        if (apps[_appId].confirms[_addr]) return true;
        return false;
    }

    /// @notice Получение баланса токена
    function getBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /// @notice Проверка: есть ли участник с таким адресом
    function isMember(address _addr) external view returns (bool) {
        require(_addr != address(0), "Zero address");
        return members[_addr];
    }

    /// Принятие заявления и рассылка токенов
    function acceptApp(uint256 _appId) private {
        Application storage a = apps[_appId];
        if (a.amount <= token.balanceOf(address(this))) {
            token.transfer(a.recipient, a.amount);
            a.success = true;
            emit AppAccepted(_appId);
        } else {
            cancelApp(_appId);
        }
    }

    /// Отмена заявления
    function cancelApp(uint256 _appId) private {
        Application storage a = apps[_appId];
        a.valid = false;
        emit AppCanceled(_appId);
    }
}
