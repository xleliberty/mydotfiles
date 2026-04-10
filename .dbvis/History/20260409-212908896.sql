
SELECT 
    w.shortname as webinstance_short, 
    DISTINCT substring(ws.server_name from '([^.]+\.[^.]+)$') as domain_name
FROM websites ws 
JOIN webinstances w on (w.id = ws.webinstance_id)
WHERE ws.active = true AND w.active = true
ORDER BY domain_name