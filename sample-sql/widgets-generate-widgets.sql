DO $$
DECLARE
    i INT;
BEGIN
	SET client_min_messages TO WARNING; -- do not cache notices in transactions memory
    FOR i IN 1..10000000 LOOP
        PERFORM widgets.generate_random_widget(
            CONCAT(SUBSTRING(MD5(RANDOM()::TEXT), 1, 20), i::TEXT),
            CONCAT(SUBSTRING(MD5(RANDOM()::TEXT), 1, 20), i::TEXT)
        );
        -- Commit after every execution makes every itteration write to database
        COMMIT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ### There is a faster way to do this, but the above approach with commits illustrates 
-- ### the real performance, when every performed transaction is immediately commited to the database
-- ### In average 10x faster.
-- SET client_min_messages TO WARNING;

-- SELECT COUNT(*) 
-- FROM generate_series(1, 10000000) t
-- WHERE widgets.generate_random_widget(
--     CONCAT(SUBSTRING(MD5(RANDOM()::TEXT), 1, 20), t::TEXT),
--     CONCAT(SUBSTRING(MD5(RANDOM()::TEXT), 1, 20), t::TEXT)
-- ) IS NOT NULL;