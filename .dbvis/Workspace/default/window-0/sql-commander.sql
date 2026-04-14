SELECT w.shortname as webinstance_short, ws.server_name  FROM websites ws JOIN webinstances w on (w.id=ws.webinstance_id)
WHERE ws.active =true AND w.active=true



SELECT 
    DISTINCT substring(ws.server_name from '([^.]+\.[^.]+)$') as domain_name
FROM websites ws 
JOIN webinstances w on (w.id = ws.webinstance_id)
WHERE ws.active = true AND w.active = true
ORDER BY domain_name

SELECT * FROM webinstances

SELECT count(*) FROM orders WHERE webinstance_id in (
29,287,1992) AND state='confirmed' AND completed_at > '2025-10-01 00:00:00'



SELECT count(*) FROM users WHERE webinstance_id in (
29,287,1992) AND state='confirmed' AND completed_at > '2025-10-01 00:00:00'



SELECT * FROM orders WHERE state='confirmed' AND completed_at > '2026-04-10 09:00:00'
AND transfer_state='init' and webinstance_id=837