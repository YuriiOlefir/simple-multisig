// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 *  @title SimpleMultisig
 *  @author Yurii
 */
contract SimpleMultisig {
    using SafeERC20 for IERC20;

    /// @dev Application for the transfer of tokens
    struct Application {
        address recipient;
        uint256 amount;
        bool canceled;
        uint256 endTime;
    }

    /**
     *  Constants
     */
    uint16 private constant NUM_MEMBERS = 5;
    uint16 private constant THRESHOLD = 3;

    /**
     *  Storage
     */
    IERC20 public token;

    uint256 private numApps;
    mapping(uint256 => Application) private apps;
    mapping(uint256 => mapping(address => bool)) private confirms;
    mapping(address => bool) private mmembers;
    address[] private members;

    /**
     *  Events
     */
    event AppSubmitted(
        address indexed sender,
        address recipient,
        uint256 amount,
        uint256 indexed appID,
        uint256 endTime
    );
    event AppAccepted(uint256 indexed appID);
    event AppCanceled(uint256 indexed appID);
    event AppConfirmed(address indexed sender, uint256 indexed appID, uint16 numConfirms);
    event ConfirmRevoked(address indexed sender, uint256 indexed appID, uint16 numConfirms);

    /**
     *  Constructor
     */
    constructor(IERC20 _token, address[] memory _members) {
        require(address(_token) != address(0), "Token zero address");
        require(_members.length == NUM_MEMBERS, "Must be 5 members");
        token = _token;
        for (uint16 i = 0; i < NUM_MEMBERS; ++i) {
            require(!mmembers[_members[i]], "Members must not repeat themselves or/and member can not be zero address");
            mmembers[_members[i]] = true;
            members.push(_members[i]);
        }
    }

    /**
     *  Modifiers
     */
    modifier nonzeroAmount(uint256 _amount) {
        require(_amount != 0, "The amount of token must be greater than zero");
        _;
    }

    modifier onlyMember() {
        require(mmembers[msg.sender], "Only a member can use this function");
        _;
    }

    modifier submittedApp(uint256 _appID) {
        require(apps[_appID].recipient != address(0), "Unknown application ID");
        _;
    }

    modifier validApp(uint256 _appID) {
        require(!apps[_appID].canceled, "This application has been canceled");
        require(block.timestamp <= apps[_appID].endTime, "This application is out of time");
        require(getConfirms(_appID) != THRESHOLD, "This application has already been applied");
        _;
    }

    /**
     *  External functions
     */
    /// @notice Submission of the application for the transfer of tokens
    /// @param _duration Application lifetime in seconds
    function submitApp(
        address _recipient,
        uint256 _amount,
        uint256 _duration
    ) external onlyMember nonzeroAmount(_amount) returns (uint256 newAppID) {
        require(_recipient != address(0), "Zero recipient address");
        require(_recipient != address(this), "The recipient's address matches the contract address");
        require(_recipient != msg.sender, "The recipient's address matches the sender's address");
        require(_amount <= token.balanceOf(address(this)), "Not enough tokens");
        require(_duration > 0, "Zero duration of the application");

        newAppID = numApps;
        Application storage a = apps[newAppID];
        a.recipient = _recipient;
        a.amount = _amount;
        a.endTime = block.timestamp + _duration;
        confirms[newAppID][msg.sender] = true;
        ++numApps;
        emit AppSubmitted(msg.sender, _recipient, _amount, newAppID, a.endTime);
    }

    /// @notice Confirmation of the application
    function confirmApp(uint256 _appID) external onlyMember submittedApp(_appID) validApp(_appID) {
        require(!confirms[_appID][msg.sender], "You have already confirmed the application");
        confirms[_appID][msg.sender] = true;
        uint16 numConfirms = getConfirms(_appID);
        emit AppConfirmed(msg.sender, _appID, numConfirms);
        if (numConfirms == THRESHOLD) _acceptApp(_appID);
    }

    /// @notice Revocation of confirmation of the application
    function revokeConfirmation(uint256 _appID) external onlyMember submittedApp(_appID) validApp(_appID) {
        require(confirms[_appID][msg.sender], "You have not confirmed the application yet");
        confirms[_appID][msg.sender] = false;
        uint16 numConfirms = getConfirms(_appID);
        emit ConfirmRevoked(msg.sender, _appID, numConfirms);
        if (numConfirms == 0) _cancelApp(_appID);
    }

    /**
     *  External view functions
     */
    /// @notice Receiving application data
    function getAppInfo(uint256 _appID)
        external
        view
        submittedApp(_appID)
        returns (
            address recipient,
            uint256 amount,
            uint16 numConfirms,
            bool canceled,
            uint256 endTime
        )
    {
        Application memory a = apps[_appID];
        return (a.recipient, a.amount, getConfirms(_appID), a.canceled, a.endTime);
    }

    /// @notice Check: whether the address has confirmed the application
    function isConfirmedBy(address _addr, uint256 _appID) external view submittedApp(_appID) returns (bool) {
        require(_addr != address(0), "Zero address");
        if (confirms[_appID][_addr]) return true;
        return false;
    }

    /// @notice Getting token balance
    function getBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /// @notice Check: is there a member with this address
    function isMember(address _addr) external view returns (bool) {
        require(_addr != address(0), "Zero address");
        return mmembers[_addr];
    }

    /**
     *  Public functions
     */
    /// @notice Getting the number of confirmations of the application
    function getConfirms(uint256 _appID) public view submittedApp(_appID) returns (uint16 count) {
        for (uint16 i = 0; i < NUM_MEMBERS; i++) if (confirms[_appID][members[i]]) ++count;
    }

    /**
     *  Private functions
     */
    /// @dev Acceptance of the application and transfer of tokens
    function _acceptApp(uint256 _appID) private {
        Application storage a = apps[_appID];
        if (a.amount <= token.balanceOf(address(this))) {
            token.safeTransfer(a.recipient, a.amount);
            emit AppAccepted(_appID);
        } else {
            _cancelApp(_appID);
        }
    }

    /// @dev Cancellation of application
    function _cancelApp(uint256 _appID) private {
        apps[_appID].canceled = true;
        emit AppCanceled(_appID);
    }
}
