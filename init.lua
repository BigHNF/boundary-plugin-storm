--
-- [boundary.com] Couchbase Lua Plugin
-- [author] Valeriu Paloş <me@vpalos.com>
--
--
--
--

--
-- Imports.
--
local dns   = require('dns')
local fs    = require('fs')
local json  = require('json')
local http  = require('http')
local math  = require('math')
local os    = require('os')
local timer = require('timer')
local tools = require('tools')
local url   = require('url')

--
-- Initialize.
--
local _parameters        = json.parse(fs.readFileSync('param.json')) or {}

local _serverHost        = _parameters.serverHost or 'localhost'
local _serverPort        = _parameters.serverPort or 8080
local _serverApi         = _parameters.serverApi or '/api/v1' -- Undocumented, but more future-proof.

local _pollRetryCount    = tools.fence(tonumber(_parameters.pollRetryCount) or    3,   0, 1000)
local _pollRetryDelay    = tools.fence(tonumber(_parameters.pollRetryDelay) or  100,   0, 1000 * 60 * 60)
local _pollInterval      = tools.fence(tonumber(_parameters.pollInterval)   or 5000, 100, 1000 * 60 * 60 * 24)

local _showAllTopologies = _parameters.showAllTopologies ~= false
local _showTopologies    = _parameters.showTopologies or {}
local _showBolts         = _parameters.showBolts ~= false
local _showSpouts        = _parameters.showSpouts ~= false

-- Select topologies.
_showTopologies.mt = { __index = {} }
setmetatable(_showTopologies, _showTopologies.mt)
for _, item in ipairs(_showTopologies) do
  _showTopologies.mt.__index[item] = true
end

--
-- Metrics source.
--
local _source =
  (type(_parameters.source) == 'string' and _parameters.source:gsub('%s+', '') ~= '' and _parameters.source) or
   os.hostname()

--
-- Get a JSON data set from the server at the given URL (includes query string)
--
local remaining = 0
function retrieve(location, callback)
  remaining = remaining + 1
  local _pollRetryRemaining = _pollRetryCount

  local options = url.parse(('http://%s:%d%s%s'):format(_serverHost, _serverPort, _serverApi, location))
  options.headers = {
    ['Accept'] = 'application/json',
    ['Connection'] = 'keep-alive'
  }

  function handler(response)
    if (response.status_code ~= 200) then
      return retry("Unexpected status code " .. response.status_code .. ", should be 200!")
    end

    local data = {}
    response:on('data', function(chunk)
      table.insert(data, chunk)
    end)
    response:on('end', function()
      local success, json = pcall(json.parse, table.concat(data))

      if success then
        remaining = remaining - 1
        callback(json)
      else
        retry("Unable to parse incoming data as a valid JSON value!")
      end

      response:destroy()
    end)

    response:once('error', retry)
  end

  function retry(result)
    if _pollRetryRemaining > 0 then
      _pollRetryRemaining = _pollRetryRemaining - 1
    end

    if _pollRetryRemaining == 0 then
      return error(tostring(result.message or result))
    end

    timer.setTimeout(_pollRetryDelay, perform)
  end

  function perform()
    local request = http.request(options, handler)
    request:once('error', retry)
    request:done()
  end

  perform()
end

--
-- Schedule poll.
--
function schedule()
  timer.setTimeout(_pollInterval, poll)
end

--
-- Print a metric.
--
function metric(stamp, id, value, source)
  print(string.format('%s %s %s %d', id, value or 0, source or _source, stamp))
end

--
-- Collect topology metrics per 1 second time window.
--
function produceTopology(stamp, id)
  retrieve(('/topology/%s?window=1'):format(id, _pollInterval), function(topology)

    -- Topology-level metrics.
    local tsrc = _source .. '/' .. id
    metric(stamp, 'STORM_TOPOLOGY_EMITTED',         topology.topologyStats.emitted,                   tsrc)
    metric(stamp, 'STORM_TOPOLOGY_TRANSFERRED',     topology.topologyStats.transferred,               tsrc)
    metric(stamp, 'STORM_TOPOLOGY_ACKED',           topology.topologyStats.acked,                     tsrc)
    metric(stamp, 'STORM_TOPOLOGY_FAILED',          topology.topologyStats.failed,                    tsrc)
    metric(stamp, 'STORM_TOPOLOGY_COMPLETELATENCY', tonumber(topology.topologyStats.completeLatency), tsrc)

    if _showBolts then
      for _, bolt in ipairs(topology.bolts) do

        -- Bolt-level metrics.
        local bsrc = tsrc .. "/bolt-" .. bolt.boltId
        metric(stamp, 'STORM_BOLT_EXECUTORS', bolt.executors,                     bsrc)
        metric(stamp, 'STORM_BOLT_TASKS', bolt.tasks,                             bsrc)
        metric(stamp, 'STORM_BOLT_EMITTED', bolt.emitted,                         bsrc)
        metric(stamp, 'STORM_BOLT_ACKED', bolt.acked,                             bsrc)
        metric(stamp, 'STORM_BOLT_FAILED', bolt.failed,                           bsrc)
        metric(stamp, 'STORM_BOLT_CAPACITY', tonumber(bolt.capacity),             bsrc)
        metric(stamp, 'STORM_BOLT_EXECUTELATENCY', tonumber(bolt.executeLatency), bsrc)
        metric(stamp, 'STORM_BOLT_PROCESSLATENCY', tonumber(bolt.processLatency), bsrc)
      end
    end

    if _showSpouts then
      for _, spout in ipairs(topology.spouts) do

        -- Spout-level metrics.
        local ssrc = tsrc .. "/spout-" .. spout.spoutId
        metric(stamp, 'STORM_SPOUT_EXECUTORS', spout.executors,                       ssrc)
        metric(stamp, 'STORM_SPOUT_TASKS', spout.tasks,                               ssrc)
        metric(stamp, 'STORM_SPOUT_EMITTED', spout.emitted,                           ssrc)
        metric(stamp, 'STORM_SPOUT_ACKED', spout.acked,                               ssrc)
        metric(stamp, 'STORM_SPOUT_FAILED', spout.failed,                             ssrc)
        metric(stamp, 'STORM_SPOUT_COMPLETELATENCY', tonumber(spout.completeLatency), ssrc)
      end
    end
  end)
end


--
-- Collect cluster metrics.
--
function poll()
  local stamp = os.time()

  -- Ensure previous collections have ended.
  if remaining > 0 then
    return schedule()
  end

  -- Trigger collection at cluster-level.
  retrieve('/cluster/summary', function(cluster)
    metric(stamp, 'STORM_CLUSTER_EXECUTORS',   cluster.executorsTotal)
    metric(stamp, 'STORM_CLUSTER_SLOTS_TOTAL', cluster.slotsTotal)
    metric(stamp, 'STORM_CLUSTER_SLOTS_USED',  cluster.slotsUsed)
    metric(stamp, 'STORM_CLUSTER_TASKS_TOTAL', cluster.tasksTotal)
  end)

  -- Trigger topologies.
  retrieve('/topology/summary', function(data)
    metric(stamp, 'STORM_CLUSTER_TOPOLOGIES',  #data.topologies)

    for _, topology in ipairs(data.topologies) do
      if _showAllTopologies or _showTopologies[topology.name] or _showTopologies[topology.id] then
        process.nextTick(function()
          produceTopology(stamp, topology.id)
        end)
      end
    end
  end)

  -- Reschedule.
  schedule()
end

--
-- Start.
--
poll()