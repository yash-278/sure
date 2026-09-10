# Railway web sleep

On Linux, set `WEB_SERVERLESS=true` on the web service only and enable Railway
Serverless. Redeploy to apply both settings. Leave the worker running normally.

This selects a Redis driver with a 900-second TCP idle keepalive interval instead
of RedisClient's 15 seconds. Command timeouts, retries and TCP keepalive remain
enabled. The default driver is unchanged when the flag is absent.

Redis also sends keepalive probes. Configure its `tcp-keepalive` to 900 seconds
in its persistent startup configuration, otherwise its default 300-second probes
can keep the web service awake. This does not change the worker client's own
15-second probes. No Redis data or queue configuration needs to change.

Close Sure browser tabs before testing: live Action Cable connections and actual
requests should keep the service awake. External scanners can also wake it;
filter unwanted traffic at the edge, before it reaches Rails, if necessary.

Verify Railway network flows become idle, wait for its sleeping state, and then
check a real request, cache access and job enqueueing after wake-up. The first
request can be slow or receive a temporary gateway error.

To roll back, unset `WEB_SERVERLESS`, disable Serverless and redeploy web. Restore
Redis's `tcp-keepalive` to its previous value if no other service needs the longer
idle interval.
