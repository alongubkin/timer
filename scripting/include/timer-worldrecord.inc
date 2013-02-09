#if defined _timer_worldrecord_included
#endinput
#endif
#define _timer_worldrecord_included

forward OnTimerDeleteOneRecord(client, Float:time, const String:map[], jumps, difficulty, flashbangs);
native Timer_ForceReloadWorldRecordCache();

public SharedPlugin:__pl_timer_worldrecord = 
{
	name = "timer-worldrecord",
	file = "timer-worldrecord.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

public __pl_timer_worldrecord_SetNTVOptional()
{
	MarkNativeAsOptional("Timer_ForceReloadWorldRecordCache");
}