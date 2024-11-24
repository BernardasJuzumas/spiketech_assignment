DROP FUNCTION IF EXISTS widgets.get_random_association(widgets.port_type);
CREATE FUNCTION widgets.get_random_association(port widgets.port_type) RETURNS TABLE(serial_number1 text, serial_number2 text) AS $$
BEGIN
	RETURN QUERY
		SELECT w1.serial_number AS serial_number1, w2.serial_number AS serial_number2
		FROM 
			( 
				SELECT 
				    (array_agg(widget))[1] as widget1,
					(array_agg(widget))[2] as widget2
				FROM (
				    SELECT DISTINCT widget
				    FROM widgets.slots TABLESAMPLE SYSTEM(1)
				    WHERE association IS NULL
				    AND slot = port
				    LIMIT 2
				) subquery
			) AS a
		LEFT JOIN widgets.widgets AS w1 ON a.widget1 = w1.id
		LEFT JOIN widgets.widgets AS w2 ON a.widget2 = w2.id;
END;
$$ LANGUAGE plpgsql;
