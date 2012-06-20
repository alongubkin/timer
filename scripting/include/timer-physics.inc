#if defined _timer_physics_included
 #endinput
#endif
#define _timer_physics_included

native Timer_GetClientDifficulty(client);
native Timer_GetDifficultyName(difficulty, String:name[], maxlength);

public SharedPlugin:__pl_timer_physics = 
{
	name = "timer-physics",
	file = "timer-physics.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

public __pl_timer_physics_SetNTVOptional()
{
	MarkNativeAsOptional("Timer_GetClientDifficulty");
	MarkNativeAsOptional("Timer_GetDifficultyName");
}