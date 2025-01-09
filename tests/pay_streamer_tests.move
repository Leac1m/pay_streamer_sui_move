#[test_only]
module pay_streamer::pay_streamer_tests {
    use pay_streamer::pay_streamer::{Self as ps, AdminCap};
    use sui::coin;
    use sui::sui::SUI;
    use sui::test_scenario::{Self as ts, Scenario, ctx, next_tx};
    use sui::clock::{Self};
    use sui::test_utils;

    const ADDR1: address = @0xA;
    const ADDR2: address = @0xB;

    const DUMMY_MS: u64 = 987654321;
    const HOUR_TIMEFRAME: u64 = 3600;
    const DAY_TIMEFRAME: u64 = 3600 * 24;
    
    //otw for coin used in tests
    public struct COIN1 has drop {}

    const CREATED: u64 = 0;
    const ACTIVE: u64 = 1;
    const PAUSED: u64 = 2;
    // const CANCELLED: u64 = 3;

    fun test_scenario_init(sender: address): Scenario {
        let mut scenario = ts::begin(sender);
        {
            ps::test_init(ctx(&mut scenario));
        };
        next_tx(&mut scenario, sender);

        scenario
    }

    /* ===create_payment create payment test*/
    fun test_scenario_create_payment<COIN>(scenario: &mut Scenario, amount: u64, duration: u64): ps::Payment<COIN> {
        let coin = coin::mint_for_testing<COIN>(amount, ctx(scenario));
        let mut payments = ts::take_shared<ps::Payments>(scenario);

        let payment = ps::create_payment<COIN>(coin, duration, &mut payments, ctx(scenario));

        ts::return_shared(payments);
        payment
    }
    

    #[test]
    fun test_add_coin() {
        let scenario = test_scenario_init(ADDR1);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut payments = ts::take_shared<ps::Payments>(&scenario);

            ps::add_coin<COIN1>(&admin_cap, &mut payments);
            assert!(ps::test_coin_in_bag<COIN1>(&payments), 0);

            ts::return_to_address<AdminCap>(ADDR1, admin_cap);
            ts::return_shared(payments);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_create_payment() {
        let mut scenario = test_scenario_init(ADDR1);
        {
            let coin = coin::mint_for_testing<SUI>(1_000_000, ctx(&mut scenario));

            let mut payments = ts::take_shared<ps::Payments>(&scenario);
            let payment = ps::create_payment<SUI>(coin, 3600 * 24, &mut payments, ctx(&mut scenario));
            payment.check_status<SUI>(CREATED);

            payment.destroy_for_testing();
            ts::return_shared(payments);
        };

        ts::end(scenario);
    }

    #[test, expected_failure(abort_code = ps::ECoinNotSupported)]
    fun test_unsupport_coin() {
        let mut scenario = test_scenario_init(ADDR1);
        {
            let coin = coin::mint_for_testing<COIN1>(1_000_000, ctx(&mut scenario));
            let mut payments = ts::take_shared<ps::Payments>(&scenario);
            
            let payment = ps::create_payment<COIN1>(coin, 3600 * 24, &mut payments, ctx(&mut scenario));

            payment.destroy_for_testing();
            ts::return_shared(payments);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_start_payment() {
        let mut scenario = test_scenario_init(ADDR1);
        let payment = test_scenario_create_payment<SUI>(&mut scenario, 1_000_000, DAY_TIMEFRAME);

        next_tx(&mut scenario, ADDR1);
        {
            let mut payments = ts::take_shared<ps::Payments>(&scenario);
            let mut clock = clock::create_for_testing(ctx(&mut scenario));
            clock.set_for_testing(DUMMY_MS);

            let payment_id = object::id(&payment);
            let payer_cap = ps::start_payment<SUI>(&mut payments, payment, ADDR2, &clock, ctx(&mut scenario));
            

            let payment = payments.get_payment<SUI>(payment_id);
            payment.check_status<SUI>(ACTIVE);


            transfer::public_transfer(payer_cap, ADDR1);
            payments.return_payment<SUI>(payment);
            ts::return_shared(payments);
            clock.destroy_for_testing();
        };

        next_tx(&mut scenario, ADDR2);
        {
            let payee_cap = ts::take_from_sender<ps::PayeeCap>(&scenario);
            ts::return_to_address(ADDR2, payee_cap);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_pause_payment() {
        let mut scenario = test_scenario_init(ADDR1);
        let payment = test_scenario_create_payment<SUI>(&mut scenario, 1_000_000, DAY_TIMEFRAME);

        next_tx(&mut scenario, ADDR1);
        {
            let mut payments = ts::take_shared<ps::Payments>(&scenario);
            let mut clock = clock::create_for_testing(ctx(&mut scenario));
            clock.set_for_testing(DUMMY_MS);

            let payment_id = object::id(&payment);
            let payer_cap = ps::start_payment<SUI>(&mut payments, payment, ADDR2, &clock, ctx(&mut scenario));
            
            ps::pause_payment<SUI>(&payer_cap, &mut payments, &clock);
            
            let payment = payments.get_payment<SUI>(payment_id);
            payment.check_status<SUI>(PAUSED);


            transfer::public_transfer(payer_cap, ADDR1);
            payments.return_payment<SUI>(payment);
            ts::return_shared(payments);
            clock.destroy_for_testing();
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ps::EPaymentNotActive)]
    fun test_pause_payment_abort_if_not_active() {
        let mut scenario = test_scenario_init(ADDR1);
        let payment = test_scenario_create_payment<SUI>(&mut scenario, 1_000_000, DAY_TIMEFRAME);
        
        
        next_tx(&mut scenario, ADDR1);
        let (mut payments, clock, payer_cap) = {
            let mut payments = ts::take_shared<ps::Payments>(&scenario);
            let mut clock = clock::create_for_testing(ctx(&mut scenario));
            clock.set_for_testing(DUMMY_MS);

            let payer_cap = payments.start_payment<SUI>(payment, ADDR2, &clock, ctx(&mut scenario));
            payer_cap.pause_payment<SUI>(&mut payments, &clock);

            (payments, clock, payer_cap)
        };

        next_tx(&mut scenario, ADDR1);
        {
            payer_cap.pause_payment<SUI>(&mut payments, &clock); //aborts here

            transfer::public_transfer(payer_cap, ADDR1);
            clock.destroy_for_testing();
            ts::return_shared(payments);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_resume_payment() {
        let mut scenario = test_scenario_init(ADDR1);
        let payment = test_scenario_create_payment<SUI>(&mut scenario, 1_000_000, DAY_TIMEFRAME);

        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        clock.set_for_testing(DUMMY_MS);

        next_tx(&mut scenario, ADDR1);
        let (payer_cap, mut payments) ={
            let mut payments = ts::take_shared<ps::Payments>(&scenario);
            let payer_cap = payments.start_payment<SUI>(payment, ADDR2, &clock, ctx(&mut scenario));
            payer_cap.pause_payment<SUI>(&mut payments, &clock);

            (payer_cap, payments)
        };

        next_tx(&mut scenario, ADDR1);
        {
            clock.increment_for_testing(DAY_TIMEFRAME);
            payer_cap.resume_payment<SUI>(&mut payments, &clock);

            ts::return_shared(payments);
            clock.destroy_for_testing();
            transfer::public_transfer(payer_cap, ADDR1);
        };
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ps::EPaymentNotPaused)]
    fun test_resume_payment_abort_if_not_paused() {
       let mut scenario = test_scenario_init(ADDR1);
        let payment = test_scenario_create_payment<SUI>(&mut scenario, 1_000_000, DAY_TIMEFRAME);

        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        clock.set_for_testing(DUMMY_MS);

        next_tx(&mut scenario, ADDR1);
        let (payer_cap, mut payments) ={
            let mut payments = ts::take_shared<ps::Payments>(&scenario);
            let payer_cap = payments.start_payment<SUI>(payment, ADDR2, &clock, ctx(&mut scenario));
            payer_cap.pause_payment<SUI>(&mut payments, &clock);

            (payer_cap, payments)
        };

        next_tx(&mut scenario, ADDR1);
        {
            clock.increment_for_testing(DAY_TIMEFRAME);
            payer_cap.resume_payment<SUI>(&mut payments, &clock);
        };

        next_tx(&mut scenario, ADDR1);
        {
            clock.increment_for_testing(DAY_TIMEFRAME);
            payer_cap.resume_payment<SUI>(&mut payments, &clock); // aborts here

            ts::return_shared(payments);
            clock.destroy_for_testing();
            transfer::public_transfer(payer_cap, ADDR1);
        };
        ts::end(scenario); 
    }

    #[test]
    fun test_cancel_payent() {
        let mut scenario = test_scenario_init(ADDR1);
        let payment = test_scenario_create_payment(&mut scenario, 1003, HOUR_TIMEFRAME);
        // let payment_id = object::id(&payment);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        clock.set_for_testing(DUMMY_MS);

        next_tx(&mut scenario, ADDR1);
        {   let mut payments = ts::take_shared<ps::Payments>(&scenario);
            let payer_cap = payments.start_payment<SUI>(payment, ADDR2, &clock, ctx(&mut scenario));
            
            let coin = payer_cap.cancel_payment<SUI>(&mut payments, &clock, ctx(&mut scenario));
            test_utils::assert_eq<u64>(coin.value(), 1000);

            coin.burn_for_testing();
            clock.destroy_for_testing();
            transfer::public_transfer(payer_cap, ADDR1);
            ts::return_shared(payments);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_withdraw_payment() {
        let mut scenario = test_scenario_init(ADDR1);
        let payment = test_scenario_create_payment(&mut scenario, 60180, HOUR_TIMEFRAME);
        // let payment_id = object::id(&payment);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        clock.set_for_testing(DUMMY_MS);

        next_tx(&mut scenario, ADDR1);
        let mut payments = ts::take_shared<ps::Payments>(&scenario);
        {   
            let payer_cap = payments.start_payment<SUI>(payment, ADDR2, &clock, ctx(&mut scenario));
            clock.increment_for_testing(45 * 60); //45 minutes
            transfer::public_transfer(payer_cap, ADDR1);
        };

        next_tx(&mut scenario, ADDR2);
        {
            let mut payee_cap = ts::take_from_sender<ps::PayeeCap>(&scenario);
            let coin = payee_cap.withdraw_payment<SUI>(&mut payments, &clock, ctx(&mut scenario));
            test_utils::assert_eq<u64>(coin.value(), 45_000);

            coin.burn_for_testing();
            clock.destroy_for_testing();
            transfer::public_transfer(payee_cap, ADDR2);
            ts::return_shared(payments);
        };
        ts::end(scenario);
    }

}

