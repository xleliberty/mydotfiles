SELECT id FROM contractors WHERE provider_type ='sd'


SELECT count(*) FROM orders WHERE state='confirmed' AND contractor_id in (SELECT id FROM contractors WHERE provider_type ='sd')
AND created_at > '2025-10-01' AND purchase_type='consumption'

SELECT count(*), delivery_mode FROM orders WHERE state='confirmed' AND contractor_id in (SELECT id FROM contractors WHERE provider_type ='sd')
and salesplatform = 'website' AND purchase_type in ('firstpurchase','both') AND pickupsite_id is null
AND created_at > '2025-10-01'
GROUP BY 2


SELECT count(*)  FROM orders WHERE state='confirmed' AND contractor_id in (SELECT id FROM contractors WHERE provider_type ='sd')
and salesplatform in( 'api', 'website') AND purchase_type in ('both', 'firstpurchase')
AND delivery_mode in ('pickup', 'kiosk')
AND created_at > '2025-10-01'
GROUP BY 2


SELECT count(*), salesplatform FROM orders WHERE state='confirmed' AND contractor_id in (SELECT id FROM contractors WHERE provider_type ='sd')
AND created_at > '2025-10-01'
GROUP BY 2

