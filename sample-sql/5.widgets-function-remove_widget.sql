-- Deletes a widget of a given serial number.
CREATE OR REPLACE FUNCTION widgets.remove_widget(
    widget_sn text
) RETURNS void 
SECURITY DEFINER -- this function will always be ran with admin (user that defined it).
AS $$
BEGIN
    DELETE FROM widgets.widgets
    WHERE serial_number = widget_sn;

    RAISE NOTICE 'Widget % removed successfully', widget_sn;
END;
$$ LANGUAGE plpgsql;
