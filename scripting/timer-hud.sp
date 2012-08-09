#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <timer>

#undef REQUIRE_PLUGIN
#include <timer-physics>
#include <updater>

#define UPDATE_URL "http://dl.dropbox.com/u/16304603/timer/updateinfo-timer-hud.txt"

/**
 * Global Variables
 */
new String:g_currentMap[64];
new bool:g_timerPhysics = false;

new Handle:g_showSpeedCvar = INVALID_HANDLE;
new Handle:g_showJumpsCvar = INVALID_HANDLE;
new Handle:g_showTimeCvar = INVALID_HANDLE;
new Handle:g_showDifficultyCvar = INVALID_HANDLE;
new Handle:g_showBestTimesCvar = INVALID_HANDLE;
new Handle:g_showNameCvar = INVALID_HANDLE;
new Handle:g_fragsCvar = INVALID_HANDLE;
new Handle:g_jumpsDeathCvar = INVALID_HANDLE;

new bool:g_showSpeed = true;
new bool:g_showJumps = true;
new bool:g_showTime = true;
new bool:g_showDifficulty = true;
new bool:g_showBestTimes = true;
new bool:g_showName = true;
new bool:g_frags = false;
new bool:g_jumpsDeath = false;

public Plugin:myinfo =
{
    name        = "[Timer] HUD",
    author      = "alongub | Glite",
    description = "HUD component for [Timer]",
    version     = PL_VERSION,
    url         = "https://github.com/alongubkin/timer"
};

public OnPluginStart()
{
	g_timerPhysics = LibraryExists("timer-physics");
	LoadTranslations("timer.phrases");
	
	g_showSpeedCvar = CreateConVar("timer_hud_speed", "1", "Whether or not speed is shown in the HUD.");
	g_showJumpsCvar = CreateConVar("timer_hud_jumps", "1", "Whether or not jump count is shown in the HUD.");
	g_showTimeCvar = CreateConVar("timer_hud_time", "1", "Whether or not time is shown in the HUD.");
	g_showDifficultyCvar = CreateConVar("timer_hud_difficulty", "1", "Whether or not difficulty is shown in the HUD, if the timer-physics module is enabled.");
	g_showBestTimesCvar = CreateConVar("timer_hud_besttimes", "1", "Whether or not best times for this map is shown in the HUD.");
	g_showNameCvar = CreateConVar("timer_hud_name", "1", "Whether or not spectating player's name is shown in the HUD.");
	g_fragsCvar = CreateConVar("timer_frags", "0", "Whether or not players' score should be his current timer.");
	g_jumpsDeathCvar = CreateConVar("timer_jumps_death", "0", "Whether or not players' death count should be their jump count.");

	HookConVarChange(g_showSpeedCvar, Action_OnSettingsChange);
	HookConVarChange(g_showJumpsCvar, Action_OnSettingsChange);	
	HookConVarChange(g_showTimeCvar, Action_OnSettingsChange);
	HookConVarChange(g_showDifficultyCvar, Action_OnSettingsChange);	
	HookConVarChange(g_showBestTimesCvar, Action_OnSettingsChange);
	HookConVarChange(g_showNameCvar, Action_OnSettingsChange);
	HookConVarChange(g_fragsCvar, Action_OnSettingsChange);	
	HookConVarChange(g_jumpsDeathCvar, Action_OnSettingsChange);
	
	AutoExecConfig(true, "timer-hud");
		
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}	
}

public OnMapStart() 
{
	GetCurrentMap(g_currentMap, sizeof(g_currentMap));
	StringToLower(g_currentMap);
	
	CreateTimer(0.25, HUDTimer, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "timer-physics"))
	{
		g_timerPhysics = true;
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
		g_timerPhysics = false;
	}
}

public Action_OnSettingsChange(Handle:cvar, const String:oldvalue[], const String:newvalue[])
{
	if (cvar == g_showSpeedCvar)
		g_showSpeed = bool:StringToInt(newvalue);
	else if (cvar == g_showJumpsCvar)
		g_showJumps = bool:StringToInt(newvalue);
	else if (cvar == g_showTimeCvar)
		g_showTime = bool:StringToInt(newvalue);
	else if (cvar == g_showDifficultyCvar)
		g_showDifficulty = bool:StringToInt(newvalue);
	else if (cvar == g_showBestTimesCvar)
		g_showBestTimes = bool:StringToInt(newvalue);	
	else if (cvar == g_showNameCvar)
		g_showName = bool:StringToInt(newvalue);	
	else if (cvar == g_fragsCvar)
		g_frags = bool:StringToInt(newvalue);
	else if (cvar == g_jumpsDeathCvar)
		g_jumpsDeath = bool:StringToInt(newvalue);		
}

public Action:HUDTimer(Handle:timer)
{
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
			UpdateHUD(client);
	}

	return Plugin_Continue;
}

UpdateHUD(client)
{
	if (!g_showTime && !g_showJumps && !g_showSpeed && !g_showBestTimes && !g_showDifficulty && !g_showName)
		return;
		
	new target = client;
	new t;
	
	if (IsClientObserver(client))
	{
		new observerMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		if (observerMode == 4 || observerMode == 3)
		{
			t = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if (IsClientInGame(t) && !IsFakeClient(t))
				target = t;
		}		
	}

	new bool:enabled;
	new Float:time;
	new jumps;
	new fpsmax;

	Timer_GetClientTimer(target, enabled, time, jumps, fpsmax);
	
	if (client == target)
	{		
		if (g_frags)
		{
			new roundedTime = RoundToFloor(time);
			SetEntProp(target, Prop_Data, "m_iFrags", (roundedTime / 60) * 100 + (roundedTime % 60));
		}
		
		if (g_jumpsDeath)
		{
			SetEntProp(target, Prop_Data, "m_iDeaths", jumps);		
		}
	}
	
	new String:hintText[256];
	
	if (enabled)
	{
		if (g_showTime)
		{
			new String:timeString[32];
			Timer_SecondsToTime(time, timeString, sizeof(timeString), false);
			
			Format(hintText, sizeof(hintText), "%s%t: %s", hintText, "Time", timeString);
		}
		
		if (g_showJumps)
		{
			if (g_showTime)
				Format(hintText, sizeof(hintText), "%s\n", hintText);
				
			Format(hintText, sizeof(hintText), "%s%t: %d", hintText, "Jumps", jumps);
		}
	}
	
	if (g_showSpeed)
	{
		decl Float:fVelocity[3];
		GetEntPropVector(target, Prop_Data, "m_vecVelocity", fVelocity);	
		
		if (enabled && (g_showTime || g_showJumps))
			Format(hintText, sizeof(hintText), "%s\n", hintText);
		
		Format(hintText, sizeof(hintText), "%s%t: %d u/s", hintText, "HUD Speed", 
				RoundToFloor(SquareRoot(Pow(fVelocity[0],2.0)+Pow(fVelocity[1],2.0))));
	}
	
	if (g_showBestTimes)
	{
		new Float:bestTime;
		new bestJumps;
		
		Timer_GetBestRound(target, g_currentMap, bestTime, bestJumps);	
		
		new String:buffer[32];
		Timer_SecondsToTime(bestTime, buffer, sizeof(buffer), false);	
		
		if ((enabled && (g_showTime || g_showJumps)) || g_showSpeed)
			Format(hintText, sizeof(hintText), "%s\n", hintText);
			
		Format(hintText, sizeof(hintText), "%s%t: %s", hintText, "HUD Best Times", buffer);
	}
	
	if (g_timerPhysics && g_showDifficulty) 
	{
		decl String:difficulty[32];
		Timer_GetDifficultyName(Timer_GetClientDifficulty(target), difficulty, sizeof(difficulty));
		
		if ((enabled && (g_showTime || g_showJumps)) || g_showSpeed || g_showBestTimes)
			Format(hintText, sizeof(hintText), "%s\n", hintText);
			
		Format(hintText, sizeof(hintText), "%s%t: %s", hintText, "HUD Difficulty", difficulty);
	}
	
	if (g_showName && target == t)
	{
		decl String:name[MAX_NAME_LENGTH];
		GetClientName(target, name, sizeof(name));
		
		if ((enabled && (g_showTime || g_showJumps)) || g_showSpeed || g_showBestTimes || g_showDifficulty)
			Format(hintText, sizeof(hintText), "%s\n", hintText);
	
		Format(hintText, sizeof(hintText), "%s%t: %s", hintText, "Player", name);	
	}
	
	PrintHintText(client, hintText);
	
	StopSound(client, SNDCHAN_STATIC, "UI/hint.wav");
}