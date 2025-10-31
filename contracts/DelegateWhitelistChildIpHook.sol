// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { BaseModule } from "@storyprotocol/core/modules/BaseModule.sol";
import { AccessControlled } from "@storyprotocol/core/access/AccessControlled.sol";
import { ILicensingHook } from "@storyprotocol/core/interfaces/modules/licensing/ILicensingHook.sol";
import { ILicenseTemplate } from "@storyprotocol/core/interfaces/modules/licensing/ILicenseTemplate.sol";
import { IIPAccount } from "@storyprotocol/core/interfaces/IIPAccount.sol";
import { ILicenseRegistry } from "@storyprotocol/core/interfaces/registries/ILicenseRegistry.sol";

/// @title Delegate Whitelist Child IP Hook
/// @notice This hook enforces whitelist restrictions for derivative registration.
///         An IP owner can delegate whitelisting capabilities to a third party,
///         who can whitelist an IP owner and specific child IP to register as
///         a derivative to your IP on your behalf.
contract DelegateWhitelistChildIpHook is BaseModule, AccessControlled, ILicensingHook {
    string public constant override name = "DELEGATE_WHITELIST_CHILD_IP_HOOK";

    ILicenseRegistry public immutable LICENSE_REGISTRY;

    /// @notice Stores the whitelist status for an IP owner and specific child IP to register as
    ///         a derivative to your IP.
    /// @dev The key is keccak256(licensorIpId, licenseTemplate, licenseTermsId, childIpId, minter).
    /// @dev The value is true if the address is whitelisted, false otherwise.
    /// @dev If minter is address(0), it acts as a wildcard allowing any caller.
    mapping(bytes32 => bool) private whitelist;

    /// @notice Stores the delegate status for addresses for a given license.
    /// @dev The key is keccak256(licensorIpId, licenseTemplate, licenseTermsId, delegateAddress).
    /// @dev The value is true if the address is a delegate, false otherwise.
    mapping(bytes32 => bool) private delegates;

    /// @notice Emitted when a delegate is added
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param delegate The address that was added as delegate
    event DelegateAdded(
        address indexed licensorIpId,
        address indexed licenseTemplate,
        uint256 indexed licenseTermsId,
        address delegate
    );

    /// @notice Emitted when a delegate is removed
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param delegate The address that was removed as delegate
    event DelegateRemoved(
        address indexed licensorIpId,
        address indexed licenseTemplate,
        uint256 indexed licenseTermsId,
        address delegate
    );

    /// @notice Emitted when an address is added to the whitelist
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param childIpId The child IP id
    /// @param minter The address that was whitelisted
    event AddressWhitelisted(
        address indexed licensorIpId,
        address indexed licenseTemplate,
        uint256 indexed licenseTermsId,
        address childIpId,
        address minter
    );

    /// @notice Emitted when an address is removed from the whitelist
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param childIpId The child IP id
    /// @param minter The address that was removed from whitelist
    event AddressRemovedFromWhitelist(
        address indexed licensorIpId,
        address indexed licenseTemplate,
        uint256 indexed licenseTermsId,
        address childIpId,
        address minter
    );

    error DelegateWhitelistChildIpHook_AddressNotWhitelisted(address childIpId, address minter);
    error DelegateWhitelistChildIpHook_AddressAlreadyWhitelisted(address childIpId, address minter);
    error DelegateWhitelistChildIpHook_AddressNotInWhitelist(address childIpId, address minter);
    error DelegateWhitelistChildIpHook_NotOwnerOrDelegate(address caller, address ipOwner);
    error DelegateWhitelistChildIpHook_DelegateAlreadyAdded(address delegate);
    error DelegateWhitelistChildIpHook_DelegateNotFound(address delegate);
    error DelegateWhitelistChildIpHook_LicenseNotAttachedToIP();
    error DelegateWhitelistChildIpHook_MintLicenseTokensDisabled();

    constructor(
        address accessController,
        address ipAssetRegistry,
        address licenseRegistry
    ) AccessControlled(accessController, ipAssetRegistry) {
        LICENSE_REGISTRY = ILicenseRegistry(licenseRegistry);
    }

    /// @notice Add a delegate for a specific license
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param delegate The address to add as delegate
    function addDelegate(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        address delegate
    ) external verifyPermission(licensorIpId) {
        if (!LICENSE_REGISTRY.hasIpAttachedLicenseTerms(licensorIpId, licenseTemplate, licenseTermsId)) {
            revert DelegateWhitelistChildIpHook_LicenseNotAttachedToIP();
        }

        address ipOwner = IIPAccount(payable(licensorIpId)).owner();
        bytes32 key = keccak256(abi.encodePacked(ipOwner, licensorIpId, licenseTemplate, licenseTermsId, delegate));
        if (delegates[key]) revert DelegateWhitelistChildIpHook_DelegateAlreadyAdded(delegate);

        delegates[key] = true;
        emit DelegateAdded(licensorIpId, licenseTemplate, licenseTermsId, delegate);
    }

    /// @notice Remove a delegate for a specific license
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param delegate The address to remove as delegate
    function removeDelegate(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        address delegate
    ) external verifyPermission(licensorIpId) {
        address ipOwner = IIPAccount(payable(licensorIpId)).owner();
        bytes32 key = keccak256(abi.encodePacked(ipOwner, licensorIpId, licenseTemplate, licenseTermsId, delegate));
        if (!delegates[key]) revert DelegateWhitelistChildIpHook_DelegateNotFound(delegate);

        delegates[key] = false;
        emit DelegateRemoved(licensorIpId, licenseTemplate, licenseTermsId, delegate);
    }

    /// @notice Check if an address is a delegate for a specific license
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param delegate The address to check
    /// @return isDelegate True if the address is a delegate, false otherwise
    function isDelegate(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        address delegate
    ) external view returns (bool isDelegate) {
        address ipOwner = IIPAccount(payable(licensorIpId)).owner();
        bytes32 key = keccak256(abi.encodePacked(ipOwner, licensorIpId, licenseTemplate, licenseTermsId, delegate));
        return delegates[key];
    }

    /// @notice Add an address to the whitelist for a specific license
    /// @dev Can be called by the IP owner or their delegates
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param childIpId The child IP id
    /// @param minter The address to add to the whitelist (use address(0) to allow any caller)
    function addToWhitelist(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        address childIpId,
        address minter
    ) external {
        address ipOwner = IIPAccount(payable(licensorIpId)).owner();
        _verifyOwnerOrDelegate(ipOwner, licensorIpId, licenseTemplate, licenseTermsId, msg.sender);

        if (!LICENSE_REGISTRY.hasIpAttachedLicenseTerms(licensorIpId, licenseTemplate, licenseTermsId)) {
            revert DelegateWhitelistChildIpHook_LicenseNotAttachedToIP();
        }

        bytes32 key = keccak256(
            abi.encodePacked(ipOwner, licensorIpId, licenseTemplate, licenseTermsId, childIpId, minter)
        );
        if (whitelist[key]) revert DelegateWhitelistChildIpHook_AddressAlreadyWhitelisted(childIpId, minter);

        whitelist[key] = true;
        emit AddressWhitelisted(licensorIpId, licenseTemplate, licenseTermsId, childIpId, minter);
    }

    /// @notice Remove an address from the whitelist for a specific license
    /// @dev Can be called by the IP owner or their delegates
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param childIpId The child IP id
    /// @param minter The address to remove from the whitelist
    function removeFromWhitelist(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        address childIpId,
        address minter
    ) external {
        address ipOwner = IIPAccount(payable(licensorIpId)).owner();
        _verifyOwnerOrDelegate(ipOwner, licensorIpId, licenseTemplate, licenseTermsId, msg.sender);

        bytes32 key = keccak256(
            abi.encodePacked(ipOwner, licensorIpId, licenseTemplate, licenseTermsId, childIpId, minter)
        );
        if (!whitelist[key]) revert DelegateWhitelistChildIpHook_AddressNotInWhitelist(childIpId, minter);

        whitelist[key] = false;
        emit AddressRemovedFromWhitelist(licensorIpId, licenseTemplate, licenseTermsId, childIpId, minter);
    }

    /// @notice Check if an address is whitelisted for a specific license
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param childIpId The child IP id
    /// @param minter The address to check
    /// @return isWhitelisted True if the address is whitelisted, false otherwise
    function isWhitelisted(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        address childIpId,
        address minter
    ) external view returns (bool isWhitelisted) {
        address ipOwner = IIPAccount(payable(licensorIpId)).owner();
        bytes32 key = keccak256(
            abi.encodePacked(ipOwner, licensorIpId, licenseTemplate, licenseTermsId, childIpId, minter)
        );
        return whitelist[key];
    }

    /// @notice This function is called when the LicensingModule mints license tokens.
    /// @dev The hook can be used to implement various checks and determine the minting price.
    /// The hook should revert if the minting is not allowed.
    /// @param caller The address of the caller who calling the mintLicenseTokens() function.
    /// @param licensorIpId The ID of licensor IP from which issue the license tokens.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms within the license template,
    /// which is used to mint license tokens.
    /// @param amount The amount of license tokens to mint.
    /// @param receiver The address of the receiver who receive the license tokens.
    /// @param hookData The data to be used by the licensing hook.
    /// @return totalMintingFee The total minting fee to be paid when minting amount of license tokens.
    function beforeMintLicenseTokens(
        address caller,
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        uint256 amount,
        address receiver,
        bytes calldata hookData
    ) external returns (uint256 totalMintingFee) {
        revert DelegateWhitelistChildIpHook_MintLicenseTokensDisabled();
    }

    /// @notice This function is called before finalizing LicensingModule.registerDerivative(), after calling
    /// LicenseRegistry.registerDerivative().
    /// @dev The hook can be used to implement various checks and determine the minting price.
    /// The hook should revert if the registering of derivative is not allowed.
    /// @param childIpId The derivative IP ID.
    /// @param parentIpId The parent IP ID.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms within the license template.
    /// @param hookData The data to be used by the licensing hook.
    /// @return mintingFee The minting fee to be paid when register child IP to the parent IP as derivative.
    function beforeRegisterDerivative(
        address caller,
        address childIpId,
        address parentIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        bytes calldata hookData
    ) external returns (uint256 mintingFee) {
        _checkWhitelist(parentIpId, licenseTemplate, licenseTermsId, childIpId, caller);
        return _calculateFee(licenseTemplate, licenseTermsId, 1);
    }

    /// @notice This function is called when the LicensingModule calculates/predict the minting fee for license tokens.
    /// @dev The hook should guarantee the minting fee calculation is correct and return the minting fee which is
    /// the exact same amount with returned by beforeMintLicenseTokens().
    /// The hook should revert if the minting fee calculation is not allowed.
    /// @param caller The address of the caller who calling the mintLicenseTokens() function.
    /// @param licensorIpId The ID of licensor IP from which issue the license tokens.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTermsId The ID of the license terms within the license template,
    /// which is used to mint license tokens.
    /// @param amount The amount of license tokens to mint.
    /// @param receiver The address of the receiver who receive the license tokens.
    /// @param hookData The data to be used by the licensing hook.
    /// @return totalMintingFee The total minting fee to be paid when minting amount of license tokens.
    function calculateMintingFee(
        address caller,
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        uint256 amount,
        address receiver,
        bytes calldata hookData
    ) external view returns (uint256 totalMintingFee) {
        return _calculateFee(licenseTemplate, licenseTermsId, amount);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(BaseModule, IERC165) returns (bool) {
        return interfaceId == type(ILicensingHook).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev checks if an address is whitelisted for a given license
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param childIpId The child IP id
    /// @param minter The address to check
    function _checkWhitelist(
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        address childIpId,
        address minter
    ) internal view {
        address ipOwner = IIPAccount(payable(licensorIpId)).owner();

        // First check if the specific minter is whitelisted
        bytes32 key = keccak256(
            abi.encodePacked(ipOwner, licensorIpId, licenseTemplate, licenseTermsId, childIpId, minter)
        );
        if (whitelist[key]) {
            return;
        }

        // If not, check if address(0) wildcard is whitelisted
        bytes32 wildcardKey = keccak256(
            abi.encodePacked(ipOwner, licensorIpId, licenseTemplate, licenseTermsId, childIpId, address(0))
        );
        if (whitelist[wildcardKey]) {
            return;
        }

        revert DelegateWhitelistChildIpHook_AddressNotWhitelisted(childIpId, minter);
    }

    /// @dev calculates the minting fee for a given license
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param amount The amount of license tokens to mint
    /// @return totalMintingFee The total minting fee to be paid when minting amount of license tokens
    function _calculateFee(
        address licenseTemplate,
        uint256 licenseTermsId,
        uint256 amount
    ) internal view returns (uint256 totalMintingFee) {
        (, , uint256 mintingFee, ) = ILicenseTemplate(licenseTemplate).getRoyaltyPolicy(licenseTermsId);
        return amount * mintingFee;
    }

    /// @dev verifies that the caller is either the IP owner or one of their delegates for a specific license
    /// @param ipOwner The IP owner address
    /// @param licensorIpId The licensor IP id
    /// @param licenseTemplate The license template address
    /// @param licenseTermsId The license terms id
    /// @param caller The caller address
    function _verifyOwnerOrDelegate(
        address ipOwner,
        address licensorIpId,
        address licenseTemplate,
        uint256 licenseTermsId,
        address caller
    ) internal view {
        if (caller != ipOwner) {
            bytes32 key = keccak256(abi.encodePacked(ipOwner, licensorIpId, licenseTemplate, licenseTermsId, caller));
            if (!delegates[key]) {
                revert DelegateWhitelistChildIpHook_NotOwnerOrDelegate(caller, ipOwner);
            }
        }
    }
}
