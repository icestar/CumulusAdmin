SET SQL_MODE="NO_AUTO_VALUE_ON_ZERO";

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;

CREATE TABLE IF NOT EXISTS `applications` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `enabled` enum('0','1') NOT NULL DEFAULT '0',
  `path` varchar(100) NOT NULL,
  `developer_id` int(10) unsigned NOT NULL,
  `allow_publish` enum('0','1') NOT NULL DEFAULT '0',
  `publish_password` varchar(200) DEFAULT NULL,
  `subscribe_callback` varchar(50) DEFAULT NULL,
  `unsubscribe_callback` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `path` (`path`),
  KEY `developer_id` (`developer_id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1;

INSERT INTO `applications` VALUES(1, '0', '', 1, '0', NULL, NULL, NULL);
INSERT INTO `applications` VALUES(2, '1', '/example', 2, '1', NULL, 'onRelayPeerConnect', 'onRelayPeerDisconnect');

CREATE TABLE IF NOT EXISTS `clients` (
  `id` varchar(64) NOT NULL,
  `application_id` int(10) unsigned NOT NULL,
  `address` varchar(50) NOT NULL,
  `pageUrl` varchar(255) DEFAULT NULL,
  `swfUrl` varchar(255) DEFAULT NULL,
  `flashVersion` varchar(20) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `application_id` (`application_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `developers` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `enabled` enum('0','1') NOT NULL DEFAULT '1',
  `connectkey` varchar(64) DEFAULT NULL,
  `contact` varchar(255) DEFAULT NULL,
  `password` varchar(64) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB  DEFAULT CHARSET=latin1;

INSERT INTO `developers` VALUES(1, '0', '', '', NULL);
INSERT INTO `developers` VALUES(2, '1', 'YOURCONNECTKEY', 'example@example.org', NULL);

CREATE TABLE IF NOT EXISTS `groups` (
  `id` varchar(64) NOT NULL,
  `application_id` int(10) unsigned NOT NULL,
  `members` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `application_id` (`application_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `groups_clients` (
  `group_id` varchar(64) NOT NULL,
  `client_id` varchar(64) NOT NULL,
  UNIQUE KEY `group_id` (`group_id`,`client_id`),
  KEY `client_id` (`client_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `publications` (
  `application_id` int(10) unsigned NOT NULL,
  `client_id` varchar(64) NOT NULL,
  `name` varchar(255) NOT NULL,
  `subscribers` int(10) unsigned NOT NULL DEFAULT '0',
  UNIQUE KEY `name` (`name`),
  KEY `application_id` (`application_id`),
  KEY `client_id` (`client_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `publications_clients` (
  `publication_name` varchar(255) NOT NULL,
  `client_id` varchar(64) NOT NULL,
  UNIQUE KEY `publication_name` (`publication_name`,`client_id`),
  KEY `client_id` (`client_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;


ALTER TABLE `applications`
  ADD CONSTRAINT `applications_ibfk_1` FOREIGN KEY (`developer_id`) REFERENCES `developers` (`id`) ON UPDATE CASCADE;

ALTER TABLE `clients`
  ADD CONSTRAINT `clients_ibfk_1` FOREIGN KEY (`application_id`) REFERENCES `applications` (`id`) ON UPDATE CASCADE;

ALTER TABLE `groups`
  ADD CONSTRAINT `groups_ibfk_1` FOREIGN KEY (`application_id`) REFERENCES `applications` (`id`) ON UPDATE CASCADE;

ALTER TABLE `groups_clients`
  ADD CONSTRAINT `groups_clients_ibfk_2` FOREIGN KEY (`client_id`) REFERENCES `clients` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `groups_clients_ibfk_1` FOREIGN KEY (`group_id`) REFERENCES `groups` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE `publications`
  ADD CONSTRAINT `publications_ibfk_1` FOREIGN KEY (`application_id`) REFERENCES `applications` (`id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `publications_ibfk_2` FOREIGN KEY (`client_id`) REFERENCES `clients` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE `publications_clients`
  ADD CONSTRAINT `publications_clients_ibfk_1` FOREIGN KEY (`publication_name`) REFERENCES `publications` (`name`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `publications_clients_ibfk_2` FOREIGN KEY (`client_id`) REFERENCES `clients` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;
