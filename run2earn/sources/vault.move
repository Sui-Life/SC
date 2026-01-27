module run2earn::vault {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    public struct Vault has key, store {
        id: UID,
        reward: Balance<SUI>,
        claimed: bool,
    }

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

    /// Returns Coin<SUI> - caller responsible for transferring
    public fun claim_internal(vault: &mut Vault, ctx: &mut TxContext): Coin<SUI> {
        assert!(!vault.claimed, 1);
        vault.claimed = true;
        let amount = balance::value(&vault.reward);
        coin::take(&mut vault.reward, amount, ctx)
    }
}