GO
IF OBJECT_ID('dbo.GetCatalog') IS NOT NULL
BEGIN
	DROP FUNCTION dbo.GetCatalog;
END

GO
CREATE FUNCTION [dbo].[GetCatalog]()
RETURNS nvarchar(max)
AS
BEGIN
	RETURN 'CATALOG_NAME'
END

GO
IF OBJECT_ID('SpCreateTableLog') IS NOT NULL
BEGIN
	DROP PROCEDURE SpCreateTableLog;
END

GO
CREATE PROCEDURE SpCreateTableLog 
	@TableName NVARCHAR(MAX)
AS
BEGIN
	DECLARE @Catalog NVARCHAR(MAX);
	SET @Catalog = dbo.GetCatalog();
	DECLARE @CreateSQL NVARCHAR(MAX);
	DECLARE @TriggerInsert NVARCHAR(MAX);
	DECLARE @TriggerUpdate NVARCHAR(MAX);
	DECLARE @TriggerDelete NVARCHAR(MAX);

	DECLARE @TableStructure table (column_name NVARCHAR(MAX));
	INSERT INTO @TableStructure 
		SELECT 
			COLUMN_NAME 
			+ ' ' 
			+ UPPER(
				CASE 
					WHEN DATA_TYPE = 'varchar' 
						THEN 
							CASE WHEN CHARACTER_MAXIMUM_LENGTH = -1 
								THEN 
									'varchar(MAX)'
								ELSE 
									'varchar(' + CAST(CHARACTER_MAXIMUM_LENGTH as NVARCHAR(MAX)) + ')'
								END
					WHEN DATA_TYPE = 'nvarchar' 
						THEN 
							CASE WHEN CHARACTER_MAXIMUM_LENGTH = -1 
								THEN 
									'nvarchar(MAX)'
								ELSE 
									'nvarchar(' + CAST(CHARACTER_MAXIMUM_LENGTH as NVARCHAR(MAX)) + ')'
								END
					WHEN DATA_TYPE = 'varbinary'
						THEN
							CASE WHEN CHARACTER_MAXIMUM_LENGTH = -1
								THEN
									'varbinary(MAX)'
								ELSE 
									'varbinary(' + CAST(CHARACTER_MAXIMUM_LENGTH as NVARCHAR(MAX)) + ')'
								END
					WHEN DATA_TYPE = 'binary'
						THEN
							CASE WHEN CHARACTER_MAXIMUM_LENGTH = -1
								THEN
									'binary(MAX)'
								ELSE 
									'binary(' + CAST(CHARACTER_MAXIMUM_LENGTH as NVARCHAR(MAX)) + ')'
								END
					WHEN DATA_TYPE = 'image' THEN 'image'
					WHEN DATA_TYPE = 'nchar' 
						THEN
							CASE WHEN CHARACTER_MAXIMUM_LENGTH = -1
								THEN
									'nchar(MAX)'
								ELSE 
									'nchar(' + CAST(CHARACTER_MAXIMUM_LENGTH as NVARCHAR(MAX)) + ')'
								END
					WHEN DATA_TYPE = 'numeric' THEN 'numeric(' + CAST(NUMERIC_PRECISION as NVARCHAR(MAX)) + ', ' + CAST(NUMERIC_SCALE as NVARCHAR(MAX)) + ')'
					WHEN DATA_TYPE = 'decimal' THEN 'decimal(' + CAST(NUMERIC_PRECISION as NVARCHAR(MAX)) + ', ' + CAST(NUMERIC_SCALE as NVARCHAR(MAX)) + ')'
					ELSE DATA_TYPE END
			) 
			+ ' DEFAULT NULL'
			as data_type
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE
			TABLE_NAME = @TableName
			AND TABLE_CATALOG = @Catalog
			;

	-- CLEAR TRIGGER
	SET @TriggerInsert = REPLACE('
		IF OBJECT_ID(''{TABLE_NAME}_TblLog_OnAfterInsert'') IS NOT NULL
		BEGIN
			DROP TRIGGER IF EXISTS {TABLE_NAME}_TblLog_OnAfterInsert;
		END', 
		'{TABLE_NAME}',
		@TableName
	);
	EXEC sp_executesql @TriggerInsert;

	SET @TriggerUpdate = REPLACE('
		IF OBJECT_ID(''{TABLE_NAME}_TblLog_OnAfterUpdate'') IS NOT NULL
		BEGIN
			DROP TRIGGER IF EXISTS {TABLE_NAME}_TblLog_OnAfterUpdate;
		END', 
		'{TABLE_NAME}',
		@TableName
	);
	EXEC sp_executesql @TriggerUpdate;

	SET @TriggerDelete = REPLACE('
		IF OBJECT_ID(''{TABLE_NAME}_TblLog_OnAfterDelete'') IS NOT NULL
		BEGIN
			DROP TRIGGER IF EXISTS {TABLE_NAME}_TblLog_OnAfterDelete;
		END', 
		'{TABLE_NAME}',
		@TableName
	);

	EXEC sp_executesql @TriggerDelete;


	-- CREATE TABLE LOG
	SET @CreateSQL = REPLACE('
					IF OBJECT_ID(''{TABLE_NAME}_TblLog'') IS NOT NULL 
					BEGIN 
						DROP TABLE {TABLE_NAME}_TblLog; 
					END
					', '{TABLE_NAME}', @TableName);
    
	EXEC sp_executesql @CreateSQL;
	SET @CreateSQL =	
						'CREATE TABLE ' 
						+ @TableName + '_TblLog (' 
						+ STUFF((SELECT ', ' + column_name FROM @TableStructure FOR XML PATH('')), 1, 2, '') 
						+ ', data_log_created_date DateTime NULL'
						+ ', data_log_action_type NVARCHAR(20) NULL'
						+ ')';
	EXEC sp_executesql @CreateSQL;

	-- ADD TRIGGER INSERT
	SET @TriggerInsert = 
		REPLACE('
				CREATE TRIGGER {TABLE_NAME}_TblLog_OnAfterInsert
				ON {TABLE_NAME}
				AFTER INSERT 
				AS
				BEGIN
					SET NOCOUNT ON;
					INSERT INTO {TABLE_NAME}_TblLog SELECT *, GETDATE(), ''INSERTED'' FROM inserted;
				END
			'
			,'{TABLE_NAME}'
			, @TableName
		);
	EXEC sp_executesql @TriggerInsert;

	-- ADD TRIGGER UPDATE
	SET @TriggerUpdate = 
		REPLACE('
				CREATE TRIGGER {TABLE_NAME}_TblLog_OnAfterUpdate
				ON {TABLE_NAME}
				AFTER UPDATE 
				AS
				BEGIN
					SET NOCOUNT ON;
					INSERT INTO {TABLE_NAME}_TblLog SELECT *, GETDATE(), ''UPDATE-OLD'' FROM deleted;
					INSERT INTO {TABLE_NAME}_TblLog SELECT *, GETDATE(), ''UPDATE-NEW'' FROM inserted;
				END
			'
			,'{TABLE_NAME}'
			, @TableName
		);
	EXEC sp_executesql @TriggerUpdate;

	-- ADD TRIGGER DELETE
	SET @TriggerDelete = 
		REPLACE('
				CREATE TRIGGER {TABLE_NAME}_TblLog_OnAfterDelete
				ON {TABLE_NAME}
				AFTER DELETE 
				AS
				BEGIN
					SET NOCOUNT ON;
					INSERT INTO {TABLE_NAME}_TblLog SELECT *, GETDATE(), ''DELETE'' FROM deleted;
				END
			'
			,'{TABLE_NAME}'
			, @TableName
		);
	EXEC sp_executesql @TriggerDelete;
END;