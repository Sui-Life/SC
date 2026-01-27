// Test module for SuiLife - Vault and Event modules
#[test_only]
module suilife::suilife_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::test_utils;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use suilife::vault::{Self, Vault};
    use suilife::event::{Self, Event, EventNFT, Participant};
    use token::life_token::LIFE_TOKEN;

    // Test addresses
    const CREATOR: address = @0xCAFE;
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    const USER3: address = @0x3;

    // Test constants
    const REWARD_AMOUNT: u64 = 1_000_000_000; // 1 SUI
    const LIFE_FEE: u64 = 10_000_000_000;     // 10 LIFE (EVENT_FEE_LIFE)
    const ONE_HOUR_MS: u64 = 3600000;
    const ONE_DAY_MS: u64 = 86400000;

    // ============ Helper Functions ============

    /// Create a test coin with specified amount
    fun mint_sui(amount: u64, ctx: &mut TxContext): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ctx)
    }

    /// Create a test LIFE token with specified amount
    fun mint_life(amount: u64, ctx: &mut TxContext): Coin<LIFE_TOKEN> {
        coin::mint_for_testing<LIFE_TOKEN>(amount, ctx)
    }

    /// Create a test clock at given timestamp
    fun create_clock_at(timestamp_ms: u64, ctx: &mut TxContext): Clock {
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, timestamp_ms);
        clock
    }

    // ============ Vault Tests ============

    #[test]
    fun test_vault_create_and_withdraw() {
        let mut scenario = ts::begin(CREATOR);
        
        // Create vault with 1 SUI
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward_coin = mint_sui(REWARD_AMOUNT, ctx);
            let _vault_id = vault::create_and_share(reward_coin, ctx);
        };

        // Withdraw half
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut vault = ts::take_shared<Vault>(&scenario);
            assert!(vault::get_reward_amount(&vault) == REWARD_AMOUNT, 0);
            assert!(!vault::is_claimed(&vault), 1);
            
            let ctx = ts::ctx(&mut scenario);
            let withdrawn = vault::withdraw(&mut vault, REWARD_AMOUNT / 2, ctx);
            
            assert!(coin::value(&withdrawn) == REWARD_AMOUNT / 2, 2);
            assert!(vault::get_remaining_balance(&vault) == REWARD_AMOUNT / 2, 3);
            assert!(!vault::is_claimed(&vault), 4);
            
            test_utils::destroy(withdrawn);
            ts::return_shared(vault);
        };

        // Withdraw remaining
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let withdrawn = vault::withdraw(&mut vault, REWARD_AMOUNT / 2, ctx);
            
            assert!(coin::value(&withdrawn) == REWARD_AMOUNT / 2, 5);
            assert!(vault::is_empty(&vault), 6);
            assert!(vault::is_claimed(&vault), 7);
            
            test_utils::destroy(withdrawn);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_vault_claim_internal() {
        let mut scenario = ts::begin(CREATOR);
        
        // Create vault
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward_coin = mint_sui(REWARD_AMOUNT, ctx);
            vault::create_and_share(reward_coin, ctx);
        };

        // Claim all
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let claimed = vault::claim_internal(&mut vault, ctx);
            
            assert!(coin::value(&claimed) == REWARD_AMOUNT, 0);
            assert!(vault::is_claimed(&vault), 1);
            
            test_utils::destroy(claimed);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vault::E_ALREADY_CLAIMED)]
    fun test_vault_double_claim_fails() {
        let mut scenario = ts::begin(CREATOR);
        
        // Create vault
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward_coin = mint_sui(REWARD_AMOUNT, ctx);
            vault::create_and_share(reward_coin, ctx);
        };

        // First claim
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let claimed = vault::claim_internal(&mut vault, ctx);
            test_utils::destroy(claimed);
            ts::return_shared(vault);
        };

        // Second claim should fail
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let claimed = vault::claim_internal(&mut vault, ctx);
            test_utils::destroy(claimed);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vault::E_INSUFFICIENT_BALANCE)]
    fun test_vault_withdraw_insufficient_balance() {
        let mut scenario = ts::begin(CREATOR);
        
        // Create vault
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let reward_coin = mint_sui(REWARD_AMOUNT, ctx);
            vault::create_and_share(reward_coin, ctx);
        };

        // Try to withdraw more than available
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let withdrawn = vault::withdraw(&mut vault, REWARD_AMOUNT + 1, ctx);
            test_utils::destroy(withdrawn);
            ts::return_shared(vault);
        };

        ts::end(scenario);
    }

    // ============ Event Creation Tests ============

    #[test]
    fun test_event_creation() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let sui_payment = mint_sui(REWARD_AMOUNT * 2, ctx);
            let life_fee = mint_life(LIFE_FEE, ctx);
            
            event::create_event(
                b"Test Event",
                b"A test event description",
                b"Complete the mission",
                b"https://example.com/image.png",
                REWARD_AMOUNT,
                start_time,
                end_time,
                10, // max_participants
                sui_payment,
                life_fee,
                ctx
            );
        };

        // Verify event was created
        ts::next_tx(&mut scenario, CREATOR);
        {
            let event_obj = ts::take_shared<Event>(&scenario);
            
            assert!(event::get_creator(&event_obj) == CREATOR, 0);
            assert!(event::get_reward_amount(&event_obj) == REWARD_AMOUNT, 1);
            assert!(event::get_max_participants(&event_obj) == 10, 2);
            assert!(event::get_current_participants(&event_obj) == 0, 3);
            assert!(event::get_status(&event_obj) == 0, 4); // STATUS_PENDING
            assert!(!event::is_event_full(&event_obj), 5);
            
            ts::return_shared(event_obj);
        };

        // Verify creator received EventNFT
        ts::next_tx(&mut scenario, CREATOR);
        {
            let nft = ts::take_from_sender<EventNFT>(&scenario);
            ts::return_to_sender(&scenario, nft);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = event::E_INVALID_LIFE_FEE)]
    fun test_event_creation_invalid_life_fee() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let sui_payment = mint_sui(REWARD_AMOUNT * 2, ctx);
            let life_fee = mint_life(LIFE_FEE / 2, ctx); // Wrong fee
            
            event::create_event(
                b"Test Event",
                b"Description",
                b"Instructions",
                b"https://example.com/image.png",
                REWARD_AMOUNT,
                start_time,
                end_time,
                10,
                sui_payment,
                life_fee,
                ctx
            );
        };

        ts::end(scenario);
    }

    // ============ Event Join Tests ============

    #[test]
    fun test_join_event() {
        let mut scenario = ts::begin(CREATOR);
        let current_time = ONE_DAY_MS / 2;
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        
        // Create event
        create_test_event(&mut scenario, start_time, end_time, 10);
        
        // User1 joins
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(current_time, ctx);
            
            event::join_event(&mut event_obj, &clock, ctx);
            
            assert!(event::get_current_participants(&event_obj) == 1, 0);
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        // Verify User1 received Participant NFT
        ts::next_tx(&mut scenario, USER1);
        {
            let participant = ts::take_from_sender<Participant>(&scenario);
            ts::return_to_sender(&scenario, participant);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = event::E_ALREADY_JOINED)]
    fun test_join_event_twice_fails() {
        let mut scenario = ts::begin(CREATOR);
        let current_time = ONE_DAY_MS / 2;
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        
        // Create event
        create_test_event(&mut scenario, start_time, end_time, 10);
        
        // User1 joins first time
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(current_time, ctx);
            
            event::join_event(&mut event_obj, &clock, ctx);
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        // User1 tries to join again - should fail
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(current_time, ctx);
            
            event::join_event(&mut event_obj, &clock, ctx);
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = event::E_EVENT_FULL)]
    fun test_join_full_event_fails() {
        let mut scenario = ts::begin(CREATOR);
        let current_time = ONE_DAY_MS / 2;
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        
        // Create event with max 2 participants
        create_test_event(&mut scenario, start_time, end_time, 2);
        
        // User1 joins
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(current_time, ctx);
            event::join_event(&mut event_obj, &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        // User2 joins
        ts::next_tx(&mut scenario, USER2);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(current_time, ctx);
            event::join_event(&mut event_obj, &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        // User3 tries to join - should fail
        ts::next_tx(&mut scenario, USER3);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(current_time, ctx);
            event::join_event(&mut event_obj, &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = event::E_EVENT_ENDED)]
    fun test_join_ended_event_fails() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let after_end_time = end_time + ONE_HOUR_MS;
        
        // Create event
        create_test_event(&mut scenario, start_time, end_time, 10);
        
        // Try to join after event ended
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(after_end_time, ctx);
            
            event::join_event(&mut event_obj, &clock, ctx);
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    // ============ Submit Proof Tests ============

    #[test]
    fun test_submit_proof() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let during_event = start_time + ONE_HOUR_MS;
        
        // Create event
        create_test_event(&mut scenario, start_time, end_time, 10);
        
        // User1 joins before event starts
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(start_time - ONE_HOUR_MS, ctx);
            event::join_event(&mut event_obj, &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        // User1 submits proof during event
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(during_event, ctx);
            
            event::submit_proof(
                &mut event_obj,
                b"proof_hash_12345",
                &clock,
                ctx
            );
            
            assert!(event::get_status(&event_obj) == 1, 0); // STATUS_RUNNING
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = event::E_EVENT_NOT_STARTED)]
    fun test_submit_proof_before_start_fails() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let before_start = start_time - ONE_HOUR_MS;
        
        // Create event
        create_test_event(&mut scenario, start_time, end_time, 10);
        
        // User1 joins
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(before_start, ctx);
            event::join_event(&mut event_obj, &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        // User1 tries to submit proof before event starts
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(before_start, ctx);
            
            event::submit_proof(&mut event_obj, b"proof", &clock, ctx);
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = event::E_NO_SUBMISSION)]
    fun test_submit_proof_not_participant_fails() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let during_event = start_time + ONE_HOUR_MS;
        
        // Create event
        create_test_event(&mut scenario, start_time, end_time, 10);
        
        // User1 (not joined) tries to submit proof
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(during_event, ctx);
            
            event::submit_proof(&mut event_obj, b"proof", &clock, ctx);
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    // ============ Verify Participants Tests ============

    #[test]
    fun test_verify_participants() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let after_end = end_time + ONE_HOUR_MS;
        
        // Create event and have users join
        create_test_event(&mut scenario, start_time, end_time, 10);
        join_users_to_event(&mut scenario, start_time - ONE_HOUR_MS);
        
        // Creator verifies participants
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(after_end, ctx);
            
            let approved = vector[USER1, USER2];
            event::verify_participants(&mut event_obj, approved, &clock, ctx);
            
            assert!(event::get_status(&event_obj) == 3, 0); // STATUS_VERIFIED
            assert!(event::get_reward_per_person(&event_obj) == REWARD_AMOUNT / 2, 1);
            assert!(event::is_user_approved(&event_obj, USER1), 2);
            assert!(event::is_user_approved(&event_obj, USER2), 3);
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = event::E_NOT_CREATOR)]
    fun test_verify_by_non_creator_fails() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let after_end = end_time + ONE_HOUR_MS;
        
        // Create event
        create_test_event(&mut scenario, start_time, end_time, 10);
        
        // Non-creator tries to verify
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(after_end, ctx);
            
            let approved = vector[USER1];
            event::verify_participants(&mut event_obj, approved, &clock, ctx);
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = event::E_EVENT_NOT_ENDED)]
    fun test_verify_before_end_fails() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let during_event = start_time + ONE_HOUR_MS;
        
        // Create event
        create_test_event(&mut scenario, start_time, end_time, 10);
        
        // Creator tries to verify before event ends
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(during_event, ctx);
            
            let approved = vector[USER1];
            event::verify_participants(&mut event_obj, approved, &clock, ctx);
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = event::E_ALREADY_VERIFIED)]
    fun test_verify_twice_fails() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let after_end = end_time + ONE_HOUR_MS;
        
        // Create event and have users join
        create_test_event(&mut scenario, start_time, end_time, 10);
        join_users_to_event(&mut scenario, start_time - ONE_HOUR_MS);
        
        // First verification
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(after_end, ctx);
            
            let approved = vector[USER1];
            event::verify_participants(&mut event_obj, approved, &clock, ctx);
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        // Second verification should fail
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(after_end, ctx);
            
            let approved = vector[USER2];
            event::verify_participants(&mut event_obj, approved, &clock, ctx);
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    // ============ Claim Reward Tests ============

    #[test]
    fun test_claim_reward() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let after_end = end_time + ONE_HOUR_MS;
        
        // Setup: Create event, users join, creator verifies
        create_test_event(&mut scenario, start_time, end_time, 10);
        join_users_to_event(&mut scenario, start_time - ONE_HOUR_MS);
        verify_event(&mut scenario, after_end, vector[USER1, USER2]);
        
        // User1 claims reward
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            
            event::claim_reward(&mut event_obj, &mut vault, ctx);
            
            assert!(event::has_user_claimed(&event_obj, USER1), 0);
            assert!(event::get_total_claimed(&event_obj) == REWARD_AMOUNT / 2, 1);
            
            ts::return_shared(vault);
            ts::return_shared(event_obj);
        };

        // Verify User1 received SUI
        ts::next_tx(&mut scenario, USER1);
        {
            let reward = ts::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&reward) == REWARD_AMOUNT / 2, 2);
            test_utils::destroy(reward);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_claim_reward_last_claimer_gets_remainder() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let after_end = end_time + ONE_HOUR_MS;
        
        // Create event with reward that doesn't divide evenly
        let odd_reward = 1_000_000_001; // 3 people = 333333333 each, 2 remainder
        
        ts::next_tx(&mut scenario, CREATOR);
        {
            let ctx = ts::ctx(&mut scenario);
            let sui_payment = mint_sui(odd_reward * 2, ctx);
            let life_fee = mint_life(LIFE_FEE, ctx);
            
            event::create_event(
                b"Test Event",
                b"Description",
                b"Instructions",
                b"https://example.com/image.png",
                odd_reward,
                start_time,
                end_time,
                10,
                sui_payment,
                life_fee,
                ctx
            );
        };
        
        // All 3 users join
        join_users_to_event(&mut scenario, start_time - ONE_HOUR_MS);
        
        // User3 also joins
        ts::next_tx(&mut scenario, USER3);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(start_time - ONE_HOUR_MS, ctx);
            event::join_event(&mut event_obj, &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };
        
        verify_event(&mut scenario, after_end, vector[USER1, USER2, USER3]);
        
        // User1 claims
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            event::claim_reward(&mut event_obj, &mut vault, ctx);
            ts::return_shared(vault);
            ts::return_shared(event_obj);
        };
        
        // User2 claims
        ts::next_tx(&mut scenario, USER2);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            event::claim_reward(&mut event_obj, &mut vault, ctx);
            ts::return_shared(vault);
            ts::return_shared(event_obj);
        };
        
        // User3 claims last - should get remainder
        ts::next_tx(&mut scenario, USER3);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            event::claim_reward(&mut event_obj, &mut vault, ctx);
            
            assert!(event::get_total_claimed(&event_obj) == odd_reward, 0);
            assert!(vault::is_empty(&vault), 1);
            
            ts::return_shared(vault);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = event::E_NOT_VERIFIED)]
    fun test_claim_before_verification_fails() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        
        // Create event and join
        create_test_event(&mut scenario, start_time, end_time, 10);
        join_users_to_event(&mut scenario, start_time - ONE_HOUR_MS);
        
        // User1 tries to claim without verification
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            
            event::claim_reward(&mut event_obj, &mut vault, ctx);
            
            ts::return_shared(vault);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = event::E_NOT_APPROVED)]
    fun test_claim_not_approved_fails() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let after_end = end_time + ONE_HOUR_MS;
        
        // Create event and join
        create_test_event(&mut scenario, start_time, end_time, 10);
        join_users_to_event(&mut scenario, start_time - ONE_HOUR_MS);
        
        // Only USER1 is approved
        verify_event(&mut scenario, after_end, vector[USER1]);
        
        // User2 (not approved) tries to claim
        ts::next_tx(&mut scenario, USER2);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            
            event::claim_reward(&mut event_obj, &mut vault, ctx);
            
            ts::return_shared(vault);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = event::E_ALREADY_CLAIMED)]
    fun test_claim_twice_fails() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let after_end = end_time + ONE_HOUR_MS;
        
        // Setup
        create_test_event(&mut scenario, start_time, end_time, 10);
        join_users_to_event(&mut scenario, start_time - ONE_HOUR_MS);
        verify_event(&mut scenario, after_end, vector[USER1, USER2]);
        
        // User1 claims first time
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            event::claim_reward(&mut event_obj, &mut vault, ctx);
            ts::return_shared(vault);
            ts::return_shared(event_obj);
        };
        
        // User1 tries to claim again
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            event::claim_reward(&mut event_obj, &mut vault, ctx);
            ts::return_shared(vault);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    // ============ Update Status Tests ============

    #[test]
    fun test_update_status() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        
        create_test_event(&mut scenario, start_time, end_time, 10);
        
        // Before start - should be PENDING
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(start_time - 1, ctx);
            
            event::update_status(&mut event_obj, &clock, ctx);
            assert!(event::get_status(&event_obj) == 0, 0); // STATUS_PENDING
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };
        
        // During event - should be RUNNING
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(start_time + ONE_HOUR_MS, ctx);
            
            event::update_status(&mut event_obj, &clock, ctx);
            assert!(event::get_status(&event_obj) == 1, 1); // STATUS_RUNNING
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };
        
        // After end - should be ENDED
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(end_time + ONE_HOUR_MS, ctx);
            
            event::update_status(&mut event_obj, &clock, ctx);
            assert!(event::get_status(&event_obj) == 2, 2); // STATUS_ENDED
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    // ============ Full Flow Integration Test ============

    #[test]
    fun test_full_event_flow() {
        let mut scenario = ts::begin(CREATOR);
        let start_time = ONE_DAY_MS;
        let end_time = start_time + ONE_DAY_MS;
        let before_start = start_time - ONE_HOUR_MS;
        let during_event = start_time + ONE_HOUR_MS;
        let after_end = end_time + ONE_HOUR_MS;
        
        // 1. Creator creates event
        create_test_event(&mut scenario, start_time, end_time, 10);
        
        // 2. Users join before event starts
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(before_start, ctx);
            event::join_event(&mut event_obj, &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };
        
        ts::next_tx(&mut scenario, USER2);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(before_start, ctx);
            event::join_event(&mut event_obj, &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };
        
        // 3. Users submit proofs during event
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(during_event, ctx);
            event::submit_proof(&mut event_obj, b"user1_completed_mission", &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };
        
        ts::next_tx(&mut scenario, USER2);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(during_event, ctx);
            event::submit_proof(&mut event_obj, b"user2_completed_mission", &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };
        
        // 4. Creator verifies after event ends
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let clock = create_clock_at(after_end, ctx);
            
            let approved = vector[USER1, USER2];
            event::verify_participants(&mut event_obj, approved, &clock, ctx);
            
            assert!(event::get_status(&event_obj) == 3, 0); // STATUS_VERIFIED
            
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };
        
        // 5. Users claim rewards
        ts::next_tx(&mut scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            event::claim_reward(&mut event_obj, &mut vault, ctx);
            ts::return_shared(vault);
            ts::return_shared(event_obj);
        };
        
        ts::next_tx(&mut scenario, USER2);
        {
            let mut event_obj = ts::take_shared<Event>(&scenario);
            let mut vault = ts::take_shared<Vault>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            event::claim_reward(&mut event_obj, &mut vault, ctx);
            ts::return_shared(vault);
            ts::return_shared(event_obj);
        };
        
        // 6. Verify final state
        ts::next_tx(&mut scenario, CREATOR);
        {
            let event_obj = ts::take_shared<Event>(&scenario);
            let vault = ts::take_shared<Vault>(&scenario);
            
            // All rewards distributed
            assert!(event::get_total_claimed(&event_obj) == REWARD_AMOUNT, 1);
            assert!(vault::is_empty(&vault), 2);
            assert!(vault::is_claimed(&vault), 3);
            
            // Both users claimed
            assert!(event::has_user_claimed(&event_obj, USER1), 4);
            assert!(event::has_user_claimed(&event_obj, USER2), 5);
            
            ts::return_shared(vault);
            ts::return_shared(event_obj);
        };

        ts::end(scenario);
    }

    // ============ Helper Functions for Tests ============

    fun create_test_event(scenario: &mut Scenario, start_time: u64, end_time: u64, max_participants: u64) {
        ts::next_tx(scenario, CREATOR);
        {
            let ctx = ts::ctx(scenario);
            let sui_payment = mint_sui(REWARD_AMOUNT * 2, ctx);
            let life_fee = mint_life(LIFE_FEE, ctx);
            
            event::create_event(
                b"Test Event",
                b"Test description",
                b"Test instructions",
                b"https://example.com/image.png",
                REWARD_AMOUNT,
                start_time,
                end_time,
                max_participants,
                sui_payment,
                life_fee,
                ctx
            );
        };
    }

    fun join_users_to_event(scenario: &mut Scenario, join_time: u64) {
        ts::next_tx(scenario, USER1);
        {
            let mut event_obj = ts::take_shared<Event>(scenario);
            let ctx = ts::ctx(scenario);
            let clock = create_clock_at(join_time, ctx);
            event::join_event(&mut event_obj, &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };
        
        ts::next_tx(scenario, USER2);
        {
            let mut event_obj = ts::take_shared<Event>(scenario);
            let ctx = ts::ctx(scenario);
            let clock = create_clock_at(join_time, ctx);
            event::join_event(&mut event_obj, &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };
    }

    fun verify_event(scenario: &mut Scenario, verify_time: u64, approved: vector<address>) {
        ts::next_tx(scenario, CREATOR);
        {
            let mut event_obj = ts::take_shared<Event>(scenario);
            let ctx = ts::ctx(scenario);
            let clock = create_clock_at(verify_time, ctx);
            event::verify_participants(&mut event_obj, approved, &clock, ctx);
            clock::destroy_for_testing(clock);
            ts::return_shared(event_obj);
        };
    }
}
