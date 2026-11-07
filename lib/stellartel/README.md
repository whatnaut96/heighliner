# StellarTel

StellarTel is a basic data engineering project for Elite Dangerous.
Journals are received from `beacon` on the game's machine and sent here for processing.

## Journal Types Supported
### Status
Status events are broken down to individual metrics and pushed to VictoriaMetrics via the support for the Prometheus Pushgateway.

