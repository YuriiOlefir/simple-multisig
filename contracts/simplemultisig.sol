// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleMultisig {
    uint256 private creationTime;
    IERC20 public token;

    ////uint8 private numMembers;
    mapping(address => bool) private members;

    // Заявление на рассылку токенов
    struct Application {
        address sender;
        address recipient;
        uint256 amount;
        mapping(address => bool) confirms;
        uint8 numConfirms;
        bool success;
        bool canceled;
        uint256 endTime;
    }

    uint256 private numApps;
    mapping(uint256 => Application) private apps;

    constructor(IERC20 _token) {
        token = _token;
        //members[addr1] = true;
        //members[addr2] = true;
        //members[addr3] = true;
        //members[addr4] = true;
        //members[addr5] = true;
        ////numMembers = 5;
        creationTime = block.timestamp;
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
        require(apps[_appId].canceled == false, "This application was canceled");
        require(apps[_appId].success == false, "This application has already been applied");
        require(block.timestamp <= apps[_appId].endTime, "This application is out of time");
        _;
    }

    // Подача заявления на рассылку токенов
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
        //a.canceled = false;
        a.endTime = block.timestamp + _duration;
        ++numApps;
        emit appSubmitted(msg.sender, _recipient, _amount, newAppId, a.endTime);
    }

    // Подтверждение заявления
    function confirmApp(uint256 _appId, bool _answerYes) external onlyMember validAppId(_appId) validApp(_appId) {
        Application storage a = apps[_appId];

        require(a.confirms[msg.sender] == false, "You have already confirmed the application");

        if (_answerYes) {
            a.confirms[msg.sender] = true;
            ++a.numConfirms;
            emit appConfirmed(msg.sender, _appId, a.numConfirms);
        }
        if (a.numConfirms == 3) acceptApp(_appId);
    }

    // Отзыв подтверждения заявления
    function withdrawConfirm(uint256 _appId) external onlyMember validAppId(_appId) validApp(_appId) {
        Application storage a = apps[_appId];

        require(a.confirms[msg.sender], "You have not confirmed the application yet");

        a.confirms[msg.sender] = false;
        --a.numConfirms;
        emit confirmWithdrawn(msg.sender, _appId, a.numConfirms);
        if (a.numConfirms == 0) cancelApp(_appId);
    }

    // Принятие заявления и рассылка токенов
    function acceptApp(uint256 _appId) private {
        Application storage a = apps[_appId];
        if (a.amount <= token.balanceOf(address(this))) {
            token.transfer(a.recipient, a.amount);
            a.success = true;
            emit appAccepted(_appId);
        } else cancelApp(_appId);
    }

    // Отмена заявления
    function cancelApp(uint256 _appId) private {
        Application storage a = apps[_appId];
        a.canceled = true;
        emit appCanceled(_appId);
    }

    // Узнать количество подтвердивших заявление
    function getAppConfirms(uint256 _appId) external view onlyMember validAppId(_appId) returns (uint8) {
        return apps[_appId].numConfirms;
    }

    // Узнать баланс токена
    function getBalance() external view onlyMember returns (uint256) {
        return token.balanceOf(address(this));
    }

    // Узнать время создания контракта
    function getCreationTime() external view onlyMember returns (uint256) {
        return creationTime;
    }

    // Узнать: есть ли участник с таким адресом
    function isMember(address _addr) external view onlyMember returns (bool) {
        return members[_addr];
    }

    event appSubmitted(address sender, address recipient, uint256 amount, uint256 appId, uint256 endTime);

    event appAccepted(uint256 appId);

    event appCanceled(uint256 appId);

    event appConfirmed(address sender, uint256 appId, uint8 numConfirms);

    event confirmWithdrawn(address sender, uint256 appId, uint8 numConfirms);
}
