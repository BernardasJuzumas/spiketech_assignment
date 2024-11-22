--EXPLAIN ANALYZE
-- This is a most optimized way I found to two random different widgets sharing the same open port slot
-- Query *may* not return results
-- The only other "issue" is that both widgets returned this way are pretty close to one another

SELECT a.widget1, w1.serial_number, a.widget2, w2.serial_number, a.slot
FROM 
	( 
		SELECT 
		    (array_agg(widget))[1] as widget1,
		    (array_agg(slot))[1] as slot,
			(array_agg(widget))[2] as widget2
		FROM (
		    SELECT DISTINCT ON (widget) widget, slot
		    FROM widgets.slots TABLESAMPLE SYSTEM(1)
		    WHERE association IS NULL
		    AND slot = (SELECT (enum_range(NULL::widgets.port_type))[floor(random() * array_length(enum_range(NULL::widgets.port_type), 1)) + 1])
		    LIMIT 2
		) subquery
	) AS a
LEFT JOIN widgets.widgets AS w1 ON a.widget1 = w1.id
LEFT JOIN widgets.widgets AS w2 ON a.widget2 = w2.id