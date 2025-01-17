-- UDF to calculate p95 value given an integer array
CREATE FUNCTION p95(x BIGINT ARRAY NOT NULL) RETURNS BIGINT;

CREATE FUNCTION NANOS_TO_SECONDS(NANOS BIGINT) RETURNS BIGINT AS
(NANOS / 1000000000::BIGINT);

CREATE FUNCTION NANOS_TO_MILLIS(NANOS BIGINT) RETURNS BIGINT AS
(NANOS / 1000000::BIGINT);

CREATE FUNCTION MAKE_TIMESTAMP_FROM_NANOS(NANOS BIGINT) RETURNS TIMESTAMP AS
TIMESTAMPADD(SECOND, NANOS_TO_SECONDS(NANOS), DATE '1970-01-01');

CREATE TYPE KeyValue AS (
    key VARCHAR,
    value VARIANT
);

CREATE TYPE Event AS (
    timeUnixNano VARCHAR,
    name VARCHAR,
    attributes KeyValue ARRAY
);

CREATE TYPE Span AS (
    traceId VARCHAR,
    spanId VARCHAR,
    traceState VARCHAR,
    parentSpanId VARCHAR,
    flags BIGINT,
    name VARCHAR,
    kind INT,
    startTimeUnixNano VARCHAR,
    endTimeUnixNano VARCHAR,
    attributes KeyValue ARRAY,
    events Event ARRAY
);

CREATE TYPE Metric AS (
    name VARCHAR,
    description VARCHAR,
    unit VARCHAR,
    data VARIANT,
    metadata KeyValue ARRAY
);

CREATE TYPE LogRecords AS (
    attributes KeyValue ARRAY,
    timeUnixNano VARCHAR,
    observedTimeUnixNano VARCHAR,
    severityNumber INT,
    severityText VARCHAR,
    flags INT4,
    traceId VARCHAR,
    spanId VARCHAR,
    eventName VARCHAR,
    body VARIANT
);

CREATE TYPE Scope AS (
    name VARCHAR,
    version VARCHAR,
    attributes KeyValue ARRAY
);

CREATE TYPE ScopeSpans AS (
    scope Scope,
    spans Span ARRAY
);

CREATE TYPE ScopeLogs AS (
    scope Scope,
    logRecords LogRecords ARRAY
);

CREATE TYPE ScopeMetrics AS (
    scope Scope,
    metrics Metric ARRAY
);

CREATE TYPE Resource AS (
    attributes KeyValue ARRAY
);

CREATE TYPE ResourceMetrics AS (
    resource Resource,
    scopeMetrics ScopeMetrics ARRAY
);

CREATE TYPE ResourceSpans AS (
    resource Resource,
    scopeSpans ScopeSpans ARRAY
);

CREATE TYPE ResourceLogs AS (
    resource Resource,
    scopeLogs ScopeLogs ARRAY
);

-- Input table that ingests resource spans from the collector.
CREATE TABLE otel_traces (
    resourceSpans ResourceSpans ARRAY
) WITH ('append_only' = 'true');

-- Input table that ingests resource logs from the collector.
CREATE TABLE otel_logs (
    resourceLogs ResourceLogs ARRAY
) WITH ('append_only' = 'true');

-- Input table that ingests resource metrics from the collector.
CREATE TABLE otel_metrics (
    resourceMetrics ResourceMetrics ARRAY
) WITH ('append_only' = 'true');

-- (ResouceMetrics[N]) -> (Resource, ScopeMetrics[N])
CREATE LOCAL VIEW rsMetrics AS SELECT resource, scopeMetrics 
FROM otel_metrics, UNNEST(resourceMetrics) as t (resource, scopeMetrics);

-- (ResouceSpans[N]) -> (Resource, ScopeSpans[N])
CREATE LOCAL VIEW rsSpans AS SELECT resource, scopeSpans 
FROM otel_traces, UNNEST(resourceSpans) as t (resource, scopeSpans);

-- (ResouceLogs[N]) -> (Resource, ScopeLogs[N])
CREATE LOCAL VIEW rsLogs AS SELECT resource, scopeLogs 
FROM otel_logs, UNNEST(resourceLogs) as t (resource, scopeLogs);

-- (Resource, ScopeMetrics[N]) -> (_, ScopeMetrics) x N
CREATE LOCAL VIEW metrics_array AS
SELECT metrics From rsMetrics, UNNEST(rsMetrics.scopeMetrics) as t(_, metrics);

-- (ScopeMetrics[N]) -> (_, Metric) x N
CREATE MATERIALIZED VIEW metrics AS
SELECT
    name,
    description,
    unit,
    data,
    metadata
FROM metrics_array, UNNEST(metrics_array.metrics);

-- (Resource, ScopeLogs[N]) -> (_, ScopeLogs) x N
CREATE LOCAL VIEW logs_array AS
SELECT logs FROM rsLogs, UNNEST(rsLogs.scopeLogs) as t(_, logs);

-- (ScopeLogs[N]) -> (_, Logs) x N
CREATE MATERIALIZED VIEW logs AS
SELECT
    attributes,
    timeUnixNano,
    observedTimeUnixNano,
    severityNumber,
    severityText,
    flags,
    traceId,
    spanId,
    eventName,
    body
FROM logs_array, UNNEST(logs_array.logs);

-- (Resource, ScopeSpans[N]) -> (_, ScopeSpans) x N
CREATE LOCAL VIEW spans_array AS
SELECT spans FROM rsSpans, UNNEST(rsSpans.scopeSpans) as t(_, spans);

-- (ScopeSpans[N]) -> (Span, elapsedTimeMillis, eventTime) x N
CREATE MATERIALIZED VIEW spans AS
SELECT 
    traceId,
    spanId,
    tracestate,
    parentSpanId,
    flags,
    name,
    kind,
    startTimeUnixNano,
    endTimeUnixNano,
    attributes,
    events,
    ((endTimeUnixNano::BIGINT - startTimeUnixNano::BIGINT) / 1000000::BIGINT) as elapsedTimeMillis,
    MAKE_TIMESTAMP_FROM_NANOS(startTimeUnixNano) as eventTime
FROM spans_array, UNNEST(spans_array.spans);

-- (Combine all Resources together)
CREATE LOCAL VIEW resources AS
SELECT resource 
FROM 
(SELECT resource FROM rsMetrics) UNION 
(SELECT resource FROM rsSpans) UNION
(SELECT resource FROM rsLogs);

-- (Combine all Scopes together)
CREATE LOCAL VIEW scopes AS
SELECT scope
FROM 
(SELECT s.scope FROM rsLogs, UNNEST(rsLogs.scopeLogs) as s) UNION
(SELECT s.scope FROM rsSpans, UNNEST(rsSpans.scopeSpans) as s) UNION
(SELECT s.scope FROM rsMetrics, UNNEST(rsMetrics.scopeMetrics) as s);

-- Calculate the p95 latency in milliseconds over a tumbling window of 30 seconds
CREATE MATERIALIZED VIEW p95_latency AS
SELECT
elapsedTimeMillis as latencyMs,
TUMBLE_START(
    eventTime,
    INTERVAL '30' SECONDS
) as tumble_start_time
FROM spans
GROUP BY
TUMBLE(
    eventTime,
    INTERVAL '30' SECONDS
), elapsedTimeMillis;

-- Calculate the number of requests over a tumbling window of 1 minute
CREATE MATERIALIZED VIEW requests AS
SELECT
COUNT(*) as count,
TUMBLE_START(
    eventTime,
    INTERVAL '1' MINUTE
) as tumble_start_time
FROM spans
WHERE spans.parentSpanId = ''
GROUP BY
TUMBLE(
    eventTime,
    INTERVAL '1' MINUTE
);

-- Calculate the throughput over a tumbling window of 1 minute
-- Throughput = Number of total root level spans
CREATE MATERIALIZED VIEW throughput AS
SELECT
COUNT(*) as throughput,
TUMBLE_START(
    eventTime,
    INTERVAL '1' MINUTE
) as tumble_start_time
FROM spans
WHERE spans.parentSpanId = ''
GROUP BY
TUMBLE(
    eventTime,
    INTERVAL '1' MINUTE
);

-- CREATE MATERIALIZED VIEW resource_attribute_keys AS
-- SELECT DISTINCT key
-- FROM resources, UNNEST(resources.resource.attributes) as t (key, _);

-- Unsure about this as I get no SEVERE records
CREATE MATERIALIZED VIEW error_impact AS
SELECT
    t.traceId,
    t.spanId,
    l.severityText AS log_severity,
    l.body AS error_message,
    t.name AS span_name,
    t.elapsedTimeMillis AS span_duration,
    t.eventTime AS span_start_time
FROM spans t
JOIN logs l
ON t.traceId = l.traceId AND t.spanId = l.spanId
WHERE l.severityNumber < 4;

CREATE MATERIALIZED VIEW request_lifecycle AS
SELECT
    t.traceId,
    t.spanId,
    t.name AS span_name,
    NANOS_TO_MILLIS(t.startTimeUnixNano) AS spanStartTime,
    NANOS_TO_MILLIS(t.endTimeUnixNano) AS spanEndTime,
    e.name AS event_name,
    MAKE_TIMESTAMP_FROM_NANOS(e.timeUnixNano) AS eventTime,
    l.body AS logMessage
FROM spans t, UNNEST(t.events) AS e
LEFT JOIN logs l
ON t.traceId = l.traceId AND t.spanId = l.spanId
WHERE t.parentSpanId = '';

-- slowest top 5 traces
CREATE MATERIALIZED VIEW slowest_traces AS
SELECT
    t.traceId,
    t.spanId,
    t.parentSpanId,
    t.name AS span_name,
    t.eventTime,
    t.elapsedTimeMillis
FROM (SELECT t.*, row_number() OVER (ORDER BY elapsedTimeMillis DESC) rn FROM spans t) t
WHERE rn < 6;

-- slowest top 5 requests
CREATE MATERIALIZED VIEW slowest_requests AS
SELECT
    t.traceId,
    t.spanId,
    t.name AS span_name,
    t.eventTime,
    t.elapsedTimeMillis
FROM (SELECT t.*, row_number() OVER (ORDER BY elapsedTimeMillis DESC) rn FROM spans t WHERE t.parentSpanId = '') t
WHERE rn < 6;

CREATE MATERIALIZED VIEW alert_high_latency AS
SELECT
    traceId,
    spanId,
    name AS span_name,
    elapsedTimeMillis AS latency,
    eventTime
FROM spans
WHERE elapsedTimeMillis > 5000;


