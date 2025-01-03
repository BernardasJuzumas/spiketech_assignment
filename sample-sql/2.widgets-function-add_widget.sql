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

