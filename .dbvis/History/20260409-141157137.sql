

SELECT * FROM orders WHERE state='confirmed' AND contractor_id in (SELECT id FROM contractors WHERE provider_type ='sd')
AND created_at < CURRENT_TIMESTAMP - interval '1 month'