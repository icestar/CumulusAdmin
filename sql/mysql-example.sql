-- Create a developer that is enabled and has some key
INSERT INTO developers (id, enabled, `key`, contact) VALUES (2, '1', 'EXAMPLEKEY', 'example@example.org');

-- Create an application that is enabled under some path
INSERT INTO applications (id, enabled, path, developer_id, allow_publish, publish_password, subscribe_callback, unsubscribe_callback) VALUES (2, '1', '/example', 2, '1', 'PUBPASS', 'onRelayConnect', 'onPeerDisconnect');
