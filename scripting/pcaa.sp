#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <multicolors>

#define PLUGIN_VERSION "1.0.0"
#define MAX_VALUE_LENGTH 16

ConVar g_hCVAirAccelerate;
ConVar g_hCVAdminFlag;

float g_fClientAA[MAXPLAYERS+1];
int g_iOriginalFlags;
float g_fOriginalValue;
Handle g_hCookie;

int g_iMenuTarget[MAXPLAYERS+1];  // Stores target client for each admin's menu

public Plugin myinfo = 
{
    name = "per-Client sv_airaccelerate",
    author = "hy1ex",
    description = "This plugin allows the admin to set the value of sv_airaccelerate convar per client.",
    version = PLUGIN_VERSION,
    url = "https://github.com/Hy1ex"
};

public void OnPluginStart()
{
    // Create convars
    g_hCVAdminFlag = CreateConVar("sm_pcaa_adminflag", "b", "Admin flag required for sm_pcaa command");
    AutoExecConfig(true, "pcaa");
    
    // Find and modify sv_airaccelerate
    g_hCVAirAccelerate = FindConVar("sv_airaccelerate");
    if (g_hCVAirAccelerate == null)
        SetFailState("Could not find sv_airaccelerate convar");
    
    g_iOriginalFlags = g_hCVAirAccelerate.Flags;
    g_fOriginalValue = g_hCVAirAccelerate.FloatValue;
    g_hCVAirAccelerate.Flags &= ~FCVAR_REPLICATED;
    
    // Create cookie for persistent storage
    g_hCookie = RegClientCookie("pcaa_value", "per-Client sv_airaccelerate", CookieAccess_Private);
    
    // Register commands
    RegAdminCmd("sm_pcaa", Command_PCAA, ADMFLAG_GENERIC, "per-Client sv_airaccelerate management menu");
    
    // Hook existing clients
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            OnClientPutInServer(i);
            if (AreClientCookiesCached(i)) 
                OnClientCookiesCached(i);
        }
    }
}

public void OnPluginEnd()
{
    // Restore original convar state
    if (g_hCVAirAccelerate != null)
    {
        g_hCVAirAccelerate.Flags = g_iOriginalFlags;
        g_hCVAirAccelerate.FloatValue = g_fOriginalValue;
    }
}

public void OnClientPutInServer(int client)
{
    if (IsFakeClient(client))
        return;
    
    // Set default value to server's original sv_airaccelerate
    g_fClientAA[client] = g_fOriginalValue;
    SDKHook(client, SDKHook_PreThink, OnPreThink);
    
    // Load from cookie if available
    if (AreClientCookiesCached(client))
        OnClientCookiesCached(client);
}

public void OnClientCookiesCached(int client)
{
    if (IsFakeClient(client))
        return;
    
    char sCookieValue[16];
    GetClientCookie(client, g_hCookie, sCookieValue, sizeof(sCookieValue));
    
    // Only use cookie value if it's not empty
    if (sCookieValue[0] != '\0')
        g_fClientAA[client] = StringToFloat(sCookieValue);
    
    SendConVarValueToClient(client);
}

public void OnClientDisconnect(int client)
{
    if (IsFakeClient(client) || !AreClientCookiesCached(client))
        return;
    
    char sCookieValue[16];
    FloatToString(g_fClientAA[client], sCookieValue, sizeof(sCookieValue));
    SetClientCookie(client, g_hCookie, sCookieValue);
}

public void OnPreThink(int client)
{
    if (!IsClientInGame(client)) 
        return;
    
    g_hCVAirAccelerate.FloatValue = g_fClientAA[client];
}

void SendConVarValueToClient(int client)
{
    char sValue[16];
    FloatToString(g_fClientAA[client], sValue, sizeof(sValue));
    SendConVarValue(client, g_hCVAirAccelerate, sValue);
}

public Action Command_PCAA(int client, int args)
{
    if (args == 0)
    {
        if (!CheckCommandAccess(client, "sm_pcaa", ADMFLAG_GENERIC))
        {
            CReplyToCommand(client, "[{green}PCAA{default}] You don't have access to this command");
            return Plugin_Handled;
        }
        
        ShowPlayerMenu(client);
        return Plugin_Handled;
    }
    
    if (args != 2)
    {
        CReplyToCommand(client, "[{green}PCAA{default}] Usage: sm_pcaa <target> <value>");
        return Plugin_Handled;
    }
    
    char sTarget[64], sValueArg[16];
    GetCmdArg(1, sTarget, sizeof(sTarget));
    GetCmdArg(2, sValueArg, sizeof(sValueArg));
    
    float fValue = StringToFloat(sValueArg);
    if (fValue < 0.0)
        fValue = 0.0;
    
    char sTargetName[MAX_TARGET_LENGTH];
    int iTargetList[MAXPLAYERS], iTargetCount;
    bool tnIsML;
    
    iTargetCount = ProcessTargetString(
        sTarget,
        client,
        iTargetList,
        MAXPLAYERS,
        COMMAND_FILTER_NO_BOTS,
        sTargetName,
        sizeof(sTargetName),
        tnIsML);
    
    if (iTargetCount <= 0)
    {
        // Custom error handling to avoid translation issues
        CReplyToCommand(client, "[{green}PCAA{default}] No matching players found");
        return Plugin_Handled;
    }
    
    for (int i = 0; i < iTargetCount; i++)
    {
        int iTarget = iTargetList[i];
        g_fClientAA[iTarget] = fValue;
        SendConVarValueToClient(iTarget);
        
        char sCookieValue[16];
        FloatToString(fValue, sCookieValue, sizeof(sCookieValue));
        SetClientCookie(iTarget, g_hCookie, sCookieValue);
    }
    
    ShowActivity2(client, "[PCAA] ", "Set sv_airaccelerate to %.1f for %s", fValue, sTargetName);
    return Plugin_Handled;
}

void ShowPlayerMenu(int client)
{
    Menu menu = new Menu(PlayerMenuHandler);
    menu.SetTitle("per-Client sv_airaccelerate");
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
            continue;
            
        char sUserID[11], sDisplay[64];
        IntToString(GetClientUserId(i), sUserID, sizeof(sUserID));
        Format(sDisplay, sizeof(sDisplay), "%N (%.1f)", i, g_fClientAA[i]);
        menu.AddItem(sUserID, sDisplay);
    }
    
    if (menu.ItemCount == 0)
    {
        menu.AddItem("", "No players available", ITEMDRAW_DISABLED);
    }
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int PlayerMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }
    
    if (action != MenuAction_Select)
        return 0;
    
    char sUserID[11];
    menu.GetItem(param2, sUserID, sizeof(sUserID));
    
    int target = GetClientOfUserId(StringToInt(sUserID));
    if (!target || !IsClientInGame(target))
    {
        CReplyToCommand(client, "[{green}PCAA{default}] Player is no longer available");
        return 0;
    }
    
    g_iMenuTarget[client] = target;  // Store target for this admin
    ShowValueMenu(client);
    return 0;
}

void ShowValueMenu(int client)
{
    int target = g_iMenuTarget[client];
    if (!target || !IsClientInGame(target))
    {
        CReplyToCommand(client, "[{green}PCAA{default}] Player is no longer available");
        return;
    }
    
    Menu menu = new Menu(ValueMenuHandler);
    menu.SetTitle("Set %N's sv_airaccelerate", target);
    
    menu.AddItem("10", "10");
    menu.AddItem("100", "100");
    menu.AddItem("1000", "1000");
    menu.AddItem("9999", "9999");
    menu.AddItem("99999", "99999");
    menu.AddItem("custom", "Custom Value");
    
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int ValueMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
        return 0;
    }
    
    if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_ExitBack)
            ShowPlayerMenu(client);
        return 0;
    }
    
    if (action != MenuAction_Select)
        return 0;
    
    int target = g_iMenuTarget[client];
    if (!target || !IsClientInGame(target))
    {
        CReplyToCommand(client, "[{green}PCAA{default}] Player is no longer available");
        return 0;
    }
    
    char sInfo[32];
    menu.GetItem(param2, sInfo, sizeof(sInfo));
    
    if (StrEqual(sInfo, "custom"))
    {
        CPrintToChat(client, "[{green}PCAA{default}] Enter custom value in console:");
        PrintToConsole(client, "sm_pcaa \"%N\" <value>", target);
        ShowValueMenu(client);  // Reopen menu
        return 0;
    }
    
    float fValue = StringToFloat(sInfo);
    g_fClientAA[target] = fValue;
    SendConVarValueToClient(target);
    
    char sCookieValue[16];
    FloatToString(fValue, sCookieValue, sizeof(sCookieValue));
    SetClientCookie(target, g_hCookie, sCookieValue);
    
    ShowActivity2(client, "[PCAA] ", "Set %N's sv_airaccelerate to %.1f", target, fValue);
    ShowValueMenu(client);  // Reopen menu with new value
    return 0;
}