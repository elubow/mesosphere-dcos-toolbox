# Scripts
This is a list of scripts that have been put together in support of work for dcos-metrics.

## install_dcos_metrics_prom_on_master.sh
Install the dcos-metrics prometheus plugin on the master and start systemd to ensure it's up.
Can also be run from the command line: `curl --retry 3 -fsSL https://raw.githubusercontent.com/elubow/mesosphere-dcos-toolbox/master/scripts/dcos_metrics/install_dcos_metrics_prom_on_master.sh`

## install_dcos_metrics_prom_on_agent.sh
Install the dcos-metrics prometheus plugin on agent and start systemd to ensure it's up.
Can also be run from the command line: `curl --retry 3 -fsSL https://raw.githubusercontent.com/elubow/mesosphere-dcos-toolbox/master/scripts/dcos_metrics/install_dcos_metrics_prom_on_agent.sh`
