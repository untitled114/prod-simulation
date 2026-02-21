-- Seed sample data: 100 customers, 500 orders, 1500 items
USE SentinelDB;
GO

-- Only seed if tables are empty
IF (SELECT COUNT(*) FROM customers) = 0
BEGIN
    PRINT 'Seeding sample data...';

    -- 100 customers
    DECLARE @i INT = 1;
    WHILE @i <= 100
    BEGIN
        INSERT INTO customers (name, email, region, is_active)
        VALUES (
            CONCAT('Customer_', @i),
            CONCAT('customer', @i, '@example.com'),
            CASE @i % 5
                WHEN 0 THEN 'US-East'
                WHEN 1 THEN 'US-West'
                WHEN 2 THEN 'EU-West'
                WHEN 3 THEN 'APAC'
                WHEN 4 THEN 'US-Central'
            END,
            CASE WHEN @i % 10 = 0 THEN 0 ELSE 1 END
        );
        SET @i = @i + 1;
    END

    -- 500 orders
    SET @i = 1;
    WHILE @i <= 500
    BEGIN
        INSERT INTO orders (customer_id, order_date, total_amount, status, shipping_region)
        VALUES (
            (@i % 100) + 1,
            DATEADD(DAY, -(@i % 90), GETDATE()),
            ROUND(RAND(CHECKSUM(NEWID())) * 500 + 10, 2),
            CASE @i % 4
                WHEN 0 THEN 'pending'
                WHEN 1 THEN 'shipped'
                WHEN 2 THEN 'delivered'
                WHEN 3 THEN 'cancelled'
            END,
            CASE @i % 5
                WHEN 0 THEN 'US-East'
                WHEN 1 THEN 'US-West'
                WHEN 2 THEN 'EU-West'
                WHEN 3 THEN 'APAC'
                WHEN 4 THEN 'US-Central'
            END
        );
        SET @i = @i + 1;
    END

    -- 1500 order items (3 per order)
    SET @i = 1;
    DECLARE @products TABLE (name NVARCHAR(100));
    INSERT INTO @products VALUES ('Widget A'), ('Widget B'), ('Gadget X'), ('Gadget Y'), ('Tool Z');

    WHILE @i <= 500
    BEGIN
        INSERT INTO order_items (order_id, product, quantity, unit_price)
        VALUES
            (@i, CASE @i % 5 WHEN 0 THEN 'Widget A' WHEN 1 THEN 'Widget B' WHEN 2 THEN 'Gadget X' WHEN 3 THEN 'Gadget Y' ELSE 'Tool Z' END, (@i % 5) + 1, ROUND(RAND(CHECKSUM(NEWID())) * 100 + 5, 2)),
            (@i, CASE (@i+1) % 5 WHEN 0 THEN 'Widget A' WHEN 1 THEN 'Widget B' WHEN 2 THEN 'Gadget X' WHEN 3 THEN 'Gadget Y' ELSE 'Tool Z' END, (@i % 3) + 1, ROUND(RAND(CHECKSUM(NEWID())) * 100 + 5, 2)),
            (@i, CASE (@i+2) % 5 WHEN 0 THEN 'Widget A' WHEN 1 THEN 'Widget B' WHEN 2 THEN 'Gadget X' WHEN 3 THEN 'Gadget Y' ELSE 'Tool Z' END, (@i % 4) + 1, ROUND(RAND(CHECKSUM(NEWID())) * 100 + 5, 2));
        SET @i = @i + 1;
    END

    PRINT 'Sample data seeded: 100 customers, 500 orders, 1500 items.';
END
ELSE
    PRINT 'Sample data already exists, skipping seed.';
GO
