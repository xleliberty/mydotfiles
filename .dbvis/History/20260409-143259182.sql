
SELECT count(*), delivery_mode FROM orders WHERE state='confirmed' AND contractor_id in (SELECT id FROM contractors WHERE provider_type ='sd')
and salesplatform = 'website' AND purchase_type in ('firstpurchase','both') AND pickupsite_id is null
AND created_at > '2025-10-01'
GROUP BY 2
