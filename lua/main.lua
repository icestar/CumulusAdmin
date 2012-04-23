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

local dbDriver = "mysql"
local dbHost = "localhost"
local dbPort = 3306
local dbName = "cumulus"
local dbUser = "root"
local dbPass = ""
local dbPrefix = ""
local updateInterval = 60

if cumulus.configs.admin.db_driver then
	dbDriver = cumulus.configs.admin.db_driver
end
if cumulus.configs.admin.db_host then
	dbHost = cumulus.configs.admin.db_host
end
if cumulus.configs.admin.db_port then
	dbPort = cumulus.configs.admin.db_port
end
if cumulus.configs.admin.db_name then
	dbName = cumulus.configs.admin.db_name
end
if cumulus.configs.admin.db_user then
	dbUser = cumulus.configs.admin.db_user
end
if cumulus.configs.admin.db_pass then
	dbPass = cumulus.configs.admin.db_pass
end
if cumulus.configs.admin.db_prefix then
	dbPrefix = cumulus.configs.admin.db_prefix
end
if cumulus.configs.admin.update_interval then
	updateInterval = cumulus.configs.admin.update_interval
end

-- Custom NOTE function
function CA_NOTE(s)
	NOTE("[CumulusAdmin] "..s)
end

-- Custom WARN function
function CA_WARN(s)
	WARN("[CumulusAdmin] "..s)
end

-- Custom ERROR function
function CA_ERROR(s)
	ERROR("[CumulusAdmin] "..s)
end

NOTE("Loading CumulusAdmin (http://www.openrtmfp.net)")
-- See: http://www.keplerproject.org/luasql/
local dbSource = dbDriver.."://"..dbHost..":"..dbPort.."/"..dbName
if dbPass and dbPass ~= "" then
	CA_NOTE("Connecting to "..dbSource.." as '"..dbUser.."' using password (prefix='"..dbPrefix.."')")
else
	CA_NOTE("Connecting to "..dbSource.." as '"..dbUser.."' not using password (prefix='"..dbPrefix.."')")
end
local db = nil
if dbDriver == "mysql" then
	require "luasql.mysql"
	db = assert(luasql.mysql(), "Failed to get MySQL handle: Is the MySQL driver installed?")
	con = assert(db:connect(dbName, dbUser, dbPass, dbHost, dbPort), "Failed to connect to database via MySQL")
elseif dbDriver == "postgres" then
	require "luasql.postgres"
	db = assert(luasql.postgres(), "Failed to get Postgres handle: Is the Postgres driver installed?")
	con = assert(db:connect(dbName, dbUser, dbPass, dbHost, dbPort), "Failed to connect to database via Postgres")
else
	require "luasql.odbc"
	db = assert(luasql.odbc(), "Failed to get ODBC handle: Is the ODBC driver installed?")
	con = assert(db:connect(dbSource, dbUser, dbPass), "Failed to connect to database via ODBC")
end

local app = nil -- Application descriptor
local appUpdateTime = -1 -- Last application update time
local appPath = nil -- Remembered app path
local appClients = 0 -- Number of connected clients to this app
local appClientsCounter = 0 -- Incrementing clients counter
local appGroups = 0 -- Number of groups in this app
local appGroupsCounter = 0 -- Incrementing groups counter
local dev = nil -- Developer descriptor

-- Called as soon as the application is started
function onStart(path)
	appPath = path -- store it so we don't leave it
	
	-- If starting the main application, clean up everything
	if path == "" then
		CA_NOTE("Cleaning up previous state")
		con:execute(string.format([[
			"DELETE FROM %spublications_clients"
		]], dbPrefix))
		con:execute(string.format([[
			"DELETE FROM %spublications"
		]], dbPrefix))
		con:execute(string.format([[
			"DELETE FROM %sgroups_clients"
		]], dbPrefix))
		con:execute(string.format([[
			"DELETE FROM %sgroups"
		]], dbPrefix))
		con:execute(string.format([[
			"DELETE FROM %sclients"
		]], dbPrefix))
	end
	app = loadapp(path)
	if not app then
		if path == "" then
			CA_WARN("Master application could not be found in the database and will be disabled")
		else
			CA_WARN("Application ?:"..path.." could not be found in the database and will be disabled")
		end
		return
	end
	if app.enabled == "0" then
		if path == "" then
			CA_NOTE("Master application "..app.id.." is disabled by configuration")
		else
			CA_NOTE("Application "..app.id..":"..app.path.." is disabled by configuration")
		end
		return
	end
	if app.developer_id and app.developer_id ~= "" and app.developer_od ~= "0" then
		dev = loaddev(app.developer_id)
		if not dev then
			if path == "" then
				CA_WARN("Master application "..app.id.." has an invalid developer set (id="..app.developer_id..") and thus is disabled")
			else
				CA_WARN("Application "..app.id..":"..app.path.." has an invalid developer set (id="..app.developer_id..") and thus is disabled")
			end
			return
		end
	else
		if path == "" then
			CA_WARN("Master application "..app.id.." has no developer set and thus is disabled")
		else
			CA_WARN("Application "..app.id..":"..app.path.." has no developer set and thus is disabled")
		end
		return
	end
	if path ~= "" then
		CA_NOTE("Application "..app.id..":"..app.path.." has been started")
	end
end

-- Called as soon as a new client has connected to Cumulus
function onConnection(client, response, connectkey)
	if not app or app.enabled == "0" then
		CA_NOTE("Client "..client.address.." rejected: Application "..app.id..":"..app.path.." is disabled")
		return "Application disabled"
	end
	if not dev then
		CA_NOTE("Client "..client.address.." rejected: Application "..app.id..":"..app.path.." has no developer")
		return "Application has no developer"
	elseif dev.enabled == "0" then
		CA_NOTE("Client "..client.address.." rejected: Developer "..dev.id.." is disabled")
		return "Developer disabled"
	end
	-- Allow connections only if there is no developer key set or, if it is, the provided key matches
	if dev.connectkey and dev.connectkey ~= "" and connectkey ~= dev.connectkey then
		CA_NOTE("Client "..client.address.." rejected: Invalid key for developer "..dev.id)
		return "Invalid developer key"
	end
	appClients = appClients+1
	appClientsCounter = appClientsCounter+1
	client.appId = app.id
	client.appClientId = appClientsCounter
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." ("..client.address..") connected to application "..app.id..":"..app.path.." ("..appClients.." clients)")
	local pageUrl = client.pageUrl
	if pageUrl == "" or pageUrl == "0" then
		pageUrl = nil
	else
		pageUrl = esc(pageUrl)
	end
	local swfUrl = client.swfUrl
	if swfUrl == "" or swfUrl == "0" then
		swfUrl = nil
	else
		swfUrl = esc(swfUrl)
	end
	assert(con:execute(string.format([[
		INSERT INTO %sclients (id, application_id, address, pageUrl, swfUrl, flashVersion)
		VALUES ('%s', %d, '%s', %s, %s, %s)
	]], dbPrefix, esc(client.id), app.id, esc(client.address), quote(pageUrl), quote(swfUrl), quote(client.flashVersion))), "Failed to insert client into database")
end

-- Called as soon as a client calls publish(...) on a NetStream connected with "CONNECT_TO_FMS"
function onPublish(client, publication, ...)
	if not app or app.enabled == "0" then
		CA_NOTE("Client "..app.id.."-"..client.appClientId.." rejected to publish in application "..client.appId..":"..client.path..": Application is disabled")
		return "Application disabled"
	end
	local pass = unpack(arg)
	-- Allow publishing only if it is generally allowed and there is no password defined or the password matches
	if app.allow_publish == "0" or (app.publish_password and app.publish_password ~= "" and app.publish_password ~= pass) then
		CA_NOTE("Client "..client.appId.."-"..client.appClientId.." ("..client.address..") rejected to publish in application "..app.id..":"..app.path..": Permission denied")
		return "Permission denied"
	end
	publication.clientId = client.id
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." published '"..publication.name.."' to application "..app.id..":"..app.path)
	assert(con:execute(string.format([[
		INSERT INTO %spublications (application_id, client_id, name, subscribers)
		VALUES (%d, '%s', '%s', %d)
	]], dbPrefix, app.id, esc(client.id), esc(publication.name), 0)), "Failed to insert publication into database")
end

-- Called as soon as a publication is unpublished either implicitly by Cumulus or explicitly by the client
function onUnpublish(client, publication)
	-- Don't use "app." here, the application may have been disabled
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." unpublished '"..publication.name.."' from application "..client.appId..":"..client.path)
	assert(con:execute(string.format([[
		DELETE FROM %spublications WHERE application_id=%d AND name='%s'
	]], dbPrefix, client.appId, esc(publication.name))), "Failed to delete publication from database")
end

-- Called as soon as a client subscribes to a previous made publication by calling play("publicationname") on a NetStream that has been created with "CONNECT_TO_FMS"
function onSubscribe(client, listener)
	if not app or app.enabled == "0" then
		CA_NOTE("Client "..client.appId.."-"..client.appClientId.." rejected to subscribe in application "..client.appId..":"..client.path..": Application has been disabled")
		return "Application disabled"
	end
	local total = listener.publication.listeners.count+1
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." subscribed to '"..publication.name.."' ("..total.." subscribers) in application "..app.id..":"..app.path)
	assert(con:execute(string.format([[
		UPDATE %spublications SET subscribers=%d WHERE application_id=%d AND name='%s'
	]], dbPrefix, total, app.id, esc(listener.publication.name))), "Failed to update publication to database")
	assert(con:execute(string.format([[
		INSERT INTO %spublications_clients (publication_name, client_id) VALUES ('%s', '%s')
	]], dbPrefix, listener.publication.name, client.id)), "Failed to insert publication/client relation into database")
	if app and app.subscribe_callback and app.subscribe_callback ~= "" then
		local publisher = cumulus.clients(listener.publication.clientId)
		if publisher then
			publisher.writer:writeAMFMessage(app.subscribe_callback, listener.publication.name, client.id, total)
		end
	end
end

-- Called as soon as a client unsubscribes from a publication either implicitly on disconnect or explicitly by a call to close() on the corresponding NetStream
function onUnsubscribe(client, listener)
	-- Don't use "app." here, the application may have been disabled
	local total = listener.publication.listeners_count-1
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." unsubscribed from '"..publication.name.."' ("..total.." subscribers) in application "..client.appId..":"..client.path)
	assert(con:execute(string.format([[
		UPDATE %spublications SET subscribers=%d WHERE application_id=%d AND name='%s'
	]], dbPrefix, total, client.appId, esc(listener.publication.name))), "Failed to update publication to database")
	assert(con:execute(string.format([[
		DELETE FROM %spublications_clients WHERE publication_name='%s' AND client_id='%s'
	]], dbPrefix, listener.publication.name, client.id)), "Failed to delete publication/client relation from database")
	if app and app.unsubscribe_callback and app.unsubscribe_callback ~= "" then
		local publisher = cumulus.clients(listener.publication.clientId)
		if publisher then
			publisher.writer:writeAMFMessage(app.unsubscribe_callback, listener.publication.name, client.id, total)
		end
	end
end

-- Called as soon as a client joins or creates a group
function onJoinGroup(client, group)
	if not app or app.enabled == "0" then
		CA_NOTE("Client "..client.appId.."-"..client.appClientId.." has been rejected to join a group: Application is disabled")
		return "Application is disabled"
	end
	if group.size == 1 then
		appGroups = appGroups+1
		appGroupsCounter = appGroupsCounter+1
		group.appId = app.id
		group.appGroupId = appGroupsCounter
		assert(con:execute(string.format([[
			INSERT INTO %sgroups (id, application_id, members) VALUES ('%s', %d, %d)
		]], dbPrefix, esc(group.id), app.id, 1)), "Failed to insert group into database")
	else
		assert(con:execute(string.format([[
			UPDATE %sgroups SET members=%d WHERE id='%s'
		]], dbPrefix, group.size, esc(group.id))), "Failed to update group to database")
	end
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." joined to group "..group.appId.."_"..group.appGroupId.." ("..group.size.." members)")
	assert(con:execute(string.format([[
		INSERT INTO %sgroups_clients (group_id, client_id) VALUES ('%s', '%s')
	]], dbPrefix, esc(group.id), esc(client.id))), "Failed to insert group/client relation into database")
end

-- Called as soon as a client leaves a group
function onUnjoinGroup(client, group)
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." left group "..group.appId.."_"..group.appGroupId)
	assert(con:execute(string.format([[
		DELETE FROM %sgroups_clients WHERE group_id='%s' AND client_id='%s'
	]], dbPrefix, esc(group.id), esc(client.id))), "Failed to delete group/client relation from database")
	if group.size == 0 then
		appGroups = appGroups-1
		assert(con:execute(string.format([[
			DELETE FROM %sgroups WHERE id='%s'
		]], dbPrefix, esc(group.id))), "Failed to delete group from database")
	else
		assert(con:execute(string.format([[
			UPDATE %sgroups SET members=%d WHERE id='%s'
		]], dbPrefix, group.size, esc(group.id))), "Failed to update group to database")
	end
end

-- Called as soon as a client has disconnected from Cumulus for whatever local or remote reason
function onDisconnection(client, ...)
	appClients = appClients-1
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." disconnected from application "..client.appId..":"..client.path.." ("..appClients.." clients)")
	assert(con:execute(string.format([[
		DELETE FROM %sclients WHERE id='%s'
	]], dbPrefix, esc(client.id))), "Failed to delete client from database")
end

-- Called as soon as the application is stopped, usually when Cumulus is shut down gracefully
function onStop(path)
	if app then
		cleanup(app)
		if path ~= "" then
			CA_NOTE("Application "..app.id..":"..app.path.." has been stopped")
		end
	else
		CA_NOTE("Application ?:"..appPath.." has been stopped")
	end
end

-- Called every 2 seconds
function onManage()
	local now = os.time()
	if (appUpdateTime < now-updateInterval) then -- update from database every updateInterval seconds
		appUpdateTime = now
		local appData = loadapp(appPath)
		if app and not appData then
			if app.enabled == "1" then
				CA_WARN("Application "..app.id..":"..app.path.." has been deleted from the database and will be disabled")
			else
				CA_NOTE("Application "..app.id..":"..app.path.." has been deleted from the database (already disabled)")
			end
		elseif not app and appData then
			if appData.enabled == "1" then
				CA_NOTE("Application "..appData.id..":"..appData.path.." has been re-created and enabled")
			else
				CA_NOTE("Application "..appData.id..":"..appData.path.." has been re-created (still disabled)")
			end
		elseif app.enabled == "0" and appData.enabled == "1" then
			CA_NOTE("Application "..appData.id..":"..appData.path.." has been enabled")
		elseif app.enabled == "1" and appData.enabled == "0" then
			CA_NOTE("Application "..appData.id..":"..appData.path.." has been disabled")
		end
		app = appData
	end
end

-- Loads a developer from the database
function loaddev(id)
	local cur = assert(con:execute(string.format([[
		SELECT id, enabled, connectkey FROM %sdevelopers WHERE id=%d
	]], dbPrefix, id)), "Failed to fetch developer from database")
	if not cur or cur:numrows() == 0 then
		return nil
	end
	return cur:fetch({}, "a")
end

-- Loads an app from the database
function loadapp(path)
	local cur = assert(con:execute(string.format([[
		SELECT id, enabled, path, developer_id, allow_publish, publish_password, subscribe_callback, unsubscribe_callback FROM %sapplications WHERE path='%s'
	]], dbPrefix, esc(path))), "Failed to fetch application from database")
	if not cur or cur:numrows() == 0 then
		return nil
	end
	return cur:fetch({}, "a")
end

-- Cleans up the database for the given application
function cleanup(app)
	CA_NOTE("Cleaning up application "..app.id..":"..app.path)
	assert(con:execute(string.format([[
		DELETE FROM %spublications WHERE application_id=%d
	]], dbPrefix, app.id)), "Failed to clean up application publications")
	assert(con:execute(string.format([[
		DELETE FROM %sclients WHERE application_id=%d
	]], dbPrefix, app.id)), "Failed to clean up application clients")
end

-- Escapes a string to be used in database queries
function esc(s)
	s = string.gsub(s, "(['\"\\])", "\\%1")
	return (string.gsub(s, "%z", "\\0"))
end

-- Quotes a string to be used in database queries
function quote(s)
	if s == nil then
		return "NULL"
	else
		return "'"..esc(s).."'"
	end
end