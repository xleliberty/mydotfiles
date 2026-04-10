
SELECT count(*), salesplatform FROM orders WHERE state='confirmed' AND contractor_id in (SELECT id FROM contractors WHERE provider_type ='sd')
AND created_at > '2025-12-01'