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

CAdbDriver = "mysql"
CAdbHost = "localhost"
CAdbPort = 3306
CAdbName = "cumulus"
CAdbUser = "root"
CAdbPass = ""
CAdbPrefix = ""
CAupdateInterval = 60

if cumulus.configs.admin.db_driver then
	CAdbDriver = cumulus.configs.admin.db_driver
end
if cumulus.configs.admin.db_host then
	CAdbHost = cumulus.configs.admin.db_host
end
if cumulus.configs.admin.db_port then
	CAdbPort = cumulus.configs.admin.db_port
end
if cumulus.configs.admin.db_name then
	CAdbName = cumulus.configs.admin.db_name
end
if cumulus.configs.admin.db_user then
	CAdbUser = cumulus.configs.admin.db_user
end
if cumulus.configs.admin.db_pass then
	CAdbPass = cumulus.configs.admin.db_pass
end
if cumulus.configs.admin.db_prefix then
	CAdbPrefix = cumulus.configs.admin.db_prefix
end
if cumulus.configs.admin.update_interval then
	CAupdateInterval = cumulus.configs.admin.update_interval
end

-- Custom NOTE function
function CA_NOTE(s)
	NOTE("[CA] "..s)
end

-- Custom WARN function
function CA_WARN(s)
	WARN("[CA] "..s)
end

-- Custom ERROR function
function CA_ERROR(s)
	ERROR("[CA] "..s)
end

NOTE("Initializing CumulusAdmin[CA] (http://www.openrtmfp.net)")
-- See: http://www.keplerproject.org/luasql/
local CAdbSource = CAdbDriver.."://"..CAdbHost..":"..CAdbPort.."/"..CAdbName
if CAdbPass and CAdbPass ~= "" then
	CA_NOTE("Connecting to "..CAdbSource.." as '"..CAdbUser.."' using password (prefix='"..CAdbPrefix.."')")
else
	CA_NOTE("Connecting to "..CAdbSource.." as '"..CAdbUser.."' not using password (prefix='"..CAdbPrefix.."')")
end
CAdb = nil
CAcon = nil
if CAdbDriver == "mysql" then
	require "luasql.mysql"
	CAdb = assert(luasql.mysql(), "Failed to get MySQL handle: Is the MySQL driver installed?")
	CAcon = assert(CAdb:connect(CAdbName, CAdbUser, CAdbPass, CAdbHost, CAdbPort), "Failed to connect to database via MySQL")
elseif CAdbDriver == "postgres" then
	require "luasql.postgres"
	CAdb = assert(luasql.postgres(), "Failed to get Postgres handle: Is the Postgres driver installed?")
	CAcon = assert(CAdb:connect(CAdbName, CAdbUser, CAdbPass, CAdbHost, CAdbPort), "Failed to connect to database via Postgres")
else
	require "luasql.odbc"
	CAdb = assert(luasql.odbc(), "Failed to get ODBC handle: Is the ODBC driver installed?")
	CAcon = assert(CAdb:connect(CAdbSource, CAdbUser, CAdbPass), "Failed to connect to database via ODBC")
end

if not loaded then -- this are our defaults
	CAapp = nil -- Application descriptor
	CAappUpdateTime = nil -- Last application update time
	CAappPath = nil -- Remembered app path
	CAappClients = 0 -- Number of connected clients to this app
	CAappClientsCounter = 0 -- Incrementing clients counter
	CAappGroups = 0 -- Number of groups in this app
	CAappGroupsCounter = 0 -- Incrementing groups counter
	CAdev = nil -- Developer descriptor
	CAreloaded = false
	CAloaded = true
else
	CAreloaded = true
end
CAappUpdateTime = os.time()

-- Called as soon as the application is started
function onStart(path)
	if CAreloaded then
		CA_NOTE("Application "..CAappPath.." has been reloaded")
		return
	end
	CAloaded = true
	CAappPath = path -- store it so we don't leave it
	
	-- If starting the main application, clean up everything
	if path == "" then
		CA_NOTE("Cleaning up previous state")
		CAcon:execute(string.format([[
			"DELETE FROM %spublications_clients"
		]], CAdbPrefix))
		CAcon:execute(string.format([[
			"DELETE FROM %spublications"
		]], CAdbPrefix))
		CAcon:execute(string.format([[
			"DELETE FROM %sgroups_clients"
		]], CAdbPrefix))
		CAcon:execute(string.format([[
			"DELETE FROM %sgroups"
		]], CAdbPrefix))
		CAcon:execute(string.format([[
			"DELETE FROM %sclients"
		]], CAdbPrefix))
	end
	CAapp = loadapp(path)
	if not CAapp then
		if path == "" then
			CA_WARN("Master application could not be found in the database and will be disabled")
		else
			CA_WARN("Application ?:"..path.." could not be found in the database and will be disabled")
		end
		return
	end
	if CAapp.enabled == "0" then
		if path == "" then
			CA_NOTE("Master application "..CAapp.id.." is disabled by configuration")
		else
			CA_NOTE("Application "..CAapp.id..":"..CAapp.path.." is disabled by configuration")
		end
		return
	end
	if CAapp.developer_id and CAapp.developer_id ~= "" and CAapp.developer_od ~= "0" then
		CAdev = loaddev(CAapp.developer_id)
		if not CAdev then
			if path == "" then
				CA_WARN("Master application "..CAapp.id.." has an invalid developer set (id="..CAapp.developer_id..") and thus is disabled")
			else
				CA_WARN("Application "..CAapp.id..":"..CAapp.path.." has an invalid developer set (id="..CAapp.developer_id..") and thus is disabled")
			end
			return
		end
	else
		if path == "" then
			CA_WARN("Master application "..CAapp.id.." has no developer set and thus is disabled")
		else
			CA_WARN("Application "..CAapp.id..":"..CAapp.path.." has no developer set and thus is disabled")
		end
		return
	end
	if path ~= "" then
		CA_NOTE("Application "..CAapp.id..":"..CAapp.path.." has been started")
	end
end

-- Called as soon as a new client has connected to Cumulus
function onConnection(client, response, connectkey)
	if not CAapp or CAapp.enabled == "0" then
		CA_NOTE("Client "..client.address.." rejected: Application "..CAapp.id..":"..CAapp.path.." is disabled")
		return "Application disabled"
	end
	if not CAdev then
		CA_NOTE("Client "..client.address.." rejected: Application "..CAapp.id..":"..CAapp.path.." has no developer")
		return "Application has no developer"
	elseif CAdev.enabled == "0" then
		CA_NOTE("Client "..client.address.." rejected: Developer "..CAdev.id.." is disabled")
		return "Developer disabled"
	end
	-- Allow connections only if there is no developer key set or, if it is, the provided key matches
	if CAdev.connectkey and CAdev.connectkey ~= "" and connectkey ~= CAdev.connectkey then
		CA_NOTE("Client "..client.address.." rejected: Invalid key for developer "..CAdev.id)
		return "Invalid developer key"
	end
	CAappClients = CAappClients+1
	CAappClientsCounter = CAappClientsCounter+1
	client.appId = CAapp.id
	client.appClientId = CAappClientsCounter
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." ("..client.address..") connected to application "..CAapp.id..":"..CAapp.path.." ("..CAappClients.." clients)")
	local pageUrl = client.pageUrl
	if pageUrl == nil or pageUrl == "" or pageUrl == "0" then
		pageUrl = nil
	else
		pageUrl = esc(pageUrl)
	end
	local swfUrl = client.swfUrl
	if swfUrl == nil or swfUrl == "" or swfUrl == "0" then
		swfUrl = nil
	else
		swfUrl = esc(swfUrl)
	end
	assert(CAcon:execute(string.format([[
		INSERT INTO %sclients (id, application_id, address, pageUrl, swfUrl, flashVersion)
		VALUES ('%s', %d, %s, %s, %s, %s)
	]], CAdbPrefix, esc(client.id), CAapp.id, quote(client.address), quote(pageUrl), quote(swfUrl), quote(client.flashVersion))), "Failed to insert client into database")
end

-- Called as soon as a client calls publish(...) on a NetStream connected with "CONNECT_TO_FMS"
function onPublish(client, publication, ...)
	if not CAapp or CAapp.enabled == "0" then
		CA_NOTE("Client "..CAapp.id.."-"..client.appClientId.." rejected to publish in application "..client.appId..":"..client.path..": Application is disabled")
		return "Application disabled"
	end
	local pass = unpack(arg)
	-- Allow publishing only if it is generally allowed and there is no password defined or the password matches
	if CAapp.allow_publish == "0" or (CAapp.publish_password and CAapp.publish_password ~= "" and CAapp.publish_password ~= pass) then
		CA_NOTE("Client "..client.appId.."-"..client.appClientId.." ("..client.address..") rejected to publish in application "..CAapp.id..":"..CAapp.path..": Permission denied")
		return "Permission denied"
	end
	publication.clientId = client.id
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." published '"..publication.name.."' to application "..CAapp.id..":"..CAapp.path)
	assert(CAcon:execute(string.format([[
		INSERT INTO %spublications (application_id, client_id, name, subscribers)
		VALUES (%d, '%s', '%s', %d)
	]], CAdbPrefix, CAapp.id, esc(client.id), esc(publication.name), 0)), "Failed to insert publication into database")
end

-- Called as soon as a publication is unpublished either implicitly by Cumulus or explicitly by the client
function onUnpublish(client, publication)
	-- Don't use "app." here, the application may have been disabled
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." unpublished '"..publication.name.."' from application "..client.appId..":"..client.path)
	assert(CAcon:execute(string.format([[
		DELETE FROM %spublications WHERE application_id=%d AND name='%s'
	]], CAdbPrefix, client.appId, esc(publication.name))), "Failed to delete publication from database")
end

-- Called as soon as a client subscribes to a previous made publication by calling play("publicationname") on a NetStream that has been created with "CONNECT_TO_FMS"
function onSubscribe(client, listener)
	if not CAapp or CAapp.enabled == "0" then
		CA_NOTE("Client "..client.appId.."-"..client.appClientId.." rejected to subscribe in application "..client.appId..":"..client.path..": Application has been disabled")
		return "Application disabled"
	end
	local total = listener.publication.listeners.count+1
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." subscribed to '"..publication.name.."' ("..total.." subscribers) in application "..CAapp.id..":"..CAapp.path)
	assert(CAcon:execute(string.format([[
		UPDATE %spublications SET subscribers=%d WHERE application_id=%d AND name='%s'
	]], CAdbPrefix, total, CAapp.id, esc(listener.publication.name))), "Failed to update publication to database")
	assert(CAcon:execute(string.format([[
		INSERT INTO %spublications_clients (publication_name, client_id) VALUES ('%s', '%s')
	]], CAdbPrefix, listener.publication.name, client.id)), "Failed to insert publication/client relation into database")
	if CAapp and CAapp.subscribe_callback and CAapp.subscribe_callback ~= "" then
		local publisher = cumulus.clients(listener.publication.clientId)
		if publisher then
			publisher.writer:writeAMFMessage(CAapp.subscribe_callback, listener.publication.name, client.id, total)
		end
	end
end

-- Called as soon as a client unsubscribes from a publication either implicitly on disconnect or explicitly by a call to close() on the corresponding NetStream
function onUnsubscribe(client, listener)
	-- Don't use "CAapp." here, the application may have been disabled
	local total = listener.publication.listeners_count-1
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." unsubscribed from '"..publication.name.."' ("..total.." subscribers) in application "..client.appId..":"..client.path)
	assert(CAcon:execute(string.format([[
		UPDATE %spublications SET subscribers=%d WHERE application_id=%d AND name='%s'
	]], CAdbPrefix, total, client.appId, esc(listener.publication.name))), "Failed to update publication to database")
	assert(CAcon:execute(string.format([[
		DELETE FROM %spublications_clients WHERE publication_name='%s' AND client_id='%s'
	]], CAdbPrefix, listener.publication.name, client.id)), "Failed to delete publication/client relation from database")
	-- Check it!
	if CAapp and CAapp.unsubscribe_callback and CAapp.unsubscribe_callback ~= "" then
		local publisher = cumulus.clients(listener.publication.clientId)
		if publisher then
			publisher.writer:writeAMFMessage(CAapp.unsubscribe_callback, listener.publication.name, client.id, total)
		end
	end
end

-- Called as soon as a client joins or creates a group
function onJoinGroup(client, group)
	if not CAapp or CAapp.enabled == "0" then
		CA_NOTE("Client "..client.appId.."-"..client.appClientId.." has been rejected to join a group: Application is disabled")
		return "Application is disabled"
	end
	if group.size == 1 then
		CAappGroups = CAappGroups+1
		CAappGroupsCounter = CAappGroupsCounter+1
		group.appId = CAapp.id
		group.appGroupId = CAappGroupsCounter
		assert(CAcon:execute(string.format([[
			INSERT INTO %sgroups (id, application_id, members) VALUES ('%s', %d, %d)
		]], CAdbPrefix, esc(group.id), CAapp.id, 1)), "Failed to insert group into database")
	else
		assert(CAcon:execute(string.format([[
			UPDATE %sgroups SET members=%d WHERE id='%s'
		]], CAdbPrefix, group.size, esc(group.id))), "Failed to update group to database")
	end
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." joined to group "..group.appId.."_"..group.appGroupId.." ("..group.size.." members)")
	assert(CAcon:execute(string.format([[
		INSERT INTO %sgroups_clients (group_id, client_id) VALUES ('%s', '%s')
	]], CAdbPrefix, esc(group.id), esc(client.id))), "Failed to insert group/client relation into database")
end

-- Called as soon as a client leaves a group
function onUnjoinGroup(client, group)
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." left group "..group.appId.."_"..group.appGroupId)
	assert(CAcon:execute(string.format([[
		DELETE FROM %sgroups_clients WHERE group_id='%s' AND client_id='%s'
	]], CAdbPrefix, esc(group.id), esc(client.id))), "Failed to delete group/client relation from database")
	if group.size == 0 then
		CAappGroups = CAappGroups-1
		assert(CAcon:execute(string.format([[
			DELETE FROM %sgroups WHERE id='%s'
		]], CAdbPrefix, esc(group.id))), "Failed to delete group from database")
	else
		assert(CAcon:execute(string.format([[
			UPDATE %sgroups SET members=%d WHERE id='%s'
		]], CAdbPrefix, group.size, esc(group.id))), "Failed to update group to database")
	end
end

-- Called as soon as a client has disconnected from Cumulus for whatever local or remote reason
function onDisconnection(client, ...)
	CAappClients = CAappClients-1
	CA_NOTE("Client "..client.appId.."-"..client.appClientId.." disconnected from application "..client.appId..":"..client.path.." ("..CAappClients.." clients)")
	assert(CAcon:execute(string.format([[
		DELETE FROM %sclients WHERE id='%s'
	]], CAdbPrefix, esc(client.id))), "Failed to delete client from database")
end

-- Called as soon as the application is stopped, usually when Cumulus is shut down gracefully
function onStop(path)
	if CAapp then
		if path ~= "" then
			CA_NOTE("Application "..CAapp.id..":"..CAapp.path.." has been unloaded")
		end
	else
		CA_NOTE("Application ?:"..CAappPath.." has been unloaded")
	end
end

-- Called every 2 seconds
function onManage()
	local now = os.time()
	if (CAappUpdateTime < now-CAupdateInterval) then -- update from database every updateInterval seconds
		CAappUpdateTime = now
		local appData = loadapp(CAappPath)
		if CAapp and not appData then
			if CAapp.enabled == "1" then
				CA_WARN("Application "..CAapp.id..":"..CAapp.path.." has been deleted from the database and will be disabled")
			else
				CA_NOTE("Application "..CAapp.id..":"..CAapp.path.." has been deleted from the database (already disabled)")
			end
		elseif not CAapp and appData then
			if appData.enabled == "1" then
				CA_NOTE("Application "..appData.id..":"..appData.path.." has been re-created and enabled")
			else
				CA_NOTE("Application "..appData.id..":"..appData.path.." has been re-created (still disabled)")
			end
		elseif CAapp.enabled == "0" and appData.enabled == "1" then
			CA_NOTE("Application "..appData.id..":"..appData.path.." has been enabled")
		elseif CAapp.enabled == "1" and appData.enabled == "0" then
			CA_NOTE("Application "..appData.id..":"..appData.path.." has been disabled")
		end
		CAapp = appData
	end
end

-- Loads a developer from the database
function loaddev(id)
	local cur = assert(CAcon:execute(string.format([[
		SELECT id, enabled, connectkey FROM %sdevelopers WHERE id=%d
	]], CAdbPrefix, id)), "Failed to fetch developer from database")
	if not cur or cur:numrows() == 0 then
		return nil
	end
	return cur:fetch({}, "a")
end

-- Loads an app from the database
function loadapp(path)
	local cur = assert(CAcon:execute(string.format([[
		SELECT id, enabled, path, developer_id, allow_publish, publish_password, subscribe_callback, unsubscribe_callback FROM %sapplications WHERE path='%s'
	]], CAdbPrefix, esc(path))), "Failed to fetch application from database")
	if not cur or cur:numrows() == 0 then
		return nil
	end
	return cur:fetch({}, "a")
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