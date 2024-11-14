-- Deletes a widget of a given serial number.
CREATE OR REPLACE FUNCTION widgets.remove_widget(
    widget_sn text
) RETURNS TEXT 
SECURITY DEFINER -- this function will always be ran with admin (user that defined it).
AS $$
BEGIN
    DELETE FROM widgets.widgets
    WHERE serial_number = widget_sn;

    RETURN 'Widget removed successfully';
END;
$$ LANGUAGE plpgsql;
