CREATE FUNCTION widgets.generate_random_widget(
    widget_sn_prefix text,
    widget_name_prefix text
) RETURNS void AS $$
DECLARE
    random_slot_count int;
    random_slots text[];
    random_port widgets.port_type;
    i int;
BEGIN
    -- Step 1: Generate a random slot count between 0 and 3
    random_slot_count := floor(random() * 4)::int;

    -- Step 2: Initialize an empty array to hold the random slots
    random_slots := ARRAY[]::text[];

    -- Step 3: Loop to generate random ports up to random_slot_count
    FOR i IN 1..random_slot_count LOOP
        -- Select a random port type from the set {'P', 'R', 'Q'}
        SELECT (array['P', 'R', 'Q'])[floor(random() * 3 + 1)::int] INTO random_port;
        random_slots := array_append(random_slots, random_port::text);
    END LOOP;

    -- Step 4: Create a unique serial number and widget name
    PERFORM widgets.add_widget(
        widget_sn_prefix || floor(random() * 100000)::text,
        widget_name_prefix || floor(random() * 100)::text,
        random_slots
    );
END;
$$ LANGUAGE plpgsql;
