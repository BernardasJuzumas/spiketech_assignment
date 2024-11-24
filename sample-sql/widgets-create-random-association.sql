DO $$
DECLARE
    rec RECORD;
    i INT;
	unique_violations INT;
BEGIN
	SET client_min_messages TO WARNING; -- do not cache notices in transactions memory
	unique_violations := 0;
    FOR i IN 1..10000 LOOP
        FOR rec IN
            SELECT serial_number1, serial_number2, port
            FROM widgets.get_random_association()
        LOOP
            BEGIN
                -- Perform the operation
                PERFORM widgets.associate_widgets(rec.serial_number1, rec.serial_number2, rec.port);
            		EXCEPTION 
                		WHEN unique_violation THEN
                   		 -- Handle the unique violation and continue
							unique_violations = unique_violations + 1;
                    		RAISE NOTICE 'Unique violation occurred, continuing...';
            			END;
        		END LOOP;
    END LOOP;
	SET client_min_messages TO NOTICE;
	RAISE NOTICE 'Unique violations: %', unique_violations;
END;
$$;
