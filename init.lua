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
local notEmpty = framework.string.notEmpty

local params = framework.params

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
  local options = createOptions(item)
  options.path = options.path .. '/cluster/summary'
  options.meta = {CLUSTER_SUMMARY_KEY, item}
  return WebRequestDataSource:new(options)
end

local function createTopologyDetailDataSource(item, topology_id)
  local options = createOptions(item) 
  options.path = options.path .. ('/topology/%s?window=1'):format(topology_id)
  options.meta = {TOPOLOGY_DETAIL_KEY, item}
  return WebRequestDataSource:new(options)
end

local function createTopologySummaryDataSource(item)
  local options = createOptions(item)
  options.path = options.path .. '/topology/summary'
  options.meta = {TOPOLOGY_SUMMARY_KEY, item}

  local ds = WebRequestDataSource:new(options)
  ds:chain(function (context, callback, data, extra)
     if not isHttpSuccess(extra.status_code) then
      return nil
    end

    local success, parsed = parseJson(data)
    if not success then
      return nil
    end

   -- First emit some metrics.
    callback(data, extra)

    local datasources = {}
    for _, topology in ipairs(parsed.topologies) do
      if not item.topologies_filter or item.topologies_filter[topology.name] or item.topologies_filter[topology.id] then
        local ds_detail = createTopologyDetailDataSource(item, topology.id)
        ds_detail:propagate('error', context)
        table.insert(datasources, ds_detail)
      end
    end
    return datasources
  end)

  return ds
end

local function topologySummaryExtractor (data, item)
  local result = {}
  local metric = function (...) ipack(result, ...) end
  metric('STORM_CLUSTER_TOPOLOGIES',  #data.topologies, nil, item.source)
  return result
end

local function clusterSummaryExtractor (data, item)
  local result = {}
  local metric = function (...) ipack(result, ...) end
  metric('STORM_CLUSTER_EXECUTORS', data.executorsTotal, nil, item.source)
  metric('STORM_CLUSTER_SLOTS_TOTAL', data.slotsTotal, nil, item.source)
  metric('STORM_CLUSTER_SLOTS_USED',  data.slotsUsed, nil, item.source)
  metric('STORM_CLUSTER_TASKS_TOTAL', data.tasksTotal, nil, item.source)
  metric('STORM_CLUSTER_SUPERVISORS', data.supervisors, nil, item.source)
  return result
end

local function topologyDetailExtractor(topology, item)
    local result = {}
    local metric = function (...) ipack(result, ...) end

    -- Topology-level metrics.
    local tsrc = item.source .. '.' .. topology.name
    metric('STORM_TOPOLOGY_TASKS_TOTAL', topology.tasksTotal, nil, tsrc)
    metric('STORM_TOPOLOGY_WORKERS_TOTAL', topology.workersTotal, nil, tsrc)
    metric('STORM_TOPOLOGY_EXECUTORS_TOTAL', topology.executorsTotal, nil, tsrc)

    -- Spout-level metrics.
    if item.show_spouts then
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
    if item.show_bolts then
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

local function createPollers(params)
  local pollers = PollerCollection:new()
  for _, item in pairs(params.items) do

    local topologies_map = {}
    local count = 0
    for i, v in ipairs(item.topologies_filter) do
      if notEmpty(v) then
        topologies_map[v] = true;
        count = count + 1
      end
    end
    item.topologies_filter = (count > 0) and topologies_map or nil

    local ds = createClusterSummaryDataSource(item)
    ds:chain(function (context, callback, data, extra)
      if not isHttpSuccess(extra.status_code) then
        return nil
      end
      return { createTopologySummaryDataSource(item) }
    end)
    local poller = DataSourcePoller:new(item.pollInterval, ds)
    pollers:add(poller)
  end
  return pollers
end

local pollers = createPollers(params)
local plugin = Plugin:new(params, pollers)

function plugin:onParseValues(data, extra)

  if not isHttpSuccess(extra.status_code) then
    self:emitEvent('error', ('Http request returned status code %s instead of OK. Please verify configuration.'):format(extra.status_code))
    return
  end

  local success, parsed = parseJson(data)
  if not success then
    self:emitEvent('error', 'Cannot parse metrics. Please verify configuration.') 
    return
  end

  local key, item = unpack(extra.info)
  local extractor = extractors_map[key]
  return extractor(parsed, item)
end

plugin:run()
