-- ===================================================================
-- COMP2350/COMP6350 Assignment 2 – Part A 
-- ===================================================================

-- =========================
-- Task 1: Setup
-- =========================
USE COMP2350_zA2W29TeamD;
SET @@foreign_key_checks = 1;

-- Ensure a generic payment method exists
INSERT INTO PaymentMethod(methodName, description)
SELECT 'Card', 'Submission test method'
WHERE NOT EXISTS (SELECT 1 FROM PaymentMethod WHERE methodName IN ('Card','Credit Card'));
SET @pm_card := (SELECT paymentMethodID FROM PaymentMethod WHERE methodName IN ('Credit Card','Card') ORDER BY paymentMethodID LIMIT 1);

-- ===================================================================
-- Task 2: Functions
-- ===================================================================
DELIMITER //

DROP FUNCTION IF EXISTS calcLoyaltyPoints //
CREATE FUNCTION calcLoyaltyPoints(p_orderID INT)
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE v_total DECIMAL(10,2);
    DECLARE v_status ENUM('Processing','Delivered','Cancelled','Returned');
    DECLARE v_points INT DEFAULT 0;

    -- Assumptions:
    -- A1. Earn rate = 1 point per $1 spent (configurable via v_points_per_dollar).
    -- A2. Redemption value = 100 points = $1 (handled elsewhere).
    -- A3. Award only when orderStatus='Delivered'.
    -- A4. Floor to whole points (no fractions).
    -- A5. Use CusOrder.totalAmount (final charged amount).

    DECLARE v_points_per_dollar INT DEFAULT 1;

    -- Get total & status
    SELECT totalAmount, orderStatus
      INTO v_total, v_status
      FROM CusOrder
     WHERE orderID = p_orderID;

    -- Not found or not Delivered → 0 points
    IF v_total IS NULL OR v_status <> 'Delivered' THEN
        RETURN 0;
    END IF;

    -- Earn points (floor, not round, to avoid being overly generous)
    SET v_points = FLOOR(v_total * v_points_per_dollar);

    RETURN v_points;
END //

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

-- -------------------
-- Task 2.3: Testing
-- -------------------

-- Make a test user (ignore if already exists)
INSERT IGNORE INTO `User` (userName, email, userPassword, phone, loyaltyPoints, isMember)
VALUES ('T23_Simple', 't23_simple@example.com', 'x', '000', 100, 1);

-- ---------------------------------------------
-- A) calcLoyaltyPoints(orderID)
-- Assumptions: earn 1 point per $1, award only when Delivered, floor to integer.

-- Build orders with known totals/status for this user
INSERT INTO CusOrder (userID, totalAmount, orderStatus)
VALUES 
((SELECT userID FROM `User` WHERE email='t23_simple@example.com' LIMIT 1), 79.40,  'Delivered'),
((SELECT userID FROM `User` WHERE email='t23_simple@example.com' LIMIT 1), 79.40,  'Processing'),
((SELECT userID FROM `User` WHERE email='t23_simple@example.com' LIMIT 1), 120.00, 'Cancelled'),
((SELECT userID FROM `User` WHERE email='t23_simple@example.com' LIMIT 1), 45.50,  'Returned'),
((SELECT userID FROM `User` WHERE email='t23_simple@example.com' LIMIT 1), 0.99,   'Delivered'),
((SELECT userID FROM `User` WHERE email='t23_simple@example.com' LIMIT 1), 100.00, 'Delivered');

-- Show results for ALL the above orders (easy screenshot)
SELECT orderID, orderStatus, totalAmount,
       calcLoyaltyPoints(orderID) AS pts
FROM CusOrder
WHERE userID = (SELECT userID FROM `User` WHERE email='t23_simple@example.com' LIMIT 1)
ORDER BY orderID;

-- Non-existent order test (should be 0)
SELECT 'Nonexistent -> 0' AS case_desc, calcLoyaltyPoints(99999999) AS pts;

-- ---------------------------------------------
-- B) isGiftCardValid(code)
-- Valid if: card exists AND isActive=1 AND expirationDate >= CURDATE().

-- Create some gift cards for the same user (ignore if they already exist)
INSERT IGNORE INTO GiftCard (giftCardCode, userID, balance, isActive, expirationDate) VALUES
('S_TODAY',  (SELECT userID FROM `User` WHERE email='t23_simple@example.com' LIMIT 1), 25.00, 1, CURDATE()),
('S_FUTURE', (SELECT userID FROM `User` WHERE email='t23_simple@example.com' LIMIT 1), 50.00, 1, DATE_ADD(CURDATE(), INTERVAL 30 DAY)),
('S_YDAY',   (SELECT userID FROM `User` WHERE email='t23_simple@example.com' LIMIT 1), 50.00, 1, DATE_SUB(CURDATE(), INTERVAL 1 DAY)),
('S_OFF',    (SELECT userID FROM `User` WHERE email='t23_simple@example.com' LIMIT 1), 50.00, 0, DATE_ADD(CURDATE(), INTERVAL 30 DAY)),
('S_ZERO',   (SELECT userID FROM `User` WHERE email='t23_simple@example.com' LIMIT 1),  0.00, 1, DATE_ADD(CURDATE(), INTERVAL 30 DAY));

-- One-line checks
SELECT
  t.case_desc,
  t.code,
  t.expected_valid,
  isGiftCardValid(t.code) AS actual_valid,
  CASE
    WHEN isGiftCardValid(t.code) = t.expected_valid THEN 'PASS'
    ELSE 'FAIL'
  END AS result
FROM (
  SELECT 1 AS idx, 'TODAY -> 1'     AS case_desc, 'S_TODAY'  AS code, 1 AS expected_valid
  UNION ALL
  SELECT 2, 'FUTURE -> 1',           'S_FUTURE',               1
  UNION ALL
  SELECT 3, 'YESTERDAY -> 0',        'S_YDAY',                 0
  UNION ALL
  SELECT 4, 'INACTIVE -> 0',         'S_OFF',                  0
  UNION ALL
  SELECT 5, 'ZERO -> 1',             'S_ZERO',                 1
  UNION ALL
  SELECT 6, '404 -> 0',              'NOPE',                   0
  UNION ALL
  SELECT 7, 'EMPTY -> 0',            '',                       0
) AS t
ORDER BY t.idx;


-- ===================================================================
-- Task 3: Procedures
-- ===================================================================

-- ----------------------------------------
-- Task 3.2: Checkout Process Automation
-- ----------------------------------------

DELIMITER //

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

-- -------------------
-- Task 3.3: Testing
-- -------------------

-- === BR1 test: user has NO primary address (userID = 2) ===

-- pick a payment method id (uses a seeded name)
SET @pm_card := (
  SELECT paymentMethodID FROM PaymentMethod
  WHERE methodName IN ('Credit Card','Card')
  LIMIT 1
);

-- pick a product and remember its price (Cotton T-Shirt, productID = 3)
SET @price := (SELECT price FROM Product WHERE productID = 3);

-- make an order whose total equals the item price
INSERT INTO CusOrder (userID, totalAmount, orderStatus)
VALUES (2, @price, 'Processing');
SET @o_no_primary := LAST_INSERT_ID();

-- add 1 line item with the same price we set above
INSERT INTO OrderItem (orderID, productID, quantity, priceAtPurchase)
VALUES (@o_no_primary, 3, 1, @price);

-- pay exactly the order total (Completed)
INSERT INTO Payment (orderID, paymentMethodID, amountPaid, paymentStatus)
VALUES (@o_no_primary, @pm_card, @price, 'Completed');

-- expect: Error Code 1644 + message 'No primary address on file (BR1)'
CALL CheckoutOrder(@o_no_primary, 0);


-- === BR5 test: force low stock ===

-- pick a payment method
SET @pm_card := (
  SELECT paymentMethodID FROM PaymentMethod
  WHERE methodName IN ('Credit Card','Card')
  LIMIT 1
);

-- choose a product and read its price + current stock
-- (productID 11 or 3 works; We’ll use 11 as example)
SET @prod := 11;
SET @price := (SELECT price FROM Product WHERE productID = @prod);
SET @stock := (SELECT stockQuantity FROM Product WHERE productID = @prod);

-- make quantity one more than stock to guarantee failure
SET @qty := @stock + 1;

-- user with a primary address (userID = 1)
-- total = price * qty (no aggregates)
INSERT INTO CusOrder (userID, totalAmount, orderStatus)
VALUES (1, @price * @qty, 'Processing');
SET @o_low_stock := LAST_INSERT_ID();

-- 1 line item
INSERT INTO OrderItem (orderID, productID, quantity, priceAtPurchase)
VALUES (@o_low_stock, @prod, @qty, @price);

-- pay exactly the total so only stock causes the error
INSERT INTO Payment (orderID, paymentMethodID, amountPaid, paymentStatus)
VALUES (@o_low_stock, @pm_card, @price * @qty, 'Completed');

-- expect: Error Code 1644 + 'Insufficient stock (BR5)'
CALL CheckoutOrder(@o_low_stock, 0);


-- === BR2 minimal test: payments don't match total ===

-- pick a payment method
SET @pm_card := (
  SELECT paymentMethodID FROM PaymentMethod
  WHERE methodName IN ('Credit Card','Card')
  LIMIT 1
);

-- simple product (Cotton T-Shirt, id = 3)
SET @prod := 3;
SET @price := (SELECT price FROM Product WHERE productID = @prod);

-- user with primary address (userID = 1)
INSERT INTO CusOrder (userID, totalAmount, orderStatus)
VALUES (1, @price, 'Processing');
SET @o_bad_pay := LAST_INSERT_ID();

-- 1 line item
INSERT INTO OrderItem (orderID, productID, quantity, priceAtPurchase)
VALUES (@o_bad_pay, @prod, 1, @price);

-- pay LESS than total (so the sum of Completed/Approved != total)
INSERT INTO Payment (orderID, paymentMethodID, amountPaid, paymentStatus)
VALUES (@o_bad_pay, @pm_card, 1.00, 'Completed');  -- 1.00 < @price

-- (optional: add a 'Pending' payment; it won't be counted)
-- INSERT INTO Payment (orderID, paymentMethodID, amountPaid, paymentStatus)
-- VALUES (@o_bad_pay, @pm_card, @price - 1.00, 'Pending');

-- expect: Error Code 1644 + 'Payment total does not equal order total (BR2)'
CALL CheckoutOrder(@o_bad_pay, 0);

-- ---- SUCCESS example: exact payment + small points redemption
-- pick a payment method
SET @pm_card := (
  SELECT paymentMethodID FROM PaymentMethod
  WHERE methodName IN ('Credit Card','Card')
  LIMIT 1
);

-- product with stock (use id = 3)
SET @prod := 3;
SET @price := (SELECT price FROM Product WHERE productID = @prod);

-- small points to redeem to keep it safe (most seeds give user 1 enough points)
SET @redeem := 10;

-- user with primary address (userID = 1)
-- total = 2 * price (no aggregates)
INSERT INTO CusOrder (userID, totalAmount, orderStatus)
VALUES (1, 2 * @price, 'Processing');
SET @o_ok := LAST_INSERT_ID();

-- 1 line item with quantity 2
INSERT INTO OrderItem (orderID, productID, quantity, priceAtPurchase)
VALUES (@o_ok, @prod, 2, @price);

-- pay the exact total (Completed)
INSERT INTO Payment (orderID, paymentMethodID, amountPaid, paymentStatus)
VALUES (@o_ok, @pm_card, 2 * @price, 'Completed');

-- expect: success (no error), stock deducted, points redeemed by 10
CALL CheckoutOrder(@o_ok, @redeem);

-- quick check
SELECT loyaltyPoints FROM `User` WHERE userID = 1;
SELECT productID, stockQuantity FROM Product WHERE productID = @prod;

-- ===================================================================
-- Task 4: Triggers
-- ===================================================================

-- --------------------
-- 4.2 Implementation
-- --------------------

DELIMITER //

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

-- ------------------------------
-- Task 4.3: Test data + queries
-- ------------------------------

-- Refund flow using the success order's item (caps refund to purchase price)
INSERT INTO ReturnedItem(orderItemID, returnReason, requestedAt, returnStatus)
VALUES (1, 'Beginner test', NOW(), 'Pending');
UPDATE ReturnedItem
   SET returnStatus='Accepted', decisionDate=NOW(), refundAmount=9999.99
 WHERE returnID = LAST_INSERT_ID();
SELECT * FROM Refund ORDER BY refundID DESC LIMIT 3;

-- Loyalty: mark the success order Delivered to credit points, then Cancelled to claw back
UPDATE CusOrder SET orderStatus='Delivered' WHERE orderID = 2;
SELECT u.loyaltyPoints, lt.*
  FROM `User` u JOIN LoyaltyTransaction lt ON u.userID = lt.userID
 WHERE lt.orderID = 2;
UPDATE CusOrder SET orderStatus='Cancelled' WHERE orderID = 2;
SELECT u.loyaltyPoints, lt.*
  FROM `User` u JOIN LoyaltyTransaction lt ON u.userID = lt.userID
 WHERE lt.orderID = 2;

-- End of file
