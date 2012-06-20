#pragma semicolon 1

#include <sourcemod>
#include <loghelper>

#include <timer>
#include <timer-physics>

/**
 * Global Variables
 */
new String:g_currentMap[64];

public Plugin:myinfo =
{
    name        = "[Timer] HUD",
    author      = "alongub",
    description = "HUD component for [Timer]",
    version     = PL_VERSION,
    url         = "http://steamcommunity.com/id/alon"
};

public OnPluginStart()
{
	
}

public OnMapStart() 
{
	GetCurrentMap(g_currentMap, sizeof(g_currentMap));
	CreateTimer(0.4, HUDTimer, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

public Action:HUDTimer(Handle:timer)
{
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsValidPlayer(client))
			UpdateHUD(client);
	}

	return Plugin_Continue;
}

UpdateHUD(client)
{
	new target = client;
	
	if (IsClientObserver(client))
	{
		new observerMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		if (observerMode == 4 || observerMode == 3)
		{
			new t = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if (IsValidPlayer(t) && !IsFakeClient(t))
				target = t;
		}		
	}

	new bool:enabled;
	new time;
	new jumps;
	new fpsmax;

	Timer_GetClientTimer(client, enabled, time, jumps, fpsmax);

	new String:timeString[32];
	FormatTime(timeString, sizeof(timeString), "%T", time - 2 * 3600);

	new bestTime;
	new bestJumps;
	
	Timer_GetBestRound(client, g_currentMap, bestTime, bestJumps);
	
	new String:buffer[32];
	FormatTime(buffer, sizeof(buffer), "%T", bestTime - 2 * 3600);
	
	decl Float:fVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);

	new speed = RoundToFloor(SquareRoot(Pow(fVelocity[0],2.0)+Pow(fVelocity[1],2.0)+Pow(fVelocity[2],2.0)));

	if (enabled)
	{
		decl String:difficulty[32];
		Timer_GetDifficultyName(Timer_GetClientDifficulty(client), difficulty, sizeof(difficulty));

		PrintHintText(target, "Time: %s\nJumps: %d\nSpeed: %d m/s\nBest Times: %s\nDifficulty: %s\nFPS Max: %d", timeString, jumps, speed, buffer, difficulty, fpsmax);
	}
	else
	{
		PrintHintText(target, "Speed: %d m/s\nBest Times: %s", speed, buffer);
	}
}