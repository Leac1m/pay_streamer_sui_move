A simple Sui Move stream payment-based payroll system.

## Introduction
+ This module allows anyone to send micro-payments per time interval to another user.
+ After a `Payment` is created, the `Payee` can start the payment by providing the recipient's address.
+ `Payment` is then stored in a shared object `Payments` and capabilities (`PayeeCap` and `PayerCap`) for access control.
+ The `PayerCap` has privilages like `pause_payment`, `resume_payment` and `cancel_payment`.
+ The `PayeeCap` has the privilege of `withdraw_payment`. This takes into account the amount that has already been withdrawn.
+ Composability and convenience were put into consideration when creating functions and structs.

## Core Sturcts
1. Payments
+ `Payments` is a shared object that keeps information like fee rates, supported tokens, and the balance of fees collected.
+ Also when a payment is active, Its `Payment` struct is dynamically linked to this shared object.

2. Payment
+ `Payment` is an object created by a payer. It stores the balance to be "streamed" along with time-related variables to take track of how much has been "streamed".

3. PayerCap
+ `PayerCap` is an access control for the payer.

4. PayeeCap
+ `PayeeCap` is an access control for the recipient.

5. AdminCap
+ `AdminCap` has the authority to alter the `Payments` object. 
+ It can change fee rates, withdraw fee balance, and add a new coin to the whitelist.

## Core function
1. create_payment<COIN-TYPE>
+ Create a `Payment` struct.
+ Input with `Coin`, `duration` (how long you want to stream), `payments`
+ Note: `Coin`: balance you want to stream + fee (default 0.3%).

2. start_payment<COIN-TYPE>
+ starts a `Payment` and sends `PayeeCap` to `Recipient address`.
+ Input with `Payment` `Recipient address` `&Clock` `&mut Payments`
+ Output: `PayerCap`.

3. pause_payment<COIN-TYPE>
+ pause a `Payment`.
+ permission: user with `PayerCap`

4. resume_payment<COIN-TYPE>
+ Resume a pause `Payment`, fails in `Payment` status in not `PAUSED`.
+ permission: user with `PayerCap`

5. cancel_payment<COIN-TYPE>
+ cancel a `Payment`, fails in `Payment` status in already `CANCELLED`.
+ Returns: "unstreamed" `Coin<COIN-TYPE>`
+ permission: user with `PayerCap`

4. withdraw_payment<COIN-TYPE>
+ withdraw stream coins from `Payment`.
+ can be run multiple times.
+ Keep account of how much has been withdrawn.
+ Returns: "streamed" `Coin<COIN-TYPE>
+ permission: user with `PayeeCap`.

5. set_fee_percent<COIN-TYPE>
+ Change current fee rates.
+ permission: user with `AdminCap`

6. Admin_withdraw<COIN-TYPE>
+ withdraw a from fee balance.
+ permission: user with `AdminCap`

## Unit test
![](<unit_tests.png>)
