# This script uses the Feldera API to create and start a pipeline using SQL
# program in 'otel.sql'.

from feldera import FelderaClient, PipelineBuilder

sql = open("otel.sql").read()
udf = open("udf.rs").read()

client = FelderaClient('http://localhost:28080')

print('Starting pipeline')
pipeline = PipelineBuilder(client, 'otel', sql, udf_rust=udf).create_or_replace()
pipeline.start()
