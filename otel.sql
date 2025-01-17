-- UDF to calculate p95 value given an integer array
CREATE FUNCTION p95(x BIGINT ARRAY NOT NULL) RETURNS BIGINT;

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
CREATE MATERIALIZED VIEW metrics AS SELECT resource, scopeMetrics 
FROM otel_metrics, UNNEST(resourceMetrics) as t (resource, scopeMetrics);

-- (ResouceSpans[N]) -> (Resource, ScopeSpans[N])
CREATE MATERIALIZED VIEW traces AS SELECT resource, scopeSpans 
FROM otel_traces, UNNEST(resourceSpans) as t (resource, scopeSpans);

-- (ResouceLogs[N]) -> (Resource, ScopeLogs[N])
CREATE MATERIALIZED VIEW logs AS SELECT resource, scopeLogs 
FROM otel_logs, UNNEST(resourceLogs) as t (resource, scopeLogs);

-- (Combine all Resources together)
CREATE MATERIALIZED VIEW resources AS
SELECT resource 
FROM 
(SELECT resource FROM metrics) UNION 
(SELECT resource FROM traces) UNION
(SELECT resource FROM logs);

-- (Combine all Scopes together)
CREATE MATERIALIZED VIEW scopes AS
SELECT scope
FROM 
(SELECT s.scope FROM logs, UNNEST(logs.scopeLogs) as s) UNION
(SELECT s.scope FROM traces, UNNEST(traces.scopeSpans) as s) UNION
(SELECT s.scope FROM metrics, UNNEST(metrics.scopeMetrics) as s);

-- (Resource, ScopeSpans[N]) -> (_, ScopeSpans) x N
CREATE LOCAL VIEW spans_array AS
SELECT spans FROM traces, UNNEST(traces.scopeSpans) as t(_, spans);

-- (ScopeSpans[N]) -> (Span, elapsedTimeMillis, eventTime) x N
CREATE MATERIALIZED VIEW spans AS
SELECT 
    traceId,
    spanId,
    traceState,
    parentSpanId,
    flags,
    name,
    kind,
    startTimeUnixNano,
    endTimeUnixNano,
    attributes,
    events,
    ((endTimeUnixNano::BIGINT - startTimeUnixNano::BIGINT) / 1000000::BIGINT) as elapsedTimeMillis,
    TIMESTAMPADD(SECOND, startTimeUnixNano::BIGINT / 1000000000::BIGINT, DATE '1970-01-01') as eventTime
FROM spans_array, UNNEST(spans_array.spans) as span;

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


