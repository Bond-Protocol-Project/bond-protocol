// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {IBondProtocol} from "../interfaces/IBondProtocol.sol";

/// @title - Bond protocol bridge contract
contract BondBridge is CCIPReceiver, Ownable {
    using SafeERC20 for IERC20;

    // Custom errors to provide more descriptive revert messages.
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance to cover the fees.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error DestinationChainNotAllowed(uint64 destinationChainSelector); // Used when the destination chain has not been allowlisted by the contract owner.
    error SourceChainNotAllowed(uint64 sourceChainSelector); // Used when the source chain has not been allowlisted by the contract owner.
    error SenderNotAllowed(address sender); // Used when the sender has not been allowlisted by the contract owner.
    error InvalidReceiverAddress(); // Used when the receiver address is 0.
    error OnlyProtocolIsAllowed(); // only protocol is allowed to send
    error DestinationAddressError();

    // Event emitted when a message is sent to another chain.
    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address feeToken,
        uint256 fees
    );

    // Event emitted when a message is received from another chain.
    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        bytes32 intentId,
        address token,
        uint256 tokenAmount
    );

    bytes32 public s_lastReceivedMessageId; // Store the last received messageId.
    address public s_lastReceivedTokenAddress; // Store the last received token address.
    uint256 public s_lastReceivedTokenAmount; // Store the last received amount.
    DataTypes.BridgeMsgData public s_lastReceivedMsg; // Store the last received msg data.

    IBondProtocol public protocol;

    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 => bool) public allowlistedDestinationChains;

    // Mapping to keep track of allowlisted source chains.
    mapping(uint64 => bool) public allowlistedSourceChains;

    // Mapping to keep track of allowlisted senders.
    mapping(address => bool) public allowlistedSenders;

    mapping(uint64 chainSelector => address)
        public chainSelectorToBridgeAddress;

    IERC20 private s_linkToken;

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    /// @param _protocol The address of the protocol contract.
    constructor(
        address _router,
        address _link,
        address _protocol,
        address _initialOwner
    ) CCIPReceiver(_router) Ownable(_initialOwner) {
        s_linkToken = IERC20(_link);
        protocol = IBondProtocol(_protocol);
    }

    /// @dev Modifier that checks if the chain with the given destinationChainSelector is allowlisted.
    /// @param _destinationChainSelector The selector of the destination chain.
    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector])
            revert DestinationChainNotAllowed(_destinationChainSelector);
        _;
    }

    /// @dev Modifier that checks the receiver address is not 0.
    /// @param _receiver The receiver address.
    modifier validateReceiver(address _receiver) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        _;
    }

    /// @dev Modifier that checks if the chain with the given sourceChainSelector is allowlisted and if the sender is allowlisted.
    /// @param _sourceChainSelector The selector of the destination chain.
    /// @param _sender The address of the sender.
    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!allowlistedSourceChains[_sourceChainSelector])
            revert SourceChainNotAllowed(_sourceChainSelector);
        if (!allowlistedSenders[_sender]) revert SenderNotAllowed(_sender);
        _;
    }

    modifier onlyProtocol() {
        if (msg.sender != address(protocol)) revert OnlyProtocolIsAllowed();
        _;
    }

    /// @dev Updates the allowlist status of a destination chain for transactions.
    /// @notice This function can only be called by the owner.
    /// @param _destinationChainSelector The selector of the destination chain to be updated.
    /// @param allowed The allowlist status to be set for the destination chain.
    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    /// @dev Updates the allowlist status of a source chain
    /// @notice This function can only be called by the owner.
    /// @param _sourceChainSelector The selector of the source chain to be updated.
    /// @param allowed The allowlist status to be set for the source chain.
    function allowlistSourceChain(
        uint64 _sourceChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
    }

    // function setProtocol(address _protocol) external onlyOwner {
    //     protocol = protocol;
    // }

    /// @dev Updates the allowlist status of a sender for transactions.
    /// @notice This function can only be called by the owner.
    /// @param _sender The address of the sender to be updated.
    /// @param allowed The allowlist status to be set for the sender.
    // function allowlistSender(address _sender, bool allowed) external onlyOwner {
    //     allowlistedSenders[_sender] = allowed;
    // }

    /// @notice Sends data and transfer tokens to receiver on the destination chain.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _bridgeMsgData The bytes data to be sent.
    /// @param _token token address.
    /// @param _amount token amount.
    /// @param _gasLimit gas limit for ccip
    /// @return fees The ID of the CCIP message that was sent.
    /// @return messageId The ID of the CCIP message that was sent.
    function sendMessage(
        uint64 _destinationChainSelector,
        bytes calldata _bridgeMsgData,
        address _token,
        uint256 _amount,
        uint64 _gasLimit
    )
        external
        onlyProtocol
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        returns (uint256 fees, bytes32 messageId)
    {
        address bridgeAddress = chainSelectorToBridgeAddress[
            _destinationChainSelector
        ];

        if (bridgeAddress == address(0)) revert DestinationAddressError();
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        // address(linkToken) means fees are paid in LINK
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            bridgeAddress,
            _bridgeMsgData,
            _token,
            _amount,
            address(s_linkToken),
            _gasLimit
        );

        // Initialize a router client instance to interact with cross-chain router
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the CCIP message
        fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > s_linkToken.balanceOf(address(this)))
            revert NotEnoughBalance(s_linkToken.balanceOf(address(this)), fees);

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        s_linkToken.approve(address(router), fees);

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        if (_token != address(0)) {
            IERC20(_token).approve(address(router), _amount);
        }

        // Send the message through the router and store the returned message ID
        messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(
            messageId,
            _destinationChainSelector,
            msg.sender,
            address(s_linkToken),
            fees
        );

        // Return the message ID
        return (fees, messageId);
    }

    function getFees(
        uint64 _destinationChainSelector,
        bytes calldata _bridgeMsgData,
        address _token,
        uint256 _amount,
        uint64 _gasLimit
    ) external view onlyProtocol returns (uint256 _fee) {
        address bridgeAddress = chainSelectorToBridgeAddress[
            _destinationChainSelector
        ];

        if (bridgeAddress == address(0)) revert DestinationAddressError();
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        // address(linkToken) means fees are paid in LINK
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            bridgeAddress,
            _bridgeMsgData,
            _token,
            _amount,
            address(s_linkToken),
            _gasLimit
        );

        // Initialize a router client instance to interact with cross-chain router
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the CCIP message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        // Return the message ID
        return fees;
    }

    /**
     * @notice Returns the details of the last CCIP received message.
     * @dev This function retrieves the ID, text, token address, and token amount of the last received CCIP message.
     * @return messageId The ID of the last received CCIP message.
     * @return bridgeMsgData The text of the last received CCIP message.
     * @return tokenAddress The address of the token in the last CCIP received message.
     * @return tokenAmount The amount of the token in the last CCIP received message.
     */
    function getLastReceivedMessageDetails()
        public
        view
        returns (
            bytes32 messageId,
            DataTypes.BridgeMsgData memory bridgeMsgData,
            address tokenAddress,
            uint256 tokenAmount
        )
    {
        return (
            s_lastReceivedMessageId,
            s_lastReceivedMsg,
            s_lastReceivedTokenAddress,
            s_lastReceivedTokenAmount
        );
    }

    /// handle a received message
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlisted(
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address))
        ) // Make sure source chain and sender are allowlisted
    {
        // Expect one token to be transferred at once, but you can transfer several tokens.
        address tokenAddress;
        uint256 tokenAmount;

        if (any2EvmMessage.destTokenAmounts.length > 0) {
            tokenAddress = any2EvmMessage.destTokenAmounts[0].token;
            tokenAmount = any2EvmMessage.destTokenAmounts[0].amount;
        }

        DataTypes.BridgeMsgData memory msgData = abi.decode(
            any2EvmMessage.data,
            (DataTypes.BridgeMsgData)
        ); // abi-decoding of the sent text

        s_lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        s_lastReceivedMsg = msgData;
        s_lastReceivedTokenAddress = tokenAddress;
        s_lastReceivedTokenAmount = tokenAmount;

        if (tokenAddress != address(0) && tokenAmount > 0) {
            IERC20(tokenAddress).transfer(address(protocol), tokenAmount);
        }

        if (msgData.isBatch == false) {
            DataTypes.BridgeData memory _bridgeData = abi.decode(
                msgData.bridgeData,
                (DataTypes.BridgeData)
            );
            protocol.confirmIncomingIntent(
                _bridgeData.intentData,
                any2EvmMessage.sourceChainSelector
            );
        } else {
            DataTypes.BridgeData[] memory _bridgeDatas = abi.decode(
                msgData.bridgeData,
                (DataTypes.BridgeData[])
            );
            for (uint i = 0; i < _bridgeDatas.length; i++) {
                protocol.confirmIncomingIntent(
                    _bridgeDatas[i].intentData,
                    any2EvmMessage.sourceChainSelector
                );
            }
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            abi.decode(any2EvmMessage.data, (bytes32)),
            tokenAddress,
            tokenAmount
        );
    }

    /// @notice Construct a CCIP message.
    /// @dev This function will create an EVM2AnyMessage struct with all the necessary information for programmable tokens transfer.
    /// @param _receiver The address of the receiver.
    /// @param _bridgeMsgData The bytes data to be sent.
    /// @param _token The token to be transferred.
    /// @param _amount The amount of the token to be transferred.
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
    function _buildCCIPMessage(
        address _receiver,
        bytes calldata _bridgeMsgData,
        address _token,
        uint256 _amount,
        address _feeTokenAddress,
        uint64 _gasLimit
    ) private pure returns (Client.EVM2AnyMessage memory) {
        // Conditionally set the token amounts based on whether _token is zero address
        Client.EVMTokenAmount[] memory tokenAmounts;

        if (_token == address(0)) {
            // If token is zero address, create empty array (no tokens to transfer)
            tokenAmounts = new Client.EVMTokenAmount[](0);
        } else {
            // If token is valid, create array with token transfer details
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: _token,
                amount: _amount
            });
        }

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver), // ABI-encoded receiver address
                data: _bridgeMsgData, // ABI-encoded string
                tokenAmounts: tokenAmounts, // The amount and type of token being transferred (or empty array)
                extraArgs: Client._argsToBytes(
                    Client.GenericExtraArgsV2({
                        gasLimit: _gasLimit*5,
                        allowOutOfOrderExecution: true
                    })
                ),
                // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
                feeToken: _feeTokenAddress
            });
    }

    /// @dev Updates the allowlist status of a sender for transactions.
    /// @notice This function can only be called by the owner.
    /// @param _sender The address of the sender to be updated.
    /// @param allowed The allowlist status to be set for the sender.
    function configureAllowListedSender(
        address _sender,
        bool allowed
    ) external onlyOwner {
        allowlistedSenders[_sender] = allowed;
    }

    function configureDestinationBridgeAddress(
        uint64 _chainSelector,
        address _bridge
    ) external onlyOwner {
        chainSelectorToBridgeAddress[_chainSelector] = _bridge;
    }

    /// @notice Fallback function to allow the contract to receive Ether.
    /// @dev This function has no function body, making it a default function for receiving Ether.
    /// It is automatically called when Ether is sent to the contract without any data.
    receive() external payable {}

    /// @notice Allows the contract owner to withdraw the entire balance of Ether from the contract.
    /// @dev This function reverts if there are no funds to withdraw or if the transfer fails.
    /// It should only be callable by the owner of the contract.
    /// @param _beneficiary The address to which the Ether should be sent.
    function withdraw(address _beneficiary) public onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = address(this).balance;

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        // Attempt to send the funds, capturing the success status and discarding any return data
        (bool sent, ) = _beneficiary.call{value: amount}("");

        // Revert if the send failed, with information about the attempted transfer
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    /// @notice Allows the owner of the contract to withdraw all tokens of a specific ERC20 token.
    /// @dev This function reverts with a 'NothingToWithdraw' error if there are no tokens to withdraw.
    /// @param _beneficiary The address to which the tokens will be sent.
    /// @param _token The contract address of the ERC20 token to be withdrawn.
    function withdrawToken(
        address _beneficiary,
        address _token
    ) public onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = IERC20(_token).balanceOf(address(this));

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).safeTransfer(_beneficiary, amount);
    }
}
