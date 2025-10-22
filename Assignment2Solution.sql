USE COMP2350_zA2W29TeamD;

-- Just in case: keep foreign keys on
SET @@foreign_key_checks = 1;

-- ================================================================
-- TASK 2 — FUNCTIONS
-- ================================================================
DELIMITER //

-- 2.1 calcLoyaltyPoints(orderID)
-- Rule: earn points ONLY when order is 'Delivered' (BR6).
--       1 point per $1, using normal rounding.
DROP FUNCTION IF EXISTS calcLoyaltyPoints //
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
-- ---------------------------------------------------------------

-- 2.2 isGiftCardValid(code)
-- A gift card is valid if: it exists, isActive = 1, and expirationDate >= today (BR3, BR4).
DROP FUNCTION IF EXISTS isGiftCardValid //
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
DELIMITER ;

-- 2.3 TEST IDEAS (run these one by one and screenshot results)
-- (Adjust userID to a valid one)
-- INSERT INTO GiftCard(giftCardCode, userID, balance, isActive, expirationDate) VALUES
-- ('GC_OK' , 1, 50.00, 1, DATE_ADD(CURDATE(), INTERVAL 7 DAY)),
-- ('GC_EXP', 1, 50.00, 1, DATE_SUB(CURDATE(), INTERVAL 1 DAY)),
-- ('GC_OFF', 1, 50.00, 0, DATE_ADD(CURDATE(), INTERVAL 7 DAY));
-- SELECT 'ok'  AS scenario, isGiftCardValid('GC_OK')  AS result;
-- SELECT 'exp' AS scenario, isGiftCardValid('GC_EXP') AS result;
-- SELECT 'off' AS scenario, isGiftCardValid('GC_OFF') AS result;
-- SELECT '404' AS scenario, isGiftCardValid('NO_CARD') AS result;
-- SELECT orderID, orderStatus, totalAmount, calcLoyaltyPoints(orderID) AS pts
--   FROM CusOrder ORDER BY orderID;

-- ================================================================
-- TASK 3 — PROCEDURES
-- ================================================================

/*
3.1 redeemGiftCard — DESIGN ONLY
Purpose (BR2, BR3, BR4):
  Use a valid, active, non-expired gift card with enough balance to pay part/all of an order.
Inputs:
  p_orderID, p_giftCardCode, p_amount
Outputs:
  (optional) a message string like 'Redeemed $X from gift card'
Pre-conditions:
  • Order exists and is not already fully paid.
  • Gift card exists, isActive = 1, expirationDate >= today, balance >= p_amount.
Post-conditions:
  • GiftCard.balance decreases by p_amount.
  • Payment row is inserted (method 'Gift Card') with amountPaid = p_amount and status 'Completed'.
  • If any check fails, nothing changes (rollback).
Tables touched:
  GiftCard (balance), Payment (orderID, amountPaid, paymentStatus, paymentMethodID/Method)
Errors (examples):
  'Order not found', 'Gift card invalid or expired', 'Insufficient gift card balance', 'Overpayment would occur'
*/

DELIMITER //

-- 3.2 CheckoutOrder — IMPLEMENTATION
-- What it does (simple version):
--   1) Check customer has a primary address (BR1).
--   2) Check stock is enough for all items, then deduct (BR5).
--   3) If using points, deduct points and log it (BR3, BR6 note).
--   4) Make sure completed/approved payments exactly equal order total (BR2).
DROP PROCEDURE IF EXISTS CheckoutOrder //
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
DELIMITER ;

-- 3.3 TEST IDEAS (paste, edit IDs, and screenshot)
-- CALL CheckoutOrder(<order_without_primary>, 0);    -- expect BR1 error
-- CALL CheckoutOrder(<order_with_low_stock>, 0);     -- expect BR5 error
-- CALL CheckoutOrder(<order_with_bad_payment>, 0);   -- expect BR2 error
-- CALL CheckoutOrder(1, 50);                         -- success example


-- ================================================================
-- TASK 4 — TRIGGERS
-- ================================================================

/*
4.1 Trigger Designs (no code needed here)
A) Stock Deduction (BR5)
   BEFORE INSERT ON OrderItem:
     - If Product.stockQuantity < NEW.quantity → SIGNAL error.
     - Else subtract the quantity from Product.stockQuantity immediately.

B) Overpayment Prevention (BR2)
   BEFORE INSERT ON Payment (and BEFORE UPDATE of amount/status):
     - Sum existing Completed/Approved + NEW.amount (if NEW qualifies).
     - If sum > order total → SIGNAL error "Overpayment not allowed".
*/

DELIMITER //

-- 4.2 Trigger 1: Refund Processing (BR7 & BR8)
-- When a return turns to 'Accepted', create one Refund row and
-- make sure refund <= original price * quantity.
DROP TRIGGER IF EXISTS trg_return_accepted_refund //
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
-- ---------------------------------------------------------------

-- 4.2 Trigger 2: Loyalty Points Adjustment (BR6 & BR10)
-- Credit points when an order becomes Delivered.
-- If later Cancelled or Returned, take those points back (not below 0).
DROP TRIGGER IF EXISTS trg_order_points_simple //
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
DELIMITER ;

-- 4.3 TEST IDEAS (run, then screenshot)
-- -- Refund flow:
-- INSERT INTO ReturnedItem(orderItemID, returnReason, requestedAt, returnStatus)
-- VALUES (1, 'Beginner test', NOW(), 'Pending');
-- UPDATE ReturnedItem
--    SET returnStatus='Accepted', decisionDate=NOW(), refundAmount=9999.99
--  WHERE returnID = LAST_INSERT_ID();
-- SELECT * FROM Refund ORDER BY refundID DESC LIMIT 3;

-- -- Points credit then reversal:
-- UPDATE CusOrder SET orderStatus='Delivered' WHERE orderID = 2;
-- SELECT u.loyaltyPoints, lt.*
--   FROM `User` u JOIN LoyaltyTransaction lt ON u.userID = lt.userID
--  WHERE lt.orderID = 2;
-- UPDATE CusOrder SET orderStatus='Cancelled' WHERE orderID = 2;
-- SELECT u.loyaltyPoints, lt.*
--   FROM `User` u JOIN LoyaltyTransaction lt ON u.userID = lt.userID
--  WHERE lt.orderID = 2;

-- ====================== END (BEGINNER VERSION) ======================
