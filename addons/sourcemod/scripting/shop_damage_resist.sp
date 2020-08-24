
#include <sourcemod>
#include <sdkhooks>
#include <shop>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name		= "[SHOP] Damage Resist",
	author	  	= "iLoco",
	description = "",
	version	 	= "1.0.2",
	url			= "iLoco#7631"
};

KeyValues iKv[MAXPLAYERS+1];

ConVar cvar_Enable;
KeyValues kv;
char gFilePath[256];

public void OnPluginEnd()
{
	Shop_UnregisterMe();
}

public void OnPluginStart()
{
	BuildPath(Path_SM, gFilePath, sizeof(gFilePath), "configs/shop/damage_resist.txt");
	LoadCfg();
	RegAdminCmd("sm_shop_nodamage_reload", CMD_Reload, ADMFLAG_ROOT, "Перезагружает конфиг configs/shop/damage_resist.cfg");

	(cvar_Enable = CreateConVar("sm_shop_nodamage_enable", "1", "Включен ли этот модуль", _, true, 0.0, true, 1.0)).AddChangeHook(Hook_OnConVarChanged);
	AutoExecConfig(true, "shop_nofalldamage", "shop");
	
	if(Shop_IsStarted())
		Shop_Started();

	for(int i = 1; i <= MaxClients; i++)	if(IsClientAuthorized(i) && IsClientInGame(i))
		OnClientPostAdminCheck(i);

	HookEvent("player_disconnect", Event_OnDisconnect);
}

public void Event_OnDisconnect(Event event, const char[] name, bool DontBroadCast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(iKv[client])
		delete iKv[client];
}

public Action CMD_Reload(int client, int args)
{
	if(!cvar_Enable.IntValue)
	{
		ReplyToCommand(client, "ConVar 'sm_shop_nodamage_reload' is off");
		return Plugin_Handled;
	}

	LoadCfg();

	Shop_UnregisterMe();
	if(Shop_IsStarted())
		Shop_Started();

	ReplyToCommand(client, "Cfg reloaded sucefull!");
	return Plugin_Handled;
}

public void LoadCfg()
{
	if(kv)
		delete kv;
	kv = new KeyValues("NoDamage Abilities");

	if(!kv.ImportFromFile(gFilePath))
		SetFailState("File '%s' does not exist", gFilePath);
}

public void Hook_OnConVarChanged(ConVar cvar, const char[] oldValue, const char[] newValue)
{
	Shop_UnregisterMe();

	if(cvar.IntValue && Shop_IsStarted())
		Shop_Started();
}

public void OnClientPostAdminCheck(int client)
{
	if(IsFakeClient(client))
		return;

	iKv[client] = new KeyValues("cfg");

	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public Action Hook_OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	static int resist;
	static char offset[64];
	bool changed;

	iKv[client].Rewind();
	if(iKv[client].GotoFirstSubKey(false))
	{
		do
		{
			kv.GetSectionName(offset, sizeof(offset));

			if(StringToInt(offset) & damagetype)
			{
				resist = iKv[client].GetNum(NULL_STRING);

				if(resist != 100)
					damage = damage / (100 / resist);
				else
					damage = 0.0;

				if(damage < 0.0)
					damage = 0.0;

				changed = true;
			}
		}
		while(iKv[client].GotoNextKey(false));
	}	
	
	if(changed)
		return Plugin_Changed;

	return Plugin_Continue;
}

public void Shop_Started()
{
	if(!cvar_Enable.IntValue)
		return;

	char id[64], name[128];
	CategoryId category_id;
	
	kv.Rewind();
	if(kv.GotoFirstSubKey())
	{
		kv.SavePosition();
		
		do
		{
			kv.GetSectionName(id, sizeof(id));
			kv.GetString("name", name, sizeof(name));
			category_id = Shop_RegisterCategory(id, name, "");

			if(kv.GotoFirstSubKey())
			{
				do
				{
					if(!kv.GetNum("enable", 1))
						continue; 

					kv.GetSectionName(id, sizeof(id));
					kv.GetString("name", name, sizeof(name));

					if(Shop_StartItem(category_id, id))
					{
						Shop_SetInfo(name, "", kv.GetNum("price"), kv.GetNum("sell price"), Item_Togglable, kv.GetNum("duration"));
						Shop_SetCallbacks(_, CallBack_Shop_OnItemToggled);
						Shop_EndItem();
					}
				}
				while(kv.GotoNextKey());

				kv.GoBack();
			}
		}
		while(kv.GotoNextKey());
	}
}

public ShopAction CallBack_Shop_OnItemToggled(int client, CategoryId category_id, const char[] category, ItemId item_id, const char[] item, bool isOn, bool elapsed)
{
	if(!(JumpToAbility(category, item) && kv.JumpToKey("Protection") && kv.GotoFirstSubKey(false)))
		return Shop_UseOff;

	char offset[64];

	iKv[client].Rewind();
	do
	{
		kv.GetSectionName(offset, sizeof(offset));
		
		if(!isOn)
			iKv[client].SetNum(offset, iKv[client].GetNum(offset) + kv.GetNum(NULL_STRING));
		else 
			iKv[client].SetNum(offset, iKv[client].GetNum(offset) - kv.GetNum(NULL_STRING));
	}
	while(kv.GotoNextKey(false));
	

	if (isOn || elapsed)
		return Shop_UseOff;

	return Shop_UseOn;
}

stock bool JumpToAbility(const char[] category, const char[] item)
{
	kv.Rewind();

	if(kv.JumpToKey(category) && kv.JumpToKey(item))
		return true;
	
	return false;
}