#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <smlib/arrays>

#include <timer>
#include <timer-logging>

#undef REQUIRE_PLUGIN
#include <timer-physics>
#include <updater>

#define UPDATE_URL "http://dl.dropbox.com/u/16304603/timer/updateinfo-timer-core.txt"

/** 
* Global Enums
*/
enum Timer
{
	Enabled,
	Float:StartTime,
	Float:EndTime,
	Jumps,
	Flashbangs,
	bool:IsPaused,
	Float:PauseStartTime,
	Float:PauseLastOrigin[3],
	Float:PauseLastVelocity[3],
	Float:PauseLastAngles[3],
	Float:PauseTotalTime,
	FpsMax
}

enum BestTimeCacheEntity
{
	IsCached,
	Jumps,
	Flashbangs,
	Float:Time
}

/**
* Global Variables
*/
new Handle:g_hSQL;

new String:g_sCurrentMap[32];
new g_iReconnectCounter = 0;

new g_timers[MAXPLAYERS+1][Timer];
new g_bestTimeCache[MAXPLAYERS+1][BestTimeCacheEntity];

new g_iTotalRankCache;

new Handle:g_hTimerStartedForward;
new Handle:g_hTimerStoppedForward;
new Handle:g_hTimerRestartForward;

new Handle:g_hCvarRestartEnabled = INVALID_HANDLE;
new Handle:g_hCvarStopEnabled = INVALID_HANDLE;
new Handle:g_hCvarPauseResumeEnabled = INVALID_HANDLE;
new Handle:g_hCvarShowJumps = INVALID_HANDLE;
new Handle:g_hCvarShowFlashbangs = INVALID_HANDLE;

new bool:g_bRestartEnabled = true;
new bool:g_bStopEnabled = true;
new bool:g_bPauseResumeEnabled = true;
new bool:g_bShowJumps = true;
new bool:g_bShowFlashbangs = false;

new bool:g_bTimerPhysics = false;
new g_fVelocity;

public Plugin:myinfo =
{
	name        = "[Timer] Core",
	author      = "alongub | Glite",
	description = "Core component for [Timer]",
	version     = PL_VERSION,
	url         = "https://github.com/alongubkin/timer"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("timer");
	
	CreateNative("Timer_Start", Native_TimerStart);
	CreateNative("Timer_Stop", Native_TimerStop);
	CreateNative("Timer_Restart", Native_TimerRestart);
	CreateNative("Timer_GetBestRound", Native_GetBestRound);
	CreateNative("Timer_GetClientTimer", Native_GetClientTimer);
	CreateNative("Timer_FinishRound", Native_FinishRound);
	CreateNative("Timer_ForceReloadBestRoundCache", Native_ForceReloadBestRoundCache);
	CreateNative("Timer_GetTotalRank", Native_GetTotalRank);

	return APLRes_Success;
}

public OnPluginStart()
{
	CreateConVar("timer_version", PL_VERSION, "Timer Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	g_hTimerStartedForward = CreateGlobalForward("OnTimerStarted", ET_Event, Param_Cell);
	g_hTimerStoppedForward = CreateGlobalForward("OnTimerStopped", ET_Event, Param_Cell);
	g_hTimerRestartForward = CreateGlobalForward("OnTimerRestart", ET_Event, Param_Cell);

	g_fVelocity = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");
	g_bTimerPhysics = LibraryExists("timer-physics");
	
	LoadTranslations("timer.phrases");
	
	HookEvent("player_jump", Event_PlayerJump);
	HookEvent("player_death", Event_StopTimer);
	HookEvent("player_team", Event_StopTimer);
	HookEvent("player_spawn", Event_StopTimer);
	HookEvent("player_disconnect", Event_StopTimer);
	HookEvent("player_connect", Event_StopTimer);
	HookEvent("weapon_fire", Event_WeaponFire);
	
	
	RegConsoleCmd("sm_restart", Command_Restart);
	RegConsoleCmd("sm_r", Command_Restart);
	RegConsoleCmd("sm_stop", Command_Stop);
	RegConsoleCmd("sm_pause", Command_Pause);
	RegConsoleCmd("sm_resume", Command_Resume);
	
	g_hCvarRestartEnabled = CreateConVar("timer_restart_enabled", "1", "Whether or not players can restart their timers.");
	g_hCvarStopEnabled = CreateConVar("timer_stop_enabled", "1", "Whether or not players can stop their timers.");
	g_hCvarPauseResumeEnabled = CreateConVar("timer_pauseresume_enabled", "1", "Whether or not players can resume or pause their timers.");
	g_hCvarShowJumps = CreateConVar("timer_showjumpsinfinishmessage", "1", "Whether or not players will see jumps in finish message.");
	g_hCvarShowFlashbangs = CreateConVar("timer_showflashbangsinfinishmessage", "0", "Whether or not players will see flashbangs in finish message.");
	
	HookConVarChange(g_hCvarRestartEnabled, Action_OnSettingsChange);
	HookConVarChange(g_hCvarStopEnabled, Action_OnSettingsChange);	
	HookConVarChange(g_hCvarPauseResumeEnabled, Action_OnSettingsChange);
	HookConVarChange(g_hCvarShowJumps, Action_OnSettingsChange);
	HookConVarChange(g_hCvarShowFlashbangs, Action_OnSettingsChange);
	
	AutoExecConfig(true, "timer-core");
	
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}	
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "timer-physics"))
	{
		g_bTimerPhysics = true;
	}
	else if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, "timer-physics"))
	{
		g_bTimerPhysics = false;
	}
}

public OnMapStart()
{	
	ConnectSQL();
	
	GetCurrentMap(g_sCurrentMap, sizeof(g_sCurrentMap));
	StringToLower(g_sCurrentMap);
	
	ClearCache();
}

public OnMapEnd()
{
	ClearCache();
}

/**
* Events
*/
public Action:Event_PlayerJump(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (g_timers[client][Enabled] && !g_timers[client][IsPaused])
	{
		g_timers[client][Jumps]++;
	}
	
	return Plugin_Continue;
}

public Action:Event_StopTimer(Handle:event, const String:name[], bool:dontBroadcast)
{
	StopTimer(GetClientOfUserId(GetEventInt(event, "userid")));
	
	return Plugin_Continue;
}

public Action:Event_WeaponFire(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (g_timers[client][Enabled] && !g_timers[client][IsPaused])
	{
		decl String:weapon[32];
		GetEventString(event, "weapon", weapon, sizeof(weapon));
		
		if (StrEqual(weapon, "flashbang"))
		{
			g_timers[client][Flashbangs]++;
		}
	}
	
	return Plugin_Continue;
}

public Action:Command_Restart(client, args)
{
	if (g_bRestartEnabled)
	{
		RestartTimer(client);
	}
	
	return Plugin_Handled;
}

public Action:Command_Stop(client, args)
{
	if (g_bStopEnabled)
	{
		StopTimer(client);
	}
	
	return Plugin_Handled;
}

public Action:Command_Pause(client, args)
{
	if (g_bPauseResumeEnabled)
	{
		PauseTimer(client);
	}
	
	return Plugin_Handled;
}

public Action:Command_Resume(client, args)
{
	if (g_bPauseResumeEnabled)
	{
		ResumeTimer(client);
	}
	
	return Plugin_Handled;
}

public FpsMaxCallback(QueryCookie:cookie, client, ConVarQueryResult:result, const String:cvarName[], const String:cvarValue[])
{
	g_timers[client][FpsMax] = StringToInt(cvarValue);
}

public Action_OnSettingsChange(Handle:cvar, const String:oldvalue[], const String:newvalue[])
{
	if (cvar == g_hCvarRestartEnabled)
	{
		g_bRestartEnabled = bool:StringToInt(newvalue);
	}
	else if (cvar == g_hCvarStopEnabled)
	{
		g_bStopEnabled = bool:StringToInt(newvalue);
	}
	else if (cvar == g_hCvarPauseResumeEnabled)
	{
		g_bPauseResumeEnabled = bool:StringToInt(newvalue);	
	}
	else if (cvar == g_hCvarShowJumps)
	{
		g_bShowJumps = bool:StringToInt(newvalue);	
	}
	else if (cvar == g_hCvarShowFlashbangs)
	{
		g_bShowFlashbangs = bool:StringToInt(newvalue);	
	}
}

/**
* Core Functionality
*/
bool:StartTimer(client)
{
	if (!IsPlayerAlive(client))
	{
		return false;
	}
	
	if (g_timers[client][Enabled])
	{
		return false;
	}
	
	g_timers[client][Enabled] = true;
	g_timers[client][StartTime] = GetGameTime();
	g_timers[client][EndTime] = -1.0;
	g_timers[client][Jumps] = 0;
	g_timers[client][Flashbangs] = 0;
	g_timers[client][IsPaused] = false;
	g_timers[client][PauseStartTime] = 0.0;
	g_timers[client][PauseTotalTime] = 0.0;
	
	QueryClientConVar(client, "fps_max", FpsMaxCallback, client);
	
	Call_StartForward(g_hTimerStartedForward);
	Call_PushCell(client);
	Call_Finish();
	
	return true;
}

bool:StopTimer(client, bool:stopPaused = true)
{
	if (!g_timers[client][Enabled])
	{
		return false;
	}
	
	if (!stopPaused && g_timers[client][IsPaused])
	{
		return false;
	}
	
	g_timers[client][Enabled] = false;
	g_timers[client][EndTime] = GetGameTime();

	Call_StartForward(g_hTimerStoppedForward);
	Call_PushCell(client);
	Call_Finish();
	
	return true;
}

bool:RestartTimer(client)
{
	if (!IsPlayerAlive(client))
	{
		return false;
	}
	
	Call_StartForward(g_hTimerRestartForward);
	Call_PushCell(client);
	Call_Finish();
	
	return StartTimer(client);
}

bool:PauseTimer(client)
{
	if (!IsPlayerAlive(client))
	{
		return false;
	}
	
	if (!g_timers[client][Enabled] || g_timers[client][IsPaused])
	{
		return false;
	}
	
	g_timers[client][IsPaused] = true;
	g_timers[client][PauseStartTime] = GetGameTime();
	
	new Float:origin[3];
	GetClientAbsOrigin(client, origin);
	Array_Copy(origin, g_timers[client][PauseLastOrigin], 3);
	
	new Float:angles[3];
	GetClientAbsAngles(client, angles);
	Array_Copy(angles, g_timers[client][PauseLastAngles], 3);
	
	new Float:velocity[3];
	GetClientAbsVelocity(client, velocity);
	Array_Copy(velocity, g_timers[client][PauseLastVelocity], 3);
	
	return true;
}

bool:ResumeTimer(client)
{
	if (!IsPlayerAlive(client))
	{
		return false;
	}
	
	if (!g_timers[client][Enabled] || !g_timers[client][IsPaused])
	{
		return false;
	}
	
	g_timers[client][IsPaused] = false;
	g_timers[client][PauseTotalTime] += GetGameTime() - g_timers[client][PauseStartTime];
	
	new Float:origin[3];
	Array_Copy(g_timers[client][PauseLastOrigin], origin, 3);
	
	new Float:angles[3];
	Array_Copy(g_timers[client][PauseLastAngles], angles, 3);
	
	new Float:velocity[3];
	Array_Copy(g_timers[client][PauseLastVelocity], velocity, 3);
	
	TeleportEntity(client, origin, angles, velocity);
	
	return true;
}

bool:GetBestRound(client, const String:map[], &Float:time, &jumps, &flashbangs)
{
	if (!IsClientInGame(client))
	{
		return false;
	}
	
	if (g_bestTimeCache[client][IsCached])
	{			
		time = g_bestTimeCache[client][Time];
		jumps = g_bestTimeCache[client][Jumps];
		flashbangs = g_bestTimeCache[client][Flashbangs];
		
		return true;
	}

	decl String:auth[32];
	GetClientAuthString(client, auth, sizeof(auth));
	
	decl String:query[255], String:error[255];
	FormatEx(query, sizeof(query), "SELECT id, map, auth, time, jumps, flashbangs FROM round WHERE auth = '%s' AND map = '%s' ORDER BY time ASC LIMIT 1", auth, map);
	
	SQL_LockDatabase(g_hSQL);

	new Handle:hQuery = SQL_Query(g_hSQL, query);
	
	if (hQuery == INVALID_HANDLE)
	{
		SQL_GetError(g_hSQL, error, sizeof(error));
		Timer_LogError("SQL Error on GetBestRound: %s", error);
		SQL_UnlockDatabase(g_hSQL);
		return false;
	}

	SQL_UnlockDatabase(g_hSQL); 

	if (SQL_FetchRow(hQuery))
	{			
		time = SQL_FetchFloat(hQuery, 3);
		jumps = SQL_FetchInt(hQuery, 4);
		flashbangs = SQL_FetchInt(hQuery, 5);
		
		g_bestTimeCache[client][IsCached] = true;
		g_bestTimeCache[client][Time] = time;
		g_bestTimeCache[client][Jumps] = jumps;
		g_bestTimeCache[client][Flashbangs] = flashbangs;
		
		CloseHandle(hQuery);
	}
	else
	{
		g_bestTimeCache[client][IsCached] = true;
		g_bestTimeCache[client][Time] = 0.0;
		g_bestTimeCache[client][Jumps] = 0;	
		g_bestTimeCache[client][Flashbangs] = 0;
		
		CloseHandle(hQuery);
		return false;
	}
	
	return true;
}

ClearCache()
{
	for (new client = 1; client <= MaxClients; client++)
	{
		ClearClientCache(client);
	}
}

ClearClientCache(client)
{
	g_bestTimeCache[client][IsCached] = false;
	g_bestTimeCache[client][Jumps] = 0;
	g_bestTimeCache[client][Flashbangs] = 0;
	g_bestTimeCache[client][Time] = 0.0;	
}

FinishRound(client, const String:map[], Float:time, jumps, flashbangs, physicsDifficulty, fpsmax)
{
	if (!IsClientInGame(client))
	{
		return;
	}
	
	if (!IsPlayerAlive(client))
	{
		return;
	}
	
	new Float:fLastTime;
	new iLastJumps, iLastFlashbangs;
	decl String:sTimeDiff[32];
	decl String:sBuffer[32];
	
	if (Timer_GetBestRound(client, map, fLastTime, iLastJumps, iLastFlashbangs))
	{
		fLastTime -= time;			
		if(fLastTime < 0.0)
		{	
			fLastTime *= -1.0;
			Timer_SecondsToTime(fLastTime, sBuffer, sizeof(sBuffer), true);
			FormatEx(sTimeDiff, sizeof(sTimeDiff), "+%s", sBuffer);
		}
		else if(fLastTime > 0.0)
		{
			Timer_SecondsToTime(fLastTime, sBuffer, sizeof(sBuffer), true);
			FormatEx(sTimeDiff, sizeof(sTimeDiff), "-%s", sBuffer);
		}
		else if(fLastTime == 0.0)
		{
			Timer_SecondsToTime(fLastTime, sBuffer, sizeof(sBuffer), true);
			FormatEx(sTimeDiff, sizeof(sTimeDiff), "%s", sBuffer);
		}
	}
	else
	{
		fLastTime = 0.0;
		Timer_SecondsToTime(fLastTime, sBuffer, sizeof(sBuffer), true);
		FormatEx(sTimeDiff, sizeof(sTimeDiff), "%s", sBuffer);
	}
	
	decl String:auth[32];
	GetClientAuthString(client, auth, sizeof(auth));

	decl String:name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	
	decl String:safeName[2 * strlen(name) + 1];
	SQL_EscapeString(g_hSQL, name, safeName, 2 * strlen(name) + 1);

	decl String:query[256];
	FormatEx(query, sizeof(query), "INSERT INTO round (map, auth, time, jumps, physicsdifficulty, name, fpsmax, flashbangs) VALUES ('%s', '%s', %f, %d, %d, '%s', %d, %d);", map, auth, time, jumps, physicsDifficulty, safeName, fpsmax, flashbangs);
	
	SQL_TQuery(g_hSQL, FinishRoundCallback, query, client, DBPrio_High);
	
	decl String:sTimeString[32];
	Timer_SecondsToTime(time, sTimeString, sizeof(sTimeString), true);
	
	decl String:sMessage[256];
	
	FormatEx(sMessage, sizeof(sMessage), PLUGIN_PREFIX, "Round Finish Message", name, sTimeString, sTimeDiff);
	
	if (g_bShowJumps)
	{
		Format(sMessage, sizeof(sMessage), "%s %t", sMessage, "Jumps Message", jumps);
	}
	
	if (g_bShowFlashbangs)
	{
		Format(sMessage, sizeof(sMessage), "%s %t", sMessage, "Flashbangs Message", flashbangs);
	}
	
	if (g_bTimerPhysics)
	{
		new String:difficulty[32];
		Timer_GetDifficultyName(physicsDifficulty, difficulty, sizeof(difficulty));	
		
		Format(sMessage, sizeof(sMessage), "%s %t", sMessage, "Difficulty Message", difficulty);
	}
	
	Format(sMessage, sizeof(sMessage), "%s.", sMessage);
	
	PrintToChatAll(sMessage);
	
}

public FinishRoundCallback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on FinishRound: %s", error);
		return;
	}

	g_bestTimeCache[client][IsCached] = false;
	
	GetTotalRank(g_sCurrentMap);
}

GetTotalRank(const String:map[])
{
	decl String:query[384];
	FormatEx(query, sizeof(query), "SELECT m.id, m.auth, m.time, MAX(m.jumps) jumps, m.physicsdifficulty, m.name FROM round AS m INNER JOIN (SELECT MIN(n.time) time, n.auth FROM round n WHERE n.map = '%s' GROUP BY n.physicsdifficulty, n.auth) AS j ON (j.time = m.time AND j.auth = m.auth) WHERE m.map = '%s' GROUP BY m.physicsdifficulty, m.auth ORDER BY m.time ASC", map, map);
	
	SQL_TQuery(g_hSQL, GetTotalRankCallback, query, _, DBPrio_Low);
}

public GetTotalRankCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on GetTotalRank: %s", error);
		return;
	}

	g_iTotalRankCache = SQL_GetRowCount(hndl);
}

Float:CalculateTime(client)
{
	if (g_timers[client][Enabled] && g_timers[client][IsPaused])
	{
		return g_timers[client][PauseStartTime] - g_timers[client][StartTime] - g_timers[client][PauseTotalTime];
	}
	else
	{
		return (g_timers[client][Enabled] ? GetGameTime() : g_timers[client][EndTime]) - g_timers[client][StartTime] - g_timers[client][PauseTotalTime];
	}
}

ConnectSQL()
{
	if (g_hSQL != INVALID_HANDLE)
	{
		CloseHandle(g_hSQL);
	}
	
	g_hSQL = INVALID_HANDLE;

	if (SQL_CheckConfig("timer"))
	{
		SQL_TConnect(ConnectSQLCallback, "timer");
	}
	else
	{
		Timer_LogError("PLUGIN STOPPED - Reason: no config entry found for 'timer' in databases.cfg - PLUGIN STOPPED");
	}
}

public ConnectSQLCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (g_iReconnectCounter >= 5)
	{
		Timer_LogError("PLUGIN STOPPED - Reason: reconnect counter reached max - PLUGIN STOPPED");
		return;
	}

	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("Connection to SQL database has failed, Reason: %s", error);
		
		g_iReconnectCounter++;
		ConnectSQL();
		
		return;
	}

	decl String:driver[16];
	SQL_GetDriverIdent(owner, driver, sizeof(driver));

	g_hSQL = CloneHandle(hndl);		
	
	if (StrEqual(driver, "mysql", false))
	{
		SQL_FastQuery(g_hSQL, "SET NAMES  'utf8'");
		SQL_TQuery(g_hSQL, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `round` (`id` int(11) NOT NULL AUTO_INCREMENT, `map` varchar(32) NOT NULL, `auth` varchar(32) NOT NULL, `time` float NOT NULL, `jumps` int(11) NOT NULL, `physicsdifficulty` int(11) NOT NULL, `name` varchar(64) NOT NULL, `fpsmax` int(11) NOT NULL, `flashbangs` int(11) NOT NULL, PRIMARY KEY (`id`));");
	}
	else if (StrEqual(driver, "sqlite", false))
	{
		SQL_TQuery(g_hSQL, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `round` (`id` INTEGER PRIMARY KEY, `map` varchar(32) NOT NULL, `auth` varchar(32) NOT NULL, `time` float NOT NULL, `jumps` INTEGER NOT NULL, `physicsdifficulty` INTEGER NOT NULL, `name` varchar(64) NOT NULL, `fpsmax` INTEGER NOT NULL, `flashbangs` INTEGER NOT NULL);");
	}
	
	g_iReconnectCounter = 1;
}

public CreateSQLTableCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{	
	if (owner == INVALID_HANDLE)
	{
		Timer_LogError(error);
		
		g_iReconnectCounter++;
		ConnectSQL();

		return;
	}
	
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on CreateSQLTable: %s", error);
		return;
	}
}

public Native_GetTotalRank(Handle:plugin, numParams)
{
	new bool:update = bool:GetNativeCell(1);
	if (update)
	{
		GetTotalRank(g_sCurrentMap);
	}
	return g_iTotalRankCache;
}

public Native_TimerStart(Handle:plugin, numParams)
{
	return StartTimer(GetNativeCell(1));
}

public Native_TimerStop(Handle:plugin, numParams)
{
	return StopTimer(GetNativeCell(1), bool:GetNativeCell(2));
}

public Native_TimerRestart(Handle:plugin, numParams)
{
	return RestartTimer(GetNativeCell(1));
}

public Native_GetBestRound(Handle:plugin, numParams)
{
	decl String:map[32];
	GetNativeString(2, map, sizeof(map));
	
	new Float:time;
	new jumps, flashbangs;
	
	new bool:success = GetBestRound(GetNativeCell(1), map, time, jumps, flashbangs);

	if (success)
	{
		SetNativeCellRef(3, time);
		SetNativeCellRef(4, jumps);
		SetNativeCellRef(5, flashbangs);
		
		return true;
	}
	
	return false;
}

public Native_GetClientTimer(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	
	SetNativeCellRef(2, g_timers[client][Enabled]);
	SetNativeCellRef(3, CalculateTime(client));
	SetNativeCellRef(4, g_timers[client][Jumps]);
	SetNativeCellRef(5, g_timers[client][FpsMax]);	
	SetNativeCellRef(6, g_timers[client][Flashbangs]);

	return true;
}

public Native_FinishRound(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);

	decl String:map[32];
	GetNativeString(2, map, sizeof(map));
	
	new Float:time = GetNativeCell(3);
	new jumps = GetNativeCell(4);
	new flashbangs = GetNativeCell(5);
	new physicsDifficulty = GetNativeCell(6);
	new fpsmax = GetNativeCell(7);

	FinishRound(client, map, time, jumps, flashbangs, physicsDifficulty, fpsmax);
}

public Native_ForceReloadBestRoundCache(Handle:plugin, numParams)
{
	ClearCache();
}

/**
* Utils methods
*/
stock GetClientAbsVelocity(client, Float:vecVelocity[3])
{
	for (new x = 0; x < 3; x++)
	{
		vecVelocity[x] = GetEntDataFloat(client, g_fVelocity + (x*4));
	}
}