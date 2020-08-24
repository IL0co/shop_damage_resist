
#include <sourcemod>
#include <sdkhooks>
#include <shop>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name		= "[SHOP] No Fall Damage",
	author	  	= "iLoco",
	description = "",
	version	 	= "1.0.1",
	url			= "iLoco#7631"
};

ConVar cvar_Enable;

ArrayList iArray[MAXPLAYERS+1], iArrayDamage[MAXPLAYERS+1];

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

	if(iArray[client])
		delete iArray[client];
	if(iArrayDamage[client])
		delete iArrayDamage[client];
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

	iArray[client] = new ArrayList(64);
	iArrayDamage[client] = new ArrayList(64);

	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public Action Hook_OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	static int length, resist, type;
	bool changed;

	if(!(length = iArray[client].Length))
		return Plugin_Continue;

	for(int p; p < length; p++)	if((type = iArray[client].Get(p)) & damagetype || type == 0)
	{
		resist = iArrayDamage[client].Get(p);

		if(resist != 100)
			damage = damage / (100 / resist);
		else
			damage = 0.0;

		if(damage < 0.0)
			damage = 0.0;

		changed = true;
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
	if(!JumpToAbility(category, item))
		return Shop_UseOff;

	if(!isOn)
	{
		iArray[client].Push(kv.GetNum("offset"));
		iArrayDamage[client].Push(kv.GetNum("damage"));
	}
	else
	{
		for(int p; p < iArray[client].Length; p++)	if(iArray[client].Get(p) == kv.GetNum("offset") && iArrayDamage[client].Get(p) == kv.GetNum("damage"))
		{
			iArray[client].Erase(p);
			iArrayDamage[client].Erase(p);
		}
	}

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