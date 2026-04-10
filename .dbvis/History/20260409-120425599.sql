SELECT w.shortname as webinstance_short, ws.server_name  FROM websites ws JOIN webinstances w on (w.id=ws.webinstance_id)
WHERE ws.active =true AND w.active=true
