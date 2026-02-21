-- Sample application schema for data validation demos
-- Replace with your own tables — validation rules are config-driven
USE SentinelDB;
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'customers')
CREATE TABLE customers (
    id          INT IDENTITY(1,1) PRIMARY KEY,
    name        NVARCHAR(200) NOT NULL,
    email       NVARCHAR(200) NOT NULL,
    region      VARCHAR(50) NOT NULL,
    created_at  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    is_active   BIT NOT NULL DEFAULT 1
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'orders')
CREATE TABLE orders (
    id              INT IDENTITY(1,1) PRIMARY KEY,
    customer_id     INT NOT NULL,
    order_date      DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    total_amount    DECIMAL(12,2) NOT NULL,
    status          VARCHAR(30) NOT NULL DEFAULT 'pending',
    shipping_region VARCHAR(50) NULL,
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    CONSTRAINT CK_orders_status CHECK (status IN ('pending', 'shipped', 'delivered', 'cancelled', 'corrupted', 'phantom')),
    CONSTRAINT CK_orders_total CHECK (total_amount >= -99999.99)  -- intentionally wide to allow chaos injection; validation rules enforce stricter bounds
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_orders_customer')
    CREATE INDEX IX_orders_customer ON orders(customer_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_orders_date')
    CREATE INDEX IX_orders_date ON orders(order_date DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'order_items')
CREATE TABLE order_items (
    id          INT IDENTITY(1,1) PRIMARY KEY,
    order_id    INT NOT NULL,
    product     NVARCHAR(200) NOT NULL,
    quantity    INT NOT NULL,
    unit_price  DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(id),
    CONSTRAINT CK_order_items_quantity CHECK (quantity >= 0),
    CONSTRAINT CK_order_items_price CHECK (unit_price >= -9999.99)  -- wide bounds; validation rules enforce stricter
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_order_items_order')
    CREATE INDEX IX_order_items_order ON order_items(order_id);
GO

PRINT 'Sample schema created successfully.';
GO
