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
	String:Name[MAX_NAME_LENGTH],
	String:TimeString[16],
	Jumps,
	Flashbangs,
	String:RecordPhysicsDifficulty[32],
	String:Auth[MAX_AUTHID_LENGTH],
	bool:Ignored
}

/**
* Global Variables
*/
new Handle:g_hSQL;

new String:g_sCurrentMap[MAX_MAPNAME_LENGTH];
new g_iReconnectCounter = 0;

new g_difficulties[32][PhysicsDifficulty];
new g_difficultyCount = 0;

new Handle:hTopMenu = INVALID_HANDLE;
new TopMenuObject:oMapZoneMenu;

new g_cache[1024][RecordCache];
new g_cacheCount = 0;
new bool:g_bCacheLoaded = false;

new bool:g_bTimerPhysics = false;

new g_iDeleteMenuSelection[MAXPLAYERS+1];

new Handle:g_hCvarShowJumps = INVALID_HANDLE;
new Handle:g_hCvarShowFlashbangs = INVALID_HANDLE;
new bool:g_bShowJumps = true;
new bool:g_bShowFlashbangs = false;

new Handle:g_hTimerDeleteRecordForward;

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
	
	g_bTimerPhysics = LibraryExists("timer-physics");
	LoadTranslations("timer.phrases");
	
	g_hCvarShowJumps = CreateConVar("timer_showjumps", "1", "Whether or not jumps will be shown in some of the WR menus.");
	g_hCvarShowFlashbangs = CreateConVar("timer_showflashbangs", "0", "Whether or not flashbangs will be shown in some of the WR menus.");
	
	g_hTimerDeleteRecordForward = CreateGlobalForward("OnTimerDeleteOneRecord", ET_Event, Param_Cell, Param_Float, Param_String, Param_Cell, Param_Cell, Param_Cell);

	HookConVarChange(g_hCvarShowJumps, Action_OnSettingsChange);
	HookConVarChange(g_hCvarShowFlashbangs, Action_OnSettingsChange);
	
	AutoExecConfig(true, "timer-worldrecord");
	
	g_bShowJumps = GetConVarBool(g_hCvarShowJumps);
	g_bShowFlashbangs = GetConVarBool(g_hCvarShowFlashbangs);
	
	RegConsoleCmd("sm_wr", Command_WorldRecord);
	RegConsoleCmd("sm_delete", Command_Delete);
	RegConsoleCmd("sm_record", Command_PersonalRecord);
	RegConsoleCmd("sm_reloadcache", Command_ReloadCache);
	
	RegAdminCmd("sm_deleterecord_all", Command_DeleteRecord_All, ADMFLAG_RCON, "sm_deleterecord_all STEAM_ID");
	RegAdminCmd("sm_deleterecord", Command_DeleteRecord, ADMFLAG_RCON, "sm_deleterecord STEAM_ID");
	
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
	else if (StrEqual(name, "adminmenu"))
	{
		hTopMenu = INVALID_HANDLE;
	}
}

public OnMapStart()
{
	GetCurrentMap(g_sCurrentMap, sizeof(g_sCurrentMap));
	StringToLower(g_sCurrentMap);
	
	RefreshCache();
}

public OnClientAuthorized(client, const String:auth[])
{
	decl String:sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));
	
	decl String:sSafeName[2 * strlen(sName) + 1];
	SQL_EscapeString(g_hSQL, sName, sSafeName, 2 * strlen(sName) + 1);

	decl String:sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "UPDATE round SET name = '%s' WHERE auth = '%s';", sSafeName, auth);

	SQL_TQuery(g_hSQL, ChangeNameCallback, sQuery, _, DBPrio_High);
}

public ChangeNameCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on ChangeName: %s", error);
		return;
	}
	
	RefreshCache();
}


public Action_OnSettingsChange(Handle:cvar, const String:oldvalue[], const String:newvalue[])
{
	if (cvar == g_hCvarShowJumps)
	{
		g_bShowJumps = bool:StringToInt(newvalue);
	}
	else if (cvar == g_hCvarShowFlashbangs)
	{
		g_bShowFlashbangs = bool:StringToInt(newvalue);
	}

}

public Action:OnClientCommand(client, args)
{
	new String:sCommand[16];
	GetCmdArg(0, sCommand, sizeof(sCommand));

	if (StrEqual(sCommand, "wr"))
	{
		if (g_bTimerPhysics)
		{
			ConsoleWR(client, Timer_GetClientDifficulty(client));
		}
		else
		{
			ConsoleWR(client, -1);
		}

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action:Command_WorldRecord(client, args)
{
	if (g_bTimerPhysics)
	{
		CreateDifficultyMenu(client);
	}
	else
	{
		CreateWRMenu(client, -1);
	}
	
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
		{
			target = targets[0];
		}
	}

	if (target == -1)
	{
		PrintToChat(client, PLUGIN_PREFIX, "No target");
	}
	else
	{
		decl String:sAuthID[MAX_AUTHID_LENGTH];
		GetClientAuthString(target, sAuthID, sizeof(sAuthID));

		for (new t = 0; t < g_cacheCount; t++)
		{
			if (StrEqual(g_cache[t][Auth], sAuthID))
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

	decl String:sAuthID[MAX_AUTHID_LENGTH];
	GetCmdArgString(sAuthID, sizeof(sAuthID));

	decl String:sQuery[128];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM round WHERE auth = '%s'", sAuthID);

	SQL_TQuery(g_hSQL, DeleteRecordsCallback, sQuery, _, DBPrio_High);
	
	return Plugin_Handled;
}

public Action:Command_DeleteRecord(client, args)
{	
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_deleterecord <steamid>");
		return Plugin_Handled;
	}
	
	decl String:sAuthID[MAX_AUTHID_LENGTH];
	GetCmdArgString(sAuthID, sizeof(sAuthID));

	decl String:sQuery[160];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM round WHERE auth = '%s' AND map = '%s'", sAuthID, g_sCurrentMap);

	SQL_TQuery(g_hSQL, DeleteRecordsCallback, sQuery, _, DBPrio_High);
	
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
	new String:sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/timer/difficulties.cfg");

	new Handle:hKv = CreateKeyValues("difficulties");
	if (!FileToKeyValues(hKv, sPath))
	{
		CloseHandle(hKv);
		return;
	}

	g_difficultyCount = 0;

	if (!KvGotoFirstSubKey(hKv))
	{
		CloseHandle(hKv);
		return;
	}
	
	do 
	{
		decl String:sSectionName[32];
		KvGetSectionName(hKv, sSectionName, sizeof(sSectionName));
		
		g_difficulties[g_difficultyCount][Id] = StringToInt(sSectionName);

		KvGetString(hKv, "name", g_difficulties[g_difficultyCount][Name], 32);
		g_difficulties[g_difficultyCount][IsDefault] = bool:KvGetNum(hKv, "default", 0);

		g_difficultyCount++;
	} while (KvGotoNextKey(hKv));
	
	CloseHandle(hKv);	
}

public OnAdminMenuReady(Handle:topmenu)
{
	// Block this from being called twice
	if (topmenu == hTopMenu) 
	{
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

public AdminMenu_CategoryHandler(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayTitle)
	{
		FormatEx(buffer, maxlength, "%t", "Timer Management");
	} 
	else if (action == TopMenuAction_DisplayOption) 
	{
		FormatEx(buffer, maxlength, "%t", "Timer Management");
	}
}

public AdminMenu_DeleteMapRecords(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption) 
	{
		FormatEx(buffer, maxlength, "%t", "Delete Map Records");
	} 
	else if (action == TopMenuAction_SelectOption) 
	{
		decl String:sMap[MAX_MAPNAME_LENGTH];
		GetCurrentMap(sMap, sizeof(sMap));
		
		DeleteMapRecords(sMap);
	}
}

public AdminMenu_DeleteRecord(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption) 
	{
		FormatEx(buffer, maxlength, "%t", "Delete Player Record");
	} 
	else if (action == TopMenuAction_SelectOption) 
	{
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
		{
			continue;
		}
		
		decl String:sText[92];
		FormatEx(sText, sizeof(sText), "#%d: %s - %s", (cache + 1), g_cache[cache][Name], g_cache[cache][TimeString]);
		
		if (g_bShowJumps)
		{
			Format(sText, sizeof(sText), "%s (%d %T)", sText, g_cache[cache][Jumps], "Jumps", client);
		}
		
		if (g_bShowFlashbangs)
		{
			Format(sText, sizeof(sText), "%s (%d %T)", sText, g_cache[cache][Flashbangs], "Flashbangs", client);
		}

		AddMenuItem(menu, g_cache[cache][Auth], sText);
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
		decl String:sInfo[32];		
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		decl String:sQuery[256];
		FormatEx(sQuery, sizeof(sQuery), "DELETE FROM `round` WHERE auth = '%s' AND map = '%s'", sInfo, g_sCurrentMap);

		SQL_TQuery(g_hSQL, DeletePlayersRecordCallback, sQuery, param1, DBPrio_High);
		
		for (new cache = 0; cache < g_cacheCount; cache++)
		{
			if (StrEqual(g_cache[cache][Auth], sInfo))
			{
				g_cache[cache][Ignored] = true;
			}
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
	decl String:sQuery[96];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM `round` WHERE map = '%s'", map);	

	SQL_TQuery(g_hSQL, DeleteMapRecordsCallback, sQuery, _, DBPrio_High);
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
	g_bCacheLoaded = false;
	LoadDifficulties();

	if (g_hSQL == INVALID_HANDLE)
	{
		ConnectSQL(true);
	}
	else
	{	
		decl String:sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), "SELECT m.id, m.auth, m.time, MAX(m.jumps) jumps, m.physicsdifficulty, m.name, MAX(m.flashbangs) flashbangs FROM round AS m INNER JOIN (SELECT MIN(n.time) time, n.auth FROM round n WHERE n.map = '%s' GROUP BY n.physicsdifficulty, n.auth) AS j ON (j.time = m.time AND j.auth = m.auth) WHERE m.map = '%s' GROUP BY m.physicsdifficulty, m.auth ORDER BY m.time ASC LIMIT 0, 1000", g_sCurrentMap, g_sCurrentMap);	
		
		SQL_TQuery(g_hSQL, RefreshCacheCallback, sQuery, _, DBPrio_High);
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
		SQL_FetchString(hndl, 1, g_cache[g_cacheCount][Auth], MAX_AUTHID_LENGTH);
		Timer_SecondsToTime(SQL_FetchFloat(hndl, 2), g_cache[g_cacheCount][TimeString], 16, true);
		g_cache[g_cacheCount][Jumps] = SQL_FetchInt(hndl, 3);
		g_cache[g_cacheCount][RecordPhysicsDifficulty] = SQL_FetchInt(hndl, 4);
		SQL_FetchString(hndl, 5, g_cache[g_cacheCount][Name], MAX_NAME_LENGTH);
		g_cache[g_cacheCount][Flashbangs] = SQL_FetchInt(hndl, 6);
		g_cache[g_cacheCount][Ignored] = false;
		
		g_cacheCount++;
	}
	
	Timer_ForceReloadBestRoundCache();
	
	Timer_GetTotalRank(true);
	
	g_bCacheLoaded = true;
}

ConnectSQL(bool:refreshCache)
{
	if (g_hSQL != INVALID_HANDLE)
	{
		CloseHandle(g_hSQL);
	}
	
	g_hSQL = INVALID_HANDLE;

	if (SQL_CheckConfig("timer"))
	{
		SQL_TConnect(ConnectSQLCallback, "timer", refreshCache);
	}
	else
	{
		SetFailState("PLUGIN STOPPED - Reason: no config entry found for 'timer' in databases.cfg - PLUGIN STOPPED");
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
		ConnectSQL(data);
		
		return;
	}

	decl String:sDriver[16];
	SQL_GetDriverIdent(owner, sDriver, sizeof(sDriver));
	
	if (StrEqual(sDriver, "mysql", false))
	{
		SQL_TQuery(hndl, SetNamesCallback, "SET NAMES  'utf8'", _, DBPrio_High);
	}

	g_hSQL = CloneHandle(hndl);

	g_iReconnectCounter = 1;

	if (data)
	{
		RefreshCache();	
	}
}

public SetNamesCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{	
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on SetNames: %s", error);
		return;
	}
}


CreateDifficultyMenu(client)
{
	if (!g_bCacheLoaded)
	{
		PrintToChat(client, PLUGIN_PREFIX, "World Record Loading");
		return;	
	}

	new Handle:menu = CreateMenu(MenuHandler_Difficulty);

	SetMenuTitle(menu, "%T", "Physics Difficulty", client);
	SetMenuExitButton(menu, true);

	for (new difficulty = 0; difficulty < g_difficultyCount; difficulty++)
	{
		decl String:sID[5];
		IntToString(g_difficulties[difficulty][Id], sID, sizeof(sID));
		
		AddMenuItem(menu, sID, g_difficulties[difficulty][Name]);
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
		decl String:sInfo[32];		
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		CreateWRMenu(param1, StringToInt(sInfo));
	}
}

CreateWRMenu(client, difficulty)
{
	new Handle:menu = CreateMenu(MenuHandler_WR);

	SetMenuTitle(menu, "%T (%d)", "World Record Menu Title", client, g_sCurrentMap, g_cacheCount);
	
	if (g_bTimerPhysics)
	{
		SetMenuExitBackButton(menu, true);
	}
	else
	{
		SetMenuExitButton(menu, true);
	}
	
	new items = 0; 

	for (new cache = 0; cache < g_cacheCount; cache++)
	{	
		if (difficulty == -1 || g_cache[cache][RecordPhysicsDifficulty] == difficulty)
		{
			decl String:sID[5];
			IntToString(g_cache[cache][Id], sID, sizeof(sID));
			
			decl String:sText[92];
			FormatEx(sText, sizeof(sText), "#%d: %s - %s", (cache + 1), g_cache[cache][Name], g_cache[cache][TimeString]);
			
			if (g_bShowJumps)
			{
				Format(sText, sizeof(sText), "%s (%d %T)", sText, g_cache[cache][Jumps], "Jumps", client);
			}
			
			if (g_bShowFlashbangs)
			{
				Format(sText, sizeof(sText), "%s (%d %T)", sText, g_cache[cache][Flashbangs], "Flashbangs", client);
			}
			
			AddMenuItem(menu, sID, sText);
			items++;
		}
	}

	if (items == 0)
	{	
		if (difficulty == -1)
		{
			PrintToChat(client, PLUGIN_PREFIX, "No Records");	
		}
		else
		{
			PrintToChat(client, PLUGIN_PREFIX, "No Difficulty Records");
		}
		
		CloseHandle(menu);
		return;
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
			if (g_bTimerPhysics)
			{
				CreateDifficultyMenu(param1);
			}
		}
	} 
	else if (action == MenuAction_Select) 
	{
		decl String:sInfo[32];		
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		CreatePlayerInfoMenu(param1, StringToInt(sInfo), true);
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
			decl String:sDifficulty[5];
			IntToString(g_cache[cache][RecordPhysicsDifficulty], sDifficulty, sizeof(sDifficulty));

			decl String:sText[92];

			SetMenuTitle(menu, "%T\n \n", "Record Info", client);

			FormatEx(sText, sizeof(sText), "%T: %s (%s)", "Player Name", client, g_cache[cache][Name], g_cache[cache][Auth]);
			AddMenuItem(menu, sDifficulty, sText);

			FormatEx(sText, sizeof(sText), "%T: #%d on %s", "Rank", client, cache + 1, g_sCurrentMap);
			AddMenuItem(menu, sDifficulty, sText);

			FormatEx(sText, sizeof(sText), "%T: %s", "Time", client, g_cache[cache][TimeString]);
			AddMenuItem(menu, sDifficulty, sText);
			
			if (g_bShowJumps)
			{
				FormatEx(sText, sizeof(sText), "%T: %d", "Jumps", client, g_cache[cache][Jumps]);
				AddMenuItem(menu, sDifficulty, sText);
			}
			
			if (g_bShowFlashbangs)
			{
				FormatEx(sText, sizeof(sText), "%T: %d", "Flashbangs", client, g_cache[cache][Flashbangs]);
				AddMenuItem(menu, sDifficulty, sText);
			}
			
			if (g_bTimerPhysics)
			{
				decl String:difficultyName[32];
				Timer_GetDifficultyName(g_cache[cache][RecordPhysicsDifficulty], difficultyName, sizeof(difficultyName));
				
				FormatEx(sText, sizeof(sText), "%T: %s", "Physics Difficulty", client, difficultyName);
				AddMenuItem(menu, sDifficulty, sText);
			}
			
			if (back)
			{
				AddMenuItem(menu, sDifficulty, "Back");
			}

			break;
		}
		
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);	
}

ConsoleWR(client, difficulty)
{
	if (g_bTimerPhysics)
	{
		PrintToConsole(client, "difficulty: %s", g_difficulties[difficulty][Name]);
	}
	
	PrintToConsole(client, "map: %s\n", g_sCurrentMap);

	PrintToConsole(client, "# rank\tname\t\t\tsteamid\t\t\ttime\t\tjumps\t\tflashbangs");

	for (new cache = 0; cache < g_cacheCount; cache++)
	{
		if (!g_bTimerPhysics || g_cache[cache][RecordPhysicsDifficulty] == difficulty)
		{
			PrintToConsole(client, "# %d\t%s\t%s\t%s\t%d\t%d",
			cache + 1,
			g_cache[cache][Name],
			g_cache[cache][Auth],
			g_cache[cache][TimeString],
			g_cache[cache][Jumps],
			g_cache[cache][Flashbangs]);		
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
		decl String:sAuthID[MAX_AUTHID_LENGTH];
		GetClientAuthString(client, sAuthID, sizeof(sAuthID));
		
		decl String:sQuery[256];
		FormatEx(sQuery, sizeof(sQuery), "SELECT id, time, jumps, physicsdifficulty, auth, flashbangs FROM `round` WHERE map = '%s' AND auth = '%s' ORDER BY physicsdifficulty, time, jumps, flashbangs", g_sCurrentMap, sAuthID);	
		
		g_iDeleteMenuSelection[client] = target;
		SQL_TQuery(g_hSQL, CreateDeleteMenuCallback, sQuery, client, DBPrio_Normal);
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
	
	decl String:sAuthID[MAX_AUTHID_LENGTH];
	GetClientAuthString(client, sAuthID, sizeof(sAuthID));
	
	while (SQL_FetchRow(hndl))
	{
		decl String:sSteamID[MAX_AUTHID_LENGTH];
		SQL_FetchString(hndl, 4, sSteamID, sizeof(sSteamID));
		
		if (!StrEqual(sSteamID, sAuthID))
		{
			CloseHandle(menu);
			return;
		}
		
		decl String:sID[10];
		IntToString(SQL_FetchInt(hndl, 0), sID, sizeof(sID));

		decl String:sTime[16];
		Timer_SecondsToTime(SQL_FetchFloat(hndl, 1), sTime, sizeof(sTime));
		
		new String:sDifficulty[32];	
		
		if (g_bTimerPhysics)
		{
			Timer_GetDifficultyName(SQL_FetchInt(hndl, 3), sDifficulty, sizeof(sDifficulty));
		}

		decl String:sValue[92];
		FormatEx(sValue, sizeof(sValue), "%s %s", sTime, sDifficulty);
		
		if (g_bShowJumps)
		{
			Format(sValue, sizeof(sValue), "%s %T: %d", sValue, "Jumps", client, SQL_FetchInt(hndl, 2));
		}

		if (g_bShowFlashbangs)
		{
			Format(sValue, sizeof(sValue), "%s %T: %d", sValue, "Flashbangs", client, SQL_FetchInt(hndl, 5));
		}	
		
		AddMenuItem(menu, sID, sValue);
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
		decl String:sInfo[32];		
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));

		decl String:sQuery[256];
		FormatEx(sQuery, sizeof(sQuery), "SELECT id, auth, time, map, jumps, physicsdifficulty, flashbangs FROM `round` WHERE id = %s", sInfo);	
		
		SQL_TQuery(g_hSQL, GetRecordInfoBeforeDelete, sQuery, param1, DBPrio_Normal);
	}
}

public GetRecordInfoBeforeDelete(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on GetRecordInfoBeforeDelete: %s", error);
		return;
	}

	new id = SQL_FetchInt(hndl, 0);

	decl String:auth[32];
	SQL_FetchString(hndl, 1, auth, sizeof(auth));

	new Float:time = SQL_FetchFloat(hndl, 2);

	decl String:map[32];
	SQL_FetchString(hndl, 3, map, sizeof(map));	

	new jumps = SQL_FetchInt(hndl, 4);
	new difficulty = SQL_FetchInt(hndl, 5);
	new flashbangs = SQL_FetchInt(hndl, 6);

	Call_StartForward(g_hTimerDeleteRecordForward);
	Call_PushCell(client);
	Call_PushFloat(time);
	Call_PushString(map);
	Call_PushCell(jumps);
	Call_PushCell(difficulty);
	Call_PushCell(flashbangs);
	Call_Finish();

	decl String:sQuery[64];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM `round` WHERE id = %d", id);	

	SQL_TQuery(g_hSQL, DeleteRecordCallback, sQuery, client, DBPrio_High);
}

public DeleteRecordCallback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on DeleteRecord: %s", error);
		return;
	}

	CreateDeleteMenu(client, g_iDeleteMenuSelection[client]);
}

public Native_ForceReloadWorldRecordCache(Handle:plugin, numParams)
{
	RefreshCache();
}