#pragma semicolon 1

#include <sourcemod>
#include <loghelper>
#include <smlib>
#include <timer>

/** 
 * Global Enums
 */
enum Timer
{
	Enabled,
	StartTime,
	EndTime,
	Jumps,
	bool:IsPaused,
	PauseStartTime,
	Float:PauseLastOrigin[3],
	Float:PauseLastVelocity[3],
	Float:PauseLastAngles[3],
	PauseTotalTime,
	FpsMax
}

enum BestTimeCacheEntity
{
	IsCached,
	Jumps,
	Time
}

/**
 * Global Variables
 */
new Handle:g_hSQL;

new String:g_currentMap[32];
new g_reconnectCounter = 0;

new g_timers[MAXPLAYERS+1][Timer];
new g_bestTimeCache[MAXPLAYERS+1][BestTimeCacheEntity];

new Handle:g_timerStartedForward;
new Handle:g_timerStoppedForward;
new Handle:g_timerRestartForward;

new g_iVelocity;

public Plugin:myinfo =
{
    name        = "[Timer] Core",
    author      = "alongub",
    description = "Core component for [Timer]",
    version     = PL_VERSION,
    url         = "http://steamcommunity.com/id/alon"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("timer");
	
	CreateNative("Timer_Start", Native_TimerStart);
	CreateNative("Timer_Stop", Native_TimerStop);
	CreateNative("Timer_Restart", Native_TimerRestart);
	CreateNative("Timer_GetBestRound", Native_GetBestRound);
	// CreateNative("Timer_GetRoundById", Native_GetRoundById);
	CreateNative("Timer_GetClientTimer", Native_GetClientTimer);
	CreateNative("Timer_GetMapDifficulty", Native_GetMapDifficulty);
	CreateNative("Timer_FinishRound", Native_FinishRound);
	CreateNative("Timer_ForceReloadBestRoundCache", Native_ForceReloadBestRoundCache);

	return APLRes_Success;
}

public OnPluginStart()
{
	g_timerStartedForward = CreateGlobalForward("OnTimerStarted", ET_Event, Param_Cell);
	g_timerStoppedForward = CreateGlobalForward("OnTimerStopped", ET_Event, Param_Cell);
	g_timerRestartForward = CreateGlobalForward("OnTimerRestart", ET_Event, Param_Cell);

	g_iVelocity = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");

	HookEvent("player_jump", Event_PlayerJump);

	AddCommandListener(SayCommand, "say");
	AddCommandListener(SayCommand, "say_team");	
}

public OnAllPluginsLoaded()
{
	ConnectSQL();
	// CreateAdminMenu();
}

public OnMapStart()
{
	GetCurrentMap(g_currentMap, sizeof(g_currentMap));
	ClearCache();
}

public OnMapEnd()
{
	ClearCache();
}

/**
 * Events
 */
public Event_PlayerJump(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (g_timers[client][Enabled] && !g_timers[client][IsPaused])
		g_timers[client][Jumps]++;
}

public Action:SayCommand(client, const String:command[], args)
{
	decl String:buffer[128];
	GetCmdArg(1, buffer, sizeof(buffer));

	new bool:hidden = StrEqual(buffer, "/restart", true);
	if (StrEqual(buffer, "!restart", true) || hidden)
	{
		RestartTimer(client);

		if (hidden)
			return Plugin_Handled;
	}

	hidden = StrEqual(buffer, "/stop", true);
	if (StrEqual(buffer, "!stop", true) || hidden)
	{
		StopTimer(client);

		if (hidden)
			return Plugin_Handled;
	}

	hidden = StrEqual(buffer, "/pause", true);
	if (StrEqual(buffer, "!pause", true) || hidden)
	{
		PauseTimer(client);

		if (hidden)
			return Plugin_Handled;
	}

	hidden = StrEqual(buffer, "/resume", true);
	if (StrEqual(buffer, "!resume", true) || hidden)
	{
		ResumeTimer(client);

		if (hidden)
			return Plugin_Handled;
	}

	return Plugin_Continue;
}

public FpsMaxCallback(QueryCookie:cookie, client, ConVarQueryResult:result, const String:cvarName[], const String:cvarValue[])
{
	g_timers[client][FpsMax] = StringToInt(cvarValue);
}

/**
 * Core Functionality
 */
bool:StartTimer(client)
{
	if (g_timers[client][Enabled])
		return false;
	
	g_timers[client][Enabled] = true;
	g_timers[client][StartTime] = GetTime();
	g_timers[client][EndTime] = -1;
	g_timers[client][Jumps] = 0;
	g_timers[client][IsPaused] = false;
	g_timers[client][PauseStartTime] = 0;
	g_timers[client][PauseTotalTime] = 0;

	QueryClientConVar(client, "fps_max", FpsMaxCallback, client);

	Call_StartForward(g_timerStartedForward);
	Call_PushCell(client);
	Call_Finish();

	return true;
}

bool:StopTimer(client, bool:stopPaused = true)
{
	if (!g_timers[client][Enabled])
		return false;
	
	if (!stopPaused && g_timers[client][IsPaused])
		return false;
	
	g_timers[client][Enabled] = false;
	g_timers[client][EndTime] = GetTime();

	Call_StartForward(g_timerStoppedForward);
	Call_PushCell(client);
	Call_Finish();
		
	return true;
}

bool:RestartTimer(client)
{
	StopTimer(client);
	
	Call_StartForward(g_timerRestartForward);
	Call_PushCell(client);
	Call_Finish();

	return StartTimer(client);
}

bool:PauseTimer(client)
{
	if (!g_timers[client][Enabled] || g_timers[client][IsPaused])
		return false;
	
	g_timers[client][IsPaused] = true;
	g_timers[client][PauseStartTime] = GetTime();
	
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
	if (!g_timers[client][Enabled] || !g_timers[client][IsPaused])
		return false;

	g_timers[client][IsPaused] = false;
	g_timers[client][PauseTotalTime] += GetTime() - g_timers[client][PauseStartTime];

	new Float:origin[3];
	Array_Copy(g_timers[client][PauseLastOrigin], origin, 3);

	new Float:angles[3];
	Array_Copy(g_timers[client][PauseLastAngles], angles, 3);

	new Float:velocity[3];
	Array_Copy(g_timers[client][PauseLastVelocity], angles, 3);

	TeleportEntity(client, origin, angles, velocity);

	return true;
}

bool:GetBestRound(client, String:map[], &time, &jumps)
{
	if (IsValidPlayer(client))
	{
		if (g_bestTimeCache[client][IsCached])
		{			
			time = g_bestTimeCache[client][Time];
			jumps = g_bestTimeCache[client][Jumps];
			
			return true;
		}

		decl String:auth[32];
		GetClientAuthString(client, auth, sizeof(auth));
		
		decl String:query[128];
		Format(query, sizeof(query), "SELECT id, map, auth, time, jumps FROM round WHERE auth = '%s' AND map = '%s' ORDER BY time ASC LIMIT 1", auth, map);
		
		SQL_LockDatabase(g_hSQL);
	
		new Handle:hQuery = SQL_Query(g_hSQL, query);
		
		if (hQuery == INVALID_HANDLE)
		{
			SQL_UnlockDatabase(g_hSQL);
			return false;
		}

		SQL_UnlockDatabase(g_hSQL); 

		if (SQL_FetchRow(hQuery))
		{			
			time = SQL_FetchInt(hQuery, 3);
			jumps = SQL_FetchInt(hQuery, 4);
			
			g_bestTimeCache[client][IsCached] = true;
			g_bestTimeCache[client][Time] = time;
			g_bestTimeCache[client][Jumps] = jumps;
			
			CloseHandle(hQuery);
		}
		else
		{
			g_bestTimeCache[client][IsCached] = true;
			g_bestTimeCache[client][Time] = 0;
			g_bestTimeCache[client][Jumps] = 0;			
			
			CloseHandle(hQuery);
			return false;
		}
		
		return true;
	}
	
	return false;
}

ClearCache()
{
	for (new client = 1; client <= GetMaxClients(); client++)
	{
		g_bestTimeCache[client][IsCached] = false;
		g_bestTimeCache[client][Jumps] = 0;
		g_bestTimeCache[client][Time] = 0;
	}
}

GetMapDifficulty(String:map[])
{
	decl String:query[128];
	Format(query, sizeof(query), "SELECT difficulty FROM mapdifficulty WHERE map = '%s'", map);
	
	SQL_LockDatabase(g_hSQL);

	new Handle:hQuery = SQL_Query(g_hSQL, query);
	
	if (hQuery == INVALID_HANDLE)
	{
		SQL_UnlockDatabase(g_hSQL);
		return false;
	}

	SQL_UnlockDatabase(g_hSQL); 
	
	new difficulty = 0;

	if (SQL_FetchRow(hQuery))
		difficulty = SQL_FetchInt(hQuery, 0);

	CloseHandle(hQuery);
	return difficulty;
}

FinishRound(client, String:map[], Float:time, jumps, physicsDifficulty, fpsmax)
{
	if (IsValidPlayer(client))
	{
		decl String:auth[32];
		GetClientAuthString(client, auth, sizeof(auth));

		decl String:name[32];
		GetClientName(client, name, sizeof(name));

		decl String:safeName[2 * strlen(name) + 1];
		SQL_EscapeString(g_hSQL, name, safeName, 2 * strlen(name) + 1);

		decl String:query[256];
		Format(query, sizeof(query), "INSERT round (map, auth, time, jumps, physicsdifficulty, name, fpsmax) VALUES ('%s', '%s', %f, %d, %d, '%s', %d);", map, auth, time, jumps, physicsDifficulty, safeName, fpsmax);
		
		SQL_TQuery(g_hSQL, FinishRoundCallback, query, client, DBPrio_Normal);
		
		new String:buffer[32];
		FormatTime(buffer, sizeof(buffer), "%T", RoundToNearest(time) - 2 * 3600);
	
		PrintToChatAll("%s has finished the map in %s!", name, buffer);
	}
}

public FinishRoundCallback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	PrintToServer(error);
	g_bestTimeCache[client][IsCached] = false;
}

CalculateTime(client)
{
	if (g_timers[client][Enabled] && g_timers[client][IsPaused])
		return g_timers[client][PauseStartTime] - g_timers[client][StartTime] - g_timers[client][PauseTotalTime];
	else
		return (g_timers[client][Enabled] ? GetTime() : g_timers[client][EndTime]) - g_timers[client][StartTime] - g_timers[client][PauseTotalTime];	
}

ConnectSQL()
{
    if (g_hSQL != INVALID_HANDLE)
        CloseHandle(g_hSQL);
	
    g_hSQL = INVALID_HANDLE;

    if (SQL_CheckConfig("timer"))
	{
		SQL_TConnect(ConnectSQLCallback, "timer");
	}
    else
	{
        LogError("PLUGIN STOPPED - Reason: no config entry found for 'timer' in databases.cfg - PLUGIN STOPPED");
	}
}

public ConnectSQLCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
    if (g_reconnectCounter >= 5)
    {
        LogError("PLUGIN STOPPED - Reason: reconnect counter reached max - PLUGIN STOPPED");
        return -1;
    }

    if (hndl == INVALID_HANDLE)
    {
        LogError("Connection to SQL database has failed, Reason: %s", error);
		
        g_reconnectCounter++;
        ConnectSQL();
		
        return -1;
    }

    decl String:driver[16];
    SQL_GetDriverIdent(owner, driver, sizeof(driver));
	
    if (StrEqual(driver, "mysql", false))
        SQL_FastQuery(hndl, "SET NAMES  'utf8'");

    g_hSQL = CloneHandle(hndl);

    if (g_reconnectCounter == 0)
	{
		// TODO: Add table cration here.
	}
	
    g_reconnectCounter = 1;
    return 1;
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
	
	new time;
	new jumps;
	
	new bool:success = GetBestRound(GetNativeCell(1), map, time, jumps);

	if (success)
	{
		SetNativeCellRef(3, time);
		SetNativeCellRef(4, jumps);
		
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

	return true;
}

public Native_GetMapDifficulty(Handle:plugin, numParams)
{
	decl String:map[32];
	GetNativeString(1, map, sizeof(map));
	
	return GetMapDifficulty(map);
}

public Native_FinishRound(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);

	decl String:map[32];
	GetNativeString(2, map, sizeof(map));
	
	new Float:time = GetNativeCell(3);
	new jumps = GetNativeCell(4);
	new physicsDifficulty = GetNativeCell(5);
	new fpsmax = GetNativeCell(6);

	FinishRound(client, map, time, jumps, physicsDifficulty, fpsmax);
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
		vecVelocity[x] = GetEntDataFloat(client, g_iVelocity + (x*4));
	}
}