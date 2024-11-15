CREATE SCHEMA IF NOT EXISTS widgets;

CREATE TYPE IF NOT EXISTS widgets.port_type AS ENUM
    ('P', 'R', 'Q');

CREATE TABLE widgets.widgets (
    id bigserial PRIMARY KEY,
    serial_number text UNIQUE NOT NULL,
    name text NOT NULL
);


CREATE TABLE widgets.slots (
    widget bigint NOT NULL REFERENCES widgets.widgets(id) ON DELETE CASCADE,
    slot widgets.port_type NOT NULL,
    association bigint REFERENCES widgets.widgets(id) ON DELETE SET NULL
    CONSTRAINT constrain_self_reference CHECK (widget <> association)
);


--Adding constraint with partial index to only allow duplicate set values if association value is not NULL
CREATE UNIQUE INDEX idx_unique_widget_slot_assoc_except_null_assoc
ON widgets.slots(widget, slot, association) WHERE association IS NOT NULL;


-- We still need o index the whole set for fast selects. Since this will be a B-Tree this index will be relatively small
CREATE INDEX idx_slots_widget_slot_assoc ON widgets.slots(widget, slot, association);

-- Another index on widgets table's serial_nuber to help with fast select. 
-- Since the serial_number is value is TEXT this index will probably become quite large (~1.6 GB).
-- Add recommendation to define serial number constraints to make the index smallet.
CREATE INDEX idx_widgets_serial_number ON widgets.widgets(serial_number);