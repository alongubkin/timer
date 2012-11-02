#if defined _timer_physics_included
#endinput
#endif
#define _timer_physics_included

enum PhysicsDifficulty
{
	Id,
	String:Name[32],
	bool:IsDefault,
	Float:Stamina,
	Float:Gravity,
	bool:PreventAD,
	bool:PreventBack,
	bool:PreventForward,
	bool:Auto
}

/**
 * Gets the client difficulty.
 *
 * @param client    	The client to get the difficulty for.
 *
 * @return The difficulty of the client.
 */
native Timer_GetClientDifficulty(client);

/**
 * Gets the name of a difficulty.
 *
 * @param client    	The client to get the difficulty for.
 *
 * @return The difficulty of the client.
 */
native Timer_GetDifficultyName(difficulty, String:name[], maxlength);

/**
 * Indicates if Auto bunnyhop is enabled for client.
 *
 * @param client    	The client to check for Auto bunnyhop.
 *
 * @return True on success, false on failure.
 */
native bool:Timer_AutoBunny(client);


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
	MarkNativeAsOptional("Timer_AutoBunny");
}