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

    event TokensTransferedToThis(address sender, uint256 amount);

    event AppSubmitted(address sender, address recipient, uint256 amount, uint256 appID, uint256 endTime);

    event AppAccepted(uint256 appID);

    event AppCanceled(uint256 appID);

    event AppConfirmed(address sender, uint256 appID, uint8 numConfirms);

    event ConfirmWithdrawn(address sender, uint256 appID, uint8 numConfirms);

    constructor(IERC20 _token, address[] memory _members) {
        require(address(_token) != address(0), "Token zero address");
        require(_members.length == NUM_MEMBERS, "Must be 5 members");
        token = _token;
        for (uint256 i = 0; i < NUM_MEMBERS; ++i) {
            require(_members[i] != address(0), "Member zero address");
            members[_members[i]] = true;
        }
    }

    modifier nonzeroAmount(uint256 _amount) {
        require(_amount != 0, "The amount of token must be greater than zero");
        _;
    }

    modifier onlyMember() {
        require(members[msg.sender], "Only a member can use this function");
        _;
    }

    modifier validAppID(uint256 _appID) {
        require(apps[_appID].numConfirms != 0, "Unknown application ID");
        _;
    }

    modifier validApp(uint256 _appID) {
        require(apps[_appID].valid, "This application is not valid");
        require(!apps[_appID].success, "This application has already been applied");
        require(block.timestamp <= apps[_appID].endTime, "This application is out of time");
        _;
    }

    /// @notice Отправка токенов на этот контракт
    function transferToThis(uint256 _amount) external nonzeroAmount(_amount) {
        //token.transfer(address(this), _amount);
        emit TokensTransferedToThis(msg.sender, _amount);
    }

    /// @notice Подача заявления на рассылку токенов
    /// @param _duration Время жизни заявления в секундах
    function submitApp(
        address _recipient,
        uint256 _amount,
        uint256 _duration
    ) external onlyMember nonzeroAmount(_amount) returns (uint256 newAppID) {
        require(_recipient != address(0), "Zero recipient address");
        require(_amount <= token.balanceOf(address(this)), "Not enough tokens");
        require(_duration > 0, "Zero duration of the application");

        newAppID = numApps;
        Application storage a = apps[newAppID];
        a.sender = msg.sender;
        a.recipient = _recipient;
        a.amount = _amount;
        a.confirms[msg.sender] = true;
        a.numConfirms = 1;
        //a.success = false;
        a.valid = true;
        a.endTime = block.timestamp + _duration;
        ++numApps;
        emit AppSubmitted(msg.sender, _recipient, _amount, newAppID, a.endTime);
    }

    /// @notice Подтверждение заявления
    function confirmApp(uint256 _appID, bool _answerYes) external onlyMember validAppID(_appID) validApp(_appID) {
        Application storage a = apps[_appID];
        require(!a.confirms[msg.sender], "You have already confirmed the application");
        if (_answerYes) {
            a.confirms[msg.sender] = true;
            ++a.numConfirms;
            emit AppConfirmed(msg.sender, _appID, a.numConfirms);
        }
        if (a.numConfirms == THRESHOLD) acceptApp(_appID);
    }

    /// @notice Отзыв подтверждения заявления
    function withdrawConfirm(uint256 _appID) external onlyMember validAppID(_appID) validApp(_appID) {
        Application storage a = apps[_appID];
        require(a.confirms[msg.sender], "You have not confirmed the application yet");
        a.confirms[msg.sender] = false;
        --a.numConfirms;
        emit ConfirmWithdrawn(msg.sender, _appID, a.numConfirms);
        if (a.numConfirms == 0) cancelApp(_appID);
    }

    /// @notice Получение данных заявления
    function getAppInfo(uint256 _appID)
        external
        view
        validAppID(_appID)
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
        Application storage a = apps[_appID];
        return (a.sender, a.recipient, a.amount, a.numConfirms, a.success, a.valid, a.endTime);
    }

    /// @notice Проверка: подтвердил ли адрес заявление
    function isConfirmedBy(address _addr, uint256 _appID) external view validAppID(_appID) returns (bool) {
        require(_addr != address(0), "Zero address");
        if (apps[_appID].confirms[_addr]) return true;
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
    function acceptApp(uint256 _appID) private {
        Application storage a = apps[_appID];
        if (a.amount <= token.balanceOf(address(this))) {
            a.success = true;
            //////token.transferFrom(address(this), a.recipient, a.amount);
            //////////////token.transfer(a.recipient, a.amount);
            emit AppAccepted(_appID);
        } else {
            cancelApp(_appID);
        }
    }

    /// Отмена заявления
    function cancelApp(uint256 _appID) private {
        Application storage a = apps[_appID];
        a.valid = false;
        emit AppCanceled(_appID);
    }
}
