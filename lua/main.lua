--
-- CumulusAdmin
--
-- See the LICENSE file for license information
-- (c) OpenRTMFP.net
--

-- Configure the database driver you like to use, see: http://www.keplerproject.org/luasql/
require "luasql.mysql"
local db = assert(luasql.mysql())
con = assert(db::connect("database", "user", "password", "localhost", 3306))


--
-- No need to change anything below
--
local app = nil
local dev = nil

-- Cleans up the database for the given application
function cleanup(app)
	NOTE("Cleaning up application "..app.id..":"..app.path)
	con:execute(string.format([[
		DELETE FROM peers WHERE application_id=%d
	]], app.id))
	con:execute(string.format([[
		DELETE FROM publications WHERE application_id=%d
	]], app.id))
end

-- Called as soon as the application is started
function onStart(path)
	-- If starting the main application, clean up everything
	if path == "" then
		NOTE("Cleaning up previous state")
		con:execute("DELETE FROM peers")
		con:execute("DELETE FROM publications")
	end
	cur = con:execute(string.format([[
		SELECT id, enabled, path, developer_id, allow_publish, subscribe_callback, unsubscribe_callback FROM applications WHERE path='%s'
	]], path))
	if (cur:numrows() == 0) then
		NOTE("Application ?:"..path.." cannot be started: No such application")
		return
	else
		app = cur:fetch({}, "a")
		if app.enabled == "0" then
			if path == "" then
				NOTE("Master application "..app.id.." is disabled by configuration (connections will be rejected)")
			else
				NOTE("Custom application "..app.id..":"..app.path.." is disabled by configuration (connections will be rejected)")
			end
			app = nil
			return
		end
		app.clients = 0
		app.clientsCounter = 0
		cur = con:execute(string.format([[
			SELECT id, enabled, `key` FROM developers WHERE id=%d
		]], app.developer_id))
		if cur:numrows() == 0 then
			NOTE("Application "..app.id..":"..path.." cannot be started: Missing developer "..app.developer_id)
			app = nil
			return
		else
			dev = cur:fetch({}, "a")
			started = true
			if path ~= "" then
				NOTE("Application "..app.id..":"..path.." has been started")
			end
		end
	end
end

-- Called as soon as a new client has connected to Cumulus
function onConnection(client, response, key)
	if not app or app.enabled == "0" then
		NOTE("Client "..client.address.." rejected: Application "..app.id..":"..app.path.." is disabled")
		return "Application disabled"
	end
	if (dev.enabled == "0") then
		NOTE("Client "..client.address.." rejected: Developer account "..dev.id.." is disabled")
		return "Developer account disabled"
	end
	-- Allow connections only if there is there is no developer key set or, if it is, the provided key matches
	if dev.key and dev.key ~= "" and key ~= dev.key then
		NOTE("Client "..client.address.." rejected: Invalid key for developer "..dev.id)
		return "Invalid developer key"
	end
	app.clients = app.clients+1
	app.clientsCounter = app.clientsCounter+1
	client.appId = app.id
	client.appClientId = app.clientsCounter
	NOTE("Client "..app.id.."-"..client.appClientId.." ("..client.address..") connected to application "..app.id..":"..app.path.." ("..app.clients.." clients)")
	con:execute(string.format([[
		INSERT INTO peers (id, application_id, address, pageUrl, swfUrl, flashVersion)
		VALUES ('%s', %d, '%s', '%s', '%s', '%s')
	]], client.id, app.id, client.address, client.pageUrl, client.swfUrl, client.flashVersion))
	return true
end

-- Called as soon as a client calls publish() on a NetStream created with "CONNECT_TO_FMS"
function onPublish(client, publication, ...)
	local pass = unpack(arg)
	-- Allow publishing only if it is generally allowed and there is no password defined or the password matches
	if app.allow_publish == "0" or (app.publish_password and app.publish_password ~= "" and app.publish_password ~= pass) then
		NOTE("Client "..app.id.."-"..client.appClientId.." ("..client.address..") rejected to publish in application "..app.id..":"..app.path..": Not allowed")
		return "Not allowed to publish"
	end
	publication.clientId = client.id
	NOTE("Client "..app.id.."-"..client.appClientId.." published '"..publication.name.."' to application "..app.id..":"..app.path)
	con:execute(string.format([[
		INSERT INTO publications (application_id, peer_id, name, subscribers)
		VALUES (%d, '%s', '%s', %d)
	]], app.id, client.id, publication.name, 0))
end

-- Called as soon as a publication is unpublished either implicitly by Cumulus or explicitly by the client
function onUnpublish(client, publication)
	NOTE("Client "..app.id.."-"..client.appClientId.." unpublished '"..publication.name.."' from application "..app.id..":"..app.path)
	con:execute(string.format([[
		DELETE FROM publications WHERE application_id=%d AND name='%s'
	]], app.id, publication.name))
end

-- Called as soon as a client subscribes to a previous made publication by calling play("publicationname") on a NetStream that has been created with "CONNECT_TO_FMS"
function onSubscribe(client, listener)
	local total = listener.publication.listeners.count+1
	NOTE("Client "..app.id.."-"..client.appClientId.." subscribed to '"..publication.name.."' ("..total.." subscribers) in application "..app.id..":"..app.path)
	con:execute(string.format([[
		UPDATE publications SET subscribers=%d WHERE application_id=%d AND name='%s'
	]], total, app.id, listener.publication.name))
	if app.subscribe_callback and app.subscribe_callback ~= "" then
		local publisher = cumulus.clients(listener.publication.clientId)
		if publisher then
			publisher.writer:writeAMFMessage(app.subscribe_callback, listener.publication.name, client.id, total)
		end
	end
end

-- Called as soon as a client unsubscribes from a publication either implicitly on disconnect or explicitly by a call to close() on the corresponding NetStream
function onUnsubscribe(client, listener)
	local total = listener.publication.listeners_count-1
	NOTE("Client "..app.id.."-"..client.appClientId.." unsubscribed from '"..publication.name.."' ("..total.." subscribers) in application "..app.id..":"..app.path)
	con:execute(string.format([[
		UPDATE publications SET subscribers=%d WHERE application_id=%d AND name='%s'
	]], total, app.id, listener.publication.name))
	if app.unsubscribe_callback and app.unsubscribe_callback ~= "" then
		local publisher = cumulus.clients(listener.publication.clientId)
		if publisher then
			publisher.writer:writeAMFMessage(app.unsubscribe_callback, listener.publication.name, client.id, total)
		end
	end
end

-- Called as soon as a client has disconnected from Cumulus for whatever local or remote reason
function onDisconnection(client, ...)
	app.clients = app.clients-1
	NOTE("Client "..app.id.."-"..client.appClientId.." disconnected from application "..app.id..":"..app.path.." ("..app.clients.." clients)")
	con:execute(string.format([[
		DELETE FROM peers WHERE id='%s']],
		client.id
	))
end

-- Called as soon as the application is stopped, usually when Cumulus is shut down gracefully
function onStop(path)
	cleanup(app)
	if path ~= "" then
		NOTE("Application "..app.id..":"..app.path.." has been stopped")
	end
end
