#if defined _timer_included
#endinput
#endif
#define _timer_included

#pragma semicolon 1

#define PL_VERSION "1.0.7"
#define PLUGIN_PREFIX "\x0700FFBF[Timer] \x01%t"

#define MAX_MAPNAME_LENGTH	32
#define MAX_AUTHID_LENGTH	64

enum MapZoneType
{
	Start,
	End,
	Glitch1,
	Glitch2,
	Glitch3
}

enum MapZone
{
	Id,
	MapZoneType:Type,
	String:Map[MAX_MAPNAME_LENGTH],
	Float:Point1[3],
	Float:Point2[3]
}

/**
 * Called when a timer starts.
 *
 * @param client		The owner of the timer.
 *
 * @noreturn
 */
forward OnTimerStarted(client);

/**
 * Called when a timer stops.
 *
 * @param client		The owner of the timer.
 *
 * @noreturn
 */
forward OnTimerStopped(client);

/**
 * Called when a timer restarts.
 *
 * @param client		The owner of the timer.
 *
 * @noreturn
 */
forward OnTimerRestart(client);

/**
 * Called when a timer pauses.
 *
 * @param client		The owner of the timer.
 *
 * @noreturn
 */
forward OnTimerPause(client);

/**
 * Called when a timer continues.
 *
 * @param client		The owner of the timer.
 *
 * @noreturn
 */
forward OnTimerResume(client);

/**
 * Called when a round finishes.
 *
 * @param client			The client who finished the round.
 * @param map
 * @param jumps				Number of jumps.
 * @param flashbangs		Number of flashbangs.
 * @param physicsDifficulty	Difficulty index.
 * @param fpsmax			Value of fps_max convar.
 * @param timeString		Time string.
 * @param timeDiffString	Time difference string.
 * @param position			Position of player.
 * @param totalrank			Total number of player which finished the map.
 * @param overwrite			Indicates if new round is better than older.
 *
 * @noreturn
 */

forward OnFinishRound(client, const String:map[], jumps, flashbangs, physicsDifficulty, fpsmax, const String:timeString[], const String:timeDiffString[], position, totalrank, bool:overwrite);

/**
 * Starts the timer for a client.
 *
 * @param client    	The client to start the timer for.
 *
 * @return True on success, false on failure.
 */
native bool:Timer_Start(client);

/**
 * Stops the timer for a client.
 *
 * @param client    	The client to stop the timer for.
 * @param stopPaused   	Whether or not a paused timer should be stopped. 
 *
 * @return True on success, false on failure.
 */
native bool:Timer_Stop(client, bool:stopPaused = true);

/**
 * Restarts the timer for a client.
 *
 * @param client    	The client to restart the timer for.
 *
 * @return True on success, false on failure.
 */
native bool:Timer_Restart(client);

/**
 * Pauses the timer for a client.
 *
 * @param client    	The client to pause the timer for.
 *
 * @return True on success, false on failure.
 */
native bool:Timer_Pause(client);

/**
 * Continues the timer for a client.
 *
 * @param client    	The client to resume the timer for.
 *
 * @return True on success, false on failure.
 */
native bool:Timer_Resume(client);

/**
 * DEPRECATED: Use Timer_GetBestRecord instead.
 */
native bool:Timer_GetBestRound(client, const String:map[], &Float:time, &jumps, &flashbangs);

/**
 * Fetches the best record for a player.
 *
 * @param client   	 	Client index.
 * @param map			
 * @param difficulty
 * @param time			A reference to the time of the round.
 * @param jumps			A reference to the count of the jumps in that round.
 * @param fpsmax 		A reference to the client fpsmax value.
 * @param flashbangs	A reference to the count of the flashbangs in that round.
 *
 * @return True on success, false on failure.
 */
native bool:Timer_GetBestRecord(client, const String:map[] = "", difficulty = -1, &Float:time, &jumps, &fpsmax, &flashbangs);

/**
 * Gets the current active timer for a player
 *
 * @param client    	The client to get the timer for.
 * @param enabled		A reference to the state of the round.
 * @param time			A reference to the time that the round took so far.
 * @param jumps			A reference to the count of the jumps in that round.
 * @param fpsmax		A reference to the client fpsmax value.
 *
 * @return True on success, false on failure.
 */
native bool:Timer_GetClientTimer(client, &enabled, &Float:time, &jumps, &fpsmax, &flashbangs);

/**
 * Finishes a round.
 *
 * @param client    	The client that finishes the round.
 * @param map			The map of the round.
 * @param time			The time of the round, in seconds.
 * @param jumps			The count of the jumps in that round.
 * @param flashbangs	The count of the flashbangs in that round.
 * @param fpsmax		The fpsmax value of the client.
 *
 * @noreturn
 */
native Timer_FinishRound(client, const String:map[], Float:time, jumps, flashbangs, physicsDifficulty, fpsmax);

/**
 * Reloads the best round cache.
 *
 * @noreturn
 */
native Timer_ForceReloadBestRoundCache();

/**
 * Returns total rank on current map.
 *
 * @return Integer number of total rank.
 */
native Timer_GetTotalRank(bool:update = false);

/**
 * Returns current rank of player on current map.
 *
 * @return Integer number of current rank.
 */
native Timer_GetCurrentRank(client, bool:update = false);


stock Timer_SecondsToTime(Float:seconds, String:buffer[], maxlength, bool:precision = true)
{
	new t = RoundToFloor(seconds);
	
	new hour, mins;
	
	if (t >= 3600)
	{
		hour = RoundToFloor(t / 3600.0);
		t %= 3600;
	}
	
	if (t >= 60)
	{
		mins = RoundToFloor(t / 60.0);
		t %= 60;
	}
	
	Format(buffer, maxlength, "");

	if (hour)
	{
		Format(buffer, maxlength, "%s%02d:", buffer, hour);
	}
	
	Format(buffer, maxlength, "%s%02d:", buffer, mins);
	
	if (precision)
	{
		Format(buffer, maxlength, "%s%06.3f", buffer, float(t) + seconds - RoundToFloor(seconds));
	}
	else 
	{
		Format(buffer, maxlength, "%s%02d", buffer, t);
	}
}

stock StringToLower(String:f_sInput[])
{
	new f_iSize = strlen(f_sInput);
	for(new i=0;i<f_iSize;i++)
	{
		f_sInput[i] = CharToLower(f_sInput[i]);
	}
}

public SharedPlugin:__pl_timer = 
{
	name = "timer",
	file = "timer-core.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

public __pl_timer_SetNTVOptional()
{
	MarkNativeAsOptional("Timer_Start");
	MarkNativeAsOptional("Timer_Stop");
	MarkNativeAsOptional("Timer_Restart");
	MarkNativeAsOptional("Timer_Pause");
	MarkNativeAsOptional("Timer_Resume");
	MarkNativeAsOptional("Timer_GetBestRound");
	MarkNativeAsOptional("Timer_GetClientTimer");
	MarkNativeAsOptional("Timer_FinishRound");
	MarkNativeAsOptional("Timer_ForceReloadBestRoundCache");
	MarkNativeAsOptional("Timer_GetTotalRank");
	MarkNativeAsOptional("Timer_GetCurrentRank");
}