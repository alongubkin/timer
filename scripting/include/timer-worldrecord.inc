#if defined _timer_worldrecord_included
#endinput
#endif
#define _timer_worldrecord_included

enum RecordCache
{
	Id,
	String:Name[MAX_NAME_LENGTH],
	Float:Time,
	String:TimeString[16],
	Jumps,
	Flashbangs,
	RecordPhysicsDifficulty,
	String:Auth[64],
	bool:Ignored
}

/**
 * Called when a record of a currently connected player is deleted from the database.
 *
 * @param client        The client whichs record was deleted
 * @param time          The time of the record
 * @param map           The map this record was made on
 * @param jumps         The amount of times the player jumped during that record
 * @param flashbangs    The amount of thrown flashbangs during that record
 *
 * @noreturn
 */
forward OnTimerDeleteOneRecord(client, Float:time, const String:map[], jumps, difficulty, flashbangs);

/**
 * Called when the word record cache gets reloaded.
 * @noreturn
 */
forward OnTimerWorldRecordCacheLoaded();

/**
 * Refetch the world records from the database.
 * @noreturn
 */
native Timer_ForceReloadWorldRecordCache();

/**
 * Get the details of the best time in a difficulty
 * or the best time over all, if difficulty = -1.
 *
 * @param difficulty      The difficulty to get details of best time
 * @param iRecord         An array to hold the record data.
 *
 * @return                true, if there was a record for that difficulty, false otherwise.
 */
native bool:Timer_GetWorldRecordForDifficulty(difficulty, iRecord[RecordCache]);

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
	MarkNativeAsOptional("Timer_GetWorldRecordForDifficulty");
}