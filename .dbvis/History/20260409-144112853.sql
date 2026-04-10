SELECT count(*)  FROM orders WHERE state='confirmed' AND contractor_id in (SELECT id FROM contractors WHERE provider_type ='sd')
and salesplatform in( 'touch') AND purchase_type in ('both', 'firstpurchase')
AND created_at > '2025-10-01'