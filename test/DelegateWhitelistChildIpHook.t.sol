// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IIPAssetRegistry } from "@storyprotocol/core/interfaces/registries/IIPAssetRegistry.sol";
import { IPILicenseTemplate } from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import { ILicensingModule } from "@storyprotocol/core/interfaces/modules/licensing/ILicensingModule.sol";
import { ILicenseToken } from "@storyprotocol/core/interfaces/ILicenseToken.sol";
import { PILFlavors } from "@storyprotocol/core/lib/PILFlavors.sol";
import { Licensing } from "@storyprotocol/core/lib/Licensing.sol";
import { ModuleRegistry } from "@storyprotocol/core/registries/ModuleRegistry.sol";
import { MockERC20 } from "@storyprotocol/test/mocks/token/MockERC20.sol";

import { DelegateWhitelistChildIpHook } from "../contracts/DelegateWhitelistChildIpHook.sol";
import { BaseTest } from "@storyprotocol/periphery/test/utils/BaseTest.t.sol";

// Run this test:
// forge test --fork-url https://aeneid.storyrpc.io/ --match-path test/DelegateWhitelistChildIpHook.t.sol
contract DelegateWhitelistChildIpHookTest is BaseTest {
    address internal alice = address(0xa11ce);
    address internal bob = address(0xb0b);
    address internal charlie = address(0xc4a11e);
    address internal david = address(0xd4a11e);

    address internal childIpId1;
    address internal childIpId2;

    // For addresses, see https://docs.story.foundation/docs/deployed-smart-contracts
    // Protocol Core - IPAssetRegistry
    IIPAssetRegistry internal IP_ASSET_REGISTRY = IIPAssetRegistry(0x77319B4031e6eF1250907aa00018B8B1c67a244b);
    // Protocol Core - LicensingModule
    ILicensingModule internal LICENSING_MODULE = ILicensingModule(0x04fbd8a2e56dd85CFD5500A4A4DfA955B9f1dE6f);
    // Protocol Core - PILicenseTemplate
    IPILicenseTemplate internal PIL_TEMPLATE = IPILicenseTemplate(0x2E896b0b2Fdb7457499B56AAaA4AE55BCB4Cd316);
    // Protocol Core - RoyaltyPolicyLAP
    address internal ROYALTY_POLICY_LAP = 0xBe54FB168b3c982b7AaE60dB6CF75Bd8447b390E;
    // Protocol Core - AccessController
    address internal ACCESS_CONTROLLER = 0xcCF37d0a503Ee1D4C11208672e622ed3DFB2275a;
    // Protocol Core - ModuleRegistry
    address internal MODULE_REGISTRY = 0x022DBAAeA5D8fB31a0Ad793335e39Ced5D631fa5;
    // Protocol Core - LicenseRegistry
    address internal LICENSE_REGISTRY = 0x529a750E02d8E2f15649c13D69a465286a780e24;
    // Revenue Token - MERC20
    MockERC20 internal MERC20 = MockERC20(0xF2104833d386a2734a4eB3B8ad6FC6812F29E38E);

    DelegateWhitelistChildIpHook public DELEGATE_WHITELIST_CHILD_IP_HOOK;
    uint256 public tokenId;
    address public ipId;
    uint256 public licenseTermsId;

    function setUp() public override {
        super.setUp();

        DELEGATE_WHITELIST_CHILD_IP_HOOK = new DelegateWhitelistChildIpHook(
            ACCESS_CONTROLLER,
            address(IP_ASSET_REGISTRY),
            LICENSE_REGISTRY
        );

        // Make the registry *think* the hook is registered everywhere in this test
        vm.mockCall(
            MODULE_REGISTRY,
            abi.encodeWithSelector(ModuleRegistry.isRegistered.selector, address(DELEGATE_WHITELIST_CHILD_IP_HOOK)),
            abi.encode(true)
        );

        tokenId = mockNft.mint(alice);
        ipId = IP_ASSET_REGISTRY.register(block.chainid, address(mockNft), tokenId);

        licenseTermsId = PIL_TEMPLATE.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 100, // 100 wei minting fee
                commercialRevShare: 0,
                royaltyPolicy: ROYALTY_POLICY_LAP,
                currencyToken: address(MERC20)
            })
        );

        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 100,
            licensingHook: address(DELEGATE_WHITELIST_CHILD_IP_HOOK),
            hookData: "",
            commercialRevShare: 0,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(0)
        });

        vm.startPrank(alice);
        LICENSING_MODULE.attachLicenseTerms(ipId, address(PIL_TEMPLATE), licenseTermsId);
        LICENSING_MODULE.setLicensingConfig(ipId, address(PIL_TEMPLATE), licenseTermsId, licensingConfig);
        vm.stopPrank();

        // Create child IPs for testing
        uint256 childTokenId1 = mockNft.mint(bob);
        childIpId1 = IP_ASSET_REGISTRY.register(block.chainid, address(mockNft), childTokenId1);

        uint256 childTokenId2 = mockNft.mint(charlie);
        childIpId2 = IP_ASSET_REGISTRY.register(block.chainid, address(mockNft), childTokenId2);
    }

    function test_DelegateWhitelistChildIpHook_addToWhitelistSuccess() public {
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob);

        assertTrue(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob)
        );
    }

    function test_DelegateWhitelistChildIpHook_addToWhitelistWithWildcardMinter() public {
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            address(0)
        );

        assertTrue(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(
                ipId,
                address(PIL_TEMPLATE),
                licenseTermsId,
                childIpId1,
                address(0)
            )
        );
    }

    function test_DelegateWhitelistChildIpHook_revert_addToWhitelistWhenAlreadyWhitelisted() public {
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateWhitelistChildIpHook.DelegateWhitelistChildIpHook_AddressAlreadyWhitelisted.selector,
                childIpId1,
                bob
            )
        );
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob);
    }

    function test_DelegateWhitelistChildIpHook_revert_addToWhitelistWhenNoPermission() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateWhitelistChildIpHook.DelegateWhitelistChildIpHook_NotOwnerOrDelegate.selector,
                bob,
                alice
            )
        );
        vm.prank(bob); // bob doesn't have permission for alice's IP
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            charlie
        );
    }

    function test_DelegateWhitelistChildIpHook_removeFromWhitelistSuccess() public {
        // First add to whitelist
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob);

        // Then remove
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.removeFromWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            bob
        );

        assertFalse(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob)
        );
    }

    function test_DelegateWhitelistChildIpHook_revert_removeFromWhitelistWhenNotInWhitelist() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateWhitelistChildIpHook.DelegateWhitelistChildIpHook_AddressNotInWhitelist.selector,
                childIpId1,
                bob
            )
        );
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.removeFromWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            bob
        );
    }

    function test_DelegateWhitelistChildIpHook_revert_removeFromWhitelistWhenNoPermission() public {
        // First add to whitelist
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateWhitelistChildIpHook.DelegateWhitelistChildIpHook_NotOwnerOrDelegate.selector,
                bob,
                alice
            )
        );
        vm.prank(bob); // bob doesn't have permission for alice's IP
        DELEGATE_WHITELIST_CHILD_IP_HOOK.removeFromWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            bob
        );
    }

    function test_DelegateWhitelistChildIpHook_isWhitelistedReturnsFalseByDefault() public {
        assertFalse(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob)
        );
    }

    function test_DelegateWhitelistChildIpHook_childIpIdIsolation() public {
        // Whitelist bob for childIpId1
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob);

        // Bob should be whitelisted for childIpId1 but not childIpId2
        assertTrue(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob)
        );
        assertFalse(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId2, bob)
        );
    }

    function test_DelegateWhitelistChildIpHook_revert_beforeMintLicenseTokensDisabled() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateWhitelistChildIpHook.DelegateWhitelistChildIpHook_MintLicenseTokensDisabled.selector
            )
        );
        DELEGATE_WHITELIST_CHILD_IP_HOOK.beforeMintLicenseTokens(
            bob,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            1,
            bob,
            ""
        );
    }

    function test_DelegateWhitelistChildIpHook_whitelistIsolationDifferentLicenses() public {
        // Create a second license terms
        uint256 licenseTermsId2 = PIL_TEMPLATE.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 200,
                commercialRevShare: 0,
                royaltyPolicy: ROYALTY_POLICY_LAP,
                currencyToken: address(MERC20)
            })
        );
        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 200,
            licensingHook: address(DELEGATE_WHITELIST_CHILD_IP_HOOK),
            hookData: "",
            commercialRevShare: 0,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(0)
        });

        vm.startPrank(alice);
        LICENSING_MODULE.attachLicenseTerms(ipId, address(PIL_TEMPLATE), licenseTermsId2);
        LICENSING_MODULE.setLicensingConfig(ipId, address(PIL_TEMPLATE), licenseTermsId2, licensingConfig);
        // Add bob to whitelist for first license with childIpId1
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob);
        vm.stopPrank();

        // Bob should be whitelisted for first license but not second
        assertTrue(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob)
        );
        assertFalse(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(
                ipId,
                address(PIL_TEMPLATE),
                licenseTermsId2,
                childIpId1,
                bob
            )
        );
    }

    function test_DelegateWhitelistChildIpHook_wildcardMinterAllowsAnyCaller() public {
        // Whitelist childIpId1 with wildcard minter (address(0))
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            address(0)
        );

        // Now beforeRegisterDerivative should succeed with any caller
        uint256 fee = DELEGATE_WHITELIST_CHILD_IP_HOOK.beforeRegisterDerivative(
            bob,
            childIpId1,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            ""
        );

        assertEq(fee, 100); // minting fee from license terms

        // Try with a different caller - should also work
        fee = DELEGATE_WHITELIST_CHILD_IP_HOOK.beforeRegisterDerivative(
            charlie,
            childIpId1,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            ""
        );

        assertEq(fee, 100);
    }

    function test_DelegateWhitelistChildIpHook_specificMinterOverridesWildcard() public {
        // First whitelist with wildcard
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            address(0)
        );

        // Then whitelist a specific minter for the same childIpId
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob);

        // Both bob and the wildcard should work
        uint256 fee = DELEGATE_WHITELIST_CHILD_IP_HOOK.beforeRegisterDerivative(
            bob,
            childIpId1,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            ""
        );
        assertEq(fee, 100);

        // Charlie should also work because of wildcard
        fee = DELEGATE_WHITELIST_CHILD_IP_HOOK.beforeRegisterDerivative(
            charlie,
            childIpId1,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            ""
        );
        assertEq(fee, 100);
    }

    function test_DelegateWhitelistChildIpHook_beforeRegisterDerivativeSuccess() public {
        // Whitelist childIpId1 with bob as minter
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob);

        // Bob should be able to register derivative
        uint256 fee = DELEGATE_WHITELIST_CHILD_IP_HOOK.beforeRegisterDerivative(
            bob,
            childIpId1,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            ""
        );

        assertEq(fee, 100); // minting fee from license terms
    }

    function test_DelegateWhitelistChildIpHook_revert_beforeRegisterDerivativeWrongChildIp() public {
        // Whitelist childIpId1 with bob
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob);

        // Should fail for childIpId2
        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateWhitelistChildIpHook.DelegateWhitelistChildIpHook_AddressNotWhitelisted.selector,
                childIpId2,
                bob
            )
        );
        DELEGATE_WHITELIST_CHILD_IP_HOOK.beforeRegisterDerivative(
            bob,
            childIpId2,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            ""
        );
    }

    function test_DelegateWhitelistChildIpHook_revert_beforeRegisterDerivativeWrongCaller() public {
        // Whitelist childIpId1 with bob as minter
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob);

        // Should fail when charlie tries to register
        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateWhitelistChildIpHook.DelegateWhitelistChildIpHook_AddressNotWhitelisted.selector,
                childIpId1,
                charlie
            )
        );
        DELEGATE_WHITELIST_CHILD_IP_HOOK.beforeRegisterDerivative(
            charlie,
            childIpId1,
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            ""
        );
    }

    // ============ Delegation Tests ============

    function test_DelegateWhitelistChildIpHook_addDelegateSuccess() public {
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        assertTrue(DELEGATE_WHITELIST_CHILD_IP_HOOK.isDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob));
    }

    function test_DelegateWhitelistChildIpHook_revert_addDelegateWhenAlreadyDelegate() public {
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateWhitelistChildIpHook.DelegateWhitelistChildIpHook_DelegateAlreadyAdded.selector,
                bob
            )
        );
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);
    }

    function test_DelegateWhitelistChildIpHook_revert_addDelegateWhenNoPermission() public {
        vm.expectRevert(); // AccessControlled will revert
        vm.prank(bob); // bob doesn't have permission for alice's IP
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, charlie);
    }

    function test_DelegateWhitelistChildIpHook_removeDelegateSuccess() public {
        // First add delegate
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        // Then remove
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.removeDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        assertFalse(DELEGATE_WHITELIST_CHILD_IP_HOOK.isDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob));
    }

    function test_DelegateWhitelistChildIpHook_revert_removeDelegateWhenNotDelegate() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateWhitelistChildIpHook.DelegateWhitelistChildIpHook_DelegateNotFound.selector,
                bob
            )
        );
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.removeDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);
    }

    function test_DelegateWhitelistChildIpHook_revert_removeDelegateWhenNoPermission() public {
        // First add delegate
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        vm.expectRevert(); // AccessControlled will revert
        vm.prank(bob); // bob doesn't have permission for alice's IP
        DELEGATE_WHITELIST_CHILD_IP_HOOK.removeDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);
    }

    function test_DelegateWhitelistChildIpHook_isDelegateReturnsFalseByDefault() public {
        assertFalse(DELEGATE_WHITELIST_CHILD_IP_HOOK.isDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob));
    }

    function test_DelegateWhitelistChildIpHook_delegateCanAddToWhitelist() public {
        // Alice adds bob as delegate
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        // Bob (delegate) adds charlie to whitelist for childIpId1
        vm.prank(bob);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            charlie
        );

        assertTrue(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(
                ipId,
                address(PIL_TEMPLATE),
                licenseTermsId,
                childIpId1,
                charlie
            )
        );
    }

    function test_DelegateWhitelistChildIpHook_delegateCanRemoveFromWhitelist() public {
        // Alice adds bob as delegate
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        // Alice adds charlie to whitelist for childIpId1
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            charlie
        );

        // Bob (delegate) removes charlie from whitelist
        vm.prank(bob);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.removeFromWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            charlie
        );

        assertFalse(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(
                ipId,
                address(PIL_TEMPLATE),
                licenseTermsId,
                childIpId1,
                charlie
            )
        );
    }

    function test_DelegateWhitelistChildIpHook_delegateIsolationBetweenLicenses() public {
        // Create a second license terms
        uint256 licenseTermsId2 = PIL_TEMPLATE.registerLicenseTerms(
            PILFlavors.commercialRemix({
                mintingFee: 200,
                commercialRevShare: 0,
                royaltyPolicy: ROYALTY_POLICY_LAP,
                currencyToken: address(MERC20)
            })
        );
        Licensing.LicensingConfig memory licensingConfig = Licensing.LicensingConfig({
            isSet: true,
            mintingFee: 200,
            licensingHook: address(DELEGATE_WHITELIST_CHILD_IP_HOOK),
            hookData: "",
            commercialRevShare: 0,
            disabled: false,
            expectMinimumGroupRewardShare: 0,
            expectGroupRewardPool: address(0)
        });

        vm.startPrank(alice);
        LICENSING_MODULE.attachLicenseTerms(ipId, address(PIL_TEMPLATE), licenseTermsId2);
        LICENSING_MODULE.setLicensingConfig(ipId, address(PIL_TEMPLATE), licenseTermsId2, licensingConfig);
        // Add bob as delegate for first license only
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);
        vm.stopPrank();

        // Bob should be delegate for first license but not second
        assertTrue(DELEGATE_WHITELIST_CHILD_IP_HOOK.isDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob));
        assertFalse(DELEGATE_WHITELIST_CHILD_IP_HOOK.isDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId2, bob));

        // Bob should be able to add to whitelist for first license
        vm.prank(bob);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            charlie
        );
        assertTrue(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(
                ipId,
                address(PIL_TEMPLATE),
                licenseTermsId,
                childIpId1,
                charlie
            )
        );

        // Bob should NOT be able to add to whitelist for second license
        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateWhitelistChildIpHook.DelegateWhitelistChildIpHook_NotOwnerOrDelegate.selector,
                bob,
                alice
            )
        );
        vm.prank(bob);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId2,
            childIpId1,
            charlie
        );
    }

    function test_DelegateWhitelistChildIpHook_removedDelegateCantManageWhitelist() public {
        // Alice adds bob as delegate
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        // Bob can add to whitelist
        vm.prank(bob);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            charlie
        );

        // Alice removes bob as delegate
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.removeDelegate(ipId, address(PIL_TEMPLATE), licenseTermsId, bob);

        // Bob can no longer add to whitelist
        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateWhitelistChildIpHook.DelegateWhitelistChildIpHook_NotOwnerOrDelegate.selector,
                bob,
                alice
            )
        );
        vm.prank(bob);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId2, david);
    }

    function test_DelegateWhitelistChildIpHook_ownerCanAlwaysManageWhitelist() public {
        // Alice (owner) can add to whitelist without being a delegate
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.addToWhitelist(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob);

        assertTrue(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob)
        );

        // Alice (owner) can remove from whitelist
        vm.prank(alice);
        DELEGATE_WHITELIST_CHILD_IP_HOOK.removeFromWhitelist(
            ipId,
            address(PIL_TEMPLATE),
            licenseTermsId,
            childIpId1,
            bob
        );

        assertFalse(
            DELEGATE_WHITELIST_CHILD_IP_HOOK.isWhitelisted(ipId, address(PIL_TEMPLATE), licenseTermsId, childIpId1, bob)
        );
    }
}
