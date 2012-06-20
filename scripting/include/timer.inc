#if defined _timer_included
 #endinput
#endif
#define _timer_included

#pragma semicolon 1

#define PL_VERSION "1.0.0-dev"

native bool:Timer_Start(client);
native bool:Timer_Stop(client, bool:stopPaused = true);
native bool:Timer_Restart(client);
native bool:Timer_GetBestRound(client, String:map[], &time, &jumps);
native bool:Timer_GetClientTimer(&enabled, &time, &jumps, &fpsmax);
native Timer_GetMapDifficulty(String:map[]);
native Timer_FinishRound(client, String:map[], Float:time, jumps, physicsDifficulty, fpsmax);
native Timer_ForceReloadBestRoundCache();

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
	MarkNativeAsOptional("Timer_GetBestRound");
	MarkNativeAsOptional("Timer_GetClientTimer");
	MarkNativeAsOptional("Timer_GetMapDifficulty");
	MarkNativeAsOptional("Timer_FinishRound");
	MarkNativeAsOptional("Timer_ForceReloadBestRoundCache");
}