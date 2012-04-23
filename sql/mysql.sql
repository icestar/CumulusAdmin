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
  `clients` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `path` (`path`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1 AUTO_INCREMENT=3 ;

INSERT INTO `applications` (`id`, `enabled`, `path`, `developer_id`, `allow_publish`, `publish_password`, `subscribe_callback`, `unsubscribe_callback`, `clients`) VALUES
(1, '0', '', 1, '0', NULL, NULL, NULL, 0),
(2, '1', '/example', 2, '1', NULL, 'onRelayConnect', 'onRelayDisconnect', 0);

CREATE TABLE IF NOT EXISTS `developers` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `enabled` enum('0','1') NOT NULL DEFAULT '1',
  `key` varchar(64) DEFAULT NULL,
  `contact` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM  DEFAULT CHARSET=latin1 AUTO_INCREMENT=3 ;


INSERT INTO `developers` (`id`, `enabled`, `key`, `contact`) VALUES
(1, '0', '', ''),
(2, '1', 'example', 'example@example.org';

CREATE TABLE IF NOT EXISTS `peers` (
  `id` varchar(64) NOT NULL,
  `application_id` int(11) NOT NULL,
  `address` varchar(50) NOT NULL,
  `pageUrl` varchar(255) NOT NULL,
  `swfUrl` varchar(255) NOT NULL,
  `flashVersion` varchar(20) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `application_id` (`application_id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `publications` (
  `application_id` int(10) unsigned NOT NULL,
  `peer_id` varchar(64) NOT NULL,
  `name` varchar(255) NOT NULL,
  `subscribers` int(10) unsigned NOT NULL DEFAULT '0',
  UNIQUE KEY `application_id` (`application_id`,`name`),
  KEY `peer_id` (`peer_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
