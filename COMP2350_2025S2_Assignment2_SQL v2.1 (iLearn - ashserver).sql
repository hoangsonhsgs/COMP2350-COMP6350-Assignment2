-- use your unit code followed by your group ID. 
-- For example, if you are enrolled in COMP2350, and your group ID is G09
-- then, replace XXX with COMP2350_G09
-- CREATE DATABASE XXX; 
-- USE XXX;

-- User table 
CREATE TABLE User (
    userID INT PRIMARY KEY AUTO_INCREMENT,
    userName VARCHAR(50),
    email VARCHAR(30) UNIQUE,
    userPassword VARCHAR(20),
    phone VARCHAR(15),	-- "61 412 345 678" or "0 412 345 678" or "02 1234 5678" or "61 2 1234 5678"
    loyaltyPoints INT DEFAULT 0,
    isMember BOOLEAN DEFAULT FALSE,
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- User addresses table
CREATE TABLE UserAddress (
	addressID INT PRIMARY KEY AUTO_INCREMENT,
    userID INT,
    addressLabel VARCHAR(10),        -- e.g., 'Home', 'Office', etc
    streetAddress VARCHAR(30),
    city VARCHAR(30),
    state VARCHAR(3),
    postcode VARCHAR(4),
    isPrimary BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (userID) REFERENCES User(userID)
);

-- Product table 
CREATE TABLE Product (
    productID INT PRIMARY KEY AUTO_INCREMENT,
    productName VARCHAR(50),
    productDescription TEXT,
	category VARCHAR(50),
    price DECIMAL(7, 2),
    stockQuantity INT,
    isClearance BOOLEAN DEFAULT FALSE
);

-- Customer Order table 
CREATE TABLE CusOrder (
    orderID INT PRIMARY KEY AUTO_INCREMENT,
    userID INT,
    totalAmount DECIMAL(10,2),
    orderStatus ENUM('Processing','Delivered','Cancelled','Returned'), 	-- Delivered, Cancelled, Processing, or Returned
    createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES User(userID)
);

-- Order items for the customer orders 
CREATE TABLE OrderItem (
    orderItemID INT PRIMARY KEY AUTO_INCREMENT,
    orderID INT,
    productID INT,
    quantity INT,
    priceAtPurchase DECIMAL(7, 2),
    FOREIGN KEY (orderID) REFERENCES CusOrder(orderID),
    FOREIGN KEY (productID) REFERENCES Product(productID)
);

-- Payment method 
CREATE TABLE PaymentMethod (
    paymentMethodID INT PRIMARY KEY AUTO_INCREMENT,
    methodName VARCHAR(20), -- e.g., Debit/Credit Card, Gift Card, PayPal, Afterpay, Points + Pay
    description VARCHAR(30)
);

-- Payment 
CREATE TABLE Payment (
    paymentID INT PRIMARY KEY AUTO_INCREMENT,
    orderID INT,
    paymentMethodID INT,
    amountPaid DECIMAL(10,2),
    paymentDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    paymentStatus VARCHAR(50),
    FOREIGN KEY (orderID) REFERENCES CusOrder(orderID),
    FOREIGN KEY (paymentMethodID) REFERENCES PaymentMethod(paymentMethodID)
);

-- Gift card
CREATE TABLE GiftCard (
    giftCardCode VARCHAR(20) PRIMARY KEY,
    userID INT,
    balance DECIMAL(6, 2) CHECK (balance <= 1000.00),	
    isActive BOOLEAN DEFAULT TRUE,
    expirationDate DATE,	
    FOREIGN KEY (userID) REFERENCES User(userID)
);

-- Tracking Loyalty points earned and spent
CREATE TABLE LoyaltyTransaction (
    transactionID INT PRIMARY KEY AUTO_INCREMENT,
    userID INT,
    orderID INT,
    pointsEarned INT DEFAULT 0,
    pointsSpent INT DEFAULT 0,
    transactionDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userID) REFERENCES User(userID),
    FOREIGN KEY (orderID) REFERENCES CusOrder(orderID)
);

-- Tracking Afterpay payments 
CREATE TABLE Afterpay (
    afterpayID INT PRIMARY KEY AUTO_INCREMENT,
    paymentID INT,
    numberOfInstallments INT,
    installmentAmount DECIMAL(10,2),
    FOREIGN KEY (paymentID) REFERENCES Payment(paymentID)
);

-- Track return items 
CREATE TABLE ReturnedItem (
    returnID INT PRIMARY KEY AUTO_INCREMENT,
    orderItemID INT,
    returnReason VARCHAR(255),
    requestedAt TIMESTAMP,															
    returnStatus VARCHAR(50) DEFAULT 'Pending',	-- Pending, Accepted, Declined
    decisionDate DATETIME,
    refundAmount DECIMAL(7, 2),
    FOREIGN KEY (orderItemID) REFERENCES OrderItem(orderItemID)
);

-- Tracking Refunds processed. It might work for trigger example 
CREATE TABLE Refund (
    refundID INT PRIMARY KEY AUTO_INCREMENT,
    returnID INT,
    refundMethod VARCHAR(20),
    refundAmount DECIMAL(10, 2),
    processedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (returnID) REFERENCES ReturnedItem(returnID)
);


INSERT INTO User (userName, email, userPassword, phone, loyaltyPoints, isMember)
VALUES
('Chris Evans', 'chris.evans@gmail.com', 'Kf9$zX1qLp!2', '0412 345 678', 1050, TRUE),
('Scarlett Johansson', 'scarlett.johansson@yahoo.com', 'Rq#8mBn6!xV$', '0412 345 679', 640, FALSE), 
('Tom Holland', 'tom.holland@gmail.com', 'Xp3&Kn@!84Zv', '0412 345 680', 780, TRUE),
('Robert Downey Jr.', 'robert.downeyjr@outlook.com', 'Ws8$Qn@5XpL3', '0412 345 681', 480, FALSE), 
('Chris Hemsworth', 'chris.hemsworth@yahoo.com', 'Nm@62Pv#qR7!', '0412 345 682', 1372, TRUE),
('Elizabeth Olsen', 'elizabeth.olsen@gmail.com', 'Jq@4KvM#7xWe', '0412 345 683', 903, FALSE), 
('Paul Bettany', 'paul.bettany@gmail.com', 'Lp!98NzqAx#7', '0412 345 684', 777, FALSE), 
('Sebastian Stan', 'sebastian.stan@yahoo.com', 'Kr#2qAx1!Lm$', '0412 345 685', 580, TRUE),
('Jeremy Renner', 'jeremy.renner@outlook.com', 'Af!34Vz#Pq6L', '0412 345 686', 1290, TRUE),
('Mark Ruffalo', 'mark.ruffalo@gmail.com', 'Lt!83VqNz@4p', '0412 345 687', 410, TRUE),
('Benedict Cumberbatch', 'benedict.cumberbatch@gmail.com', 'Hq3#TpVz8@Lm', '0412 345 688', 1120, TRUE),
('Tom Hiddleston', 'tom.hiddleston@yahoo.com', 'Nk@93Px#Vm1Q', '0412 345 689', 550, FALSE), 
('Chadwick Boseman', 'chadwick.boseman@outlook.com', 'Vq!41LmNz@87', '0412 345 690', 130, TRUE),
('Brie Larson', 'brie.larson@gmail.com', 'Jp#7VzNqLm$52', '0412 345 691', 860, FALSE), 
('Chris Pratt', 'chris.pratt@yahoo.com', 'Mn4#XtQpVz!8', '0412 345 692', 950, TRUE),
('Elizabeth Banks', 'elizabeth.banks@gmail.com', 'Lt!QnX3Pz@9w', '0412 345 693', 720, FALSE), 
('Paul Rudd', 'paul.rudd@outlook.com', 'Gp!7VzXqLm#2', '0412 345 694', 680, TRUE),
('Evangeline Lilly', 'evangeline.lilly@yahoo.com', 'Hq#4PmVzN!82', '0412 345 695', 560, FALSE), 
('Anthony Mackie', 'anthony.mackie@gmail.com', 'Nk!9VzLp@Xm3', '0412 345 696', 1020, TRUE),
('Zoe Saldana', 'zoe.saldana@gmail.com', 'Vr!31LmXq#Np', '0412 345 697', 430, FALSE) ;

INSERT INTO UserAddress (userID, addressLabel, streetAddress, city, state, postcode, isPrimary) VALUES 
(1, 'Home', '12 Victoria Street', 'Parramatta', 'NSW', 2150 , TRUE),
(2, 'Office', '8 George Street', 'Melbourne', 'VIC', 3000   , FALSE),
(3, 'Locker', '5 Victoria Street', 'Hawthorn', 'VIC', 3122  , TRUE),
(4, 'Home', '102 Victoria Street', 'St Kilda', 'VIC', 3182  , FALSE),
(5, 'Office', '1 George Street', 'Darlinghurst', 'NSW', 2010, TRUE),
(6, 'Locker', '28 Collins Street', 'Northmead', 'NSW', 2152 , FALSE),
(7, 'Home', '120 George Street', 'Brisbane', 'QLD', 4000    , TRUE),
(8, 'Office', '33 Collins Street', 'Hobart', 'TAS', 7000    , TRUE),
(9, 'Locker', '42 George Street', 'Sydney', 'NSW', 2000     , TRUE),
(10, 'Home', '29 George Street', 'Dutton Park', 'QLD', 4102 , FALSE),
(11, 'Office', '6 Victoria Street', 'Fitzroy', 'VIC', 3065  , TRUE),
(12, 'Locker', '24 George Street', 'Carlton', 'VIC', 3053   , FALSE),
(13, 'Home', '11 Collins Street', 'Newtown', 'NSW', 2042    , TRUE),
(14, 'Office', '8 Victoria Street', 'Footscray', 'VIC', 3011, FALSE),
(15, 'Locker', '15 Victoria Street', 'Richmond', 'VIC', 3121, TRUE),
(16, 'Home', '20 George Street', 'Geelong', 'VIC', 3220     , FALSE),
(17, 'Office', '7 Collins Street', 'Bendigo', 'VIC', 3550   , TRUE),
(18, 'Locker', '30 Victoria Street', 'Ballarat', 'VIC', 3350, TRUE),
(19, 'Home', '22 George Street', 'Shepparton', 'VIC', 3630  , TRUE),
(20, 'Office', '14 Collins Street', 'Mildura', 'VIC', 3500  , TRUE);

INSERT INTO Product (productName, productDescription, category,
                      price, stockQuantity, isClearance)
VALUES
('Wireless Headphones'       , 'Noise-cancelling over-ear headphones' , 'Electronics'     , 299.99,  50, FALSE),
('Smartwatch'                , 'Fitness tracking & notification watch', 'Electronics'     , 199.99,  75, FALSE),
('Cotton T-Shirt'            , '100 % organic cotton t-shirt'         , 'Clothing'        ,  29.95, 200, FALSE),
('Yoga Mat'                  , 'Non-slip eco-friendly yoga mat'       , 'Sports'          ,  49.90, 120, FALSE),
('Stainless Steel Water Bottle','Insulated 750 ml bottle'            , 'Home & Kitchen'  ,  24.50, 150, FALSE),
('Espresso Coffee Machine'   , '15-bar pump pressure machine'         , 'Home & Kitchen'  , 349.00,  20, FALSE),
('Running Shoes'             , 'Lightweight road-running trainers'    , 'Sports'          , 149.00,  80, FALSE),
('Facial Moisturiser'        , 'Hydrating daily moisturiser 50 ml'    , 'Beauty'          ,  39.95,  90, FALSE),
('Bluetooth Speaker'         , 'Portable waterproof speaker'          , 'Electronics'     ,  89.00,  60, FALSE),
('Laptop Backpack'           , 'Water-resistant 15-inch backpack'     , 'Clothing'        ,  79.00, 100, FALSE),
('Winter Jacket (Clearance)' , 'Down-fill jacket – last season'       , 'Clothing'        , 129.00,  15, TRUE);


INSERT INTO CusOrder (userID, totalAmount, orderStatus, createdAt)
VALUES
(1 , 348.99, 'Delivered' , '2025-07-20 10:15:00'),
(3 , 238.85, 'Processing', '2025-07-21 14:32:00'),
(5 , 398.90, 'Delivered' , '2025-07-22 11:45:00'),
(7 , 199.99, 'Cancelled' , '2025-07-23 09:10:00'),
(9 , 202.50, 'Delivered' , '2025-07-23 16:05:00'),
(11, 158.90, 'Delivered' , '2025-07-24 13:55:00'),
(13, 188.90, 'Returned'  , '2025-07-25 17:20:00'),
(15, 124.30, 'Delivered' , '2025-07-26 08:40:00'),
(18, 348.99, 'Delivered' , '2025-07-27 12:25:00'),
(20, 119.85, 'Processing', '2025-07-28 18:00:00');


INSERT INTO OrderItem (orderID, productID, quantity, priceAtPurchase)
VALUES

(1 , 1 , 1 , 299.99),
(1 , 5 , 2 ,  24.50),
(2 , 3 , 3 ,  29.95),
(2 , 7 , 1 , 149.00),
(3 , 6 , 1 , 349.00),
(3 , 4 , 1 ,  49.90),
(4 , 2 , 1 , 199.99),
(5 , 9 , 2 ,  89.00),
(5 , 5 , 1 ,  24.50),
(6 ,10 , 1 ,  79.00),
(6 , 8 , 2 ,  39.95),
(7 ,11 , 1 , 129.00),
(7 , 3 , 2 ,  29.95),
(8 , 4 , 2 ,  49.90),
(8 , 5 , 1 ,  24.50),
(9 , 2 , 1 , 199.99),
(9 , 7 , 1 , 149.00),
(10, 8 , 3 ,  39.95);



INSERT INTO PaymentMethod (methodName, description)
VALUES
('Credit Card' , 'Visa / MasterCard'),
('PayPal'      , 'PayPal account' ),
('Gift Card'   , 'Store gift card'),
('Afterpay'    , 'Pay-in-4'       ),
('Points + Pay', 'Loyalty plus card');


INSERT INTO Payment (orderID, paymentMethodID, amountPaid,
                      paymentDate, paymentStatus)
VALUES
(1, 1, 348.99, '2025-07-20 10:16:00', 'Completed'),
(2, 2, 238.85, '2025-07-21 14:33:00', 'Pending'  ),
(3, 4, 398.90, '2025-07-22 11:46:00', 'Approved' ),
(5, 5, 202.50, '2025-07-23 16:06:00', 'Completed'),
(6, 3, 100.00, '2025-07-24 13:56:00', 'Completed'),  
(6, 1,  58.90, '2025-07-24 13:56:30', 'Completed'), 
(7, 1, 188.90, '2025-07-25 17:21:00', 'Completed'),
(8, 1, 124.30, '2025-07-26 08:41:00', 'Completed'),
(9, 4, 348.99, '2025-07-27 12:26:00', 'Approved' ),
(10, 2, 119.85, '2025-07-28 18:01:00', 'Pending'  ),
(4, 1, 199.99, '2025-07-23 09:11:00', 'Completed');


INSERT INTO Afterpay (paymentID, numberOfInstallments, installmentAmount)
VALUES
(3, 4,  99.73),  -- 398.90 / 4
(9, 4,  87.25);  -- 348.99 / 4 (rounded)


INSERT INTO GiftCard (giftCardCode, userID, balance, isActive, expirationDate)
VALUES
('GC1001', 11, 100.00, TRUE , '2026-06-30'),
('GC1002',  2,  75.00, TRUE , '2025-12-31'),
('GC1003', 16,   0.00, FALSE, '2024-12-31');


INSERT INTO LoyaltyTransaction (userID, orderID,
                                 pointsEarned, pointsSpent)
VALUES
(1, 1 , 349,   0),  
(5, 3 , 399,   0),  
(9, 5 , 203, 200),  
(11, 6 , 159,   0),  
(15, 8 , 124,   0),  
(18, 9 , 349,   0); 

INSERT INTO ReturnedItem (orderItemID, returnReason, requestedAt,
                          returnStatus, decisionDate, refundAmount)
VALUES
(12, 'Size too large','2025-07-23 12:00:00','Accepted', '2025-07-26 11:55:00', 129.00),
(7 , 'Customer change of mind', '2025-07-26 12:10:00','Declined', '2025-07-28 12:30:00', NULL),
(5 , 'Color is not as expected' , '2025-09-05 10:23:00', 'Accepted' , '2025-09-08 09:30:00' , 349.00),
(6 , 'Size too small','2025-09-06 12:00:00', 'Accepted' , '2025-09-09 12:30:00', 49.90),
(17, 'Customer change of mind', '2025-09-08 12:00:00', 'Pending', NULL, NULL);

-- Corresponding refund record
INSERT INTO Refund (returnID, refundMethod, refundAmount, processedAt)
VALUES
(1, 'Credit Card', 129.00, '2025-07-26 11:55:00'),
(3, 'Afterpay', 349.90, '2025-09-08 09:30:00'),  
(4, 'Afterpay', 49.90, '2025-09-09 12:30:00');  


