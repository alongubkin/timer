#pragma semicolon 1

#include <sourcemod>
#include <clientprefs>
#include <loghelper>
#include <timer>
#include <timer-physics>

new Handle:g_cookie;

new g_difficulties[32][PhysicsDifficulty];
new g_difficultyCount = 0;
new g_defaultDifficulty = 0;

new Float:g_stamina[MAXPLAYERS+1];
new g_clientDifficulty[MAXPLAYERS+1];

new bool:g_prevent[MAXPLAYERS+1];

public Plugin:myinfo =
{
    name        = "[Timer] Physics",
    author      = "alongub",
    description = "Physics component for [Timer]",
    version     = PL_VERSION,
    url         = "http://steamcommunity.com/id/alon"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("timer-physics");
	
	CreateNative("Timer_GetClientDifficulty", Native_GetClientDifficulty);
	CreateNative("Timer_GetDifficultyName", Native_GetDifficultyName);

	return APLRes_Success;
}

public OnPluginStart()
{
	g_cookie = RegClientCookie("timer-physics", "", CookieAccess_Public);

	LoadDifficulties();
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_jump", Event_PlayerJump);

	AddCommandListener(SayCommand, "say");
	AddCommandListener(SayCommand, "say_team");	
}

public OnPluginStop()
{
	CloseHandle(g_cookie);	
}

public OnMapStart()
{
	LoadDifficulties();
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	new String:buffer[10];
	GetClientCookie(client, g_cookie, buffer, sizeof(buffer));

	if (StrEqual(buffer, ""))
		g_clientDifficulty[client] = g_defaultDifficulty;
	else
		g_clientDifficulty[client] = StringToInt(buffer);
	
	ApplyDifficulty(client);
}

public Action:Event_PlayerJump(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (g_stamina[client] != -1.0)
	{
		SetEntPropFloat(client, Prop_Send, "m_flStamina", g_stamina[client]);
	}

	return Plugin_Continue;
}

public Action:SayCommand(client, const String:command[], args)
{
	decl String:buffer[128];
	GetCmdArg(1, buffer, sizeof(buffer));

	new bool:hidden = StrEqual(buffer, "/difficulty", true);

	if (StrEqual(buffer, "!difficulty", true) || hidden)
	{
		CreateDifficultyMenu(client);

		if (hidden)
			return Plugin_Handled;
	}

	return Plugin_Continue;
}

LoadDifficulties()
{
	new String:path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, PLATFORM_MAX_PATH, "configs/timer/difficulties.cfg");

	new Handle:kv = CreateKeyValues("difficulties");
	FileToKeyValues(kv, path);

	g_difficultyCount = 0;

	if (!KvGotoFirstSubKey(kv))
		return;
	
	do 
	{
		decl String:sectionName[32];
		KvGetSectionName(kv, sectionName, sizeof(sectionName));

		g_difficulties[g_difficultyCount][Id] = StringToInt(sectionName);
		KvGetString(kv, "name", g_difficulties[g_difficultyCount][Name], 32);
		g_difficulties[g_difficultyCount][IsDefault] = bool:KvGetNum(kv, "default", 0);
		g_difficulties[g_difficultyCount][Stamina] = KvGetFloat(kv, "stamina", -1.0);
		g_difficulties[g_difficultyCount][Gravity] = KvGetFloat(kv, "gravity", 1.0);
		g_difficulties[g_difficultyCount][PreventAD] = bool:KvGetNum(kv, "prevent_ad", 0);
		
		if (g_difficulties[g_difficultyCount][IsDefault])
			g_defaultDifficulty = g_difficultyCount;
		
		g_difficultyCount++;
	} while (KvGotoNextKey(kv));
	
	CloseHandle(kv);	
}

CreateDifficultyMenu(client)
{
	new Handle:menu = CreateMenu(MenuHandler_Difficulty);

	SetMenuTitle(menu, "Physics Difficulty");
	SetMenuExitButton(menu, true);

	for (new difficulty = 0; difficulty < g_difficultyCount; difficulty++)
	{
		decl String:id[5];
		IntToString(difficulty, id, sizeof(id));
			
		AddMenuItem(menu, id, g_difficulties[difficulty][Name]);
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_Difficulty(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End) 
	{
		CloseHandle(menu);
	}
	else if (action == MenuAction_Select) 
	{
		decl String:info[32];		
		GetMenuItem(menu, param2, info, sizeof(info));
		
		g_clientDifficulty[param1] = StringToInt(info);
		SetClientCookie(param1, g_cookie, info);
		ApplyDifficulty(param1);

		Timer_Restart(param1);
	}
}

ApplyDifficulty(client)
{
	if (!IsValidPlayer(client))
		return;
	
	if (g_clientDifficulty[client] < 0 || g_clientDifficulty[client] >= g_difficultyCount)
		return;

	SetEntityGravity(client, g_difficulties[g_clientDifficulty[client]][Gravity]);
	g_stamina[client] = g_difficulties[g_clientDifficulty[client]][Stamina];
	g_prevent[client] = g_difficulties[g_clientDifficulty[client]][PreventAD];
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if (!g_prevent[client])
		return Plugin_Continue;
	
	if (buttons & IN_MOVELEFT  || buttons & IN_MOVERIGHT)
		return Plugin_Handled;
	
	return Plugin_Continue;
}

public Native_GetClientDifficulty(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	return g_clientDifficulty[client];
}

public Native_GetDifficultyName(Handle:plugin, numParams)
{
	new difficulty = GetNativeCell(1);
	new maxlength = GetNativeCell(3);

	if (difficulty < 0 || difficulty >= g_difficultyCount)
		return false;

	SetNativeString(2, g_difficulties[difficulty][Name], maxlength);
	return true;
}