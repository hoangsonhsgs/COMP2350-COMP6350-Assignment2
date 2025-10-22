# BNCL Assignment 2 – Solution README

This doc walks through what’s in the `Assignment2Solution.sql`, why it’s written that way, and how to run + test it quickly. It’s written for us (not the marker), so it’s chatty but still precise.

---

## TL;DR (what we built)
- Functions:  
  - `calcLoyaltyPoints(orderID)`: credits **1 point per $1** but **only when the order is Delivered**.  
  - `isGiftCardValid(code)`: returns `1/0` depending on **active** and **not expired**.
- Procedure:  
  - `CheckoutOrder(orderID, pointsToRedeem)`: sanity checks (primary address, points, stock), deducts stock, redeems points, and enforces that **completed/approved payments = order total**.
- Triggers:  
  - `trg_return_accepted_refund`: when a **return** becomes **Accepted**, auto-create a **Refund** row with an amount **capped at original purchase price** (and avoid duplicates).  
  - `trg_order_points_simple`: when **orderStatus** changes: **credit** points on Delivered (once), **reclaim** on Cancelled/Returned.

All of this lines up with the spec’s BR1–BR10 and Tasks 2–4.

---

## How to run this quickly
1. Open **MySQL Workbench**.  
2. Run the baseline schema:  
   `COMP2350_2025S2_Assignment2_SQL v2.1 (iLearn - local server).sql`
3. Switch to the working schema if needed (the script starts with `USE ...;`).  
4. Run `Assignment2Solution.sql` top to bottom.
5. Use the **test snippets** in the file to verify functions/triggers (see sections below).

### Tables in play (from the provided base schema)
- `User`
- `UserAddress`
- `Product`
- `CusOrder`
- `OrderItem`
- `PaymentMethod`
- `Payment`
- `GiftCard`
- `LoyaltyTransaction`
- `Afterpay`
- `ReturnedItem`
- `Refund`

---

## Functions (Task 2)

### 1) `calcLoyaltyPoints(orderID)`
**Intent:** 1 point per $1 **only when Delivered**. If not delivered (or order missing) → 0 points.  
**Why:** That’s exactly how loyalty is defined for completed/delivered orders (see BR6).  
**Core idea:** We look up `CusOrder.totalAmount` and `CusOrder.orderStatus`, then `ROUND(totalAmount, 0)` only if status is `Delivered`.

```sql
CREATE FUNCTION calcLoyaltyPoints(p_orderID INT)
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE v_total DECIMAL(10,2);
    DECLARE v_status VARCHAR(20);
    DECLARE v_points INT;

    -- Get the order total and status
    SELECT totalAmount, orderStatus
      INTO v_total, v_status
      FROM CusOrder
     WHERE orderID = p_orderID;

    -- If order not found or not delivered → 0 points
    IF v_total IS NULL THEN
        SET v_points = 0;
    ELSEIF v_status = 'Delivered' THEN
        SET v_points = ROUND(v_total, 0);
    ELSE
        SET v_points = 0;
    END IF;

    RETURN v_points;
END //
```

**Notes**
- `ROUND` makes “$x.yz → points” nice and clean.  
- Safe against missing orders (returns 0).

---

### 2) `isGiftCardValid(code)`
**Intent:** Return `1` if the gift card exists **and** `isActive=1` **and** `expirationDate >= CURDATE()`. Otherwise `0`.  
**Why:** That’s the validity rule (active + not expired) and supports other BRs around gift cards.

```sql
CREATE FUNCTION isGiftCardValid(p_giftCardCode VARCHAR(20))
RETURNS TINYINT(1)
DETERMINISTIC
BEGIN
    DECLARE v_active TINYINT(1);
    DECLARE v_exp DATE;

    SELECT isActive, expirationDate
      INTO v_active, v_exp
      FROM GiftCard
     WHERE giftCardCode = p_giftCardCode;

    -- If not found → invalid (0)
    IF v_active IS NULL THEN
        RETURN 0;
    END IF;

    -- Valid = active and not expired
    IF v_active = 1 AND v_exp >= CURDATE() THEN
        RETURN 1;
    ELSE
        RETURN 0;
    END IF;
END //
```

**Notes**
- If the card isn’t found, we treat it as invalid (`0`).  
- This makes it easy to gate any gift-card spend logic later.

---

## Procedure (Task 3)

### `CheckoutOrder(orderID, pointsToRedeem)`
**What it enforces end‑to‑end:**
1) The customer has **at least one primary address**.  
2) **Stock** is available for *all* items in the order; we **deduct stock** in one go.  
3) **Loyalty points** redemption is valid (non‑negative and ≤ user balance); if >0, we deduct points and log to `LoyaltyTransaction`.  
4) Payments with status in **('Completed','Approved')** must **sum exactly** to the order’s `totalAmount`. If not → rollback + error.

```sql
CREATE PROCEDURE CheckoutOrder(IN p_orderID INT, IN p_pointsToRedeem INT)
BEGIN
    DECLARE v_userID INT;
    DECLARE v_orderTotal DECIMAL(10,2);
    DECLARE v_paid DECIMAL(10,2);
    DECLARE v_hasPrimary INT;
    DECLARE v_userPoints INT;
    DECLARE v_msg VARCHAR(255);

    -- 0) Basic order info
    SELECT userID, totalAmount
      INTO v_userID, v_orderTotal
      FROM CusOrder
     WHERE orderID = p_orderID;

    IF v_userID IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order not found';
    END IF;

    -- 1) Must have a primary address (BR1)
    SELECT COUNT(*)
      INTO v_hasPrimary
      FROM UserAddress
     WHERE userID = v_userID AND isPrimary = 1;

    IF v_hasPrimary = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No primary address on file (BR1)';
    END IF;

    -- 2) Points check (cannot be negative; cannot exceed available)
    IF p_pointsToRedeem < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Points cannot be negative';
    END IF;

    SELECT loyaltyPoints
      INTO v_userPoints
      FROM `User`
     WHERE userID = v_userID;

    IF p_pointsToRedeem > v_userPoints THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient loyalty points';
    END IF;

    START TRANSACTION;

      -- 3) Stock check (BR5). If any product has less stock than needed, stop.
      IF EXISTS (
           SELECT 1
             FROM OrderItem oi
             JOIN Product p ON p.productID = oi.productID
            WHERE oi.orderID = p_orderID
              AND p.stockQuantity < oi.quantity
      ) THEN
         ROLLBACK;
         SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient stock (BR5)';
      END IF;

      -- 4) Deduct stock for all items in the order
      UPDATE Product p
         JOIN OrderItem oi ON oi.productID = p.productID
        SET p.stockQuantity = p.stockQuantity - oi.quantity
      WHERE oi.orderID = p_orderID;

      -- 5) Redeem points now (record a spend transaction)
      IF p_pointsToRedeem > 0 THEN
         UPDATE `User`
            SET loyaltyPoints = loyaltyPoints - p_pointsToRedeem
          WHERE userID = v_userID;

         INSERT INTO LoyaltyTransaction(userID, orderID, pointsEarned, pointsSpent)
         VALUES (v_userID, p_orderID, 0, p_pointsToRedeem);
      END IF;

      -- 6) Payments must match total (Completed/Approved only) (BR2)
      SELECT COALESCE(SUM(amountPaid),0)
        INTO v_paid
        FROM Payment
       WHERE orderID = p_orderID
         AND paymentStatus IN ('Completed','Approved');

      IF v_paid <> v_orderTotal THEN
         ROLLBACK;
         SET v_msg = 'Payment total does not equal order total (BR2)';
         SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
      END IF;

    COMMIT;
END //
```

**A few implementation details worth calling out**
- **Consistency:** wraps stock check + stock deduction + points deduction inside a **transaction**.  
- **Stock check:** a single `EXISTS(...)` detects any item where `p.stockQuantity < oi.quantity`; if true, it **signals** and **rolls back**.  
- **Error style:** uses `SIGNAL SQLSTATE '45000'` with friendly messages so the caller sees *why* it failed.  
- **Idempotency:** points are only adjusted if `pointsToRedeem > 0`.

**Common error messages you’ll see**
- `No primary address on file (BR1)`  
- `Insufficient stock (BR5)`  
- `Points cannot be negative` / `Insufficient loyalty points`  
- `Payment total does not equal order total (BR2)`

---

## Triggers (Task 4)

### A) `trg_return_accepted_refund` (Refund processing)
**When:** `ReturnedItem.returnStatus` flips to `Accepted`.  
**What it does:**  
- Looks up the **original price and quantity** from `OrderItem`.  
- Computes the **max refund cap** = `priceAtPurchase * quantity`.  
- If `ReturnedItem.refundAmount` is null → use full cap. If provided → **clamp** to the cap.  
- Inserts **one** `Refund` row if one doesn’t exist yet. (Prevents duplicates.)

```sql
CREATE TRIGGER trg_return_accepted_refund
AFTER UPDATE ON ReturnedItem
FOR EACH ROW
BEGIN
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_qty INT;
    DECLARE v_cap DECIMAL(10,2);
    DECLARE v_finalRefund DECIMAL(10,2);
    DECLARE v_hasRefund INT;

    -- Only act when status changes to Accepted
    IF NEW.returnStatus = 'Accepted' AND OLD.returnStatus <> 'Accepted' THEN

        -- Find original price and quantity from OrderItem
        SELECT priceAtPurchase, quantity
          INTO v_price, v_qty
          FROM OrderItem
         WHERE orderItemID = NEW.orderItemID;

        IF v_price IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Original order item not found for refund';
        END IF;

        -- Maximum refund allowed
        SET v_cap = v_price * IFNULL(v_qty, 1);

        -- If no specific amount on ReturnedItem, use full cap; otherwise clamp
        IF NEW.refundAmount IS NULL THEN
            SET v_finalRefund = v_cap;
        ELSE
            IF NEW.refundAmount > v_cap THEN
                SET v_finalRefund = v_cap;
            ELSE
                SET v_finalRefund = NEW.refundAmount;
            END IF;
        END IF;

        -- Avoid duplicate refund rows
        SELECT COUNT(*) INTO v_hasRefund
          FROM Refund
         WHERE returnID = NEW.returnID;

        IF v_hasRefund = 0 THEN
            INSERT INTO Refund(returnID, refundMethod, refundAmount, processedAt)
            VALUES(NEW.returnID, 'Original Method', v_finalRefund, NOW());
        END IF;
    END IF;
END //
```

**Edge cases handled**
- If someone tries to set a ridiculous `refundAmount`, we cap it to the purchase price.  
- If a refund row already exists, we **don’t** insert another one (simple duplicate guard).

---

### B) `trg_order_points_simple` (Points credit + clawback)
**When:** `CusOrder.orderStatus` actually **changes**.  
**What it does:**  
- On `Delivered`: compute `v_credit = calcLoyaltyPoints(...)` and credit it **once** (we check `LoyaltyTransaction` first).  
- On `Cancelled` or `Returned`: compute the **net credited** for this order and **reclaim** it (never dropping the user below 0).  
- Always logs to `LoyaltyTransaction` for traceability.

```sql
CREATE TRIGGER trg_order_points_simple
AFTER UPDATE ON CusOrder
FOR EACH ROW
BEGIN
    DECLARE v_userID INT;
    DECLARE v_credit INT;
    DECLARE v_already INT;
    DECLARE v_reclaim INT;

    -- Only do something when status actually changes
    IF NEW.orderStatus <> OLD.orderStatus THEN

        -- Delivered → credit once
        IF NEW.orderStatus = 'Delivered' THEN
            SET v_credit = calcLoyaltyPoints(NEW.orderID);

            -- Did we already credit this order?
            SELECT COALESCE(SUM(pointsEarned),0)
              INTO v_already
              FROM LoyaltyTransaction
             WHERE orderID = NEW.orderID;

            IF v_credit > 0 AND v_already = 0 THEN
                SELECT userID INTO v_userID FROM CusOrder WHERE orderID = NEW.orderID;

                UPDATE `User`
                   SET loyaltyPoints = loyaltyPoints + v_credit
                 WHERE userID = v_userID;

                INSERT INTO LoyaltyTransaction(userID, orderID, pointsEarned, pointsSpent)
                VALUES (v_userID, NEW.orderID, v_credit, 0);
            END IF;
        END IF;

        -- Cancelled/Returned → remove any points credited for this order
        IF NEW.orderStatus IN ('Cancelled','Returned') THEN
            SELECT COALESCE(SUM(pointsEarned - pointsSpent),0)
              INTO v_reclaim
              FROM LoyaltyTransaction
             WHERE orderID = NEW.orderID;

            IF v_reclaim > 0 THEN
                SELECT userID INTO v_userID FROM CusOrder WHERE orderID = NEW.orderID;

                UPDATE `User`
                   SET loyaltyPoints = GREATEST(0, loyaltyPoints - v_reclaim)
                 WHERE userID = v_userID;

                INSERT INTO LoyaltyTransaction(userID, orderID, pointsEarned, pointsSpent)
                VALUES (v_userID, NEW.orderID, 0, v_reclaim);
            END IF;
        END IF;

    END IF;
END //
```

**Why this shape?**
- Keeps all point side‑effects hooked to the *order status* source of truth.  
- “Credit once” avoids double counting if someone toggles the status back and forth.  
- “Clawback” ensures BR6/BR10 behaviour is consistent with reality.

---

## Test quick‑starts you can paste

### Functions
```sql
-- Create a few test gift cards (adjust userID as needed)
INSERT INTO GiftCard(giftCardCode, userID, balance, isActive, expirationDate) VALUES
('GC_OK' , 1, 50.00, 1, DATE_ADD(CURDATE(), INTERVAL 7 DAY)),
('GC_EXP', 1, 50.00, 1, DATE_SUB(CURDATE(), INTERVAL 1 DAY)),
('GC_OFF', 1, 50.00, 0, DATE_ADD(CURDATE(), INTERVAL 7 DAY));

-- Validity checks
SELECT 'ok'  AS scenario, isGiftCardValid('GC_OK')  AS result;
SELECT 'exp' AS scenario, isGiftCardValid('GC_EXP') AS result;
SELECT 'off' AS scenario, isGiftCardValid('GC_OFF') AS result;
SELECT '404' AS scenario, isGiftCardValid('NO_CARD') AS result;

-- Loyalty points for a few orders
SELECT orderID, orderStatus, totalAmount, calcLoyaltyPoints(orderID) AS pts
FROM CusOrder ORDER BY orderID;
```

### Procedure
```sql
-- Example run (adjust IDs/amounts to your dataset)
CALL CheckoutOrder( /* orderID */ 2, /* pointsToRedeem */ 100 );
```

### Triggers
```sql
-- Refund flow demo
INSERT INTO ReturnedItem(orderItemID, returnReason, requestedAt, returnStatus)
VALUES (1, 'Beginner test', NOW(), 'Pending');

UPDATE ReturnedItem
   SET returnStatus='Accepted', decisionDate=NOW(), refundAmount=9999.99
 WHERE returnID = LAST_INSERT_ID();

SELECT * FROM Refund ORDER BY refundID DESC LIMIT 3;

-- Points credit then reversal
UPDATE CusOrder SET orderStatus='Delivered' WHERE orderID = 2;
UPDATE CusOrder SET orderStatus='Cancelled' WHERE orderID = 2;
SELECT * FROM LoyaltyTransaction WHERE orderID = 2;
```

---

## Design choices

- **Round points at the end** of the `calcLoyaltyPoints` path. Simple and matches “$1 → 1 point”.  
- **Use transactions** in `CheckoutOrder` to keep stock, points, and payment checks atomic. Any failure → rollback.  
- **Use `SIGNAL` with meaningful messages** so debugging and screenshots are painless.  
- **Triggers do just one thing each**: refunds are attached to return acceptance; loyalty bookkeeping is attached to order status changes.  
- **Avoid double effects** by checking if credit already happened, and by guarding duplicate refunds.

---

## What to screenshot for the PDF
- Function tests returning the expected values for both **valid** and **invalid** gift cards.  
- An order where `calcLoyaltyPoints` returns points only when it’s **Delivered**.  
- A `CheckoutOrder` run that:
  - Fails with a clear error if **no primary address** exists.
  - Fails with **Insufficient stock (BR5)** if stock is short.
  - Fails with **Payment total does not equal order total (BR2)** if payments don’t add up.
  - Succeeds when everything is correct.
- Trigger tests showing:
  - Refund capped correctly and only **one** refund row inserted.
  - Loyalty points credited on **Delivered**, and reclaimed on **Cancelled/Returned**.

---

## File structure
- `COMP2350_2025S2_Assignment2_SQL v2.1 (iLearn - local server).sql` – the base schema & seed data from iLearn.
- `Assignment2Solution.sql` – our functions, procedure, triggers + test snippets.
- This `README.md` – how to run and what to screenshot.

If anything’s unclear, ping in the group chat and we’ll tweak.
