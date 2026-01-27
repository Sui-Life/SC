module run2earn::event {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use run2earn::vault;
    use token::run_token::RUN_TOKEN;

    const EVENT_FEE_RUN: u64 = 10_000_000_000;

    const E_INVALID_RUN_FEE: u64 = 100;
    const E_VAULT_MISMATCH: u64 = 200;
    const E_ALREADY_CLAIMED: u64 = 201;
    const E_NO_SUBMISSION: u64 = 202;
    const E_SUBMISSION_EVENT_MISMATCH: u64 = 203;

    public struct Event has key, store {
        id: UID,
        creator: address,
        name: vector<u8>,
        description: vector<u8>,
        instructions: vector<u8>,
        image_url: vector<u8>,
        reward_amount: u64,
        vault_id: ID,
        reward_claimed: bool,
        winner: Option<address>,
    }

    public struct EventNFT has key, store {
        id: UID,
        event_id: ID,
    }

    public struct Participant has key, store {
        id: UID,
        event_id: ID,
        participant: address,
    }

    public struct Submission has key, store {
        id: UID,
        event_id: ID,
        participant: address,
        proof: vector<u8>,
    }
    
    public entry fun create_event(
        name: vector<u8>,
        description: vector<u8>,
        instructions: vector<u8>,
        image_url: vector<u8>,
        reward_amount: u64,
        mut sui_payment: Coin<SUI>,
        run_fee: Coin<RUN_TOKEN>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        assert!(coin::value(&run_fee) == EVENT_FEE_RUN, E_INVALID_RUN_FEE);
        transfer::public_transfer(run_fee, @0x0);

        let reward = coin::split(&mut sui_payment, reward_amount, ctx);

        transfer::public_transfer(
            sui_payment,
            sender
        );

        // Create and share vault, get its ID
        let vault_id = vault::create_and_share(reward, ctx);

        let event = Event {
            id: object::new(ctx),
            creator: sender,

            name,
            description,
            instructions,
            image_url,

            reward_amount,
            vault_id,

            reward_claimed: false,
            winner: option::none(),
        };

        let nft = EventNFT {
            id: object::new(ctx),
            event_id: object::id(&event),
        };

        transfer::share_object(event);        
        transfer::public_transfer(nft, sender);
    }

    /// User join event
    public entry fun join_event(
        event: &Event,
        ctx: &mut TxContext
    ) {
        let participant = Participant {
            id: object::new(ctx),
            event_id: object::id(event),
            participant: tx_context::sender(ctx),
        };
        transfer::public_transfer(participant, tx_context::sender(ctx));
    }

    /// User submit proof
    public entry fun submit_proof(
        event: &Event,
        proof: vector<u8>,
        ctx: &mut TxContext
    ) {
        let submission = Submission {
            id: object::new(ctx),
            event_id: object::id(event),
            participant: tx_context::sender(ctx),
            proof,
        };
        transfer::public_transfer(submission, tx_context::sender(ctx));
    }

    /// Claim reward - hanya bisa dilakukan oleh user yang sudah submit proof
    public entry fun claim_reward(
        event: &mut Event,
        vault: &mut vault::Vault,
        submission: &Submission,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        //VALIDATE AJA
        assert!(event.vault_id == object::id(vault), E_VAULT_MISMATCH);
        assert!(!event.reward_claimed, E_ALREADY_CLAIMED);
        assert!(submission.event_id == object::id(event), E_SUBMISSION_EVENT_MISMATCH);
        assert!(submission.participant == sender, E_NO_SUBMISSION);

        let reward = vault::claim_internal(vault, ctx);

        event.reward_claimed = true;
        event.winner = option::some(sender);

        // Transfer reward to sender
        transfer::public_transfer(reward, sender);
    }
}