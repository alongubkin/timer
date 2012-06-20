#pragma semicolon 1

#include <sourcemod>
#include <loghelper>
#include <timer>
#include <timer-physics>
#include <timer-worldrecord>

/**
 * Global Enums
 */

enum RecordCache
{
	Id,
	String:Name[32],
	String:TimeString[16],
	Jumps,
	String:RecordPhysicsDifficulty[32],
	String:Auth[32]
}

/**
 * Global Variables
 */
new Handle:g_hSQL;

new String:g_currentMap[32];
new g_reconnectCounter = 0;

new g_difficulties[32][PhysicsDifficulty];
new g_difficultyCount = 0;

new g_cache[100][RecordCache];
new g_cacheCount = 0;
new bool:g_cacheLoaded = false;

public Plugin:myinfo =
{
    name        = "[Timer] World Record",
    author      = "alongub",
    description = "World Record component for [Timer]",
    version     = PL_VERSION,
    url         = "http://steamcommunity.com/id/alon"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("timer-worldrecord");
	
	CreateNative("Timer_ForceReloadWorldCache", Native_ForceReloadWorldCache);

	return APLRes_Success;
}

public OnPluginStart()
{
	ConnectSQL(false);

	AddCommandListener(SayCommand, "say");
	AddCommandListener(SayCommand, "say_team");
}

public OnMapStart()
{
	GetCurrentMap(g_currentMap, sizeof(g_currentMap));
	RefreshCache();	
}

public Action:OnClientCommand(client, args)
{
	new String:cmd[16];
	GetCmdArg(0, cmd, sizeof(cmd));

	if (StrEqual(cmd, "sm_wr", true))
	{
		CreateDifficultyMenu(client);
		return Plugin_Handled;
	}
	else if (StrEqual(cmd, "wr"))
	{
		ConsoleWR(client, 0);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action:SayCommand(client, const String:command[], args)
{
	decl String:buffer[128];
	GetCmdArg(1, buffer, sizeof(buffer));

	new bool:hidden = StrEqual(buffer, "/wr", true);
	if (StrEqual(buffer, "!wr", true) || hidden)
	{
		CreateDifficultyMenu(client);

		if (hidden)
			return Plugin_Handled;
	}

	hidden = StrEqual(buffer, "/delete", true);
	if (StrEqual(buffer, "!delete", true) || hidden)
	{
		CreateDeleteMenu(client);

		if (hidden)
			return Plugin_Handled;
	}

	hidden = StrEqual(buffer, "/record", true);
	if (StrEqual(buffer, "!record", true) || hidden)
	{
		new argsCount = GetCmdArgs();
		new target = -1;

		if (argsCount == 1)
		{
			target = client;
		}
		else if (argsCount == 2)
		{
			decl String:name[64];
			GetCmdArg(2, name, sizeof(name));
			
			new targets[2];
			decl String:targetName[32];
			new bool:ml = false;

			if (ProcessTargetString(name, 0, targets, sizeof(targets), COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_NO_IMMUNITY, targetName, sizeof(targetName), ml) > 0)
				target = targets[0];
		}

		if (target == -1)
		{
			PrintToChat(client, "Couldn't find target...");
		}
		else
		{
			decl String:auth[32];
			GetClientAuthString(client, auth, sizeof(auth));

			for (new t = 0; t < g_cacheCount; t++)
			{
				if (StrEqual(g_cache[t][Auth], auth))
				{
					CreatePlayerInfoMenu(client, g_cache[t][Id]);
					break;
				}
			}		
		}

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
	{
		return;
	}
	
	do 
	{
		decl String:sectionName[32];
		KvGetSectionName(kv, sectionName, sizeof(sectionName));

		g_difficulties[g_difficultyCount][Id] = StringToInt(sectionName);

		KvGetString(kv, "name", g_difficulties[g_difficultyCount][Name], 32);
		g_difficulties[g_difficultyCount][IsDefault] = bool:KvGetNum(kv, "default", 0);

		g_difficultyCount++;
	} while (KvGotoNextKey(kv));
	
	CloseHandle(kv);	
}

RefreshCache()
{
	g_cacheLoaded = false;
	LoadDifficulties();

	if (g_hSQL == INVALID_HANDLE)
	{
		ConnectSQL(true);
	}
	else
	{	
		decl String:query[384];
		Format(query, sizeof(query), "SELECT m.id, m.auth, m.time, MAX(m.jumps) jumps, m.physicsdifficulty, m.name FROM round AS m INNER JOIN (SELECT MIN(n.time) time, n.auth FROM round n WHERE n.map = '%s' GROUP BY n.physicsdifficulty, n.auth) AS j ON (j.time = m.time AND j.auth = m.auth) WHERE m.map = '%s' GROUP BY m.physicsdifficulty, m.auth", g_currentMap, g_currentMap);	

		SQL_TQuery(g_hSQL, RefreshCacheCallback, query, _, DBPrio_Normal);
	}
}

public RefreshCacheCallback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	g_cacheCount = 0;

	if (hndl == INVALID_HANDLE)
		return 0;
	
	while (SQL_FetchRow(hndl))
	{
		g_cache[g_cacheCount][Id] = SQL_FetchInt(hndl, 0);
		SQL_FetchString(hndl, 1, g_cache[g_cacheCount][Auth], 32);
		FormatTime(g_cache[g_cacheCount][TimeString], 16, "%T", SQL_FetchInt(hndl, 2) - 2 * 3600);
		g_cache[g_cacheCount][Jumps] = SQL_FetchInt(hndl, 3);
		g_cache[g_cacheCount][RecordPhysicsDifficulty] = SQL_FetchInt(hndl, 4);
		SQL_FetchString(hndl, 5, g_cache[g_cacheCount][Name], 32);
		
		g_cacheCount++;
	}

	g_cacheLoaded = true;
	return 1;
}

ConnectSQL(bool:refreshCache)
{
    if (g_hSQL != INVALID_HANDLE)
        CloseHandle(g_hSQL);
	
    g_hSQL = INVALID_HANDLE;

    if (SQL_CheckConfig("timer"))
	{
		SQL_TConnect(ConnectSQLCallback, "timer", refreshCache);
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
        ConnectSQL(data);
		
        return -1;
    }

    decl String:driver[16];
    SQL_GetDriverIdent(owner, driver, sizeof(driver));
	
    if (StrEqual(driver, "mysql", false))
        SQL_FastQuery(hndl, "SET NAMES 'utf8'");

    g_hSQL = CloneHandle(hndl);
	
    g_reconnectCounter = 1;

    if (data)
    {
    	RefreshCache();	
    }

    return 1;
}

CreateDifficultyMenu(client)
{
	if (!g_cacheLoaded)
	{
		PrintToChat(client, "[Timer] World Record is still loading; try again in a few moments.");
		return;	
	}

	new Handle:menu = CreateMenu(MenuHandler_Difficulty);

	SetMenuTitle(menu, "Physics Difficulty");
	SetMenuExitButton(menu, true);

	for (new difficulty = 0; difficulty < g_difficultyCount; difficulty++)
	{
		decl String:id[5];
		IntToString(g_difficulties[difficulty][Id], id, sizeof(id));

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
		
		CreateWRMenu(param1, StringToInt(info));
	}
}

CreateWRMenu(client, difficulty)
{
	new Handle:menu = CreateMenu(MenuHandler_WR);

	SetMenuTitle(menu, "World Records for %s", g_currentMap);
	SetMenuExitBackButton(menu, true);

	new items = 0; 

	for (new cache = 0; cache < g_cacheCount; cache++)
	{
		if (g_cache[cache][RecordPhysicsDifficulty] == difficulty)
		{
			decl String:id[5];
			IntToString(g_cache[cache][Id], id, sizeof(id));
			
			decl String:text[92];
			Format(text, sizeof(text), "%s (%s)", g_cache[cache][Name], g_cache[cache][TimeString]);

			AddMenuItem(menu, id, text);
			items++;
		}
	}

	if (items == 0)
	{
		CloseHandle(menu);
		PrintToChat(client, "Sorry, there are no records in this difficulty.");
	}
	DisplayMenu(menu, client, MENU_TIME_FOREVER);	
}

public MenuHandler_WR(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End) 
	{
		CloseHandle(menu);
	}
	else if (action == MenuAction_Cancel) 
	{
		if (param2 == MenuCancel_ExitBack) 
		{
			CreateDifficultyMenu(param1);
		}
	} 
	else if (action == MenuAction_Select) 
	{
		decl String:info[32];		
		GetMenuItem(menu, param2, info, sizeof(info));
			
		CreatePlayerInfoMenu(param1, StringToInt(info));
	}
}

CreatePlayerInfoMenu(client, id)
{
	new Handle:menu = CreateMenu(MenuHandler_Difficulty);

	SetMenuExitButton(menu, true);

	for (new cache = 0; cache < g_cacheCount; cache++)
	{
		if (g_cache[cache][Id] == id)
		{
			decl String:difficulty[5];
			IntToString(g_cache[cache][RecordPhysicsDifficulty], difficulty, sizeof(difficulty));
					
			decl String:text[92];

			SetMenuTitle(menu, "Record Info\n \n");

			Format(text, sizeof(text), "Player Name: %s (%s)", g_cache[cache][Name], g_cache[cache][Auth]);
			AddMenuItem(menu, difficulty, text);

			Format(text, sizeof(text), "Rank: #%d on %s", cache + 1, g_currentMap);
			AddMenuItem(menu, difficulty, text);

			Format(text, sizeof(text), "Time: %s", g_cache[cache][TimeString]);
			AddMenuItem(menu, difficulty, text);

			Format(text, sizeof(text), "Jumps: %d", g_cache[cache][Jumps]);
			AddMenuItem(menu, difficulty, text);

			Format(text, sizeof(text), "Physics Difficulty: %s", g_difficulties[g_cache[cache][RecordPhysicsDifficulty]][Name]);
			AddMenuItem(menu, difficulty, text);									

			AddMenuItem(menu, difficulty, "Back");			

			break;
		}
		
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);	
}

ConsoleWR(client, difficulty)
{
	PrintToConsole(client, "difficulty: %s", g_difficulties[difficulty][Name]);
	PrintToConsole(client, "map       : %s\n", g_currentMap);

	PrintToConsole(client, "# rank\tname\t\t\tsteamid\t\t\ttime\t\tjumps");

	for (new cache = 0; cache < g_cacheCount; cache++)
	{
		if (g_cache[cache][RecordPhysicsDifficulty] == difficulty)
		{
			PrintToConsole(client, "# %d\t%s\t%s\t%s\t%d",
				cache + 1,
				g_cache[cache][Name],
				g_cache[cache][Auth],
				g_cache[cache][TimeString],
				g_cache[cache][Jumps]);		
		}
	}	
}

CreateDeleteMenu(client)
{
	if (g_hSQL == INVALID_HANDLE)
	{
		ConnectSQL(false);
	}
	else
	{
		decl String:auth[32];
		GetClientAuthString(client, auth, sizeof(auth));
			
		decl String:query[384];
		Format(query, sizeof(query), "SELECT id, time, jumps, physicsdifficulty FROM `round` WHERE map = '%s' AND auth = '%s' ORDER BY physicsdifficulty, time, jumps", g_currentMap, auth);	

		SQL_TQuery(g_hSQL, CreateDeleteMenuCallback, query, client, DBPrio_Normal);
	}	
}

public CreateDeleteMenuCallback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	PrintToChat(client, error);

	if (hndl == INVALID_HANDLE)
		return 0;

	new Handle:menu = CreateMenu(MenuHandler_DeleteRecord);

	SetMenuTitle(menu, "Delete Record\n \n");
	SetMenuExitButton(menu, true);
	
	while (SQL_FetchRow(hndl))
	{
		decl String:id[10];
		IntToString(SQL_FetchInt(hndl, 0), id, sizeof(id));

		decl String:time[16];
		FormatTime(time, 16, "%T", SQL_FetchInt(hndl, 1)- 2 * 3600);

		decl String:difficulty[32];
		Timer_GetDifficultyName(SQL_FetchInt(hndl, 3), difficulty, sizeof(difficulty));
		
		decl String:value[92];
		Format(value, sizeof(value), "%s %s, Jumps: %d", time, difficulty, SQL_FetchInt(hndl, 2));

		AddMenuItem(menu, id, value);
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
	return 1;
}

public MenuHandler_DeleteRecord(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End) 
	{
		CloseHandle(menu);
	}
	else if (action == MenuAction_Select) 
	{
		decl String:info[32];		
		GetMenuItem(menu, param2, info, sizeof(info));
			
		decl String:query[384];
		Format(query, sizeof(query), "DELETE FROM `round` WHERE id = %s", info);	

		SQL_TQuery(g_hSQL, DeleteRecordCallback, query, param1, DBPrio_Normal);

	}
}

public DeleteRecordCallback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	Timer_ForceReloadBestRoundCache();
	CreateDeleteMenu(client);
}

public Native_ForceReloadWorldCache(Handle:plugin, numParams)
{
	RefreshCache();
}