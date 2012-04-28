--
-- CumulusAdmin - A database-backed administration tool for Cumulus
--
--                         www.openrtmfp.net
--
-- (c) Daniel "dcode" Wirtz
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
--

function CA_DEBUG(s) DEBUG("[DA] "..s) end
function CA_NOTE(s)	NOTE("[CA] "..s) end
function CA_WARN(s) WARN("[CA] "..s) end
function CA_ERROR(s) ERROR("[CA] "..s) end

-- Ensures availability of the database connection
function CA_ensureDb(secret)
	if secret ~= CA.secret then
		CA_WARN("Attempt to access CA_ensureDb with a wrong secret")
		return nil
	end
	local now = os.time()
	if not CA.dbConnectTime or CA.dbConnectTime < now-60 then
		if CA.dbDriver == "mysql" then
			CA.con = assert(CA.db:connect(CA.dbName, CA.dbUser, CA.dbPass, CA.dbHost, CA.dbPort), "Failed to connect to database via MySQL")
		elseif CA.dbDriver == "postgres" then
			CA.con = assert(CA.db:connect(CA.dbName, CA.dbUser, CA.dbPass, CA.dbHost, CA.dbPort), "Failed to connect to database via Postgres")
		else
			CA.con = assert(CA.db:connect(CA.dbSource, CA.dbUser, CA.dbPass), "Failed to connect to database via ODBC")
		end
		if CA.con then
			CA.dbConnectTime = now
		end
	end
end

local secret = "ChangeByConf"
if cumulus.configs.admin.secret then
	secret = cumulus.configs.admin.secret
end

if not cumulus["CA_"..secret] then -- first start
	CA_NOTE("Loading CumulusAdmin (http://www.openrtmfp.net)")
	
	CA = {}
	CA.dbDriver = "mysql"
	CA.dbHost = "localhost"
	CA.dbPort = 3306
	CA.dbName = "cumulus"
	CA.dbUser = "root"
	CA.dbPass = ""
	CA.dbPrefix = ""
	CA.updateInterval = 60
	CA.secret = secret
	
	CA.apps = {}
	
	if cumulus.configs.admin.db_driver then
		CA.dbDriver = cumulus.configs.admin.db_driver
	end
	if cumulus.configs.admin.db_host then
		CA.dbHost = cumulus.configs.admin.db_host
	end
	if cumulus.configs.admin.db_port then
		CA.dbPort = cumulus.configs.admin.db_port
	end
	if cumulus.configs.admin.db_name then
		CA.dbName = cumulus.configs.admin.db_name
	end
	if cumulus.configs.admin.db_user then
		CA.dbUser = cumulus.configs.admin.db_user
	end
	if cumulus.configs.admin.db_pass then
		CA.dbPass = cumulus.configs.admin.db_pass
	end
	if cumulus.configs.admin.db_prefix then
		CA.dbPrefix = cumulus.configs.admin.db_prefix
	end
	if cumulus.configs.admin.update_interval then
		CA.updateInterval = cumulus.configs.admin.update_interval
	end
	
	-- See: http://www.keplerproject.org/luasql/
	CA.dbSource = CA.dbDriver.."://"..CA.dbHost..":"..CA.dbPort.."/"..CA.dbName
	if CA.dbPass and CA.dbPass ~= "" then
		CA_NOTE("Connecting to "..CA.dbSource.." as '"..CA.dbUser.."' using password=yes (prefix='"..CA.dbPrefix.."')")
	else
		CA_NOTE("Connecting to "..CA.dbSource.." as '"..CA.dbUser.."' using password=no (prefix='"..CA.dbPrefix.."')")
	end
	CA.db = nil
	CA.con = nil
	if CA.dbDriver == "mysql" then
		require "luasql.mysql"
		CA.db = assert(luasql.mysql(), "Failed to get MySQL handle: Is the MySQL driver installed?")
	elseif CA.dbDriver == "postgres" then
		require "luasql.postgres"
		CA.db = assert(luasql.postgres(), "Failed to get Postgres handle: Is the Postgres driver installed?")
	else
		require "luasql.odbc"
		CA.db = assert(luasql.odbc(), "Failed to get ODBC handle: Is the ODBC driver installed?")
	end
	CA_ensureDb(CA.secret)
	
	CA_NOTE("Cleaning up previous state")
	CA.con:execute(string.format([[
		"DELETE FROM %spublications_clients"
	]], CA.dbPrefix))
	CA.con:execute(string.format([[
		"DELETE FROM %spublications"
	]], CA.dbPrefix))
	CA.con:execute(string.format([[
		"DELETE FROM %sgroups_clients"
	]], CA.dbPrefix))
	CA.con:execute(string.format([[
		"DELETE FROM %sgroups"
	]], CA.dbPrefix))
	CA.con:execute(string.format([[
		"DELETE FROM %sclients"
	]], CA.dbPrefix))
	
	cumulus["CA_"..CA.secret] = CA
	CA_NOTE("CumulusAdmin has been loaded")

else -- reloaded
	CA_NOTE("CumulusAdmin has been reloaded")
	CA = cumulus["CA_"..secret]
end

-- Quotes a string to be used in database queries
function CA_quote(s)
	if s == nil then
		return "NULL"
	else
		s = string.gsub(s, "(['\"\\])", "\\%1")
		s = (string.gsub(s, "%z", "\\0"))
		return "'"..s.."'"
	end
end

-- Loads the developer descriptor for the given developer id from the database
function CA_loadDev(id, secret)
	if secret ~= CA.secret then
		CA_WARN("Attempt to access CA_loadDev with a wrong secret")
		return nil
	end
	if id == nil then
		return nil
	end
	local cur = assert(CA.con:execute(string.format([[
		SELECT * FROM %sdevelopers WHERE id=%d
	]], CA.dbPrefix, id)), "Failed to fetch developer from database")
	if not cur or cur:numrows() == 0 then
		return nil
	end
	return cur:fetch({}, "a")
end

-- Loads the application descriptor for the given path from the database
function CA_loadApp(path, secret)
	if secret ~= CA.secret then
		CA_WARN("Attempt to access CA_loadApp with a wrong secret")
		return nil
	end
	if path == "" then
		path = "ROOT"
	end
	local cur = assert(CA.con:execute(string.format([[
		SELECT * FROM %sapplications WHERE path=%s
	]], CA.dbPrefix, CA_quote(path))), "Failed to fetch application from database")
	if not cur or cur:numrows() == 0 then
		return nil
	end
	return cur:fetch({}, "a")
end

-- Gets the application descriptor for the given path
function CA_getApp(path, secret)
	if secret ~= CA.secret then
		CA_WARN("Attempt to access CA_getApp with a wrong secret")
		return nil
	end
	if path == "" then
		path = "ROOT"
	end
	local now = os.time()
	if CA.apps[path] then -- already loaded
		local app = CA.apps[path]
		if app.updateTime < now-CA.updateInterval then -- reload
			app.updateTime = now
			local data = CA_loadApp(path, secret)
			if not data then
				if app.enabled == "1" then
					CA_WARN("Application "..app.id..":"..app.path.." has been deleted from the database in running state and will be disabled")
					app.enabled = "0"
				else
					CA_WARN("Application "..app.id..":"..app.path.." has been deleted from the database in disabled state")
				end
				return app
			end
			app.id = data.id
			if app.enabled == "0" and data.enabled == "1" then
				CA_NOTE("Application "..app.id..":"..app.path.." has been enabled by configuration")
			elseif app.enabled == "1" and data.enabled == "0" then
				CA_NOTE("Application "..app.id..":"..app.path.." has been disabled by configuration")
			end
			app.enabled = data.enabled
			if app.developer_id ~= data.developer_id then
				CA_NOTE("Application "..app.id..":"..app.path.." has changed its developer")
				app.developer_id = data.developer_id
				app.dev = CA_loadDev(app.developer_id, secret)
			end
			app.allow_publish = data.allow_publish
			app.publish_password = data.publish_password
			app.subscribe_callback = data.subscribe_callback
			app.unsubscribe_callback = data_unsubscribe_callback
		end
		return app
	end
	local app = CA_loadApp(path, secret)
	if not app then
		return nil
	end
	-- initialize
	app.clients = 0
	app.clientsCounter = 0
	app.groups = 0
	app.groupsCounter = 0
	app.dev = CA_loadDev(app.developer_id, secret)
	app.updateTime = os.time()
	app.started = false
	app.trafficUpdateTime = app.updateTime
	app.trafficAudioIn = 0
	app.trafficVideoIn = 0
	app.trafficDataIn = 0
	app.trafficAudioOut = 0
	app.trafficVideoOut = 0
	app.trafficDataOut = 0
	CA.apps[path] = app
	return app
end

-- Called as soon as the application is started
function onStart(path)
	local app = CA_getApp(path, CA.secret)
	if not app then
		CA_WARN("Application ?:"..path.." cannot be started: Not found")
		return
	end
	if app.enabled ~= "1" then
		CA_NOTE("Application "..app.id..":"..app.path.." cannot be started: Disabled by configuration")
		return
	end
	if not app.dev then
		CA_WARN("Application "..app.id..":"..app.path.." cannot be started: No developer")
		return
	end
	if app.dev.enabled ~= "1" then
		CA_NOTE("Application "..app.id..":"..app.path.." cannot be started: Developer disabled by configuration")
		return
	end
	app.started = true
	CA_NOTE("Application "..app.id..":"..app.path.." has been started")
	assert(CA.con:execute(string.format([[
		UPDATE %sapplications SET started='1', start_time=%d, stop_time=NULL WHERE id=%d
	]], CA.dbPrefix, os.time(), app.id)), "Failed to update application to database")
end

-- Called as soon as a new client has connected to Cumulus
function onConnection(client, response, connectkey)
	local app = CA_getApp(client.path, CA.secret)
	if not app then
		CA_NOTE("Client "..client.address.." rejected: No such application ?:"..client.appPath)
		return "No such application"
	end
	if app.enabled ~= "1" then
		CA_NOTE("Client "..client.address.." rejected: Application "..app.id..":"..app.path.." is disabled")
		return "Application disabled"
	end
	if not app.dev then
		CA_NOTE("Client "..client.address.." rejected: Developer not found")
		return "Developer not found"
	end
	if app.dev.enabled ~= "1" then
		CA_NOTE("Client "..client.address.." rejected: Developer is disabled")
		return "Developer disabled"
	end
	
	-- Allow connections only if there is no developer key set or, if it is, the provided key matches
	if app.dev.connectkey and app.dev.connectkey ~= "" and connectkey ~= app.dev.connectkey then
		CA_NOTE("Client "..client.address.." rejected: Invalid connect key for developer "..app.dev.id)
		return "Invalid connect key"
	end
	
	app.clients = app.clients+1
	app.clientsCounter = app.clientsCounter+1
	client.appPath = app.path;
	client.appId = app.id
	client.appUid = app.clientsCounter
	client.connected = true
	
	CA_NOTE("Client "..client.appId.."-"..client.appUid.." ("..client.address..") connected to application "..app.id..":"..app.path.." ("..app.clients.." clients)")
	
	local pageUrl = client.pageUrl
	if pageUrl == nil or pageUrl == "" or pageUrl == "0" then
		pageUrl = nil
	end
	local swfUrl = client.swfUrl
	if swfUrl == nil or swfUrl == "" or swfUrl == "0" then
		swfUrl = nil
	end
	assert(CA.con:execute(string.format([[
		INSERT INTO %sclients (id, application_id, address, pageUrl, swfUrl, flashVersion, connect_time)
		VALUES (%s, %d, %s, %s, %s, %s, %d)
	]], CA.dbPrefix, CA_quote(client.id), app.id, CA_quote(client.address), CA_quote(pageUrl), CA_quote(swfUrl), CA_quote(client.flashVersion), os.time())), "Failed to insert client into database")
end

-- Called as soon as a client calls publish(...) on a NetStream connected with "CONNECT_TO_FMS"
function onPublish(client, publication, ...)
	local app = CA_getApp(client.path, CA.secret)
	if not app or app.enabled ~= "1" then
		CA_NOTE("Client "..client.appId.."-"..client.appUid.." rejected to publish in application "..client.appId..":"..client.appPath..": Application is disabled")
		return "Application disabled"
	end
	
	-- Allow publishing only if it is generally allowed and there is no password defined or the password matches
	local pass = unpack(arg)
	if app.allow_publish ~= "1" or (app.publish_password and app.publish_password ~= "" and app.publish_password ~= pass) then
		CA_NOTE("Client "..client.appId.."-"..client.appUid.." ("..client.address..") rejected to publish in application "..app.id..":"..app.path..": Permission denied")
		return "Permission denied"
	end
	
	publication.clientId = client.id
	
	CA_NOTE("Client "..client.appId.."-"..client.appUid.." published '"..publication.name.."' to application "..app.id..":"..app.path)
	assert(CA.con:execute(string.format([[
		INSERT INTO %spublications (application_id, client_id, name, subscribers, publish_time)
		VALUES (%d, %s, %s, %d, %d)
	]], CA.dbPrefix, app.id, CA_quote(client.id), CA_quote(publication.name), 0, os.time())), "Failed to insert publication into database")
end

-- Called as soon as a publication is unpublished either implicitly by Cumulus or explicitly by the client
function onUnpublish(client, publication)
	CA_NOTE("Client "..client.appId.."-"..client.appUid.." unpublished '"..publication.name.."' from application "..client.appId..":"..client.appPath)
	assert(CA.con:execute(string.format([[
		DELETE FROM %spublications_clients WHERE publication_name=%s
	]], CA.dbPrefix, CA_quote(publication.name))), "Failed to delete publication/client relations from database")
	assert(CA.con:execute(string.format([[
		DELETE FROM %spublications WHERE application_id=%d AND name=%s
	]], CA.dbPrefix, client.appId, CA_quote(publication.name))), "Failed to delete publication from database")
end

-- Called as soon as a client subscribes to a previous made publication by calling play("publicationname") on a NetStream that has been created with "CONNECT_TO_FMS"
function onSubscribe(client, listener)
	local app = CA_getApp(client.path, CA.secret)
	if not app or app.enabled ~= "1" then
		CA_NOTE("Client "..client.appId.."-"..client.appUid.." rejected to subscribe in application "..client.appId..":"..client.appPath..": Application has been disabled")
		return "Application disabled"
	end
	local total = listener.publication.listeners.count+1
	CA_NOTE("Client "..client.appId.."-"..client.appUid.." subscribed to '"..listener.publication.name.."' ("..total.." subscribers) in application "..app.id..":"..app.path)
	assert(CA.con:execute(string.format([[
		UPDATE %spublications SET subscribers=%d WHERE name=%s
	]], CA.dbPrefix, total, CA_quote(listener.publication.name))), "Failed to update publication to database")
	assert(CA.con:execute(string.format([[
		INSERT INTO %spublications_clients (publication_name, client_id, subscribe_time) VALUES (%s, %s, %d)
	]], CA.dbPrefix, CA_quote(listener.publication.name), CA_quote(client.id), os.time())), "Failed to insert publication/client relation into database")
	if app.subscribe_callback and app.subscribe_callback ~= "" then
		local publisher = cumulus.clients(listener.publication.clientId)
		if publisher then
			publisher.writer:writeAMFMessage(app.subscribe_callback, listener.publication.name, client.id, total)
		end
	end
end

-- Called as soon as a client unsubscribes from a publication either implicitly on disconnect or explicitly by a call to close() on the corresponding NetStream
function onUnsubscribe(client, listener)
	local total = listener.publication.listeners.count-1
	CA_NOTE("Client "..client.appId.."-"..client.appUid.." unsubscribed from '"..listener.publication.name.."' ("..total.." subscribers) in application "..client.appId..":"..client.appPath)
	assert(CA.con:execute(string.format([[
		UPDATE %spublications SET subscribers=%d WHERE application_id=%d AND name=%s
	]], CA.dbPrefix, total, client.appId, CA_quote(listener.publication.name))), "Failed to update publication to database")
	assert(CA.con:execute(string.format([[
		DELETE FROM %spublications_clients WHERE publication_name=%s AND client_id=%s
	]], CA.dbPrefix, CA_quote(listener.publication.name), CA_quote(client.id))), "Failed to delete publication/client relation from database")
	local app = CA_getApp(client.path, CA.secret)
	if app and app.unsubscribe_callback and app.unsubscribe_callback ~= "" then
		local publisher = cumulus.clients(listener.publication.clientId)
		if publisher then
			publisher.writer:writeAMFMessage(app.unsubscribe_callback, listener.publication.name, client.id, total)
		end
	end
end

-- Called as soon as a client joins or creates a group
function onJoinGroup(client, group)
	local app = CA_getApp(client.path, CA.secret)
	if not app or app.enabled ~= "1" then
		CA_NOTE("Client "..client.appId.."-"..client.appUid.." has been rejected to join a group: Application is disabled")
		return "Application is disabled" -- Is this possible?
	end
	if group.size == 1 then
		app.groups = app.groups+1
		app.groupsCounter = app.groupsCounter+1
		group.appId = app.id
		group.appGid = app.groupsCounter
		assert(CA.con:execute(string.format([[
			INSERT INTO %sgroups (id, application_id, members, create_time) VALUES (%s, %d, %d, %d)
		]], CA.dbPrefix, CA_quote(group.id), app.id, 1, os.time())), "Failed to insert group into database")
	else
		assert(CA.con:execute(string.format([[
			UPDATE %sgroups SET members=%d WHERE id=%s
		]], CA.dbPrefix, group.size, CA_quote(group.id))), "Failed to update group to database")
	end
	CA_NOTE("Client "..client.appId.."-"..client.appUid.." joined to group "..group.appId.."_"..group.appGid.." ("..group.size.." members)")
	assert(CA.con:execute(string.format([[
		INSERT INTO %sgroups_clients (group_id, client_id, join_time) VALUES (%s, %s, %d)
	]], CA.dbPrefix, CA_quote(group.id), CA_quote(client.id), os.time())), "Failed to insert group/client relation into database")
end

-- Called as soon as a client leaves a group
function onUnjoinGroup(client, group)
	CA_NOTE("Client "..client.appId.."-"..client.appUid.." left group "..group.appId.."_"..group.appGid)
	assert(CA.con:execute(string.format([[
		DELETE FROM %sgroups_clients WHERE group_id=%s AND client_id=%s
	]], CA.dbPrefix, CA_quote(group.id), CA_quote(client.id))), "Failed to delete group/client relation from database")
	if group.size == 0 then
		local app = CA_getApp(client.path, CA.secret)
		if app then
			app.groups = app.groups-1
		end
		assert(CA.con:execute(string.format([[
			DELETE FROM %sgroups WHERE id=%s
		]], CA.dbPrefix, CA_quote(group.id))), "Failed to delete group from database")
	else
		assert(CA.con:execute(string.format([[
			UPDATE %sgroups SET members=%d WHERE id=%s
		]], CA.dbPrefix, group.size, CA_quote(group.id))), "Failed to update group to database")
	end
end

-- Called for every client->server audio packet
function onAudioPacket(client, publication, time, packet)
	local app = CA_getApp(client.path, CA.secret)
	if app then
		local len = string.len(packet)
		app.trafficAudioIn = app.trafficAudioIn + len
		app.trafficAudioOut = app.trafficAudioOut + len*publication.listeners.count
	end
end

-- Called for every client->server video packet
function onVideoPacket(client, publication, time, packet)
	local app = CA_getApp(client.path, CA.secret)
	if app then
		local len = string.len(packet)
		app.trafficVideoIn = app.trafficVideoIn + len
		app.trafficVideoOut = app.trafficVideoOut + len*publication.listeners.count
	end
end

-- Called for every client->server data packet
function onDataPacket(client, publication, name, packet)
	local app = CA_getApp(client.path, CA.secret)
	if app then
		local len = string.len(packet)
		app.trafficDataIn = app.trafficDataIn + len
		app.trafficDataOut = app.trafficDataOut + len*publication.listeners.count
	end
end

-- Called as soon as a client has failed for whatever local or remote reason
function onFailed(client, error)
	onDisconnection(client)
end

-- Called as soon as a client has disconnected from Cumulus for whatever local or remote reason
function onDisconnection(client, ...)
	if client.connected then -- only once
		client.connected = false
		local app = CA_getApp(client.path, CA.secret)
		if app then
			app.clients = app.clients-1
			CA_NOTE("Client "..client.appId.."-"..client.appUid.." disconnected from application "..client.appId..":"..client.appPath.." ("..app.clients.." clients)")
		else -- should not happen
			CA_WARN("Client "..client.appId.."-"..client.appUid.." disconnected from application "..client.appId..":"..client.appPath.." (Application not found)")
		end
		assert(CA.con:execute(string.format([[
			DELETE FROM %sclients WHERE id=%s
		]], CA.dbPrefix, CA_quote(client.id))), "Failed to delete client from database")
	end
end

-- Called as soon as the application is stopped, usually when Cumulus is shut down gracefully
function onStop(path)
	local app = CA_getApp(path, CA.secret)
	if app then
		app.started = false
		if path ~= "" then
			CA_NOTE("Application "..app.id..":"..app.path.." has been unloaded")
		end
		assert(CA.con:execute(string.format([[
			UPDATE %sapplications SET started='0', stop_time=%d WHERE id=%d
		]], CA.dbPrefix, os.time(), app.id)), "Failed to update application to database")
	else
		CA_WARN("Application ?:"..path.." has been unloaded (Application not found)")
		-- If anything exists there even if it shouldn't, update it
		assert(CA.con:execute(string.format([[
			UPDATE %sapplications SET started='0', stop_time=%d WHERE path=%s
		]], CA.dbPrefix, os.time(), CA_quote(path))), "Failed to update application to database")
	end
end

-- Called every 2 seconds
function onManage()
	local now = os.time()
	CA_ensureDb(CA.secret)
	for path, app in pairs(CA.apps) do
		if app.trafficUpdateTime < now - CA.updateInterval then
			app.trafficUpdateTime = now
			local traffic_audio = app.trafficAudioIn + app.trafficAudioOut
			local traffic_video = app.trafficVideoIn + app.trafficVideoOut
			local traffic_data = app.trafficDataIn + app.trafficDataOut
			local traffic_in = app.trafficAudioIn + app.trafficVideoIn + app.trafficDataIn
			local traffic_out = app.trafficAudioOut + app.trafficVideoOut + app.trafficDataOut
			local traffic = traffic_in + traffic_out
			if traffic > 0 then
				CA_NOTE("Updating application "..app.id..":"..app.path.." with "..traffic.." bytes traffic")
				assert(CA.con:execute(string.format([[
					UPDATE %sapplications SET
						traffic=traffic+%d, traffic_audio=traffic_audio+%d, traffic_video=traffic_video+%d, traffic_data=traffic_data+%d,
						traffic_in=traffic_in+%d, traffic_audio_in=traffic_audio_in+%d, traffic_video_in=traffic_video_in+%d, traffic_data_in=traffic_data_in+%d,
						traffic_out=traffic_out+%d, traffic_audio_out=traffic_audio_out+%d, traffic_video_out=traffic_video_out+%d, traffic_data_out=traffic_data_out+%d
					WHERE id=%d
				]], CA.dbPrefix,
					traffic, traffic_audio, traffic_video, traffic_data,
					traffic_in, app.trafficAudioIn, app.trafficVideoIn, app.trafficDataIn,
					traffic_out, app.trafficAudioOut, app.trafficVideoOut, app.trafficDataOut,
				app.id)), "Failed to update application to database")
				app.trafficAudioIn = 0
				app.trafficVideoIn = 0
				app.trafficDataIn = 0
				app.trafficAudioOut = 0
				app.trafficVideoOut = 0
				app.trafficDataOut = 0
			end
		end
	end
end
