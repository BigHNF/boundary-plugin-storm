# TrueSightPulse Storm Plugin

Tracks Apache Storm metrics by polling the Storm UI Rest API.

### Prerequisites

|     OS    | Linux | Windows | SmartOS | OS X |
|:----------|:-----:|:-------:|:-------:|:----:|
| Supported |   v   |    -    |    -    |  -   |

* This plugin is compatible with Apache Storm 0.9.3 or later.

#### Boundary Meter versions v4.2 or later

- To install new meter go to Settings->Installation or [see instructions](https://help.boundary.com/hc/en-us/sections/200634331-Installation).
- To upgrade the meter to the latest version - [see instructions](https://help.boundary.com/hc/en-us/articles/201573102-Upgrading-the-Boundary-Meter).

### Plugin Setup

In order for the plugin to collect statistics from Storm you need to ensure that the Storm UI service is running. By default the service runs on the same node as the Storm Nimbus (master) service.

### Plugin Configuration Fields

|Field Name    | Description                                                                                              |
|:-------------|:---------------------------------------------------------------------------------------------------------|
| Host          | Host of the Storm UI service |
| Port          | Port of the Storm UI service |
| Username      | Username to access the Storm UI service |
| Password      | Password to access the Storm UI service |
| Topologies Filter | Select topologies (by name or id) to show metrics for. If not set, it will shows all topologies |
| Show Bolts          | Show metrics for each bolt in each topology (default: true)                            |
| Show Spouts         | Show metrics for each spout in each topology (default: true) |                           
| Source        | The Source to display in the legend for the metrics data.  It will default to the hostname of the server |
| Poll Interval | How often should the plugin poll for metrics |

### Metrics Collected

|Metric Name                    |Description                                                                 |
|:------------------------------|:---------------------------------------------------------------------------|
|STORM_CLUSTER_TOPOLOGIES       |Number of topologies running on the cluster.                                |
|STORM_CLUSTER_EXECUTORS        |Total number of executors running on the cluster.                           |
|STORM_CLUSTER_SLOTS_TOTAL      |Total number of available worker slots on the cluster.                      |
|STORM_CLUSTER_SLOTS_USED       |Number of worker slots used on the cluster.                                 |
|STORM_CLUSTER_TASKS_TOTAL      |Total number of tasks on the cluster.                                       |
|STORM_CLUSTER_SUPERVISORS      |Total number of supervisors on the cluster.			             |
|STORM_TOPOLOGY_TASKS_TOTAL     |Number of Tasks per toplogy.                                                |
|STORM_TOPOLOGY_WORKERS_TOTAL   |Number of Workers per topolgy.                                              |
|STORM_TOPOLOGY_EXECUTORS_TOTAL |Number of executors per topology.                                           |
|STORM_BOLT_EXECUTORS           |Number of executor tasks in the bolt component.                             |
|STORM_BOLT_TASKS               |Number of instances of bolt.                                                |
|STORM_BOLT_EMITTED             |Number of tuples emitted per bolt per second.                               |
|STORM_BOLT_ACKED               |Number of tuples acked by the bolt per second.                              |
|STORM_BOLT_FAILED              |Number of tuples failed by the bolt per second.                             |
|STORM_BOLT_CAPACITY            |Number of messages executed * average execute latency per second.           |
|STORM_BOLT_EXECUTELATENCY      |Average time to run the execute method of the bolt per second.              |
|STORM_BOLT_PROCESSLATENCY      |Average time of the bolt to ack a message after it was received per second. |
|STORM_BOLT_LASTERROR           |1 if an error / exception was generated, 0 otherwise.                       |
|STORM_SPOUT_EXECUTORS          |Number of executors for the spout.                                          |
|STORM_SPOUT_TASKS              |Total number of tasks for the spout.                                        |
|STORM_SPOUT_EMITTED            |Number of messages emitted per spout per second.                            |
|STORM_SPOUT_ACKED              |Number of messages acked per spout per second.                              |
|STORM_SPOUT_FAILED             |Number of messages failed per spout per second.                             |
|STORM_SPOUT_COMPLETELATENCY    |Total latency for processing the message per spout per second.              |
|STORM_SPOUT_LASTERROR          |1 if an error / exception was generated, 0 otherwise.                       |

LASTERROR value is received as nil or the error/exceptions string. We use the value 0 if lasterror is not nil and the field errorLapsedSecs is lessthan poll interval. Else the value is 0. This can be used in creating alerts for the error occured.

### Events Generated

An Event will be generated whenever the value of lasterror is not nil. The event will be displayed in the situation room. Once an error occurs an event will be triggered during each polling but, only one Event will be shown for the same error in the situation room with an occurance count. A new Event will be generated for a different error.

### Dashboards

- Storm General
- Storm Bolts
- Storm Spouts

### References
- [Apache Storm Documentation.](http://storm.apache.org/documentation.html)
