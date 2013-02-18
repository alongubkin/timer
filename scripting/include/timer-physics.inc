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
 * Sets the client difficulty.
 *
 * @param client    	The client to get the difficulty for.
 * @param difficulty  The new difficulty of the client.
 *
 * @return The difficulty of the client.
 */
native Timer_SetClientDifficulty(client, difficulty);

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

/**
 * Gets the total amount of loaded difficulties.
 *
 * @return The amount of loaded difficulties.
 */
native Timer_GetDifficultyCount();

/**
 * Gets the details of a difficulty.
 *
 * @param difficulty    	The difficulty id
 * @param details         An array to hold the details.
 *
 * @return The difficulty details.
 */
native Timer_GetDifficultyDetails(difficulty, details[PhysicsDifficulty]);

/**
 * Gets the details of a difficulty by index.
 * Useful when iterating over all difficulties from 0 to Timer_GetDifficulty_Count()
 *
 * @param difficulty    	The difficulty index
 * @param details         An array to hold the details.
 *
 * @return The difficulty details.
 */
native Timer_GetDifficultyDetailsByIndex(difficultyIndex, details[PhysicsDifficulty]);

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
	MarkNativeAsOptional("Timer_SetClientDifficulty");
	MarkNativeAsOptional("Timer_GetDifficultyName");
	MarkNativeAsOptional("Timer_AutoBunny");
	MarkNativeAsOptional("Timer_GetDifficultyCount");
	MarkNativeAsOptional("Timer_GetDifficultyDetails");
	MarkNativeAsOptional("Timer_GetDifficultyDetailsByIndex");
}