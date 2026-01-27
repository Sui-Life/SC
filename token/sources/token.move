module token::run_token {
    use sui::coin::{Self, TreasuryCap, Coin};
    use sui::sui::SUI;
    use sui::tx_context::TxContext;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::url;
    use std::option;

    const DEPLOYER: address =
        @0x670f3fa51e684b0c5788627b22d75bda01973973875eb3e457bb3d53c99ece85;

    const E_NOT_ADMIN: u64 = 1;
    const E_INSUFFICIENT_SUI: u64 = 2;

    public struct RUN_TOKEN has drop {}

    public struct TokenState has key {
        id: UID,
        total_supply: u64
    }

    public struct PriceConfig has key {
        id: UID,
        run_per_sui: u64
    }

    public struct RunVault has key {
        id: UID,
        treasury_cap: TreasuryCap<RUN_TOKEN>
    }

    fun init(
        otw: RUN_TOKEN,
        ctx: &mut TxContext
    ) {
        let (mut treasury_cap, metadata) = sui::coin::create_currency(
            otw,
            9,
            b"RUN",
            b"Run Coin",
            b"Run Coin for Run-to-Earn MVP",
            option::some(
                url::new_unsafe_from_bytes(
                    b"https://img.freepik.com/premium-vector/cartoon-character-gold-coin-running-rush-hand-drawing-illustration-vector_772546-737.jpg"
                )
            ),
            ctx
        );

        transfer::public_freeze_object(metadata);

        let price = PriceConfig {
            id: object::new(ctx),
            run_per_sui: 1_000
        };

        let mut state = TokenState {
            id: object::new(ctx),
            total_supply: 0
        };

        let initial_supply = 1_000 * 1_000_000_000;
        sui::coin::mint_and_transfer(
            &mut treasury_cap,
            initial_supply,
            DEPLOYER,
            ctx
        );
        state.total_supply = initial_supply;

        let vault = RunVault {
            id: object::new(ctx),
            treasury_cap
        };

        transfer::share_object(vault);
        transfer::share_object(price);
        transfer::share_object(state);
    }

    public entry fun buy_run(
        vault: &mut RunVault,
        price: &PriceConfig,
        amount_run: u64,
        mut sui_coin: Coin<SUI>,
        state: &mut TokenState,
        ctx: &mut TxContext
    ) {
        let required_sui =
            (amount_run + price.run_per_sui - 1) / price.run_per_sui;

        let paid = coin::value(&sui_coin);
        assert!(paid >= required_sui, E_INSUFFICIENT_SUI);

        let payment = coin::split(&mut sui_coin, required_sui, ctx);

        let refund = sui_coin;

        transfer::public_transfer(payment, DEPLOYER);
        transfer::public_transfer(refund, sui::tx_context::sender(ctx));

        coin::mint_and_transfer(
            &mut vault.treasury_cap,
            amount_run,
            sui::tx_context::sender(ctx),
            ctx
        );

        state.total_supply = state.total_supply + amount_run;
    }


    public entry fun admin_mint(
        vault: &mut RunVault,
        state: &mut TokenState,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        assert!(
            sui::tx_context::sender(ctx) == DEPLOYER,
            E_NOT_ADMIN
        );

        coin::mint_and_transfer(
            &mut vault.treasury_cap,
            amount,
            recipient,
            ctx
        );

        state.total_supply = state.total_supply + amount;
    }

    public entry fun admin_burn(
        vault: &mut RunVault,
        state: &mut TokenState,
        coin_in: Coin<RUN_TOKEN>,
        ctx: &mut TxContext
    ) {
        assert!(
            sui::tx_context::sender(ctx) == DEPLOYER,
            E_NOT_ADMIN
        );

        let amount = coin::burn(&mut vault.treasury_cap, coin_in);
        state.total_supply = state.total_supply - amount;
    }

    public fun total_supply(state: &TokenState): u64 {
        state.total_supply
    }
}
