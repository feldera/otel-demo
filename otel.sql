-- Input table that ingests resource spans from the collector.
CREATE TABLE otel_traces (
    resourceSpans VARIANT 
) WITH ('append_only' = 'true');

CREATE TABLE otel_logs (
    resourceLogs VARIANT
) WITH ('append_only' = 'true');

CREATE TABLE otel_metrics (
    resourceMetrics VARIANT
) WITH ('append_only' = 'true');
