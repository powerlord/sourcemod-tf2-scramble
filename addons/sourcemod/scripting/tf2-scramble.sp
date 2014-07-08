/**
 * vim: set ts=4 :
 * =============================================================================
 * TF2 Scramble
 * An alternative to GScramble
 *
 * TF2 Scramble (C)2014 Powerlord (Ross Bemrose).  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */
#include <sourcemod>
#include <sdktools>
#include <dhooks>

#undef REQUIRE_PLUGIN
#include <nativevotes>
#include <gameme>
#include <hlxce-sm-api>

#pragma semicolon 1
#define VERSION "0.0.1"

// #define SUPPORT_SDK2013

//SDKCalls / Hooks
new Handle:g_Call_ChangeTeam;
new Handle:g_Call_SetScramble;
new Handle:g_Hook_HandleScramble;

// CVars
new Handle:g_Cvar_Enabled;
new Handle:g_Cvar_Scramble;
new Handle:g_Cvar_Balance;
new Handle:g_Cvar_VoteScramble;

// Valve CVars
new Handle:g_Cvar_Mp_Autobalance; // mp_autobalance
new Handle:g_Cvar_Mp_Scrambleteams_Auto; // mp_scrambleteams_auto
new Handle:g_Cvar_Sv_Vote_Scramble; // sv_vote_issue_scramble_teams_allowed

public Plugin:myinfo = {
	name			= "TF2 Scramble",
	author			= "Powerlord",
	description		= "Alternative to TF2's Scramble system and GScramble",
	version			= VERSION,
	url				= ""
};

// Native Support
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	new EngineVersion:engine = GetEngineVersion();
	
	if (engine != Engine_TF2)
	{
#if defined SUPPORT_SDK2013
		if (engine != Engine_SDK2013)
		{
			strcopy(error, err_max, "Only supports TF2 and SDK 2013.");
		}
#else
	strcopy(error, err_max, "Only supports TF2.");
#endif
	}

	// might add natives to this
	RegPluginLibrary("tf2-scramble");
	
	return APLRes_Success;
}
  
public OnPluginStart()
{
	CreateConVar("tf2_scramble_version", VERSION, "TF2 Scramble version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	g_Cvar_Enabled = CreateConVar("tf2_scramble_enable", "1", "Enable TF2 Scramble?", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	g_Cvar_Scramble = CreateConVar("tf2_scramble_scramble", "1", "Enable TF2 Scramble's scramble abilities?", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_Balance = CreateConVar("tf2_scramble_balance", "1", "Enable TF2 Scramble's balance abilities?", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_VoteScramble = CreateConVar("tf2_scramble_vote", "1", "Enable our own vote scramble?  Will disable Valve's votescramble.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	// Add more cvars
	
	LoadTranslations("tf2-scramble.phrases");
	LoadTranslations("common.phrases");
	
	new Handle:gamedata = LoadGameConfigFile("tf2-scramble");
	
	if (gamedata == INVALID_HANDLE)
	{
		SetFailState("Could not load gamedata");
	}
	
	//void CBasePlayer::ChangeTeam( int iTeamNum, bool bAutoTeam, bool bSilent )
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CBasePlayer::ChangeTeam");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	g_Call_ChangeTeam = EndPrepSDKCall();
	
	//void CTeamplayRules::SetScrambleTeams( bool bScramble )
	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CTeamplayRules::SetScrambleTeams");
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	g_Call_SetScramble = EndPrepSDKCall();
	
	new handleScrambleOffset = GameConfGetOffset(gamedata, "CTeamplayRules::HandleScrambleTeams");
	
	// void CTeamplayRules::HandleScrambleTeams( void )
	g_Hook_HandleScramble = DHookCreate(handleScrambleOffset, HookType_GameRules, ReturnType_Void, ThisPointer_Ignore, HandleScrambleTeams);
	
	CloseHandle(gamedata);
}

public OnMapStart()
{
	DHookGamerules(g_Hook_HandleScramble, false);
}

public OnConfigsExecuted()
{
	if (!GetConVarBool(g_Cvar_Enabled))
	{
		return;
	}
	
	// Disable some Valve CVars based on our CVars.
	if (GetConVarBool(g_Cvar_Balance))
	{
		if (GetConVarBool(g_Cvar_Mp_Autobalance))
		{
			SetConVarBool(g_Cvar_Mp_Autobalance, false);
			LogMessage("Disabled mp_autobalance.");
		}
	}
	
	if (GetConVarBool(g_Cvar_Scramble))
	{
		if (GetConVarBool(g_Cvar_Mp_Scrambleteams_Auto))
		{
			SetConVarBool(g_Cvar_Mp_Scrambleteams_Auto, false);
			LogMessage("Disabled mp_scrambleteams_auto.");
		}
		
		if (GetConVarBool(g_Cvar_VoteScramble) && GetConVarBool(g_Cvar_Sv_Vote_Scramble))
		{
			SetConVarBool(g_Cvar_Sv_Vote_Scramble, false);
			LogMessage("Disabled sv_vote_issue_scramble_teams_allowed.");
		}
	}
}

// void CTeamplayRules::HandleScrambleTeams( void )
public MRESReturn:HandleScrambleTeams(Handle:hParams)
{
	if (!GetConVarBool(g_Cvar_Enabled) || !GetConVarBool(g_Cvar_Scramble))
	{
		return MRES_Ignored;
	}
	
	// scramble logic goes here
	
	// As far as I can tell, both these args should be true during a scramble
	// ChangeTeam(client, iTeamNum, true, true);
	return MRES_Supercede;
}

// If you're using this, one or both of the last two args should be true,
// or else you should just use ChangeClientTeam
//void CBasePlayer::ChangeTeam( int iTeamNum, bool bAutoTeam, bool bSilent )
stock SwitchTeam(client, iTeamNum, bool:bAutoTeam, bool:bSilent)
{
	SDKCall(g_Call_ChangeTeam, client, iTeamNum, bAutoTeam, bSilent);
}

//void CTeamplayRules::SetScrambleTeams( bool bScramble )
stock SetScrambleTeams(bool:bScramble)
{
	SDKCall(g_Call_SetScramble, bScramble);
}

// Some stocks that I may move to a .inc later
stock PrintValveTranslation(clients,
						    maxClients,
						    msg_dest,
						    const String:msg_name[],
						    const String:param1[]="",
						    const String:param2[]="",
						    const String:param3[]="",
						    const String:param4[]="")
{
	new Handle:bf = StartMessage("TextMsg", clients, numClients, USERMSG_RELIABLE)
	
	if (GetUserMessageType() == UM_Protobuf)
	{
		PbSetInt(bf, "msg_dest", msg_dest);
		PbAddString(bf, "params", msg_name);
		
		PbAddString(bf, "params", param1);
		PbAddString(bf, "params", param2);
		PbAddString(bf, "params", param3);
		PbAddString(bf, "params", param4);
	}
	else
	{
		BfWriteByte(bf, msg_dest);
		BfWriteString(bf, msg_name);
		
		BfWriteString(bf, param1);
		BfWriteString(bf, param2);
		BfWriteString(bf, param3);
		BfWriteString(bf, param4);
	}
	
	EndMessage();
}

stock PrintValveTranslationToAll(msg_dest,
								const String:msg_name[],
								const String:param1[]="",
								const String:param2[]="",
								const String:param3[]="",
								const String:param4[]="")
{
	new total = 0;
	new clients[MaxClients];
	for (new i=1; i<=MaxClients; i++)
	{
		if (IsClientConnected(i))
		{
			clients[total++] = i;
		}
	}
	PrintValveTranslation(clients, total, msg_dest, msg_name, param1, param2, param3, param4);
}

stock PrintValveTranslationToOne(client,
								msg_dest,
								const String:msg_name[],
								const String:param1[]="",
								const String:param2[]="",
								const String:param3[]="",
								const String:param4[]="")
{
	new players[1];
	
	players[0] = client;
	
	PrintValveTranslation(players, 1, msg_dest, msg_name, param1, param2, param3, param4);
}
