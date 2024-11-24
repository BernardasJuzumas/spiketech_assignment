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

	IF widget1_sn = widget2_sn
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
