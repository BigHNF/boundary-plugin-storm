-- Copyright 2015 BMC Software, Inc.
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--    http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local framework = require('framework')
local Plugin = framework.Plugin
local WebRequestDataSource = framework.WebRequestDataSource
local DataSourcePoller = framework.DataSourcePoller
local PollerCollection = framework.PollerCollection
local auth = framework.util.auth
local ipack = framework.util.ipack
local parseJson = framework.util.parseJson
local isHttpSuccess = framework.util.isHttpSuccess
local clone = framework.table.clone

local params = table.remove(framework.params.items, 1)
local ds
local ds_topologies

local CLUSTER_SUMMARY_KEY = 'cluster_summary'
local TOPOLOGY_SUMMARY_KEY = 'topology_summary'
local TOPOLOGY_DETAIL_KEY = 'topology_detail'

local function createOptions(config)
  local options = {}
  options.host = config.host
  options.port = config.port
  options.auth = auth(config.username, config.password)
  options.path = '/api/v1'
  return options 
end

local function createClusterSummaryDataSource(item)
  local options = createOptions(params)
  options.path = options.path .. '/cluster/summary'
  options.meta = CLUSTER_SUMMARY_KEY 
  return WebRequestDataSource:new(options)
end

local function createTopologyDetailDataSource(topology_id)
  local options = createOptions(params) 
  options.path = options.path .. ('/topology/%s?window=1'):format(topology_id)
  options.meta = TOPOLOGY_DETAIL_KEY
  return WebRequestDataSource:new(options)
end

local function createTopologySummaryDataSource()
  local options = createOptions(params)
  options.path = options.path .. '/topology/summary'
  options.meta = TOPOLOGY_SUMMARY_KEY

  local ds = WebRequestDataSource:new(options)
  ds:chain(function (context, callback, data, extra)
    -- First emit some metrics.
    callback(data, extra)

    local success, parsed = parseJson(data)
    if not success then
      return nil
    end
 
    local datasources = {}
    for _, topology in ipairs(parsed.topologies) do
      local ds_detail = createTopologyDetailDataSource(topology.id)
      ds_detail:propagate('error', context)
      table.insert(datasources, ds_detail)
    end
    return datasources
  end)

  return ds
end

local function topologySummaryExtractor (data)
  local result = {}
  local metric = function (...) ipack(result, ...) end
  metric('STORM_CLUSTER_TOPOLOGIES',  #data.topologies)
  return result
end

local function clusterSummaryExtractor (data)
  local result = {}
  local metric = function (...) ipack(result, ...) end
  metric('STORM_CLUSTER_EXECUTORS', data.executorsTotal)
  metric('STORM_CLUSTER_SLOTS_TOTAL', data.slotsTotal)
  metric('STORM_CLUSTER_SLOTS_USED',  data.slotsUsed)
  metric('STORM_CLUSTER_TASKS_TOTAL', data.tasksTotal)
  metric('STORM_CLUSTER_SUPERVISORS', data.supervisors)
  return result
end

local function topologyDetailExtractor(topology)
    local result = {}
    local metric = function (...) ipack(result, ...) end

    -- Topology-level metrics.
    local tsrc = params.source .. '.' .. topology.id
    metric('STORM_TOPOLOGY_TASKS_TOTAL', topology.tasksTotal, nil, tsrc)
    metric('STORM_TOPOLOGY_WORKERS_TOTAL', topology.workersTotal, nil, tsrc)
    metric('STORM_TOPOLOGY_EXECUTORS_TOTAL', topology.executorsTotal, nil, tsrc)

    -- Spout-level metrics.
    if params.show_spouts then
      for _, spout in ipairs(topology.spouts) do
        local ssrc = tsrc .. ".spout-" .. spout.spoutId
        metric('STORM_SPOUT_EXECUTORS', spout.executors, nil, ssrc)
        metric('STORM_SPOUT_TASKS', spout.tasks, nil, ssrc)
        metric('STORM_SPOUT_EMITTED', spout.emitted, nil, ssrc)
        metric('STORM_SPOUT_ACKED', spout.acked, nil, ssrc)
        metric('STORM_SPOUT_FAILED', spout.failed, nil, ssrc)
        metric('STORM_SPOUT_COMPLETELATENCY', tonumber(spout.completeLatency), nil, ssrc)
      end
    end

    -- Bolt-level metrics.
    if params.show_bolts then
      for _, bolt in ipairs(topology.bolts) do
        local bsrc = tsrc .. ".bolt-" .. bolt.boltId
        metric('STORM_BOLT_EXECUTORS', bolt.executors, nil, bsrc)
        metric('STORM_BOLT_TASKS', bolt.tasks, nil, bsrc)
        metric('STORM_BOLT_EMITTED', bolt.emitted, nil, bsrc)
        metric('STORM_BOLT_ACKED', bolt.acked, nil, bsrc)
        metric('STORM_BOLT_FAILED', bolt.failed, nil, bsrc)
        metric('STORM_BOLT_CAPACITY', tonumber(bolt.capacity), nil, bsrc)
        metric('STORM_BOLT_EXECUTELATENCY', tonumber(bolt.executeLatency), nil, bsrc)
        metric('STORM_BOLT_PROCESSLATENCY', tonumber(bolt.processLatency), nil, bsrc)
      end
    end

    return result
end

local extractors_map = {}
extractors_map[CLUSTER_SUMMARY_KEY] = clusterSummaryExtractor
extractors_map[TOPOLOGY_SUMMARY_KEY] = topologySummaryExtractor
extractors_map[TOPOLOGY_DETAIL_KEY] = topologyDetailExtractor

ds = createClusterSummaryDataSource()
ds:chain(function (context, callback, data, extra)
  callback(data, extra) 
  return { createTopologySummaryDataSource() }
end)
local plugin = Plugin:new(params, ds)

function plugin:onParseValues(data, extra)

  if not isHttpSuccess(extra.status_code) then
    self:emitEvent('error', ('Http request returned status code %s instead of OK. Please verify configuration.'):format(extra.status_code))
    return
  end

  local success, parsed = parseJson(data)
  if not success then
    self:emitEvent('error', 'Can not parse metrics. Please verify configuration.') 
    return
  end

  local extractor = extractors_map[extra.info]
  return extractor(parsed)
end

plugin:run()
