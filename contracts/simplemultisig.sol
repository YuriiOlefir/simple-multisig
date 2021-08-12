// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleMultisig {
    IERC20 public token;

    //uint8 numMembers;
    mapping (address => bool) public members;

    // Заявление на рассылку токенов
    struct Application {
        address sender;
        address recipient;
        uint256 amount;
        mapping (address => bool) confirms;
        uint8 numConfirms;
        bool success;
        bool canceled;
		uint256 endTime;
    }
    
    uint256 numApps;
    mapping (uint256 => Application) public apps;

    event appSubmitted(	address sender,
                       	address recipient,
                        uint256 amount,
                        uint256 appId,
						uint256 endTime		);

    event appAccepted(uint256 appId);

    event appCanceled(uint256 appId);

    event appConfirmed(	address sender,
                        uint256 appId,
                        uint8 numConfirms );

    event confirmWithdrawn(	address sender,
                            uint256 appId,
                            uint8 numConfirms );

    constructor(IERC20 _token) {
        token = _token;
        //members[addr1] = true;
        //members[addr2] = true;
        //members[addr3] = true;
        //members[addr4] = true;
        //members[addr5] = true;
        ////numMembers = 5;
    }

    // Подача заявления на рассылку токенов
    function submitApp(address _recipient, uint256 _amount, uint8 _duration) external returns (uint256 newAppId) {

        require(members[msg.sender],
                "Only the member can submit the application to send token");

        require(_recipient != address(0),
                "Invalid recipient address");

        require(_amount != 0,
                "The amount of token must be greater than zero");

        require(_amount <= token.balanceOf(address(this)),
                "Not enough tokens");

		require(_duration > 0,
				"Zero duration of the application");

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
    function confirmApp(uint256 _appId, bool _answerYes) external {

        require(members[msg.sender],
                "Only the member can confirm an application");

        Application storage a = apps[_appId];

        require(a.numConfirms != 0,
                "Unknown application identifier");

        require(a.confirms[msg.sender] == false,
                "You have already confirmed the application");

        require(a.canceled == false,
                "This application was canceled");

        require(a.success == false,
                "This application has already been applied");

		require(block.timestamp <= a.endTime,
                "This application is out of time");

        if (_answerYes)
        {
            a.confirms[msg.sender] = true;
            a.numConfirms++;
            emit appConfirmed(msg.sender, _appId, a.numConfirms);
        }
        if (a.numConfirms == 3)
            acceptApp(_appId);
    }

    // Отзыв подтверждения заявления
    function withdrawConfirm(uint256 _appId) external {

        require(members[msg.sender],
                "Only the member can confirm the application");

        Application storage a = apps[_appId];

        require(a.numConfirms != 0,
                "Unknown application identifier");

        require(a.confirms[msg.sender],
                "You have not confirmed the application yet");

        require(a.canceled == false,
                "This application was canceled");

        require(a.success == false,
                "This application has already been applied");
		
		require(block.timestamp <= a.endTime,
                "This application is out of time");

        a.confirms[msg.sender] = false;
        --a.numConfirms;
        emit confirmWithdrawn(msg.sender, _appId, a.numConfirms);
    }

    // Принятие заявления и рассылка токенов
    function acceptApp(uint256 _appId) private {
        Application storage a = apps[_appId];
        if (a.amount <= token.balanceOf(address(this)))
        {
			token.transfer(a.recipient, a.amount);
            a.success = true;
            emit appAccepted(_appId);
        }
        else
            cancelApp(_appId);
    }

    // Отмена заявления
    function cancelApp(uint256 _appId) private {
        Application storage a = apps[_appId];
        a.canceled = true;
		emit appCanceled(_appId);
    }

    // Узнать количество подтвердивших заявление
    function getAppConfirms(uint256 _appId) external view returns (uint8) {
        
        require(members[msg.sender],
                "Only the member can get the number of confirmations of the application");

        Application storage a = apps[_appId];

        require(a.numConfirms != 0,
                "Unknown application identifier");

        return a.numConfirms;
    }

    // Узнать баланс токена
    function getBalance() external view returns (uint256) {

        require(members[msg.sender],
                "Only the member can get a balance of the token");

        return token.balanceOf(address(this));
    }
}
