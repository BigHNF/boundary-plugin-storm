# Boundary Storm Plugin (pure Lua/Luvit)

Tracks Apache Storm metrics by polling the Storm UI REST API "http://localhost:8080/" (configurable setting).
The Storm UI is usually located on the same node as the Storm Nimbus (master) service.

## Prerequisites
- An Apache Storm 0.9.2+ (the monitoring API didn't exist before this version) installation with a running
  Storm UI service on the configured machine (usually the same as the numbus server).
- Metrics are collected via HTTP requests, therefore **all OSes** should work (tested on **Debian-based Linux** distributions).
- Written in pure Lua/Luvit (embedded in `boundary-meter`) therefore **no dependencies** are required.

## Plugin Setup
No special setup is required (except basic configuration of options).

## Configurable Setings
|Setting Name        |Identifier        |Type    |Description                                                                             |
|:-------------------|------------------|--------|:---------------------------------------------------------------------------------------|
|Storm UI Host       |serverHost        |string  |The Apache Storm UI service host for the node (default: 'localhost').                   |
|Storm UI Port       |serverPort        |integer |The Apache Storm UI service port for the node (default: 8091).                          |
|Poll Retry Count    |pollRetryCount    |integer |The number of times to retry failed HTTP requests (default: 3).                         |
|Poll Retry Delay    |pollRetryDelay    |integer |The interval (in milliseconds) to wait before retrying a failed request (default: 100). |
|Poll Interval       |pollInterval      |integer |How often (in milliseconds) to poll the Storm UI node for metrics (default: 5000).      |
|Show All Topologies |showAllTopologies |boolean |Show metrics for all topologies and ignore showTopologies array (default: true).        |
|Show Topologies     |showTopologies    |array   |Select topologies (by name or id) to show metrics for (default: []).                    |
|Show Bolts          |showBolts         |boolean |Show metrics for each bolt in each topology (default: true).                            |
|Show Spouts         |showSpouts        |boolean |Show metrics for each spout in each topology (default: true).                           |

## Collected Metrics
|Metric Name                    |Description                                                                 |
|:------------------------------|:---------------------------------------------------------------------------|
|STORM_CLUSTER_TOPOLOGIES       |Number of topologies running on the cluster.                                |
|STORM_CLUSTER_EXECUTORS        |Total number of executors running on the cluster.                           |
|STORM_CLUSTER_SLOTS_TOTAL      |Total number of available worker slots on the cluster.                      |
|STORM_CLUSTER_SLOTS_USED       |Number of worker slots used on the cluster.                                 |
|STORM_CLUSTER_TASKS_TOTAL      |Total number of tasks on the cluster.                                       |
|STORM_TOPOLOGY_EMITTED         |Number of messages emitted per topology per second.                         |
|STORM_TOPOLOGY_TRANSFERRED     |Number messages transferred per topology per second.                        |
|STORM_TOPOLOGY_ACKED           |Number messages acked per topology per second.                              |
|STORM_TOPOLOGY_FAILED          |Number messages failed per topology per second.                             |
|STORM_TOPOLOGY_COMPLETELATENCY |Total latency for processing messages per topology per second.              |
|STORM_BOLT_EXECUTORS           |Number of executor tasks in the bolt component.                             |
|STORM_BOLT_TASKS               |Number of instances of bolt.                                                |
|STORM_BOLT_EMITTED             |Number of tuples emitted per bolt per second.                               |
|STORM_BOLT_ACKED               |Number of tuples acked by the bolt per second.                              |
|STORM_BOLT_FAILED              |Number of tuples failed by the bolt per second.                             |
|STORM_BOLT_CAPACITY            |Number of messages executed * average execute latency per second.           |
|STORM_BOLT_EXECUTELATENCY      |Average time to run the execute method of the bolt per second.              |
|STORM_BOLT_PROCESSLATENCY      |Average time of the bolt to ack a message after it was received per second. |
|STORM_SPOUT_EXECUTORS          |Number of executors for the spout.                                          |
|STORM_SPOUT_TASKS              |Total number of tasks for the spout.                                        |
|STORM_SPOUT_EMITTED            |Number of messages emitted per spout per second.                            |
|STORM_SPOUT_ACKED              |Number of messages acked per spout per second.                              |
|STORM_SPOUT_FAILED             |Number of messages failed per spout per second.                             |
|STORM_SPOUT_COMPLETELATENCY    |Total latency for processing the message per spout per second.              |

## References
[Apache Storm UI REST API Reference](https://github.com/apache/storm/blob/master/STORM-UI-REST-API.md)

## Simulation

### Prerequisites:
- GIT.
- [Docker](docker.com).
- [Docker-Compose](http://docs.docker.com/compose/install/).
- [Apache Storm 0.9.3](http://www.apache.org/dyn/closer.cgi/storm/apache-storm-0.9.3/apache-storm-0.9.3.tar.gz).
- [Storm-Docker](https://github.com/wurstmeister/storm-docker).

### Run Storm-Docker

```
git clone https://github.com/wurstmeister/storm-docker && cd storm-docker

mv fig.yml docker-compose.yml # switch to docker-compose, fig is deprecated

sudo docker-compose up
```

### Submit example topologies
First download the `apache-storm-0.9.3.tar.gz` file then...
```
tar -zxf apache-storm-0.9.3.tar.gz

cd apache-storm-0.9.3/

bin/storm jar \
  examples/storm-starter/storm-starter-topologies-0.9.3.jar \
  storm.starter.WordCountTopology \
  word-count-topology \
  -c nimbus.host=localhost \
  -c nimbus.thrift.port=49627

bin/storm jar \
  examples/storm-starter/storm-starter-topologies-0.9.3.jar \
  storm.starter.ExclamationTopology \
  exclamation-topology \
  -c nimbus.host=localhost \
  -c nimbus.thrift.port=49627

bin/storm jar \
  examples/storm-starter/storm-starter-topologies-0.9.3.jar \
  storm.starter.ReachTopology \
  reach-topology \
  -c nimbus.host=localhost \
  -c nimbus.thrift.port=49627
```

- For running the plugin against the Storm-Docker simulation, use port `49080` in `param.json`.
