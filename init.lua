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
local auth = framework.util.auth
local ipack = framework.util.ipack
local parseJson = framework.util.parseJson
local isHttpSuccess = framework.util.isHttpSuccess

local params = framework.params
local ds
for _, i in pairs(params.items) do
  local options = {}
  options.host = i.host
  options.port = i.port
  options.protocol = 'http'
  options.auth = auth(i.username, i.password)
  options.path = '/api/v1/cluster/summary'
  
  ds = WebRequestDataSource:new(options)
end

local plugin = Plugin:new(params, ds)

function plugin:onParseValues(data, extra)
  local result = {}
  local metric = function (...) ipack(result, ...) end

  if not isHttpSuccess(extra.status_code) then
    -- TODO: Emit error event.
    return
  end

  local success, parsed = parseJson(data)
  if not success then
    -- TODO: Emit error event.
    return
  end

  metric('STORM_CLUSTER_EXECUTORS', parsed.executorsTotal)
  metric('STORM_CLUSTER_SLOTS_TOTAL', parsed.slotsTotal)
  metric('STORM_CLUSTER_SLOTS_USED',  parsed.slotsUsed)
  metric('STORM_CLUSTER_TASKS_TOTAL', parsed.tasksTotal)

  return result
end

plugin:run()
