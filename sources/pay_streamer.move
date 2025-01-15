
/// Module: pay_streamer
module pay_streamer::pay_streamer {
    use sui::dynamic_object_field as ofield;
    use sui::dynamic_field as df;
    use sui::bag::{Bag, Self};
    use sui::balance::{Balance,Self};
    use std::type_name::{Self, TypeName};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::clock::{Clock};

    /* === Payment stuct Status*/
    const CREATED: u64 = 0;
    const ACTIVE: u64 = 1;
    const PAUSED: u64 = 2;
    const CANCELLED: u64 = 3;

    /* === errors === */

    /// Coin must be whitelisted to be used.
    const ECoinNotSupported: u64 = 5;
    /// Payment have has to be active.
    const EPaymentNotActive: u64 = 6;
    /// Payment status is not [`PAUSED`].
    const EPaymentNotPaused: u64 = 7;
    /// Fee can't be greater or equal to [`FEE_BASE`]
    const EFeeTooHigh: u64 = 8;

    // Adding new error constants
    const EOVERFLOW: u64 = 12;
    const MAX_U128: u128 = 340282366920938463463374607431768211455; // 2^128 - 1

    /* === constants === */
    const FEE_BASE: u64 = 10_000;

    public struct Payments has key, store {
        id: UID,
        /// 30 is 0.3%
        fee: u64,
        coin_whitelist: Bag
    }

    public struct Payment<phantom COIN> has key, store {
        id: UID,
        status: u64,
        start_date: u64,
        duration: u64,
        pause_duration: u64,
        initial_balance: u64,
        current_balance: Balance<COIN>
    }

    public struct PayeeCap has key, store {
        id: UID,
        payment_id: ID,
        amount_withdrawned: u64
    }

    public struct PayerCap has key, store {
        id: UID,
        payment_id: ID,
    }

    public struct AdminCap has key, store {
        id: UID,
    }

    public struct FeeUpdated has copy, drop {
        old_fee: u64,
        new_fee: u64,
    }
    
    fun init(ctx: &mut TxContext) {
        let mut payments = Payments {
            id: object::new(ctx),
            fee: 30, // default fee 0.3%
            coin_whitelist: bag::new(ctx),
        };

        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        add_coin<SUI>(&admin_cap, &mut payments);
        transfer::public_share_object(payments);

        transfer::transfer(admin_cap, ctx.sender());
    }

    /* == Math == */
    // 1. fee() function has potential overflow issues and should use safer math:
    fun fee(total_amount: u64, percent: u64): u64 {
        assert!(percent <= FEE_BASE, EFeeTooHigh);
        // Check for potential overflow in multiplication
        assert!((total_amount as u128) * (percent as u128) <= MAX_U128, EOVERFLOW);
        ceil_div_u128(((total_amount * percent) as u128), ((FEE_BASE + percent) as u128)) as u64
    }

    fun ceil_div_u128(num: u128, div: u128): u128 {
        if (num == 0) 0 else (num - 1) / div + 1
    }

    // User Funtions

    /// Creates a [`Payment`] struct with a status of [`CREATED`].
    // 2. create_payment lacks proper validation:
    public fun create_payment<COIN>(mut coin: Coin<COIN>, duration: u64, payments: &mut Payments, ctx: &mut TxContext) : Payment<COIN> {
        // Add coin whitelist check
        assert!(bag::contains(&payments.coin_whitelist, type_name::get<COIN>()), ECoinNotSupported);
        // Add duration validation
        assert!(duration > 0, 0);
        
        extract_fee(&mut coin, payments, ctx);

        let payment = Payment<COIN> {
            id: object::new(ctx),
            status: CREATED,
            start_date: 0,
            duration,
            pause_duration: 0,
            initial_balance: coin.value(),
            current_balance: coin.into_balance<COIN>()
        };

        event::emit(
            PaymentCreated {
                payment_id: object::id(&payment)
            }
        );
        payment
    }
    

    /// Activates a [`Payment`] 
    public fun start_payment<COIN>(
        payments: &mut Payments,
        mut payment: Payment<COIN>,
        recipient_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): PayerCap {
        
        set_start_time<COIN>(&mut payment, clock);
        set_status<COIN>(&mut payment, ACTIVE);


        let payment_id = object::id(&payment);

        let payee_cap = PayeeCap {
            id: object::new(ctx),
            payment_id,
            amount_withdrawned: 0
        };
        transfer::public_transfer(payee_cap, recipient_address);

        let payer_cap = PayerCap {
            id: object::new(ctx),
            payment_id: payment_id,
        };

        event::emit(
            PaymentActivated {
                payment_id: payment_id,
                recipient: recipient_address,
                time: current_time(clock)
            }
        );

        ofield::add(&mut payments.id, payment_id, payment);

        payer_cap
    }

    /// Changes [`Payment`] status to [`PAUSED`]
    /// This stops the flow of coin from the [`Payer`]
    /// To the [`Payeer`] until payment is [`Resumed`] or [`cancelled`].
    /// Fails if payment is not active.
    public fun pause_payment<COIN>(
        payer: &PayerCap,
        payments: &mut Payments,
        clock: &Clock
    ) {
        let payment = ofield::borrow_mut<ID, Payment<COIN>>(&mut payments.id, payer.payment_id);
        assert!(payment.status == ACTIVE, EPaymentNotActive);
        // assert!()

        set_status<COIN>(payment, PAUSED);
        df::add(&mut payment.id, PAUSED, current_time(clock));

        event::emit(
            PaymentPaused {
                payment_id: payer.payment_id,
                time: current_time(clock)
            }
        );

    }


    /// Changes [`Payment`] status from [`PAUSED`]
    /// To [`ACTIVE`]. It fails if status is not
    /// [`PAUSED`]. Can only be runned by the owner of a [`PayerCap`]
    public fun resume_payment<COIN>(payer: &PayerCap, payments: &mut Payments, clock: &Clock) {
        let payment = ofield::borrow_mut<ID, Payment<COIN>>(&mut payments.id, payer.payment_id);
        assert!(payment.status == PAUSED, EPaymentNotPaused);

        set_status<COIN>(payment, ACTIVE);
        let previous_pause = df::remove(&mut payment.id, PAUSED);
        let pause_duration = current_time(clock) - previous_pause;
        payment.pause_duration = payment.pause_duration + pause_duration;

        event::emit(
            PaymentResumed {
                payment_id: payer.payment_id,
                time: current_time(clock)
            }
        )
    }


    /// Cancels a [`Payment`] weather in [`CREATED`],
    /// [`ACTIVE`] or [`PAUSED] status mode.
    /// This causes the remain non-withdrawable cash to be
    /// back to owner of [`PayerCap`].
    /// Can only be runned by the owner of a [`PayerCap`].
    public fun cancel_payment<COIN>(
        payer: &PayerCap,
        payments: &mut Payments,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<COIN> {
        let payment = ofield::borrow_mut<ID, Payment<COIN>>(&mut payments.id, payer.payment_id);
        // Add proper status validation
        assert!(payment.status != CANCELLED, 0);
        assert!(payment.status == ACTIVE || payment.status == PAUSED || payment.status == CREATED, 0);
        
        if (payment.status == PAUSED) {
            let previous_pause = df::remove(&mut payment.id, PAUSED);
            let pause_duration = current_time(clock) - previous_pause;
            payment.pause_duration = payment.pause_duration + pause_duration;
        };

        set_status<COIN>(payment, CANCELLED);

        // Ensure there's balance to withdraw
        assert!(balance::value(&payment.current_balance) > 0, 0);
        
        let withdrawable = get_payer_withdrawable<COIN>(payer, payment, clock, ctx);
        withdrawable
    }
    
    /// Withdraw from [`Payment`] for owner of [`Payee`].
    public fun withdraw_payment<COIN>(
        payee: &mut PayeeCap,
        payments: &mut Payments,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<COIN> {
        let payment = ofield::borrow_mut<ID, Payment<COIN>>(&mut payments.id, payee.payment_id);

        let withdrawable = get_payee_withdrawable<COIN>(payee, payment, clock, ctx);
        withdrawable
    }

    /* === Admin Funtions === */

    /// Set fee rates.
    /// 30 represents 0.3%
    public fun set_fee_percent(_: &AdminCap, payments: &mut Payments, fee_rate: u64) {
        // Add minimum fee validation and more specific error
        assert!(fee_rate > 0, 0); // Cannot set zero fee
        assert!(fee_rate <= FEE_BASE, EFeeTooHigh);
        // Add event emission for fee changes
        let old_fee = payments.fee;
        payments.fee = fee_rate;
        event::emit(FeeUpdated { 
            old_fee,
            new_fee: fee_rate 
        });
    }

    /// Adds a coin type [`Coin<COIN>`] into [`coin_whitelist`]
    /// This enables the coin to be used in the platform.
    public fun add_coin<COIN>(_: &AdminCap, payments: &mut Payments) {
        if (!bag::contains(&payments.coin_whitelist, type_name::get<COIN>())) {
        bag::add(&mut payments.coin_whitelist, type_name::get<COIN>(), balance::zero<COIN>());
        };
    }

    /* === Emit sturcts === */

    /// When [`Payment`] object is created.
    public struct PaymentCreated has copy, drop {
        payment_id: ID
    }

    /// Emits when [`Payment`] object is activated.
    public struct PaymentActivated has copy, drop {
        payment_id: ID,
        recipient: address,
        time: u64
    }

    /// Emits when [`Payment`] object is paused
    public struct PaymentPaused has copy, drop {
        payment_id: ID,
        time: u64
    }

    /// Emits when [`Payment`] object resumes after a pause.
    public struct PaymentResumed has copy, drop {
        payment_id: ID,
        time: u64
    }


    // Helper Funtions
    
    /// Getting current time
    fun current_time(clock: &Clock): u64 {
        clock.timestamp_ms()
    }

    fun set_start_time<COIN>(payment: &mut Payment<COIN>, clock: &Clock) {
        payment.start_date = clock.timestamp_ms();
    }

    fun set_status<COIN>(payment: &mut Payment<COIN>, status: u64) {
        payment.status = status;
    }

    fun extract_fee<COIN>(coin: &mut Coin<COIN>, payments: &mut Payments, ctx: &mut TxContext) {
        assert!(bag::contains(&payments.coin_whitelist, type_name::get<COIN>()), ECoinNotSupported);
        let bank = bag::borrow_mut<TypeName, Balance<COIN>>(&mut payments.coin_whitelist, type_name::get<COIN>());
        let fee = fee(coin.value(), payments.fee);

        coin::put(bank, coin.split(fee, ctx));
    }

    /// Extracts withdrable token for owner of [`PayerCap`]
    /// in an instance where payment has been cancelled.
    fun get_payer_withdrawable<COIN>(
        _: &PayerCap,
        payment: &mut Payment<COIN>,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<COIN> {
        let total_time_spent = current_time(clock) - payment.start_date - payment.pause_duration;

        let paid_amount = ((total_time_spent / payment.duration) * payment.initial_balance) as u64;
        let available_amount = payment.initial_balance - paid_amount;

        coin::take<COIN>(&mut payment.current_balance, available_amount, ctx)
    }

    /// Extracts withdrable token for owner of [`PayeeCap`]
    /// in an instance where user wants to withdraw.
    fun get_payee_withdrawable<COIN>(payee: &mut PayeeCap, payment: &mut Payment<COIN>, clock: &Clock,ctx: &mut TxContext): Coin<COIN> {
        let pause_duration = if (payment.status == PAUSED) {
            let previous_pause = df::borrow<u64, u64>(&payment.id, PAUSED);
            let  pause_duration = current_time(clock) - *previous_pause;
            payment.pause_duration + pause_duration 
        } else {
            payment.pause_duration
        };

        let total_time_spent = current_time(clock) - payment.start_date - pause_duration;

        let total_amount = (total_time_spent * payment.initial_balance / payment.duration) as u64;
        let available_amount = total_amount - payee.amount_withdrawned;
        payee.amount_withdrawned = payee.amount_withdrawned + available_amount;

        coin::take<COIN>(&mut payment.current_balance, available_amount, ctx)
    }


    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test_only]
    public fun test_coin_in_bag<COIN>(payments: &Payments): bool {
        payments.coin_whitelist.contains(type_name::get<COIN>())
    }

    #[test_only]
    public fun destroy_for_testing<COIN>(payment: Payment<COIN>) {
        let Payment {
        id,
            status: _,
            start_date: _,
            duration: _,
            pause_duration:_ ,
            initial_balance: _,
            current_balance,
         } = payment;

         id.delete();
         current_balance.destroy_for_testing();
    }
    #[test_only]
    public fun get_payment<COIN>(payments: &mut Payments, payment_id: ID): Payment<COIN>{
        ofield::remove<ID, Payment<COIN>>(&mut payments.id, payment_id)
    }

    #[test_only]
    public fun return_payment<COIN>(payments: &mut Payments, payment: Payment<COIN>) {
        ofield::add<ID, Payment<COIN>>(&mut payments.id, object::id(&payment), payment);
    }

    #[test_only]
    const EValueNotEqual: u64 = 8;

    #[test_only]
    public fun check_status<COIN>(
        payment: &Payment<COIN>,
        status: u64,
    ){
        assert!(payment.status == status, EValueNotEqual);
    }
}