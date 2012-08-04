Timer
=====

SourceMod Timer plugin for competitive CS:S Bhop, Trikz and XC servers.

About
-----

Timer is all about the competitive Bhop, Trikz and XC experience.

* It is completely **modular** and **extensible**.
* It measures the time and jumps it takes players to finish the map.
* Players can choose their **level of difficulty**. You can add up to 32 levels of difficulty, and change their physical effects on the player.
* It has an **advanced world record system**.
* A map start and end is determined by **map zones**. You can [add map zones in-game](http://www.youtube.com/watch?v=YAX7FAF_N8Q). There are also glitch map zones, that try to stop players from exploiting map bugs that can possibly be used to cheat the timer.
* It has a HUD that displays players their current timer (or if you're a spectator it displays the timer of the player you're spectating).
* It supports MySQL, and theoretically SQLite too (but because of a bug in the old version of SQLite that SM uses, the WR module currently doesn't work with SQLite).
* It supports [Updater](http://forums.alliedmods.net/showthread.php?t=169095) by GoD-Tony.

Some of its functionality existed in some form in [cP mod](http://forums.alliedmods.net/showthread.php?t=118354), among many other features. This plugin is much more focused. It is also modular and extensible - which means you can enable and disable any feature of the plugin, and developers can easily integrate it with their own plugins. If you need the checkpoints functionallity of cP mod, you can use other plugins such as [SM_CheckpointSaver](http://forums.alliedmods.net/showthread.php?t=118215).


Modules
-------

Unless stated otherwise, all modules work independently and do not require other plugins/modules to be loaded. The one exception being timer-core.smx, which is required for the timer to work at all. This means that any modules which you are not using can be disabled.


### Core (timer-core.smx)

The core component of the Timer. It is required for the timer to function. It provides the most of the API, as well as the following commands for players:

* **/restart** - Restarts your timer. If the map zones module is enabled, it will teleport the player to the start map zone.
* **/stop** - Stops your timer.
* **/pause** and **/resume** - Players can pause their timers, and move around the map. When they resume the timer, it'll automatically teleport them to where they paused it.


### Physics (timer-physics.smx)

You can configure different levels of difficulty in your server. Every level of difficulty has certain effect on the player who chooses it. You can easily add or remove levels of difficulty, and change their effects on the player.

For example, one can create an 'easy' difficulty with low gravity and auto jump enabled, a 'hard' difficulty where the A and D keys are disabled, and a 'medium' difficulty with a different value of stamina.

The physics module exposes the **/difficulty** command that allows players to change their level of difficulty.


### Map Zones (timer-mapzones.smx)

For every map, you can add different **map zones**. The plugin has an in-game map zone editor for admins. 

Timer currently supports 5 types of map zones: 

* A **start** map zone that automatically starts the timer for players who inside it,
* An end map zone that stops the timer for a player and adds a new record to the database,
* ... and 3 other 'glitch' map zones that try to stop players from exploiting map bugs that can possibly be used to cheat the timer.


### World Record (timer-worldrecord.smx)

Allows players to view the records for the current map using the **/wr** command. If the physics module is enabled, it will display different world records for each difficulty. This module supports a console version of **wr**, in the same way **status** prints results.

It also provides the **/record** and the **/record <name>** commands to view your or another player's record for the current map. In addition, it provides the **/delete** command, that allows you to delete any of your records in this map.


### HUD (timer-hud.smx)

The HUD module adds a constant hint message for players, showing them their timers. Usually, it shows the time since the timer started, jumps, speed and best times for this map. If the physics module is enabled, it also shows them their current difficulty.

If you're currently spectating someone else, it will show you his timer.


### Logging (timer-logging.smx)

The logging module has 5 different levels of messages: trace, debug, info, warning and error. It logs to *sourcemod/logs/timer-<date>.txt*. You can configure the minimum type of messages that you want in your log (for example: warning and errors only), in *configs/timer/logging.cfg*. 


Installation
------------

Just download the attached zip archive and extract to your sourcemod folder intact. Then navigate to your *configs/* directory and add the following entry in databases.cfg:

	"timer"
	{
			"driver"			"mysql"
			"host"				"<your-database-host>"
			"database"			"<your-database-name>"
			"user"				"<username>"
			"pass"				"<password>"
	}
		
The plugin will automatically create the necessary tables.


Configuration
-------------

For most modules, there is a corresponding cvar configuration file located in cfg/sourcemod/. They will be prefixed with "timer-". 

Besides the cvar configuration files, there is the levels of difficulty configuration, in *configs/timer/difficulties.cfg*.