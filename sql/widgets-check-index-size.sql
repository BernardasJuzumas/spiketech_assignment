SELECT 
	pg_size_pretty(pg_indexes_size('widgets.widgets')) AS widgets
	, pg_size_pretty(pg_indexes_size('widgets.slots')) AS slots
	;