module suilife::event {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::Clock;
    use suilife::vault;
    use token::life_token::LIFE_TOKEN;

    const EVENT_FEE_LIFE: u64 = 10_000_000_000;

    // Error codes
    const E_INVALID_LIFE_FEE: u64 = 100;
    const E_VAULT_MISMATCH: u64 = 200;
    const E_NO_SUBMISSION: u64 = 202;
    const E_EVENT_FULL: u64 = 204;
    const E_ALREADY_JOINED: u64 = 205;
    const E_EVENT_NOT_STARTED: u64 = 206;
    const E_EVENT_ENDED: u64 = 207;
    const E_EVENT_NOT_ENDED: u64 = 208;
    const E_NOT_CREATOR: u64 = 209;
    const E_ALREADY_VERIFIED: u64 = 210;
    const E_NOT_APPROVED: u64 = 211;
    const E_ALREADY_CLAIMED: u64 = 212;
    const E_NO_APPROVED_PARTICIPANTS: u64 = 213;
    const E_NOT_VERIFIED: u64 = 214;

    // Event status
    const STATUS_PENDING: u8 = 0;
    const STATUS_RUNNING: u8 = 1;
    const STATUS_ENDED: u8 = 2;
    const STATUS_VERIFIED: u8 = 3;

    public struct Event has key, store {
        id: UID,
        creator: address,
        name: vector<u8>,
        description: vector<u8>,
        instructions: vector<u8>,
        image_url: vector<u8>,
        
        // Reward
        reward_amount: u64,
        vault_id: ID,
        reward_per_person: u64,  // Calculated when verified
        total_claimed: u64,      // Track how much has been claimed
        
        // Time constraints
        start_time: u64,  // timestamp in ms
        end_time: u64,    // timestamp in ms
        
        // Capacity
        max_participants: u64,
        current_participants: u64,
        
        // Participants tracking
        participants: vector<address>,
        approved_participants: vector<address>,
        claimed_participants: vector<address>,  // Track who has claimed
        
        // Status
        status: u8,
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
    
    public fun create_event(
        name: vector<u8>,
        description: vector<u8>,
        instructions: vector<u8>,
        image_url: vector<u8>,
        reward_amount: u64,
        start_time: u64,
        end_time: u64,
        max_participants: u64,
        mut sui_payment: Coin<SUI>,
        life_fee: Coin<LIFE_TOKEN>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);

        assert!(coin::value(&life_fee) == EVENT_FEE_LIFE, E_INVALID_LIFE_FEE);
        transfer::public_transfer(life_fee, @0x0);

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
            reward_per_person: 0,  // Will be set when verified
            total_claimed: 0,

            start_time,
            end_time,
            
            max_participants,
            current_participants: 0,
            
            participants: vector::empty<address>(),
            approved_participants: vector::empty<address>(),
            claimed_participants: vector::empty<address>(),
            
            status: STATUS_PENDING,
        };

        let nft = EventNFT {
            id: object::new(ctx),
            event_id: object::id(&event),
        };

        transfer::share_object(event);        
        transfer::public_transfer(nft, sender);
    }

    /// User join event - with capacity check
    public fun join_event(
        event: &mut Event,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let now = sui::clock::timestamp_ms(clock);
        
        // Check event hasn't ended
        assert!(now < event.end_time, E_EVENT_ENDED);
        
        // Check capacity
        assert!(event.current_participants < event.max_participants, E_EVENT_FULL);
        
        // Check not already joined
        assert!(!vector::contains(&event.participants, &sender), E_ALREADY_JOINED);
        
        // Add participant
        vector::push_back(&mut event.participants, sender);
        event.current_participants = event.current_participants + 1;
        
        // Update status if event should be running
        if (now >= event.start_time && event.status == STATUS_PENDING) {
            event.status = STATUS_RUNNING;
        };

        let participant = Participant {
            id: object::new(ctx),
            event_id: object::id(event),
            participant: sender,
        };
        transfer::public_transfer(participant, sender);
    }

    /// User submit proof - only during event running
    public fun submit_proof(
        event: &mut Event,
        proof: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let now = sui::clock::timestamp_ms(clock);
        
        // Check event is running (between start and end time)
        assert!(now >= event.start_time, E_EVENT_NOT_STARTED);
        assert!(now <= event.end_time, E_EVENT_ENDED);
        
        // Check user is a participant
        assert!(vector::contains(&event.participants, &sender), E_NO_SUBMISSION);
        
        // Update status to running if needed
        if (event.status == STATUS_PENDING) {
            event.status = STATUS_RUNNING;
        };

        let submission = Submission {
            id: object::new(ctx),
            event_id: object::id(event),
            participant: sender,
            proof,
        };
        transfer::public_transfer(submission, sender);
    }

    /// Creator verify and approve participants who passed
    /// This calculates the reward_per_person and allows users to claim
    public fun verify_participants(
        event: &mut Event,
        approved_addresses: vector<address>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let now = sui::clock::timestamp_ms(clock);
        
        // Only creator can verify
        assert!(sender == event.creator, E_NOT_CREATOR);
        
        // Event must have ended
        assert!(now > event.end_time, E_EVENT_NOT_ENDED);
        
        // Can't verify twice
        assert!(event.status != STATUS_VERIFIED, E_ALREADY_VERIFIED);
        
        // Must have approved participants
        let num_approved = vector::length(&approved_addresses);
        assert!(num_approved > 0, E_NO_APPROVED_PARTICIPANTS);
        
        // Calculate reward per person
        event.reward_per_person = event.reward_amount / num_approved;
        
        // Set approved participants
        event.approved_participants = approved_addresses;
        event.status = STATUS_VERIFIED;
    }

    /// User claims their share of the reward
    /// Called by each approved user after verification
    public fun claim_reward(
        event: &mut Event,
        vault: &mut vault::Vault,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        
        // Must be verified first
        assert!(event.status == STATUS_VERIFIED, E_NOT_VERIFIED);
        
        // Check vault matches
        assert!(event.vault_id == object::id(vault), E_VAULT_MISMATCH);
        
        // Check user is approved
        assert!(vector::contains(&event.approved_participants, &sender), E_NOT_APPROVED);
        
        // Check user hasn't claimed yet
        assert!(!vector::contains(&event.claimed_participants, &sender), E_ALREADY_CLAIMED);
        
        // Determine claim amount
        let num_approved = vector::length(&event.approved_participants);
        let num_claimed = vector::length(&event.claimed_participants);
        
        let claim_amount: u64;
        if (num_claimed == num_approved - 1) {
            // Last claimer gets remaining balance (handles rounding)
            claim_amount = event.reward_amount - event.total_claimed;
        } else {
            claim_amount = event.reward_per_person;
        };
        
        // Withdraw from vault
        let reward = vault::withdraw(vault, claim_amount, ctx);
        
        // Mark as claimed
        vector::push_back(&mut event.claimed_participants, sender);
        event.total_claimed = event.total_claimed + claim_amount;
        
        // Transfer reward to user
        transfer::public_transfer(reward, sender);
    }

    /// Helper: Update event status based on current time
    public fun update_status(
        event: &mut Event,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        let now = sui::clock::timestamp_ms(clock);
        
        if (now < event.start_time) {
            event.status = STATUS_PENDING;
        } else if (now >= event.start_time && now <= event.end_time) {
            event.status = STATUS_RUNNING;
        } else if (now > event.end_time && event.status != STATUS_VERIFIED) {
            event.status = STATUS_ENDED;
        };
    }

    // ============ View Functions ============
    
    public fun get_participants(event: &Event): &vector<address> {
        &event.participants
    }
    
    public fun get_approved_participants(event: &Event): &vector<address> {
        &event.approved_participants
    }
    
    public fun get_claimed_participants(event: &Event): &vector<address> {
        &event.claimed_participants
    }
    
    public fun get_status(event: &Event): u8 {
        event.status
    }
    
    public fun get_current_participants(event: &Event): u64 {
        event.current_participants
    }
    
    public fun get_max_participants(event: &Event): u64 {
        event.max_participants
    }
    
    public fun is_event_full(event: &Event): bool {
        event.current_participants >= event.max_participants
    }
    
    public fun get_creator(event: &Event): address {
        event.creator
    }
    
    public fun get_reward_amount(event: &Event): u64 {
        event.reward_amount
    }
    
    public fun get_reward_per_person(event: &Event): u64 {
        event.reward_per_person
    }
    
    public fun get_total_claimed(event: &Event): u64 {
        event.total_claimed
    }
    
    public fun has_user_claimed(event: &Event, user: address): bool {
        vector::contains(&event.claimed_participants, &user)
    }
    
    public fun is_user_approved(event: &Event, user: address): bool {
        vector::contains(&event.approved_participants, &user)
    }
}