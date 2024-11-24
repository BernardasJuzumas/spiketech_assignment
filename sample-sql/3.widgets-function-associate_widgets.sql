-- Performs widget association operation,
-- Checks that both referenced widgets exist, that both have an open port slot of the defined type and then associates both widgets by 
-- getting setting their id's in each others association field.
-- The complexity here is that because I am avoiding additional id index on slots table I had to use cursors to target and lock specific 
-- rows for update. 
-- Otherwise there is a possibility to update more than one row.
CREATE OR REPLACE FUNCTION widgets.associate_widgets(
    widget1_sn text,
    widget2_sn text,
    port widgets.port_type
) RETURNS void 
SECURITY DEFINER -- this function will always be ran with admin (user that defined it).
AS $$
DECLARE
    widget1_id bigint;
    widget2_id bigint;

	widget1_cursor CURSOR FOR 
						SELECT widget, association FROM widgets.slots
						WHERE widget = widget1_id 
						AND slot = port 
						AND association IS NULL
						LIMIT 1
						FOR UPDATE;
	widget2_cursor CURSOR FOR 
						SELECT widget, association FROM widgets.slots
						WHERE widget = widget2_id 
						AND slot = port 
						AND association IS NULL
						LIMIT 1
						FOR UPDATE;

    widget1_slot widgets.slots%ROWTYPE; -- To store composite row with slot for widget1
    widget2_slot widgets.slots%ROWTYPE; -- Same for widget2
BEGIN

	IF widget1_sn = widget2_sn THEN
		RAISE EXCEPTION 'Widgets cannot self-associate';
	END IF;
    -- Retrieve widget IDs based on the provided serial numbers
    SELECT id INTO widget1_id FROM widgets.widgets WHERE serial_number = widget1_sn;
    SELECT id INTO widget2_id FROM widgets.widgets WHERE serial_number = widget2_sn;

    -- Check that both widgets were found
    IF widget1_id IS NULL THEN
        RAISE EXCEPTION 'Widget with serial number % does not exist', widget1_sn;
    END IF;

    IF widget2_id IS NULL THEN
        RAISE EXCEPTION 'Widget with serial number % does not exist', widget2_sn;
    END IF;

	-- Set cursor and lock rows with available slots
	OPEN widget1_cursor;
	OPEN widget2_cursor;
	
	FETCH widget1_cursor INTO widget1_slot;
	FETCH widget2_cursor INTO widget2_slot;

	IF widget1_slot.widget IS NULL THEN
		RAISE EXCEPTION 'Widget with serial number % does not not have available slots on port %', widget1_sn, port;
	END IF;

	IF widget2_slot.widget IS NULL THEN
		RAISE EXCEPTION 'Widget with serial number % does not not have available slots on port %', widget2_sn, port;
	END IF;
	
	-- Set slot values at the cursor pointer
	UPDATE widgets.slots
	SET association = widget2_id
	WHERE CURRENT OF widget1_cursor;

	UPDATE widgets.slots
	SET association = widget1_id
	WHERE CURRENT OF widget2_cursor;
	
	-- Close cursors
	CLOSE widget1_cursor;
	CLOSE widget2_cursor;

	RAISE NOTICE 'Widgets % and % have been associated on port %', widget1_sn, widget2_sn, port;
END;
$$ LANGUAGE plpgsql;