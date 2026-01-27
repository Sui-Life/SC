module suilife::vault {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    // Error codes
    const E_ALREADY_CLAIMED: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;

    public struct Vault has key, store {
        id: UID,
        reward: Balance<SUI>,
        claimed: bool,  // True when ALL funds are withdrawn
    }

    /// Create a new vault with reward and share it
    /// Returns the vault ID for reference
    public fun create_and_share(
        reward_coin: Coin<SUI>,
        ctx: &mut TxContext
    ): ID {
        let vault = Vault {
            id: object::new(ctx),
            reward: coin::into_balance(reward_coin),
            claimed: false,
        };
        let vault_id = object::id(&vault);
        transfer::share_object(vault);
        vault_id
    }

    /// Withdraw a specific amount from the vault
    /// Used for individual user claims
    public fun withdraw(vault: &mut Vault, amount: u64, ctx: &mut TxContext): Coin<SUI> {
        let current_balance = balance::value(&vault.reward);
        assert!(current_balance >= amount, E_INSUFFICIENT_BALANCE);
        
        // Take the specified amount
        let withdrawn = coin::take(&mut vault.reward, amount, ctx);
        
        // Mark as fully claimed if balance is now zero
        if (balance::value(&vault.reward) == 0) {
            vault.claimed = true;
        };
        
        withdrawn
    }

    /// Claim all rewards from vault - returns Coin<SUI>
    /// Caller is responsible for transferring/distributing the coin
    public fun claim_internal(vault: &mut Vault, ctx: &mut TxContext): Coin<SUI> {
        assert!(!vault.claimed, E_ALREADY_CLAIMED);
        vault.claimed = true;
        let amount = balance::value(&vault.reward);
        coin::take(&mut vault.reward, amount, ctx)
    }

    // ============ View Functions ============

    /// Get the current reward amount in the vault
    public fun get_reward_amount(vault: &Vault): u64 {
        balance::value(&vault.reward)
    }

    /// Get remaining balance in vault
    public fun get_remaining_balance(vault: &Vault): u64 {
        balance::value(&vault.reward)
    }

    /// Check if the vault has been fully claimed
    public fun is_claimed(vault: &Vault): bool {
        vault.claimed
    }

    /// Check if vault is empty
    public fun is_empty(vault: &Vault): bool {
        balance::value(&vault.reward) == 0
    }

    /// Get the vault ID
    public fun get_id(vault: &Vault): ID {
        object::id(vault)
    }
}