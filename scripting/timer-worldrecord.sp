#pragma semicolon 1

#include <sourcemod>
#include <adminmenu>

#include <timer>
#include <timer-logging>
#include <timer-worldrecord>

#undef REQUIRE_PLUGIN
#include <timer-physics>
#include <updater>

#define UPDATE_URL "http://dl.dropbox.com/u/16304603/timer/updateinfo-timer-worldrecord.txt"

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
	String:Auth[32],
	bool:Ignored
}

/**
 * Global Variables
 */
new Handle:g_hSQL;

new String:g_currentMap[32];
new g_reconnectCounter = 0;

new g_difficulties[32][PhysicsDifficulty];
new g_difficultyCount = 0;

new Handle:hTopMenu = INVALID_HANDLE;
new TopMenuObject:oMapZoneMenu;

new g_cache[100][RecordCache];
new g_cacheCount = 0;
new bool:g_cacheLoaded = false;

new bool:g_timerPhysics = false;

new g_deleteMenuSelection[MAXPLAYERS+1];

new Handle:g_showJumpCvar = INVALID_HANDLE;
new bool:g_showJumps = true;

public Plugin:myinfo =
{
    name        = "[Timer] World Record",
    author      = "alongub | Glite",
    description = "World Record component for [Timer]",
    version     = PL_VERSION,
    url         = "https://github.com/alongubkin/timer"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("timer-worldrecord");
	
	CreateNative("Timer_ForceReloadWorldRecordCache", Native_ForceReloadWorldRecordCache);

	return APLRes_Success;
}

public OnPluginStart()
{
	ConnectSQL(true);
	
	g_timerPhysics = LibraryExists("timer-physics");
	
	LoadTranslations("timer.phrases");
	
	RegConsoleCmd("sm_wr", Command_WorldRecord);
	RegConsoleCmd("sm_delete", Command_Delete);
	RegConsoleCmd("sm_record", Command_PersonalRecord);
	RegConsoleCmd("sm_reloadcache", Command_ReloadCache);
	
	RegAdminCmd("sm_deleterecord_all", Command_DeleteRecord_All, ADMFLAG_RCON, "sm_deleterecord_all STEAM_ID");
	RegAdminCmd("sm_deleterecord", Command_DeleteRecord, ADMFLAG_RCON, "sm_deleterecord STEAM_ID");
	
	g_showJumpCvar = CreateConVar("timer_showjumps", "1", "Whether or not jumps will be shown in some of the WR menus.");
	HookConVarChange(g_showJumpCvar, Action_OnSettingsChange);
	
	AutoExecConfig(true, "timer-worldrecord");
	
	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(topmenu);
	}
	
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}		
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
	else if (StrEqual(name, "adminmenu"))
	{
		hTopMenu = INVALID_HANDLE;
	}
}

public OnMapStart()
{
	GetCurrentMap(g_currentMap, sizeof(g_currentMap));
	RefreshCache();
}

public Action_OnSettingsChange(Handle:cvar, const String:oldvalue[], const String:newvalue[])
{
	if (cvar == g_showJumpCvar)
		g_showJumps = bool:StringToInt(newvalue);			
}

public Action:OnClientCommand(client, args)
{
	new String:cmd[16];
	GetCmdArg(0, cmd, sizeof(cmd));

	if (StrEqual(cmd, "wr"))
	{
		ConsoleWR(client, 0);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action:Command_WorldRecord(client, args)
{
	if (g_timerPhysics)
		CreateDifficultyMenu(client);
	else
		CreateWRMenu(client, -1);
	
	return Plugin_Handled;
}

public Action:Command_Delete(client, args)
{
	CreateDeleteMenu(client, client);
	return Plugin_Handled;
}

public Action:Command_PersonalRecord(client, args)
{
	new argsCount = GetCmdArgs();
	new target = -1;

	if (argsCount == 0)
	{
		target = client;
	}
	else if (argsCount == 1)
	{
		decl String:name[64];
		GetCmdArg(1, name, sizeof(name));
		
		new targets[2];
		decl String:targetName[32];
		new bool:ml = false;

		if (ProcessTargetString(name, 0, targets, sizeof(targets), COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_NO_IMMUNITY, targetName, sizeof(targetName), ml) > 0)
			target = targets[0];
	}

	if (target == -1)
	{
		PrintToChat(client, PLUGIN_PREFIX, "No target");
	}
	else
	{
		decl String:auth[32];
		GetClientAuthString(client, auth, sizeof(auth));

		for (new t = 0; t < g_cacheCount; t++)
		{
			if (StrEqual(g_cache[t][Auth], auth))
			{
				CreatePlayerInfoMenu(client, g_cache[t][Id], false);
				break;
			}
		}		
	}
	
	return Plugin_Handled;
}

public Action:Command_ReloadCache(client, args)
{
	RefreshCache();
	return Plugin_Handled;
}

public Action:Command_DeleteRecord_All(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_deleterecord_all <steamid>");
		return Plugin_Handled;
	}

	new String:auth[32];
	GetCmdArgString(auth, sizeof(auth));

	decl String:query[384];
	Format(query, sizeof(query), "DELETE FROM round WHERE auth = '%s'", auth);

	SQL_TQuery(g_hSQL, DeleteRecordsCallback, query, _, DBPrio_Normal);
	
	return Plugin_Handled;
}

public Action:Command_DeleteRecord(client, args)
{	
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_deleterecord <steamid>");
		return Plugin_Handled;
	}
	
	new String:auth[32];
	GetCmdArgString(auth, sizeof(auth));

	decl String:query[384];
	Format(query, sizeof(query), "DELETE FROM round WHERE auth = '%s' AND map = '%s'", auth, g_currentMap);

	SQL_TQuery(g_hSQL, DeleteRecordsCallback, query, _, DBPrio_Normal);
	
	return Plugin_Handled;
}

public DeleteRecordsCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on DeleteRecord: %s", error);
		return;
	}

	RefreshCache();
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
		CloseHandle(kv);
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

public OnAdminMenuReady(Handle:topmenu)
{
	// Block this from being called twice
	if (topmenu == hTopMenu) {
		return;
	}
 
	// Save the Handle
	hTopMenu = topmenu;
		
	if ((oMapZoneMenu = FindTopMenuCategory(topmenu, "Timer Management")) == INVALID_TOPMENUOBJECT)
	{
		oMapZoneMenu = AddToTopMenu(hTopMenu,
			"Timer Management",
			TopMenuObject_Category,
			AdminMenu_CategoryHandler,
			INVALID_TOPMENUOBJECT);
	}
		
	AddToTopMenu(hTopMenu, 
		"timer_delete",
		TopMenuObject_Item,
		AdminMenu_DeleteRecord,
		oMapZoneMenu,
		"timer_delete",
		ADMFLAG_RCON);
		
	AddToTopMenu(hTopMenu, 
		"timer_deletemaprecords",
		TopMenuObject_Item,
		AdminMenu_DeleteMapRecords,
		oMapZoneMenu,
		"timer_deletemaprecords",
		ADMFLAG_RCON);		
}

public AdminMenu_CategoryHandler(Handle:topmenu, 
			TopMenuAction:action,
			TopMenuObject:object_id,
			param,
			String:buffer[],
			maxlength)
{
	if (action == TopMenuAction_DisplayTitle) {
		Format(buffer, maxlength, "%t", "Timer Management");
	} else if (action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "%t", "Timer Management");
	}
}

public AdminMenu_DeleteMapRecords(Handle:topmenu, 
			TopMenuAction:action,
			TopMenuObject:object_id,
			param,
			String:buffer[],
			maxlength)
{
	if (action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "%t", "Delete Map Records");
	} else if (action == TopMenuAction_SelectOption) {
		decl String:map[32];
		GetCurrentMap(map, sizeof(map));
		
		DeleteMapRecords(map);
	}
}

public AdminMenu_DeleteRecord(Handle:topmenu, 
			TopMenuAction:action,
			TopMenuObject:object_id,
			param,
			String:buffer[],
			maxlength)
{
	if (action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "%t", "Delete Player Record");
	} else if (action == TopMenuAction_SelectOption) {
		DisplaySelectPlayerMenu(param);
	}
}

DisplaySelectPlayerMenu(client)
{
	new Handle:menu = CreateMenu(MenuHandler_SelectPlayer);

	SetMenuTitle(menu, "%T", "Choose Player", client);
	SetMenuExitButton(menu, true);
	
	new items = 0; 

	for (new cache = 0; cache < g_cacheCount; cache++)
	{
		if (g_cache[cache][Ignored])
			continue;
		
		decl String:text[92];
		Format(text, sizeof(text), "%s - %s", g_cache[cache][Name], g_cache[cache][TimeString]);
		
		if (g_showJumps)
			Format(text, sizeof(text), "%s (%d %T)", text, g_cache[cache][Jumps], "Jumps", client);

		AddMenuItem(menu, g_cache[cache][Auth], text);
		items++;
	}

	if (items == 0)
	{
		CloseHandle(menu);
		return;
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_SelectPlayer(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End) 
	{
		RefreshCache();
		CloseHandle(menu);
	}
	else if (action == MenuAction_Select) 
	{
		decl String:info[32];		
		GetMenuItem(menu, param2, info, sizeof(info));
		
		decl String:query[384];
		Format(query, sizeof(query), "DELETE FROM `round` WHERE auth = '%s' AND map = '%s'", info, g_currentMap);

		SQL_TQuery(g_hSQL, DeletePlayersRecordCallback, query, param1, DBPrio_Normal);
		
		for (new cache = 0; cache < g_cacheCount; cache++)
		{
			if (StrEqual(g_cache[cache][Auth], info))
				g_cache[cache][Ignored] = true;
		}
	}
}

public DeletePlayersRecordCallback(Handle:owner, Handle:hndl, const String:error[], any:param1)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on DeletePlayerRecord: %s", error);
		return;
	}
	
	DisplaySelectPlayerMenu(param1);
}


DeleteMapRecords(const String:map[]) 
{
	decl String:query[384];
	Format(query, sizeof(query), "DELETE FROM `round` WHERE map = '%s'", map);	

	SQL_TQuery(g_hSQL, DeleteMapRecordsCallback, query, _, DBPrio_Normal);
}

public DeleteMapRecordsCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on DeleteMapRecord: %s", error);
		return;
	}

	RefreshCache();
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
		Format(query, sizeof(query), "SELECT m.id, m.auth, m.time, MAX(m.jumps) jumps, m.physicsdifficulty, m.name FROM round AS m INNER JOIN (SELECT MIN(n.time) time, n.auth FROM round n WHERE n.map = '%s' GROUP BY n.physicsdifficulty, n.auth) AS j ON (j.time = m.time AND j.auth = m.auth) WHERE m.map = '%s' GROUP BY m.physicsdifficulty, m.auth ORDER BY m.time ASC", g_currentMap, g_currentMap);	
		
		SQL_TQuery(g_hSQL, RefreshCacheCallback, query, _, DBPrio_Normal);
	}
}

public RefreshCacheCallback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on RefreshCache: %s", error);
		return;
	}
	
	g_cacheCount = 0;
		
	while (SQL_FetchRow(hndl))
	{
		g_cache[g_cacheCount][Id] = SQL_FetchInt(hndl, 0);
		SQL_FetchString(hndl, 1, g_cache[g_cacheCount][Auth], 32);
		Timer_SecondsToTime(SQL_FetchFloat(hndl, 2), g_cache[g_cacheCount][TimeString], 16, true);
		g_cache[g_cacheCount][Jumps] = SQL_FetchInt(hndl, 3);
		g_cache[g_cacheCount][RecordPhysicsDifficulty] = SQL_FetchInt(hndl, 4);
		SQL_FetchString(hndl, 5, g_cache[g_cacheCount][Name], 32);
		g_cache[g_cacheCount][Ignored] = false;
		
		g_cacheCount++;
	}
		
	g_cacheLoaded = true;
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
		Timer_LogError("PLUGIN STOPPED - Reason: no config entry found for 'timer' in databases.cfg - PLUGIN STOPPED");
	}
}

public ConnectSQLCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (g_reconnectCounter >= 5)
	{
		Timer_LogError("PLUGIN STOPPED - Reason: reconnect counter reached max - PLUGIN STOPPED");
		return;
	}

	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("Connection to SQL database has failed, Reason: %s", error);
		
		g_reconnectCounter++;
		ConnectSQL(data);
		
		return;
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
}

CreateDifficultyMenu(client)
{
	if (!g_cacheLoaded)
	{
		PrintToChat(client, PLUGIN_PREFIX, "World Record Loading");
		return;	
	}

	new Handle:menu = CreateMenu(MenuHandler_Difficulty);

	SetMenuTitle(menu, "%T", "Physics Difficulty", client);
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

	SetMenuTitle(menu, "%T", "World Record Menu Title", client, g_currentMap);
	
	if (g_timerPhysics)
		SetMenuExitBackButton(menu, true);
	else
		SetMenuExitButton(menu, true);
		
	new items = 0; 

	for (new cache = 0; cache < g_cacheCount; cache++)
	{
		// PrintToChatAll("%d", g_cache[cache][RecordPhysicsDifficulty]);
		
		if (difficulty == -1 || g_cache[cache][RecordPhysicsDifficulty] == difficulty)
		{
			decl String:id[5];
			IntToString(g_cache[cache][Id], id, sizeof(id));
			
			decl String:text[92];
			Format(text, sizeof(text), "%s - %s", g_cache[cache][Name], g_cache[cache][TimeString]);
			
			if (g_showJumps)
				Format(text, sizeof(text), "%s (%d %T)", text, g_cache[cache][Jumps], "Jumps", client);
			
			AddMenuItem(menu, id, text);
			items++;
		}
	}

	if (items == 0)
	{
		CloseHandle(menu);
		
		if (difficulty == -1)
			PrintToChat(client, PLUGIN_PREFIX, "No Records");	
		else
			PrintToChat(client, PLUGIN_PREFIX, "No Difficulty Records");
	}
	else
	{
		DisplayMenu(menu, client, MENU_TIME_FOREVER);
	}
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
			if (g_timerPhysics)
				CreateDifficultyMenu(param1);
		}
	} 
	else if (action == MenuAction_Select) 
	{
		decl String:info[32];		
		GetMenuItem(menu, param2, info, sizeof(info));
			
		CreatePlayerInfoMenu(param1, StringToInt(info), true);
	}
}

CreatePlayerInfoMenu(client, id, bool:back)
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

			SetMenuTitle(menu, "%T\n \n", "Record Info", client);

			Format(text, sizeof(text), "%T: %s (%s)", "Player Name", client, g_cache[cache][Name], g_cache[cache][Auth]);
			AddMenuItem(menu, difficulty, text);

			Format(text, sizeof(text), "%T: #%d on %s", "Rank", client, cache + 1, g_currentMap);
			AddMenuItem(menu, difficulty, text);

			Format(text, sizeof(text), "%T: %s", "Time", client, g_cache[cache][TimeString]);
			AddMenuItem(menu, difficulty, text);
			
			if (g_showJumps)
			{
				Format(text, sizeof(text), "%T: %d", "Jumps", client, g_cache[cache][Jumps]);
				AddMenuItem(menu, difficulty, text);
			}
			
			if (g_timerPhysics)
			{
				decl String:difficultyName[32];
				Timer_GetDifficultyName(g_cache[cache][RecordPhysicsDifficulty], difficultyName, sizeof(difficultyName));
				
				Format(text, sizeof(text), "%T: %s", "Physics Difficulty", client, difficultyName);
				AddMenuItem(menu, difficulty, text);
			}
	
			if (back)
				AddMenuItem(menu, difficulty, "Back");			

			break;
		}
		
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);	
}

ConsoleWR(client, difficulty)
{
	if (g_timerPhysics)
		PrintToConsole(client, "difficulty: %s", g_difficulties[difficulty][Name]);
	
	PrintToConsole(client, "map       : %s\n", g_currentMap);

	PrintToConsole(client, "# rank\tname\t\t\tsteamid\t\t\ttime\t\tjumps");

	for (new cache = 0; cache < g_cacheCount; cache++)
	{
		if (!g_timerPhysics || g_cache[cache][RecordPhysicsDifficulty] == difficulty)
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

CreateDeleteMenu(client, target)
{	
	if (g_hSQL == INVALID_HANDLE)
	{
		ConnectSQL(false);
	}
	else
	{
		decl String:auth[32];
		GetClientAuthString(target, auth, sizeof(auth));
			
		decl String:query[384];
		Format(query, sizeof(query), "SELECT id, time, jumps, physicsdifficulty, auth FROM `round` WHERE map = '%s' AND auth = '%s' ORDER BY physicsdifficulty, time, jumps", g_currentMap, auth);	
		
		g_deleteMenuSelection[client] = target;
		SQL_TQuery(g_hSQL, CreateDeleteMenuCallback, query, client, DBPrio_Normal);
	}	
}

public CreateDeleteMenuCallback(Handle:owner, Handle:hndl, const String:error[], any:client)
{	
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on CreateDeleteMenu: %s", error);
		return;
	}

	new Handle:menu = CreateMenu(MenuHandler_DeleteRecord);

	SetMenuTitle(menu, "%T", "Delete Records", client);
	SetMenuExitButton(menu, true);
	
	decl String:auth[32];
	GetClientAuthString(client, auth, sizeof(auth));
			
	while (SQL_FetchRow(hndl))
	{
		decl String:steamid[32];
		SQL_FetchString(hndl, 4, steamid, sizeof(steamid));
		
		if (!StrEqual(steamid, auth))
		{
			CloseHandle(menu);
			return;
		}
		
		decl String:id[10];
		IntToString(SQL_FetchInt(hndl, 0), id, sizeof(id));

		decl String:time[16];
		Timer_SecondsToTime(SQL_FetchFloat(hndl, 1), time, sizeof(time));
		
		new String:difficulty[32];	
		
		if (g_timerPhysics)
			Timer_GetDifficultyName(SQL_FetchInt(hndl, 3), difficulty, sizeof(difficulty));

		decl String:value[92];
		Format(value, sizeof(value), "%s %s", time, difficulty);
		
		if (g_showJumps)
			Format(value, sizeof(value), "%s %T: %d", value, "Jumps", client, SQL_FetchInt(hndl, 2));
			
		AddMenuItem(menu, id, value);
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler_DeleteRecord(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End) 
	{
		RefreshCache();
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
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on DeleteRecord: %s", error);
		return;
	}

	CreateDeleteMenu(client, g_deleteMenuSelection[client]);
}

public Native_ForceReloadWorldRecordCache(Handle:plugin, numParams)
{
	RefreshCache();
}