

SELECT count(*)  FROM orders WHERE state='confirmed' AND contractor_id in (SELECT id FROM contractors WHERE provider_type ='sd')
and salesplatform in( 'api', 'website') AND purchase_type in ('both', 'firstpurchase')
AND delivery_mode in ('pickup', 'kiosk')
AND created_at > '2025-10-01'