WITH RECURSIVE 
-- First get all unique widgets


widget_associations AS (
	SELECT widget,
	    associations
	   FROM ( SELECT slots.widget,
	            array_agg(slots.association) AS associations
	           FROM widgets.slots
	WHERE slots.association IS NOT NULL
	GROUP BY slots.widget)

),

-- Find connected components
connected_components AS (
    -- Start with the first widget in each component
    SELECT 
        widget as start_widget,
        widget as current_widget,
        ARRAY[widget] as path
    FROM widget_associations

    UNION ALL

    -- Recursively find connected widgets
    SELECT 
        cc.start_widget,
        w2.widget,
        cc.path || w2.widget
    FROM connected_components cc
    JOIN widget_associations w1 ON w1.widget = cc.current_widget
    JOIN widget_associations w2 ON w2.widget = ANY(w1.associations)
    WHERE w2.widget <> ALL(cc.path)
),

-- Get the minimum widget ID in each component to uniquely identify groups
group_ids AS (
    SELECT 
        current_widget,
        min(start_widget) OVER (PARTITION BY current_widget) as group_id
    FROM connected_components
)

-- Final results
SELECT 
    group_id,
    array_agg(DISTINCT gi.current_widget ORDER BY gi.current_widget) as group_members,
    count(DISTINCT gi.current_widget) as group_size
FROM group_ids gi
GROUP BY group_id
ORDER BY group_size DESC
;