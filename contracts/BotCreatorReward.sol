// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./Ownable.sol";

contract BotCreatorRewardManager is Context, Ownable {

    struct BotRewardApplication {
        address receiver;       // the receiver for the reward
        address[] approvers;
        uint amount;            // the approved reward amount for the bot
        uint status;            // 0 - new, 1 - canceled, 2 - proposed, 3 - approved, 4 - rejected, 
    }

    IERC20 private _vics;
    uint public numApproverPerApplication = 1;           // number of approvals for a reward proposal
    mapping(address => bool) private _approvers;
    mapping(address => BotRewardApplication) private _application;

    event ApplicationCreated(address indexed bot);
    event ApplicationCanceled(address indexed bot);
    event ApplicationRejected(address indexed bot);
    event ApplicationDeleted(address indexed bot);
    event ApplicationApproved(address indexed bot, address indexed receiver, uint amount);
    event RewardProposal(address indexed bot, uint amount);
    event UpdateApprover(address indexed account, bool approver);

    modifier onlyBotCreator(address botContract) {
        Ownable bot = Ownable(botContract);
        require(botContract != address(0), "RewardManager: invalid bot contract");
        require(bot.owner() == _msgSender(), "RewardManager: caller must be bot creator");

        _;
    }

    modifier onlyApprover() {
        require(_approvers[_msgSender()], "RewardManager: permission denied");

        _;
    }

    constructor(IERC20 vics) {
        _vics = vics;
        _approvers[_msgSender()] = true;
    }

    function emergencyWithdraw() external onlyOwner {
        _vics.transfer(_msgSender(), _vics.balanceOf(address(this)));        
    }

    function setApproverPerApplication(uint value) external onlyOwner {
        require(value > 0, "RequireManager: value must not be 0");
        numApproverPerApplication = value;
    }

    function updateApprovers(address[] calldata accounts, bool isApprover_) external onlyOwner {
        for (uint i = 0; i < accounts.length; i++) {
            _approvers[accounts[i]] = isApprover_;
            emit UpdateApprover(accounts[i], isApprover_);
        }
    }

    function isApprover(address account) external view returns(bool) {
        return _approvers[account];
    }

    /**
    @dev Create a scolarship application for a created bot. 
    Should be called by the bot creator.
     */
    function createApplication(address botContract) external onlyBotCreator(botContract) {
        BotRewardApplication storage application = _application[botContract];
        require(application.status <= 1, "RewardManager: application has been processed");
        application.status = 0;
        application.receiver = _msgSender();

        emit ApplicationCreated(botContract);
    }

    function applicationOf(address botContract) external view returns(BotRewardApplication memory result) {
        BotRewardApplication storage application = _application[botContract];
        result = application;
    }

    /**
    @dev Cancels an application.
    Should be called by the bot creator.
     */
    function cancelApplication(address botContract) external onlyBotCreator(botContract) {
        BotRewardApplication storage application = _application[botContract];
        require(application.status == 0, "RewardManager: application is not new");

        application.status = 1; /* canceled */
        emit ApplicationCanceled(botContract);
    }

    /**
    @dev Deletes an application, no matter its current status.
     */
    function deleteApplication(address botContract) external onlyOwner {
        require(botContract != address(0), "RewardMananger: zero bot contract");
        delete _application[botContract];
        emit ApplicationDeleted(botContract);
    }

    /**
    @dev Creates a reward proposal for a bot.
     */
    function createProposal(address botContract, uint amount) external onlyApprover {
        BotRewardApplication storage application = _application[botContract];
        require(application.status == 0 && application.receiver != address(0) /* proposed */, "RewardManager: invalid application status");

        application.status = 2; /* proposed */
        application.amount = amount;
        
        emit RewardProposal(botContract, amount);

        _approve(botContract, application);
    }

    /**
    @dev Rejects an application.
     */
    function rejectApplication(address botContract) external onlyApprover {
        BotRewardApplication storage application = _application[botContract];
        require(application.status == 2 /* proposed */ || application.status == 0 /* new */, "RewardManager: invalid application status");
        
        application.status = 4; /* rejected */
        emit ApplicationRejected(botContract);
    }

    function approveApplication(address botContract) external onlyApprover {
        BotRewardApplication storage application = _application[botContract];
        _approve(botContract, application);
    }

    function _approve(address botContract, BotRewardApplication storage application) internal {
        address approver = _msgSender();
        require(application.status == 2 /* proposed */, "RewardManager: invalid application status");

        // determine for duplication of approver
        for (uint i = 0; i < application.approvers.length; i++)
            if (application.approvers[i] == approver)
                revert("RewardManager: duplicated approver");
        application.approvers.push(approver);
        if (application.approvers.length == numApproverPerApplication) {
            application.status = 3; /* approved */
            _vics.transfer(application.receiver, application.amount);
            emit ApplicationApproved(botContract, application.receiver, application.amount);
            return;
        }
        emit ApplicationApproved(botContract, address(0), 0);
    }
}
