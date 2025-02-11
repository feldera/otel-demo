# Feldera OpenTelemetry Demo

This is a demo of how to use Feldera to analyze OpenTelemetry data with
Feldera and make a Grafana dashboard to visualize this data.

This demo is documented here: [Feldera OTel Guide](https://docs.feldera.com/use_cases/otel/intro)

Feldera will run at: <http://localhost:28080>
Grafana will run at: <http://localhost:8080/grafana/>

To run this, you need:
- docker
- python3
- pip

To run the demo:

```sh
make start
```

If you get a python error, like module `pip` not found (might happen in Arch, NixOS)
we recommend you use [uv](https://docs.astral.sh/uv/)

```sh
# create a virtual environment with uv
uv venv -p 3.12
# activate the venv
source .venv/bin/activate
# install feldera python SDK
uv pip install feldera
# run the `start_feldera_pipeline.py` script
python start_feldera_pipeline.py
```

To stop the demo:

```sh
make stop
```

