
-- *** ADD_WIDGET ***

-- Add widget
SELECT widgets.add_widget('A', 'A name', ARRAY['P', 'P']);
-- Add another widget
SELECT widgets.add_widget('B', 'B name', ARRAY['P']);
-- Add same widget again (results in error)
SELECT widgets.add_widget('B', 'B name', ARRAY['P']);
-- Add same widget again, different name (results in error)
SELECT widgets.add_widget('B', 'C name', ARRAY['P']);
-- Add same widget again, different slot (results in error)
SELECT widgets.add_widget('B', 'C name', ARRAY['R']);
-- Add widget with a wrong port (results in error)
SELECT widgets.add_widget('C', 'C name', ARRAY['Z']);
-- Add widget with too many ports (results in error)
SELECT widgets.add_widget('C', 'C name', ARRAY['P','P','P','P']);
-- Add widget with all port types
SELECT widgets.add_widget('C', 'C name', ARRAY['P','R','Q']);
-- Add another widget with all port types
SELECT widgets.add_widget('D', 'D name', ARRAY['P','R','Q']);
-- Add widget with same ports as A
SELECT widgets.add_widget('E', 'E name', ARRAY['P', 'P']);
SELECT widgets.add_widget('F', 'F name', ARRAY['P', 'P']);

-- *** ASSOCIATE_WIDGETS ***

-- Associate same widget (results in error)
SELECT widgets.associate_widgets('A', 'A', 'P');
-- Associate different widgets
SELECT widgets.associate_widgets('A', 'B', 'P');
-- Associate widgets when widget (B) has no slot (results in error)
SELECT widgets.associate_widgets('C', 'B', 'P');
-- Associate widgets when widget (A) does't have a slot of given correct type (error)
SELECT widgets.associate_widgets('C', 'A', 'R');
-- Associate 2 widgets on 2 diferent ports
SELECT widgets.associate_widgets('C', 'D', 'R');
SELECT widgets.associate_widgets('C', 'D', 'Q');
-- Associate 2 widgets that have 2 slots each on the same port
SELECT widgets.associate_widgets('E', 'F', 'P');
-- Attempt to associate again (should result in error)
SELECT widgets.associate_widgets('E', 'F', 'P');

-- *** REMOVE_ASSOCIATION ***

-- Remove existing association
SELECT widgets.remove_association('E', 'F', 'P');
-- Remove not existing association
SELECT widgets.remove_association('E', 'F', 'P');
-- Remove association where widget does not exist
SELECT widgets.remove_association('Z', 'F', 'P');
-- Remove association where it does not exist on given port
SELECT widgets.remove_association('E', 'F', 'R');

-- *** REMOVE_WIDGET ***

-- Remove widget with no existing serial number
SELECT widgets.remove_widget('Z');
-- Remove widget with no existing associations
SELECT widgets.remove_widget('A');
-- Remove widget with several existing associations 
SELECT widgets.remove_widget('C');

-- ** QUERIES FOR TESTING **

SELECT widget, slot, association 
    FROM widgets.slots
    -- WHERE association IS NOT NULL
    ;
SELECT id, serial_number, name 
    FROM widgets.widgets
    -- WHERE id NOT IN (SELECT widget FROM widgets.slots WHERE association IS NOT NULL)
    ;
SELECT w.serial_number, s.slot, a.serial_number 
    FROM widgets.widgets w 
    LEFT JOIN widgets.slots s ON w.id = s.widget 
    LEFT JOIN widgets.widgets a ON s.association = a.id
    -- WHERE w.id NOT IN (SELECT widget FROM widgets.slots WHERE association IS NOT NULL)
    ;

