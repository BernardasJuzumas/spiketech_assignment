--EXPLAIN ANALYZE
-- This is a most optimized way I found to two random different widgets sharing the same open port slot
-- Query *may* not return results
-- The only other "issue" is that both widgets returned this way are pretty close to one another

SELECT a.widget1, w1.serial_number, a.widget2, w2.serial_number, a.slot
FROM 
-- the initial table where we find two matching widgets and a port
	( 
		SELECT 
		-- the idea here is to find two DISTINCT widgets on the same port, return them in two rows and then pick up
		-- the result from the table aggregate. Geneus, I know (sarcasm overload..).
		    (array_agg(widget))[1] as widget1,
		    (array_agg(slot))[1] as slot,
			(array_agg(widget))[2] as widget2
		FROM (
		-- widget is distinct, but we need the slot value too
		    SELECT DISTINCT ON (widget) widget, slot
			-- tablesample for semi-randomnes. Ordering by random is insane at this scale (testing with ~20M records)
		    FROM widgets.slots TABLESAMPLE SYSTEM(1)
		    WHERE association IS NULL
			-- random slot selector. Selecting 1 value from random_enum array. Yes this IS the shortest way.
		    AND slot = (SELECT (enum_range(NULL::widgets.port_type))[floor(random() * array_length(enum_range(NULL::widgets.port_type), 1)) + 1])
		    LIMIT 2
		) subquery
	) AS a
-- joins to add widget serial numbers (will use these later in function)
LEFT JOIN widgets.widgets AS w1 ON a.widget1 = w1.id
LEFT JOIN widgets.widgets AS w2 ON a.widget2 = w2.id

-- P.S. was hating pgAdmin until i found it has GODLIKE  Explain Analyze UI. Initally this query took 11s to complete. Now it takes 155ms.