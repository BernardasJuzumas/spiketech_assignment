DROP FUNCTION IF EXISTS widgets.get_random_association(widget_sn text);
CREATE FUNCTION widgets.get_random_association(widget_sn text) 
RETURNS TABLE(serial_number text, port widgets.port_type)
AS $$
BEGIN
	RETURN QUERY
		SELECT ww.serial_number, ss.slot AS port FROM widgets.widgets AS ww TABLESAMPLE SYSTEM(1)
			LEFT JOIN widgets.slots AS ss ON ss.widget = ww.id
			WHERE ww.serial_number <> widget_sn
			AND ss.slot IN (
				-- get slots on widget_sn
				SELECT s.slot FROM widgets.slots AS s 
				LEFT JOIN widgets.widgets AS w ON s.widget = w.id
				WHERE w.serial_number = widget_sn
				)
		LIMIT 1;
END;
$$ LANGUAGE plpgsql;
