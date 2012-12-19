#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <adminmenu>
#include <smlib/arrays>
#include <timer>
#include <timer-logging>

#undef REQUIRE_PLUGIN
#include <timer-physics>
#include <timer-worldrecord>
#include <updater>

#define UPDATE_URL "http://dl.dropbox.com/u/16304603/timer/updateinfo-timer-mapzones.txt"

/**
* Global Enums
*/
enum MapZoneEditor
{
	Step,
	Float:Point1[3],
	Float:Point2[3]
}

/**
* Global Variables
*/
new Handle:g_hSQL;

new Handle:g_hCvarStartMapZoneColor = INVALID_HANDLE;
new Handle:g_hCvarEndMapZoneColor = INVALID_HANDLE;
new Handle:g_hCvarStopPrespeed = INVALID_HANDLE;
new Handle:g_hCvarDrawMapZones = INVALID_HANDLE;

new g_startColor[4] = {0, 255, 0, 255};
new g_endColor[4] = {0, 0, 255, 255};
new bool:g_bStopPrespeed = false;
new bool:g_bDrawMapZones = true;

new String:g_sCurrentMap[MAX_MAPNAME_LENGTH];
new g_iReconnectCounter = 0;

new g_mapZones[64][MapZone];
new g_mapZonesCount = 0;

new Handle:hTopMenu = INVALID_HANDLE;
new TopMenuObject:oMapZoneMenu;

new g_mapZoneEditors[MAXPLAYERS+1][MapZoneEditor];

new g_precacheLaser;

new bool:g_bTimerPhysics = false;
new bool:g_bTimerWorldRecord = false;

public Plugin:myinfo =
{
	name        = "[Timer] MapZones",
	author      = "alongub | Glite",
	description = "Map Zones component for [Timer]",
	version     = PL_VERSION,
	url         = "https://github.com/alongubkin/timer"
};

public OnPluginStart()
{
	ConnectSQL();
	
	g_bTimerPhysics = LibraryExists("timer-physics");
	g_bTimerWorldRecord = LibraryExists("timer-worldrecord");	
	LoadTranslations("timer.phrases");

	g_hCvarStartMapZoneColor = CreateConVar("timer_startcolor", "0 255 0 255", "The color of the start map zone.");
	g_hCvarEndMapZoneColor = CreateConVar("timer_endcolor", "0 0 255 255", "The color of the end map zone.");
	g_hCvarStopPrespeed = CreateConVar("timer_stopprespeeding", "0", "If enabled players won't be able to prespeed in start zone.");
	g_hCvarDrawMapZones = CreateConVar("timer_drawzones", "1", "If enabled map zones will be drawn.");
	
	HookConVarChange(g_hCvarStartMapZoneColor, Action_OnSettingsChange);
	HookConVarChange(g_hCvarEndMapZoneColor, Action_OnSettingsChange);	
	HookConVarChange(g_hCvarStopPrespeed, Action_OnSettingsChange);
	HookConVarChange(g_hCvarDrawMapZones, Action_OnSettingsChange);
	
	AutoExecConfig(true, "timer-mapzones");
	
	g_bStopPrespeed = GetConVarBool(g_hCvarStopPrespeed);
	g_bDrawMapZones = GetConVarBool(g_hCvarDrawMapZones);
	
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

public OnMapStart()
{
	GetCurrentMap(g_sCurrentMap, sizeof(g_sCurrentMap));
	StringToLower(g_sCurrentMap);
	
	g_precacheLaser = PrecacheModel("materials/sprites/laserbeam.vmt");
	
	LoadMapZones();
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "timer-physics"))
	{
		g_bTimerPhysics = true;
	}
	else if (StrEqual(name, "timer-worldrecord"))
	{
		g_bTimerWorldRecord = true;
	}
	else if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}	
}

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, "adminmenu"))
	{
		hTopMenu = INVALID_HANDLE;
	}
	else if (StrEqual(name, "timer-physics"))
	{
		g_bTimerPhysics = false;
	}
	else if (StrEqual(name, "timer-worldrecord"))
	{
		g_bTimerWorldRecord = false;
	}
}

public Action_OnSettingsChange(Handle:cvar, const String:oldvalue[], const String:newvalue[])
{
	if (cvar == g_hCvarStartMapZoneColor)
	{
		ParseColor(newvalue, g_startColor);
	}
	else if (cvar == g_hCvarEndMapZoneColor)
	{
		ParseColor(newvalue, g_endColor);
	}
	else if (cvar == g_hCvarStopPrespeed)
	{
		g_bStopPrespeed = bool:StringToInt(newvalue);
	}
	else if (cvar == g_hCvarDrawMapZones)
	{
		g_bDrawMapZones = bool:StringToInt(newvalue);
		
		if (g_bDrawMapZones)
		{
			CreateTimer(2.0, DrawZones, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}
	}
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
	"timer_mapzones_add",
	TopMenuObject_Item,
	AdminMenu_AddMapZone,
	oMapZoneMenu,
	"timer_mapzones_add",
	ADMFLAG_RCON);

	AddToTopMenu(hTopMenu, 
	"timer_mapzones_remove",
	TopMenuObject_Item,
	AdminMenu_RemoveMapZone,
	oMapZoneMenu,
	"timer_mapzones_remove",
	ADMFLAG_RCON);

	AddToTopMenu(hTopMenu, 
	"timer_mapzones_remove_all",
	TopMenuObject_Item,
	AdminMenu_RemoveAllMapZones,
	oMapZoneMenu,
	"timer_mapzones_remove_all",
	ADMFLAG_RCON);

}

AddMapZone(String:map[], MapZoneType:type, Float:point1[3], Float:point2[3])
{
	decl String:sQuery[512];
	
	if (type == Start || type == End)
	{
		decl String:sDeleteQuery[128];
		FormatEx(sDeleteQuery, sizeof(sDeleteQuery), "DELETE FROM mapzone WHERE map = '%s' AND type = %d;", map, type);

		SQL_TQuery(g_hSQL, AddMapZoneCallback, sDeleteQuery, _, DBPrio_High);	
	}

	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO mapzone (map, type, point1_x, point1_y, point1_z, point2_x, point2_y, point2_z) VALUES ('%s', '%d', %f, %f, %f, %f, %f, %f);", map, type, point1[0], point1[1], point1[2], point2[0], point2[1], point2[2]);

	SQL_TQuery(g_hSQL, AddMapZoneCallback, sQuery, _, DBPrio_Normal);	
}

public AddMapZoneCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on AddMapZone: %s", error);
		return;
	}
	
	LoadMapZones();
}

LoadMapZones()
{
	if (g_hSQL == INVALID_HANDLE)
	{
		ConnectSQL();
	}
	else
	{	
		decl String:sQuery[384];
		FormatEx(sQuery, sizeof(sQuery), "SELECT id, type, point1_x, point1_y, point1_z, point2_x, point2_y, point2_z FROM mapzone WHERE map = '%s'", g_sCurrentMap);

		SQL_TQuery(g_hSQL, LoadMapZonesCallback, sQuery, _, DBPrio_High);
	}
}

public LoadMapZonesCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on LoadMapZones: %s", error);
		return;
	}

	g_mapZonesCount = 0;

	while (SQL_FetchRow(hndl))
	{
		strcopy(g_mapZones[g_mapZonesCount][Map], MAX_MAPNAME_LENGTH, g_sCurrentMap);
		
		g_mapZones[g_mapZonesCount][Id] = SQL_FetchInt(hndl, 0);
		g_mapZones[g_mapZonesCount][Type] = MapZoneType:SQL_FetchInt(hndl, 1);
		
		g_mapZones[g_mapZonesCount][Point1][0] = SQL_FetchFloat(hndl, 2);
		g_mapZones[g_mapZonesCount][Point1][1] = SQL_FetchFloat(hndl, 3);
		g_mapZones[g_mapZonesCount][Point1][2] = SQL_FetchFloat(hndl, 4);
		
		g_mapZones[g_mapZonesCount][Point2][0] = SQL_FetchFloat(hndl, 5);
		g_mapZones[g_mapZonesCount][Point2][1] = SQL_FetchFloat(hndl, 6);
		g_mapZones[g_mapZonesCount][Point2][2] = SQL_FetchFloat(hndl, 7);
		
		g_mapZonesCount++;
	}
	
	if (g_bDrawMapZones)
	{
		CreateTimer(2.0, DrawZones, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	
	CreateTimer(0.1, PlayerTracker, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public OnTimerRestart(client)
{
	for (new mapZone = 0; mapZone < g_mapZonesCount; mapZone++)
	{
		if (g_mapZones[mapZone][Type] == Start)
		{		
			new Float:vCenter[3];
			vCenter[0] = (g_mapZones[mapZone][Point1][0] + g_mapZones[mapZone][Point2][0]) / 2.0;
			vCenter[1] = (g_mapZones[mapZone][Point1][1] + g_mapZones[mapZone][Point2][1]) / 2.0;
			vCenter[2] = ((g_mapZones[mapZone][Point1][2] + g_mapZones[mapZone][Point2][2]) / 2.0) - 40.0;
			
			TeleportEntity(client, vCenter, Float:{0.0, 0.0, 0.0}, Float:{0.0, 0.0, 0.0});

			break;
		}
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
		ConnectSQL();
		
		return;
	}

	decl String:sDriver[16];
	SQL_GetDriverIdent(owner, sDriver, sizeof(sDriver));

	g_hSQL = CloneHandle(hndl);
	
	if (StrEqual(sDriver, "mysql", false))
	{
		SQL_TQuery(g_hSQL, SetNamesCallback, "SET NAMES  'utf8'", _, DBPrio_High);
		SQL_TQuery(g_hSQL, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `mapzone` (`id` int(11) NOT NULL AUTO_INCREMENT, `type` int(11) NOT NULL, `point1_x` float NOT NULL, `point1_y` float NOT NULL, `point1_z` float NOT NULL, `point2_x` float NOT NULL, `point2_y` float NOT NULL, `point2_z` float NOT NULL, `map` varchar(32) NOT NULL, PRIMARY KEY (`id`));");
	}
	else if (StrEqual(sDriver, "sqlite", false))
	{
		SQL_TQuery(g_hSQL, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `mapzone` (`id` INTEGER PRIMARY KEY, `type` INTEGER NOT NULL, `point1_x` float NOT NULL, `point1_y` float NOT NULL, `point1_z` float NOT NULL, `point2_x` float NOT NULL, `point2_y` float NOT NULL, `point2_z` float NOT NULL, `map` varchar(32) NOT NULL);");
	}
	
	g_iReconnectCounter = 1;
}

public SetNamesCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on SetNames: %s", error);
		return;
	}
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
	
	LoadMapZones();
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

public AdminMenu_AddMapZone(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption) 
	{
		FormatEx(buffer, maxlength, "%t", "Add Map Zone");
	} 
	else if (action == TopMenuAction_SelectOption) 
	{
		RestartMapZoneEditor(param);
		g_mapZoneEditors[param][Step] = 1;
		DisplaySelectPointMenu(param, 1);
	}
}

public AdminMenu_RemoveMapZone(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%t", "Delete Map Zone");
	} 
	else if (action == TopMenuAction_SelectOption) 
	{
		DeleteMapZone(param);
	}
}

public AdminMenu_RemoveAllMapZones(Handle:topmenu,  TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption) 
	{
		FormatEx(buffer, maxlength, "%t", "Delete All Map Zones");
	} 
	else if (action == TopMenuAction_SelectOption) 
	{
		DeleteAllMapZones(param);
	}
}

RestartMapZoneEditor(client)
{
	g_mapZoneEditors[client][Step] = 0;

	for (new i = 0; i < 3; i++)
	{
		g_mapZoneEditors[client][Point1][i] = 0.0;
	}

	for (new i = 0; i < 3; i++)
	{
		g_mapZoneEditors[client][Point1][i] = 0.0;	
	}
}

DeleteMapZone(client)
{
	new Float:vOrigin[3];
	GetClientAbsOrigin(client, vOrigin);
	
	for (new zone = 0; zone < g_mapZonesCount; zone++)
	{
		if (IsInsideBox(vOrigin, g_mapZones[zone][Point1][0], g_mapZones[zone][Point1][1], g_mapZones[zone][Point1][2], g_mapZones[zone][Point2][0], g_mapZones[zone][Point2][1], g_mapZones[zone][Point2][2]))
		{
			decl String:sQuery[64];
			FormatEx(sQuery, sizeof(sQuery), "DELETE FROM mapzone WHERE id = %d", g_mapZones[zone][Id]);

			SQL_TQuery(g_hSQL, DeleteMapZoneCallback, sQuery, client, DBPrio_High);	
			break;
		}
	}
}

DeleteAllMapZones(client)
{
	decl String:sQuery[96];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM mapzone WHERE map = '%s'", g_sCurrentMap);

	SQL_TQuery(g_hSQL, DeleteMapZoneCallback, sQuery, client, DBPrio_High);
}

public DeleteMapZoneCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		Timer_LogError("SQL Error on DeleteMapZone: %s", error);
		return;
	}

	LoadMapZones();
	
	if (IsClientInGame(data))
	{
		PrintToChat(data, PLUGIN_PREFIX, "Map Zone Delete");
	}
}

DisplaySelectPointMenu(client, n)
{
	new Handle:panel = CreatePanel();

	decl String:sMessage[255];
	decl String:sFirst[32], String:sSecond[32];
	FormatEx(sFirst, sizeof(sFirst), "%t", "FIRST");
	FormatEx(sSecond, sizeof(sSecond), "%t", "SECOND");
	
	FormatEx(sMessage, sizeof(sMessage), "%t", "Point Select Panel", (n == 1) ? sFirst : sSecond);

	DrawPanelItem(panel, sMessage, ITEMDRAW_RAWLINE);

	FormatEx(sMessage, sizeof(sMessage), "%t", "Cancel");
	DrawPanelItem(panel, sMessage);

	SendPanelToClient(panel, client, PointSelect, 540);
	CloseHandle(panel);
}

DisplayPleaseWaitMenu(client)
{
	new Handle:panel = CreatePanel();
	
	decl String:sWait[64];
	FormatEx(sWait, sizeof(sWait), "%t", "Please wait");
	DrawPanelItem(panel, sWait, ITEMDRAW_RAWLINE);

	SendPanelToClient(panel, client, PointSelect, 540);
	CloseHandle(panel);
}

public PointSelect(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End) 
	{
		CloseHandle(menu);
	} 
	else if (action == MenuAction_Select) 
	{
		if (param2 == MenuCancel_Exit && hTopMenu != INVALID_HANDLE) 
		{
			DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
		}

		RestartMapZoneEditor(param1);
	}
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if (buttons & IN_ATTACK2)
	{
		if (g_mapZoneEditors[client][Step] == 1)
		{
			new Float:vOrigin[3];			
			GetClientAbsOrigin(client, vOrigin);
			g_mapZoneEditors[client][Point1] = vOrigin;

			DisplayPleaseWaitMenu(client);

			CreateTimer(1.0, ChangeStep, GetClientSerial(client));
			return Plugin_Handled;
		}
		else if (g_mapZoneEditors[client][Step] == 2)
		{
			new Float:vOrigin[3];
			GetClientAbsOrigin(client, vOrigin);
			g_mapZoneEditors[client][Point2] = vOrigin;

			g_mapZoneEditors[client][Step] = 3;

			DisplaySelectZoneTypeMenu(client);

			return Plugin_Handled;
		}		
	}

	return Plugin_Continue;
}

public Action:ChangeStep(Handle:timer, any:serial)
{
	new client = GetClientFromSerial(serial);
	
	g_mapZoneEditors[client][Step] = 2;
	CreateTimer(0.1, DrawAdminBox, GetClientSerial(client), TIMER_REPEAT);

	DisplaySelectPointMenu(client, 2);
}

DisplaySelectZoneTypeMenu(client)
{
	new Handle:menu = CreateMenu(ZoneTypeSelect);
	SetMenuTitle(menu, "%T", "Select zone type", client);
	
	decl String:sText[256];
	
	FormatEx(sText, sizeof(sText), "%T", "Start", client);
	AddMenuItem(menu, "0", sText);

	FormatEx(sText, sizeof(sText), "%T", "End", client);
	AddMenuItem(menu, "1", sText);
	
	FormatEx(sText, sizeof(sText), "%T", "Glitch1", client);
	AddMenuItem(menu, "2", sText);
	
	FormatEx(sText, sizeof(sText), "%T", "Glitch2", client);
	AddMenuItem(menu, "3", sText);
	
	FormatEx(sText, sizeof(sText), "%T", "Glitch3", client);
	AddMenuItem(menu, "4", sText);
	
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 360);
}

public ZoneTypeSelect(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End) 
	{
		CloseHandle(menu);
		RestartMapZoneEditor(param1);
	} 
	else if (action == MenuAction_Cancel) 
	{
		if (param2 == MenuCancel_Exit && hTopMenu != INVALID_HANDLE) 
		{
			DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
			RestartMapZoneEditor(param1);
		}
	}
	else if (action == MenuAction_Select) 
	{
		new Float:point1[3];
		Array_Copy(g_mapZoneEditors[param1][Point1], point1, 3);

		new Float:point2[3];
		Array_Copy(g_mapZoneEditors[param1][Point2], point2, 3);

		point1[2] -= 2;
		point2[2] += 100;

		AddMapZone(g_sCurrentMap, MapZoneType:param2, point1, point2);
		RestartMapZoneEditor(param1);
		LoadMapZones();
	}
}

public Action:DrawAdminBox(Handle:timer, any:serial)
{
	new client = GetClientFromSerial(serial);
	
	if (g_mapZoneEditors[client][Step] == 0)
	{
		return Plugin_Stop;
	}
	
	new Float:a[3], Float:b[3];

	Array_Copy(g_mapZoneEditors[client][Point1], b, 3);

	if (g_mapZoneEditors[client][Step] == 3)
	{
		Array_Copy(g_mapZoneEditors[client][Point2], a, 3);
	}
	else
	{
		GetClientAbsOrigin(client, a);
	}

	// Effect_DrawBeamBoxToClient(client, a, b, g_precacheLaser, 0, 0, 30, 0.1, 3.0, 3.0);
	new color[4] = {255, 255, 255, 255};

	DrawBox(a, b, 0.1, color, false);
	return Plugin_Continue;
}

public Action:DrawZones(Handle:timer)
{
	if (!g_bDrawMapZones)
	{
		return Plugin_Stop;
	}
	
	for (new zone = 0; zone < g_mapZonesCount; zone++)
	{
		if (g_mapZones[zone][Type] == Start || g_mapZones[zone][Type] == End)
		{
			new Float:point1[3];
			Array_Copy(g_mapZones[zone][Point1], point1, 3);

			new Float:point2[3];
			Array_Copy(g_mapZones[zone][Point2], point2, 3);
			
			if (point1[2] < point2[2])
			{
				point2[2] = point1[2];
			}
			else
			{
				point1[2] = point2[2];
			}

			if (g_mapZones[zone][Type] == Start)
			{
				DrawBox(point1, point2, 2.0, g_startColor, true);
			}
			else if (g_mapZones[zone][Type] == End)
			{
				DrawBox(point1, point2, 2.0, g_endColor, true);
			}
		}
	}

	return Plugin_Continue;
}

public Action:PlayerTracker(Handle:timer)
{
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && IsPlayerAlive(client) && !IsClientObserver(client))
		{
			new Float:vOrigin[3];
			GetClientAbsOrigin(client, vOrigin);
			
			for (new zone = 0; zone < g_mapZonesCount; zone++)
			{
				if (IsInsideBox(vOrigin, g_mapZones[zone][Point1][0], g_mapZones[zone][Point1][1], g_mapZones[zone][Point1][2], g_mapZones[zone][Point2][0], g_mapZones[zone][Point2][1], g_mapZones[zone][Point2][2]))
				{
					if (g_mapZones[zone][Type] == Start)
					{
						Timer_Stop(client, false);
						Timer_Start(client);
						
						if (g_bStopPrespeed)
						{
							StopPrespeed(client);
						}
					}
					else if (g_mapZones[zone][Type] == End)
					{
						if (Timer_Stop(client, false))
						{
							new bool:enabled = false;
							new jumps, fpsmax, flashbangs;
							new Float:time;

							if (Timer_GetClientTimer(client, enabled, time, jumps, fpsmax, flashbangs))
							{
								new difficulty = 0;
								if (g_bTimerPhysics)
								{
									difficulty = Timer_GetClientDifficulty(client);
								}

								Timer_FinishRound(client, g_sCurrentMap, time, jumps, flashbangs, difficulty, fpsmax);
								
								if (g_bTimerWorldRecord)
								{
									Timer_ForceReloadWorldRecordCache();
								}
							}
						}
					}
					else if (g_mapZones[zone][Type] == Glitch1)
					{
						Timer_Stop(client);
					}
					else if (g_mapZones[zone][Type] == Glitch2)
					{
						Timer_Restart(client);
					}
					else if (g_mapZones[zone][Type] == Glitch3)
					{
						CS_RespawnPlayer(client);
					}

					break;
				}	
			}
		}		
	}

	return Plugin_Continue;
}

IsInsideBox(Float:fPCords[3], Float:fbsx, Float:fbsy, Float:fbsz, Float:fbex, Float:fbey, Float:fbez)
{
	new Float:fpx = fPCords[0];
	new Float:fpy = fPCords[1];
	new Float:fpz = fPCords[2];
	
	new bool:bX = false;
	new bool:bY = false;
	new bool:bZ = false;

	if (fbsx > fbex && fpx <= fbsx && fpx >= fbex)
	{
		bX = true;
	}
	else if (fbsx < fbex && fpx >= fbsx && fpx <= fbex)
	{
		bX = true;
	}
	
	if (fbsy > fbey && fpy <= fbsy && fpy >= fbey)
	{
		bY = true;
	}
	else if (fbsy < fbey && fpy >= fbsy && fpy <= fbey)
	{
		bY = true;
	}
	
	if (fbsz > fbez && fpz <= fbsz && fpz >= fbez)
	{
		bZ = true;
	}
	else if (fbsz < fbez && fpz >= fbsz && fpz <= fbez)
	{
		bZ = true;
	}
	
	if (bX && bY && bZ)
	{
		return true;
	}
	
	return false;
}

public Native_AddMapZone(Handle:plugin, numParams)
{
	decl String:map[32];
	GetNativeString(1, map, sizeof(map));
	
	new MapZoneType:type = GetNativeCell(2);	
	
	new Float:point1[3];
	GetNativeArray(3, point1, sizeof(point1));
	
	new Float:point2[3];
	GetNativeArray(3, point2, sizeof(point2));	
	
	AddMapZone(map, type, point1, point2);
}

DrawBox(Float:fFrom[3], Float:fTo[3], Float:fLife, color[4], bool:flat)
{
	//initialize tempoary variables bottom front
	decl Float:fLeftBottomFront[3];
	fLeftBottomFront[0] = fFrom[0];
	fLeftBottomFront[1] = fFrom[1];
	if(flat)
	{
		fLeftBottomFront[2] = fTo[2]-2;
	}
	else
	{
		fLeftBottomFront[2] = fTo[2];
	}
	
	decl Float:fRightBottomFront[3];
	fRightBottomFront[0] = fTo[0];
	fRightBottomFront[1] = fFrom[1];
	if(flat)
	{
		fRightBottomFront[2] = fTo[2]-2;
	}
	else
	{
		fRightBottomFront[2] = fTo[2];
	}
	
	//initialize tempoary variables bottom back
	decl Float:fLeftBottomBack[3];
	fLeftBottomBack[0] = fFrom[0];
	fLeftBottomBack[1] = fTo[1];
	if(flat)
	{
		fLeftBottomBack[2] = fTo[2]-2;
	}
	else
	{
		fLeftBottomBack[2] = fTo[2];
	}
	
	decl Float:fRightBottomBack[3];
	fRightBottomBack[0] = fTo[0];
	fRightBottomBack[1] = fTo[1];
	if(flat)
	{
		fRightBottomBack[2] = fTo[2]-2;
	}
	else
	{
		fRightBottomBack[2] = fTo[2];
	}
	
	//initialize tempoary variables top front
	decl Float:lefttopfront[3];
	lefttopfront[0] = fFrom[0];
	lefttopfront[1] = fFrom[1];
	if(flat)
	{
		lefttopfront[2] = fFrom[2]+2;
	}
	else
	{
		lefttopfront[2] = fFrom[2]+100;
	}
	
	decl Float:righttopfront[3];
	righttopfront[0] = fTo[0];
	righttopfront[1] = fFrom[1];
	if(flat)
	{
		righttopfront[2] = fFrom[2]+2;
	}
	else
	{
		righttopfront[2] = fFrom[2]+100;
	}
	
	//initialize tempoary variables top back
	decl Float:fLeftTopBack[3];
	fLeftTopBack[0] = fFrom[0];
	fLeftTopBack[1] = fTo[1];
	if(flat)
	{
		fLeftTopBack[2] = fFrom[2]+2;
	}
	else
	{
		fLeftTopBack[2] = fFrom[2]+100;
	}
	
	decl Float:fRightTopBack[3];
	fRightTopBack[0] = fTo[0];
	fRightTopBack[1] = fTo[1];
	if(flat)
	{
		fRightTopBack[2] = fFrom[2]+2;
	}
	else
	{
		fRightTopBack[2] = fFrom[2]+100;
	}
	
	//create the box
	TE_SetupBeamPoints(lefttopfront,righttopfront,g_precacheLaser,0,0,0,fLife,3.0,3.0,10,0.0,color,0);TE_SendToAll(0.0);//TE_SendToClient(client, 0.0);
	TE_SetupBeamPoints(lefttopfront,fLeftTopBack,g_precacheLaser,0,0,0,fLife,3.0,3.0,10,0.0,color,0);TE_SendToAll(0.0);//TE_SendToClient(client, 0.0);
	TE_SetupBeamPoints(fRightTopBack,fLeftTopBack,g_precacheLaser,0,0,0,fLife,3.0,3.0,10,0.0,color,0);TE_SendToAll(0.0);//TE_SendToClient(client, 0.0);
	TE_SetupBeamPoints(fRightTopBack,righttopfront,g_precacheLaser,0,0,0,fLife,3.0,3.0,10,0.0,color,0);TE_SendToAll(0.0);//TE_SendToClient(client, 0.0);

	if(!flat)
	{
		TE_SetupBeamPoints(fLeftBottomFront,fRightBottomFront,g_precacheLaser,0,0,0,fLife,3.0,3.0,10,0.0,color,0);TE_SendToAll(0.0);//TE_SendToClient(client, 0.0);
		TE_SetupBeamPoints(fLeftBottomFront,fLeftBottomBack,g_precacheLaser,0,0,0,fLife,3.0,3.0,10,0.0,color,0);TE_SendToAll(0.0);//TE_SendToClient(client, 0.0);
		TE_SetupBeamPoints(fLeftBottomFront,lefttopfront,g_precacheLaser,0,0,0,fLife,3.0,3.0,10,0.0,color,0);TE_SendToAll(0.0);//TE_SendToClient(client, 0.0);

		
		TE_SetupBeamPoints(fRightBottomBack,fLeftBottomBack,g_precacheLaser,0,0,0,fLife,3.0,3.0,10,0.0,color,0);TE_SendToAll(0.0);//TE_SendToClient(client, 0.0);
		TE_SetupBeamPoints(fRightBottomBack,fRightBottomFront,g_precacheLaser,0,0,0,fLife,3.0,3.0,10,0.0,color,0);TE_SendToAll(0.0);//TE_SendToClient(client, 0.0);
		TE_SetupBeamPoints(fRightBottomBack,fRightTopBack,g_precacheLaser,0,0,0,fLife,3.0,3.0,10,0.0,color,0);TE_SendToAll(0.0);//TE_SendToClient(client, 0.0);
		
		TE_SetupBeamPoints(fRightBottomFront,righttopfront,g_precacheLaser,0,0,0,fLife,3.0,3.0,10,0.0,color,0);TE_SendToAll(0.0);//TE_SendToClient(client, 0.0);
		TE_SetupBeamPoints(fLeftBottomBack,fLeftTopBack,g_precacheLaser,0,0,0,fLife,3.0,3.0,10,0.0,color,0);TE_SendToAll(0.0);//TE_SendToClient(client, 0.0);
	}
}

ParseColor(const String:color[], result[])
{
	decl String:buffers[4][4];
	ExplodeString(color, " ", buffers, sizeof(buffers), sizeof(buffers[]));
	
	for (new i = 0; i < sizeof(buffers); i++)
	{
		result[i] = StringToInt(buffers[i]);
	}
}

StopPrespeed(client)
{
	new Float:vVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVelocity);
	
	if (SquareRoot(Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0)) > (GetEntPropFloat(client, Prop_Data, "m_flMaxspeed") * 1.115 + 0.5))
	{
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, Float:{0.0, 0.0, 0.0});
	}	
}