DROP FUNCTION IF EXISTS widgets.get_random_association();
CREATE FUNCTION widgets.get_random_association() RETURNS TABLE(serial_number1 text, serial_number2 text, port widgets.port_type) AS $$
BEGIN
	RETURN QUERY
		SELECT w1.serial_number AS serial_number1, w2.serial_number AS serial_number2, a.slot AS port
		FROM 
			( 
				SELECT 
				    (array_agg(widget))[1] as widget1,
					(array_agg(widget))[2] as widget2,
				    (array_agg(slot))[1] as slot
				FROM (
				    SELECT DISTINCT ON (widget) widget, slot
				    FROM widgets.slots TABLESAMPLE SYSTEM(1)
				    WHERE association IS NULL
				    AND slot = (SELECT (enum_range(NULL::widgets.port_type))[floor(random() * array_length(enum_range(NULL::widgets.port_type), 1)) + 1])
				    LIMIT 2
				) subquery
			) AS a
		LEFT JOIN widgets.widgets AS w1 ON a.widget1 = w1.id
		LEFT JOIN widgets.widgets AS w2 ON a.widget2 = w2.id;
END;
$$ LANGUAGE plpgsql;
