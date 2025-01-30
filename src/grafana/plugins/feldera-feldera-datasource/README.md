<h1 align="center">
  <a href="https://feldera.com">
    <picture>
      <source height="125" media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/feldera/docs.feldera.com/refs/heads/main/static/img/logo-color-light.svg">
      <img height="125" alt="Feldera" src="https://raw.githubusercontent.com/feldera/docs.feldera.com/refs/heads/main/static/img/logo.svg">
    </picture>
  </a>
  <br>
  <br>
  <a href="https://opensource.org/licenses/MIT">
    <img src="https://img.shields.io/badge/License-MIT-green.svg">
  </a>
  <a href="https://www.feldera.com/community">
    <img salt="Slack" src="https://img.shields.io/badge/slack-blue.svg?logo=slack">
  </a>
  <a href="https://discord.gg/5YBX9Uw5u7">
    <img alt="Discord" src="https://img.shields.io/badge/discord-blue.svg?logo=discord&logoColor=white">
  </a>
  <a href="https://try.feldera.com/">
    <img alt="Sandbox" src="https://img.shields.io/badge/feldera_sandbox-blue?logo=CodeSandbox">
  </a>
</h1>

## Overview / Introduction
Visualize data from [Feldera](https://feldera.com) in Grafana.

## Requirements
- A running Feldera pipeline must be accessible to the Grafana instance.
- The views you intend to query from Grafana must be **MATERIALIZED** views. (See: [Materialized Tables and Views](https://docs.feldera.com/sql/materialized))

## Getting Started
1. Install the plugin in your Grafana instance.
2. Create a data source by specifying:
   - The URL of the Feldera instance.
   - The name of the pipeline you intend to query from.
   - The API Key used to connect to Feldera. Optional.
3. Start building dashboards and exploring data by querying the **MATERIALIZED VIEWs**. 
We recommend creating a view for each graph you want to display in Grafana, and then write [ad-hoc queries](https://docs.feldera.com/sql/ad-hoc)
with this plugin to query these views.

## Documentation

For detailed guidance, visit the [Feldera Documentation](https://docs.feldera.com/).

### Suppported Macros

| Macro           | Description                                                   |
|-----------------|---------------------------------------------------------------|
| `$__timeFrom()` | Replaced by the start time specified by Grafana time picker.  |
| `$__timeTo()`   | Replaced by the end time specified by Grafna time picker.     |

*Note that Feldera's `TIMESTAMP` type doesn't store time zone information.*

### Time Series Graphs

To create time series graphs, add a *Convert field type* transformation and specify the timestamp column in your data as type **TIME**.

## Contributing
This plugin's repository is hosted on Github: [Feldera Grafana Datasource](https://github.com/feldera/grafana-datasource).
We welcome contributions and feature requests.

