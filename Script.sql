IF DB_ID('DemoDB') IS NULL
    CREATE DATABASE DemoDB;
GO

USE DemoDB;
GO

-- 2) Drop existing tables (be careful in prod!)
IF OBJECT_ID(N'dbo.Trades', N'U') IS NOT NULL
    DROP TABLE dbo.Trades;
GO
IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
    DROP TABLE dbo.Users;
GO

-- 3) Create Users table
CREATE TABLE dbo.Users (
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Email NVARCHAR(200) NOT NULL,
    Phone NVARCHAR(50) NOT NULL,
    Username NVARCHAR(50) NOT NULL UNIQUE,
    [Password] NVARCHAR(128) NOT NULL,
    BusinessAcc NVARCHAR(50) NOT NULL UNIQUE,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- 4) Create Trades (Orders) table
-- Link to Users via BusinessAcc or UserID; we use UserID foreign key
CREATE TABLE dbo.Trades (
    TradeID INT IDENTITY(1,1) PRIMARY KEY,
    UserID INT NOT NULL,
    ProductID NVARCHAR(100) NOT NULL,
    [Type] NVARCHAR(100) NOT NULL,
    Quantity INT NOT NULL,
    Price DECIMAL(18,2) NOT NULL,       -- sale price per unit
    Cost DECIMAL(18,2) NOT NULL,        -- cost per unit
    IsDamaged BIT NOT NULL DEFAULT 0,
    DamagedQty INT NOT NULL DEFAULT 0,
    Status NVARCHAR(50) NOT NULL,       -- e.g. 'Ordered', 'Shipped', etc.
    OrderDate DATE NOT NULL DEFAULT CONVERT(date, SYSUTCDATETIME()),
    ETADays INT NOT NULL DEFAULT 0,
    ModifiedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_Trades_Users FOREIGN KEY (UserID) REFERENCES dbo.Users(UserID)
);
GO

-- 5) Insert sample users (ali, ayse)
INSERT INTO dbo.Users (Name, Email, Phone, Username, [Password], BusinessAcc)
VALUES
    (N'Ali', N'ali@example.com', N'05001234567', N'ali', N'1234', N'BA1001'),
    (N'Ayse', N'ayse@example.com', N'05559876543', N'ayse', N'5678', N'BA1002');
GO

------------------------------------------------------------------------------------------------
-- Authentication Key (for listing all users)
-- Change as desired; matches JS AUTH_KEY = '135790'
------------------------------------------------------------------------------------------------
-- We will hardcode in SP for comparison.

------------------------------------------------------------------------------------------------
-- Stored Procedures
------------------------------------------------------------------------------------------------

-- 1) Register User: sp_RegisterUser
IF OBJECT_ID(N'dbo.sp_RegisterUser', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_RegisterUser;
GO
CREATE PROCEDURE dbo.sp_RegisterUser
    @Name NVARCHAR(100),
    @Email NVARCHAR(200),
    @Phone NVARCHAR(50),
    @Username NVARCHAR(50),
    @Password NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    -- Check username uniqueness
    IF EXISTS (SELECT 1 FROM dbo.Users WHERE Username = @Username)
    BEGIN
        RAISERROR('Username taken. Choose another.', 16, 1);
        RETURN;
    END

    -- Generate a new BusinessAcc: e.g. 'BA' + (1000 + UserID)
    -- But since UserID is IDENTITY, we insert first then update BusinessAcc, or generate based on next identity
    -- Simpler: insert first with placeholder, then update BusinessAcc
    INSERT INTO dbo.Users (Name, Email, Phone, Username, [Password], BusinessAcc)
    VALUES (@Name, @Email, @Phone, @Username, @Password, N'');
    DECLARE @NewID INT = SCOPE_IDENTITY();
    DECLARE @NewBusinessAcc NVARCHAR(50) = 'BA' + CONVERT(NVARCHAR(10), 1000 + @NewID);

    UPDATE dbo.Users
    SET BusinessAcc = @NewBusinessAcc
    WHERE UserID = @NewID;

    PRINT CONCAT('✅ Registration successful. Your BusinessAcc: ', @NewBusinessAcc);
END;
GO

-- 2) Login User: sp_LoginUser
IF OBJECT_ID(N'dbo.sp_LoginUser', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_LoginUser;
GO
CREATE PROCEDURE dbo.sp_LoginUser
    @Username NVARCHAR(50),
    @Password NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserID INT;
    SELECT @UserID = UserID
    FROM dbo.Users
    WHERE Username = @Username AND [Password] = @Password;

    IF @UserID IS NULL
    BEGIN
        RAISERROR('❌ Invalid credentials. Login failed.', 16, 1);
        RETURN;
    END

    -- Return basic info (excluding password)
    SELECT UserID, Name, Email, Phone, Username, BusinessAcc
    FROM dbo.Users
    WHERE UserID = @UserID;
END;
GO

-- 3) Show My Info: sp_ShowMyInfo
IF OBJECT_ID(N'dbo.sp_ShowMyInfo', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ShowMyInfo;
GO
CREATE PROCEDURE dbo.sp_ShowMyInfo
    @Username NVARCHAR(50),
    @Password NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.Users
        WHERE Username = @Username AND [Password] = @Password
    )
    BEGIN
        RAISERROR('Invalid credentials. Cannot show info.', 16, 1);
        RETURN;
    END

    -- Return all fields including password and businessAcc
    SELECT UserID, Name, Email, Phone, Username, [Password], BusinessAcc, CreatedAt
    FROM dbo.Users
    WHERE Username = @Username;
END;
GO

-- 4) Update My Info: sp_UpdateMyInfo
IF OBJECT_ID(N'dbo.sp_UpdateMyInfo', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_UpdateMyInfo;
GO
CREATE PROCEDURE dbo.sp_UpdateMyInfo
    @Username NVARCHAR(50),
    @Password NVARCHAR(128),
    @NewName NVARCHAR(100) = NULL,
    @NewEmail NVARCHAR(200) = NULL,
    @NewPhone NVARCHAR(50) = NULL,
    @NewPassword NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Verify credentials
    DECLARE @UserID INT;
    SELECT @UserID = UserID
    FROM dbo.Users
    WHERE Username = @Username AND [Password] = @Password;

    IF @UserID IS NULL
    BEGIN
        RAISERROR('Invalid credentials. Cannot update info.', 16, 1);
        RETURN;
    END

    -- Update fields if provided
    UPDATE dbo.Users
    SET
        Name = COALESCE(@NewName, Name),
        Email = COALESCE(@NewEmail, Email),
        Phone = COALESCE(@NewPhone, Phone),
        [Password] = CASE WHEN @NewPassword IS NOT NULL AND @NewPassword <> '' THEN @NewPassword ELSE [Password] END,
        ModifiedAt = SYSUTCDATETIME()
    WHERE UserID = @UserID;

    PRINT '✏️ Your info updated.';
END;
GO

-- 5) Delete My Account: sp_DeleteMyAccount
IF OBJECT_ID(N'dbo.sp_DeleteMyAccount', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_DeleteMyAccount;
GO
CREATE PROCEDURE dbo.sp_DeleteMyAccount
    @Username NVARCHAR(50),
    @Password NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserID INT;
    SELECT @UserID = UserID
    FROM dbo.Users
    WHERE Username = @Username AND [Password] = @Password;

    IF @UserID IS NULL
    BEGIN
        RAISERROR('Invalid credentials. Cannot delete account.', 16, 1);
        RETURN;
    END

    -- Delete user's trades first (cascade-like)
    DELETE FROM dbo.Trades WHERE UserID = @UserID;

    -- Delete user
    DELETE FROM dbo.Users WHERE UserID = @UserID;

    PRINT '❌ Your account deleted.';
END;
GO

-- 6) List All Users: sp_ListAllUsers
IF OBJECT_ID(N'dbo.sp_ListAllUsers', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ListAllUsers;
GO
CREATE PROCEDURE dbo.sp_ListAllUsers
    @AuthKey NVARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    IF @AuthKey <> '135790'
    BEGIN
        RAISERROR('Invalid Authentication Key. Access denied.', 16, 1);
        RETURN;
    END

    SELECT UserID, Name, Email, Phone, Username, BusinessAcc, CreatedAt
    FROM dbo.Users;
END;
GO

-- 7) View Orders for Current User: sp_ViewOrders
IF OBJECT_ID(N'dbo.sp_ViewOrders', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ViewOrders;
GO
CREATE PROCEDURE dbo.sp_ViewOrders
    @Username NVARCHAR(50),
    @Password NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserID INT;
    SELECT @UserID = UserID FROM dbo.Users WHERE Username = @Username AND [Password] = @Password;
    IF @UserID IS NULL
    BEGIN
        RAISERROR('Invalid credentials. Cannot view orders.', 16, 1);
        RETURN;
    END

    SELECT
        t.TradeID,
        t.ProductID,
        t.Type,
        t.Quantity,
        t.Price,
        t.Cost,
        t.IsDamaged,
        t.DamagedQty,
        t.Status,
        t.OrderDate,
        t.ETADays,
        t.ModifiedAt
    FROM dbo.Trades AS t
    WHERE t.UserID = @UserID
    ORDER BY t.OrderDate DESC, t.TradeID;
END;
GO

-- 8) Create Order: sp_CreateOrder
IF OBJECT_ID(N'dbo.sp_CreateOrder', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CreateOrder;
GO
CREATE PROCEDURE dbo.sp_CreateOrder
    @Username NVARCHAR(50),
    @Password NVARCHAR(128),
    @ProductID NVARCHAR(100),
    @Type NVARCHAR(100),
    @Quantity INT,
    @Price DECIMAL(18,2),
    @Cost DECIMAL(18,2),
    @IsDamaged BIT = 0,
    @DamagedQty INT = 0,
    @ETADays INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate user
    DECLARE @UserID INT;
    SELECT @UserID = UserID FROM dbo.Users WHERE Username = @Username AND [Password] = @Password;
    IF @UserID IS NULL
    BEGIN
        RAISERROR('Invalid credentials. Cannot create order.', 16, 1);
        RETURN;
    END

    -- Validate damagedQty <= quantity
    IF @IsDamaged = 1 AND (@DamagedQty < 0 OR @DamagedQty > @Quantity)
    BEGIN
        RAISERROR('Invalid damaged quantity.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.Trades
        (UserID, ProductID, [Type], Quantity, Price, Cost, IsDamaged, DamagedQty, Status, OrderDate, ETADays)
    VALUES
        (@UserID, @ProductID, @Type, @Quantity, @Price, @Cost, @IsDamaged, @DamagedQty, N'Ordered', CONVERT(date, SYSUTCDATETIME()), @ETADays);

    PRINT '✅ Order created.';
END;
GO

-- 9) Update Order Status: sp_UpdateOrderStatus
IF OBJECT_ID(N'dbo.sp_UpdateOrderStatus', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_UpdateOrderStatus;
GO
CREATE PROCEDURE dbo.sp_UpdateOrderStatus
    @Username NVARCHAR(50),
    @Password NVARCHAR(128),
    @TradeID INT,
    @NewStatus NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate user
    DECLARE @UserID INT;
    SELECT @UserID = UserID FROM dbo.Users WHERE Username = @Username AND [Password] = @Password;
    IF @UserID IS NULL
    BEGIN
        RAISERROR('Invalid credentials. Cannot update order status.', 16, 1);
        RETURN;
    END

    -- Check ownership
    IF NOT EXISTS (SELECT 1 FROM dbo.Trades WHERE TradeID = @TradeID AND UserID = @UserID)
    BEGIN
        RAISERROR('Order not found or not owned by you.', 16, 1);
        RETURN;
    END

    UPDATE dbo.Trades
    SET Status = @NewStatus,
        ModifiedAt = SYSUTCDATETIME()
    WHERE TradeID = @TradeID;

    PRINT '✏️ Order status updated.';
END;
GO

-- 10) Profit/Loss Summary: sp_GetProfitLoss
IF OBJECT_ID(N'dbo.sp_GetProfitLoss', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetProfitLoss;
GO
CREATE PROCEDURE dbo.sp_GetProfitLoss
    @Username NVARCHAR(50),
    @Password NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate user
    DECLARE @UserID INT;
    SELECT @UserID = UserID FROM dbo.Users WHERE Username = @Username AND [Password] = @Password;
    IF @UserID IS NULL
    BEGIN
        RAISERROR('Invalid credentials. Cannot get profit/loss.', 16, 1);
        RETURN;
    END

    -- Aggregate
    SELECT
        SUM(t.Price * t.Quantity) AS TotalRevenue,
        SUM(t.Cost * t.Quantity) AS TotalCost,
        SUM(CASE WHEN t.IsDamaged = 1 THEN t.Cost * t.DamagedQty ELSE 0 END) AS TotalDamagedCost,
        SUM(t.Price * t.Quantity) - SUM(t.Cost * t.Quantity) AS GrossProfit,
        (SUM(t.Price * t.Quantity) - SUM(t.Cost * t.Quantity)) -
            SUM(CASE WHEN t.IsDamaged = 1 THEN t.Cost * t.DamagedQty ELSE 0 END) AS NetProfit
    FROM dbo.Trades AS t
    WHERE t.UserID = @UserID;
END;
GO

------------------------------------------------------------------------------------------------
-- Example Usage:
------------------------------------------------------------------------------------------------
-- 1) Register:
-- EXEC dbo.sp_RegisterUser @Name=N'Mehmet', @Email=N'mehmet@example.com', @Phone=N'05009998877',
--       @Username=N'mehmet', @Password=N'pwd123';

-- 2) Login:
-- EXEC dbo.sp_LoginUser @Username=N'mehmet', @Password=N'pwd123';

-- 3) Show My Info:
-- EXEC dbo.sp_ShowMyInfo @Username=N'mehmet', @Password=N'pwd123';

-- 4) Update My Info (e.g. change phone):
-- EXEC dbo.sp_UpdateMyInfo @Username=N'mehmet', @Password=N'pwd123', @NewPhone=N'05551234567';

-- 5) Delete My Account:
-- EXEC dbo.sp_DeleteMyAccount @Username=N'mehmet', @Password=N'pwd123';

-- 6) List All Users (requires key):
-- EXEC dbo.sp_ListAllUsers @AuthKey=N'135790';

-- 7) View Orders:
-- EXEC dbo.sp_ViewOrders @Username=N'mehmet', @Password=N'pwd123';

-- 8) Create Order:
-- EXEC dbo.sp_CreateOrder
--   @Username=N'mehmet', @Password=N'pwd123',
--   @ProductID=N'P001', @Type=N'Electronics', @Quantity=10,
--   @Price=100.00, @Cost=70.00, @IsDamaged=1, @DamagedQty=2, @ETADays=5;

-- 9) Update Order Status:
-- EXEC dbo.sp_UpdateOrderStatus @Username=N'mehmet', @Password=N'pwd123', @TradeID=1, @NewStatus=N'Shipped';

-- 10) Profit/Loss Summary:
-- EXEC dbo.sp_GetProfitLoss @Username=N'mehmet', @Password=N'pwd123';

GO