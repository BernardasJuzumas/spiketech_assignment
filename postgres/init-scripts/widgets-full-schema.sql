--------- SHEMA, TYPES, TABLES, INDEXES --------
CREATE SCHEMA IF NOT EXISTS widgets;

CREATE TYPE widgets.port_type AS ENUM
    ('P', 'R', 'Q');

CREATE TABLE widgets.widgets (
    id bigserial PRIMARY KEY,
    serial_number text UNIQUE NOT NULL,
    name text NOT NULL
);

CREATE TABLE widgets.slots (
    widget bigint NOT NULL REFERENCES widgets.widgets(id) ON DELETE CASCADE,
    slot widgets.port_type NOT NULL,
    association bigint REFERENCES widgets.widgets(id) ON DELETE SET NULL
    CONSTRAINT constrain_self_reference CHECK (widget <> association)
);

--Adding constraint with partial index to only allow duplicate set values if association value is not NULL
CREATE UNIQUE INDEX idx_unique_widget_slot_assoc_except_null_assoc
ON widgets.slots(widget, slot, association) WHERE association IS NOT NULL;


-- We still need o index the whole set for fast selects. Since this will be a B-Tree this index will be relatively small
CREATE INDEX idx_slots_widget_slot_assoc ON widgets.slots(widget, slot, association);

-- Another index on widgets table's serial_nuber to help with fast select. 
-- Since the serial_number is value is TEXT this index will probably become quite large (~1.6 GB).
-- Add recommendation to define serial number constraints to make the index smallet.
CREATE INDEX idx_widgets_serial_number ON widgets.widgets(serial_number);



--------- FUNCTIONS --------

-- Adds a widget and creates relevant ports, and returns success message or throws error if duplicate entry exists. 
-- Expects widgets serial number and name as text value, and a list of supported ports as an array.
CREATE OR REPLACE FUNCTION widgets.add_widget(
    widget_sn text,
    widget_name text,
    slots text[]
) RETURNS void 
SECURITY DEFINER -- this function will always be ran with admin (user that defined it).
AS $$
DECLARE
    new_widget_id bigint;
	slot widgets.port_type;
	casted_slots widgets.port_type[];
BEGIN
    -- Cast slots to widgets.port_type[] and assign to casted_slots
    casted_slots := ARRAY(SELECT unnest(slots)::widgets.port_type);

	-- Count of casted_slots and break if >3
	IF array_length(casted_slots, 1) > 3 THEN
        RAISE EXCEPTION 'Cannot add widget: too many slots (maximum is 3)';
    END IF;
	
	-- Insert the widget and retrieve the newly generated ID
    INSERT INTO widgets.widgets(serial_number, name)
    VALUES (widget_sn, widget_name)
    RETURNING id INTO new_widget_id;

    -- Iterate over the slots array and insert each slot
    FOREACH slot IN ARRAY casted_slots LOOP
            INSERT INTO widgets.slots(widget, slot)
            VALUES (new_widget_id, slot);
    END LOOP;

    RAISE NOTICE 'Widget with serial number % and name % added successfully', widget_sn, widget_name;
END;
$$ LANGUAGE plpgsql;



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

-- Removes association between widgets. Ensures that both widgets exist, that association exists and then removes it.
CREATE OR REPLACE FUNCTION widgets.remove_association(
    widget1_sn text,
    widget2_sn text,
    port widgets.port_type
) RETURNS void 
SECURITY DEFINER -- this function will always be ran with admin (user that defined it).
AS $$
DECLARE
    widget1_id bigint;
    widget2_id bigint;
	assoc bigint;
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

	 SELECT widget INTO assoc 
	 	FROM widgets.slots 
		WHERE widget = widget1_id 
		AND association = widget2_id 
		AND slot = port;

    -- Validate associations
    IF assoc IS NULL THEN
        RAISE EXCEPTION 'Widgets with serial numbers % and % are not associated on port %', widget1_sn, widget2_sn, port;
    END IF;

	UPDATE widgets.slots
		SET association = NULL
		WHERE widget = widget1_id 
		AND association = widget2_id 
		AND slot = port;

	UPDATE widgets.slots
		SET association = NULL
		WHERE widget = widget2_id 
		AND association = widget1_id 
		AND slot = port;

    RAISE NOTICE 'Widgets with serial numbers % and % have been disassociated on port %', widget1_sn, widget2_sn, port;
END;
$$ LANGUAGE plpgsql;


-- Deletes a widget of a given serial number.
CREATE OR REPLACE FUNCTION widgets.remove_widget(
    widget_sn text
) RETURNS void 
SECURITY DEFINER -- this function will always be ran with admin (user that defined it).
AS $$
BEGIN
    DELETE FROM widgets.widgets
    WHERE serial_number = widget_sn;

    RAISE NOTICE 'Widget % removed successfully', widget_sn;
END;
$$ LANGUAGE plpgsql;

--------- ROLES --------

create role web_anon nologin;

create role authenticator noinherit login password 'mysecretpassword';
grant web_anon to authenticator;

grant usage on schema widgets to web_anon;

grant execute on function widgets.add_widget(text, text, text[]) to web_anon;
grant execute on function widgets.associate_widgets(text, text, widgets.port_type) to web_anon;
grant execute on function widgets.remove_association(text, text, widgets.port_type) to web_anon;
grant execute on function widgets.remove_widget(text) to web_anon;