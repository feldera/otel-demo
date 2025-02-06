CREATE TYPE KeyValue AS (
    key VARCHAR,
    value VARIANT
);

CREATE TYPE Event AS (
    timeUnixNano CHAR(20),
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
    startTimeUnixNano CHAR(20),
    endTimeUnixNano CHAR(20),
    attributes KeyValue ARRAY,
    events Event ARRAY
);

CREATE TYPE Metric AS (
    name VARCHAR,
    description VARCHAR,
    unit VARCHAR,
    sum VARIANT,
    gauge VARIANT,
    summary VARIANT,
    histogram VARIANT,
    exponentialHistogram VARIANT,
    metadata KeyValue ARRAY
);

CREATE TYPE LogRecords AS (
    attributes KeyValue ARRAY,
    timeUnixNano CHAR(20),
    observedTimeUnixNano CHAR(20),
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

-- (ScopeMetrics[N]) -> (ScopeMetrics) x N
CREATE LOCAL VIEW metrics_array AS
SELECT
    resource,
    scope,
    metrics
FROM rsMetrics, UNNEST(rsMetrics.scopeMetrics) as t(scope, metrics);

-- (ScopeLogs[N]) -> (ScopeLogs) x N
CREATE LOCAL VIEW logs_array AS
SELECT 
    resource,
    scope,
    logs 
FROM rsLogs, UNNEST(rsLogs.scopeLogs) as t(scope, logs);

-- (ScopeSpans[N]) -> (ScopeSpans) x N
CREATE LOCAL VIEW spans_array AS
SELECT 
    resource,
    scope,
    spans
FROM rsSpans, UNNEST(rsSpans.scopeSpans) as t(scope, spans); 

-- (Metrics[N]) -> (_, Metric) x N
CREATE MATERIALIZED VIEW metrics AS
SELECT
    name,
    description,
    unit,
    sum,
    summary,
    gauge,
    histogram,
    exponentialHistogram,
    resource,
    scope,
    metadata
FROM metrics_array, UNNEST(metrics_array.metrics);

-- (Logs[N]) -> (_, Logs) x N
CREATE MATERIALIZED VIEW logs AS
SELECT
    resource,
    scope,
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

-- Convert nanoseconds to seconds
CREATE FUNCTION NANOS_TO_SECONDS(NANOS BIGINT) RETURNS BIGINT AS
(NANOS / 1000000000::BIGINT); 

-- Convert nanoseconds to milliseconds
CREATE FUNCTION NANOS_TO_MILLIS(NANOS BIGINT) RETURNS BIGINT AS
(NANOS / 1000000::BIGINT);

-- Convert to TIMESTAMP type from a BIGINT that represents time in nanoseconds 
CREATE FUNCTION MAKE_TIMESTAMP_FROM_NANOS(NANOS BIGINT) RETURNS TIMESTAMP AS
TIMESTAMPADD(SECOND, NANOS_TO_SECONDS(NANOS), DATE '1970-01-01');

-- (Spans[N]) -> (Span, elapsedTimeMillis, eventTime) x N
CREATE MATERIALIZED VIEW spans AS
SELECT
    resource,
    scope,
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
    NANOS_TO_MILLIS(endTimeUnixNano::BIGINT - startTimeUnixNano::BIGINT) as elapsedTimeMillis,
    MAKE_TIMESTAMP_FROM_NANOS(startTimeUnixNano) as eventTime
FROM spans_array, UNNEST(spans_array.spans);

CREATE LOCAL VIEW spans_tumble_10s AS
SELECT * FROM TABLE(
	TUMBLE(
	    TABLE spans,
	    DESCRIPTOR(eventTime),
	    INTERVAL '10' SECOND
	)
);

-- UDF to calculate p95 value given an integer array
CREATE FUNCTION p95(x BIGINT ARRAY NOT NULL) RETURNS BIGINT;

-- Calculate the p95 latency in milliseconds
CREATE MATERIALIZED VIEW p95_latency AS
SELECT
	p95(array_agg(elapsedTimeMillis)) as latencyMs,
	window_start as 'time'
FROM spans_tumble_10s
WHERE 
	parentSpanId = '' -- Only consider top-level requests
GROUP BY 
	window_start;

CREATE MATERIALIZED VIEW throughput AS
SELECT 
	COUNT(*) as throughput,
	window_start as 'time'
FROM 
	spans_tumble_10s
WHERE 
	parentSpanId = ''
GROUP BY 
	window_start;  

CREATE MATERIALIZED VIEW operation_execution_time as
SELECT 
    s.name,
    SUM(
        s.elapsedTimeMillis - 
        coalesce(
            select 
                sum(elapsedTimeMillis) 
                FROM spans k 
                WHERE k.traceId = s.traceId 
                AND k.parentSpanId = s.spanId,
            0
        )
    ) as elapsed
FROM spans s
GROUP BY s.name;
