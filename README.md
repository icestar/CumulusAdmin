CumulusAdmin
============

CumulusAdmin is a database-backed administration tool for <a href="https://github.com/OpenRTMFP/Cumulus">Cumulus</a>, an open source <a href="http://www.adobe.com/products/flash-media-enterprise/rtmfp-faq.html">RTMFP</a> server.

The server side code has been written in LUA that is provided natively by Cumulus. The administration tool itself has been written in PHP and by default it is configured to be backed by a MySQL database. Though, other databases should work, too. We use it at <a href="http://www.openrtmfp.net">OpenRTMFP.net</a> for maintainance and hereby commit it to the Cumulus community for that it will be helpful.


Features
--------

* Manage developers and applications via a database
* Manage developers' keys
* Manage applications identified by a unique path
* Enable/disable certain developers and applications
* Configure if publishing is allowed for client->server streams
* If allowed, optionally set a publishing password
* Configure subscribe/unsubscribe callbacks for publisher->server->subscriber streams to notify the publisher about connected/disconnected subscribers
* Have a complete image of peers and publications inside the database, e.g. for live statistics


Examples for subscribe/unsubscribe callbacks
--------------------------------------------

* onRelayConnect(publicationName:String, connecedPeerId:String, totalSubscribers:Number):void
* onRelayDisconnect(publicationName:String, disconnectedPeerId:String, remainingSubscribers:Number):void
* These callbacks for example allow to dynamically start/stop a stream depending on the subscriber count, mostly to save server bandwidth

SQL scheme
----------

Table "developers":
* id:Number
* enabled:0|1
* key:String|NULL
* contact:String|NULL

Table "applications":
* id:Number
* enabled:0|1
* path:String
* developer_id:Number
* allow_publish:0|1
* publish_password:String|NULL
* subscribe_callback:String|NULL
* unsubscribe_callback:String|NULL

Table "peers":
* id:String
* application_id:Number
* address:String[host:port]
* pageUrl:String
* swfUrl:String
* flashVersion:String

Table "publications":
* application_id:Number
* peer_id:Number
* name:String
* subscribers:Number


Things still to do
------------------

* Easy to use PHP administration frontend
* Extend subscribe/unsubscribe callbacks to let the publisher decide if a subscriber is allowed to connect
* Configuration via CumulusServer.ini
* Automatic refetching of developers and applications without the requirement for a server restart
* Decide what to do about the requirement to create empty directories with empty main.lua's for each application


License
-------
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
