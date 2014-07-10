/**
 * vim: set ts=4 :
 * =============================================================================
 * TF2 Scramble
 * An alternative to GScramble
 * This plugin may work on other games just by editing AskPluginLoad2 to remove
 * the game restriction... hasn't been tested, though.
 * 
 * However, it definitely doesn't work on games that use more than two player
 * teams... sorry Fortress Forever.  Then again, you're looking into moving to
 * a non-Source engine anyway... traitors.
 *
 * TF2 Scramble (C)2014 Powerlord (Ross Bemrose).  All rights reserved.
 *
 * Portions of this code were inspired by how Source SDK 2013/TF2 does things
 * Source SDK 2013 (c) 2013 Valve Software
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

 enum ScrambleType
 {
	Scramble_Random,
	Scramble_Points,
	Scramble_PointsPerMin,
	Scramble_KillDeathRatio,
	Scramble_Plugin
 }

 new g_PlayerConnectTime[MAXPLAYERS+1];
 
 stock SetPlayerConnectTime(client)
 {
	g_PlayerConnectTime[client] = GetTime();
 }
 
 stock ClearPlayerConnectTime(client)
 {
	g_PlayerConnectTime[client] = 0;
 }
 
 stock GetPlayerConnectTime(client)
 {
	return g_PlayerConnectTime[client];
 }
 
 PostRoundScrambleCheck()
{
	if (ShouldScrambleTeams())
	{
		if (g_EngineVersion == Engine_TF2)
		{
			TF2_SendScrambleAlert();
		}
		else
		{
			PrintValveTranslationToAll(HUD_PRINTCENTER, "#game_scramble_onrestart");
			PrintValveTranslationToAll(HUD_PRINTCONSOLE, "#game_scramble_onrestart");
		}
		SetScrambleTeams(true);
		PrintToServer("World triggered \"ScrambleTeams_Auto\"\n");
	}
}

//void CTeamplayRules::SetScrambleTeams( bool bScramble )
stock SetScrambleTeams(bool:bScramble)
{
	SDKCall(g_Call_SetScramble, bScramble);
}

TF2_SendScrambleAlert()
{
	new Handle:event = CreateEvent("teamplay_alert");
	if (event != INVALID_HANDLE)
	{
		SetEventInt(event, "alert_type", HUD_ALERT_SCRAMBLE_TEAMS);
		FireEvent(event);
	}
}

bool:ShouldScrambleTeams()
{
	if (!GetConVarBool(g_Cvar_Scramble))
	{
		return false;
	}
	
	// Logic to determine if we should scramble here
	return false;
}

stock ForceScramble()
{
	new time = 5; // Fix this later, this is just here so we have this code when we need it.
	
	if (time > 1)
	{
		pFormat = "#game_scramble_in_secs";
	}
	else
	{
		pFormat = "#game_scramble_in_sec";
	}
	
	// Valve's idea to use 64 here
	new String:strRestartDelay[64];
	Format(strRestartDelay, sizeof(strRestartDelay), "%d", time);
	PrintValveTranslationToAll(HUD_PRINTCENTER, pFormat, strRestartDelay);
	PrintValveTranslationToAll(HUD_PRINTCONSOLE, pFormat, strRestartDelay);
	
	TF2_SendScrambleAlert();
	
	// Logic to start timer before forcing scramble here
}

// void CTeamplayRules::HandleScrambleTeams( void )
public MRESReturn:HandleScrambleTeams(Handle:hParams)
{
	if (!GetConVarBool(g_Cvar_Enabled) || !GetConVarBool(g_Cvar_Scramble))
	{
		return MRES_Ignored;
	}
	
	new switched = 0;
	
	
	new teamNum = GetTeamCount();
	new teamCounts[teamNum];
	GetTeamCounts(teamCounts, teamNum);
	
	new realTeamNum = teamNum-2;
	new sortedTeamCounts[realTeamNum][2];
	
	for (new i = 2; i < teamNum; i++)
	{
		sortedTeamCounts[i-2][Sorted_TeamNum] = i;
		sortedTeamCounts[i-2][Sorted_TeamCount] = teamCounts[i];
	}
	
	SortCustom2D(sortedTeamCounts, realTeamNum, SortTeamCountsDesc);
	
	if (realTeamNum == 2)
	{
		new totalPlayers = teamCounts[2] + teamCounts[3];
		new playersToMove = RoundFloat(totalPlayers * GetConVarFloat(g_Cvar_Scramble_Percent));
		// If may seem odd getting the balance count, but this is how many players we MUST move to one team in addition to moving equal(ish) numbers from both teams.
		new balanceCount = (sortedTeamCounts[0][Sorted_TeamCount] - sortedTeamCounts[1][Sorted_TeamCount]) / 2; // We switch half as many players
		if (playersToMove > balanceCount)
		{
			playersToMove -= balanceCount;
		}
		
		switch (GetConVarInt(g_Cvar_ScrambleMode))
		{
			case Scramble_Random:
			{
				switched = TwoTeam_ScrambleByRandom(playersToMove, balanceCount, sortedTeamCounts[1][Sorted_TeamCount]);
			}
			
			case Scramble_Points:
			{
				switched = TwoTeam_ScrambleByPoints(playersToMove, balanceCount, sortedTeamCounts[1][Sorted_TeamCount]);
			}
			
			case Scramble_PointsPerMin:
			{
				switched = TwoTeam_ScrambleByPointsPerMinute(playersToMove, balanceCount, sortedTeamCounts[1][Sorted_TeamCount]);
			}
			
			case Scramble_KillDeathRatio:
			{
				switched = TwoTeam_ScrambleByKDR(playersToMove, balanceCount, sortedTeamCounts[1][Sorted_TeamCount]);
			}
			
			case Scramble_Plugin:
			{
				switched = TwoTeam_ScrambleByPlugin(playersToMove, balanceCount, sortedTeamCounts[1][Sorted_TeamCount]);
			}
		}
	}
	else
	{
		// Worry about more teams later
	}
	

	// As far as I can tell, the last arg should be true during a balance/scramble
	// SwitchTeam(client, iTeamNum, false, true);
	return MRES_Supercede;
}

TwoTeam_ScrambleByRandom(playersToMove, playersToBalance, teamToBalanceTo)
{
	new switched;
	new team1Players[MaxClients];
	new team2Players[MaxClients];
	
	new count1 = GetPlayers(PLAYER_TEAM_1, team1Players);
	new count2 = GetPlayers(PLAYER_TEAM_2, team2Players);
	
	ShuffleArray(team1Players, count1);
	ShuffleArray(team2Players, count2);
	
	new team1Moved = 0;
	new team2Moved = 0;
	
	if (teamToBalanceTo == PLAYER_TEAM_1)
	{
		for (new i = 0; i < playersToBalance; i++)
		{
			SwitchTeam(team1Players[i], PLAYER_TEAM_2, false, true);
		}
		team1Moved = playersToBalance;
	}
	else
	{
		for (new i = 0; i < playersToBalance; i++)
		{
			SwitchTeam(team2Players[i], PLAYER_TEAM_1, false, true);
		}
		team2Moved = playersToBalance;
	}
	
	// Remaining move logic here
}

TwoTeam_ScrambleByPoints(playersToMove, playersToBalance, teamToBalanceTo)
{
	new switched;
	
}

TwoTeam_ScrambleByPointsPerMinute(playersToMove, playersToBalance, teamToBalanceTo)
{
	new switched;
	
}

TwoTeam_ScrambleByKDR(playersToMove, playersToBalance, teamToBalanceTo)
{
	new switched;
	
}

TwoTeam_ScrambleByPlugin(playersToMove, playersToBalance, teamToBalanceTo)
{
	new switched;
	
}

GetPlayers(team, players[])
{
	new count = 0;
	
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && GetClientTeam(client) == team)
		{
			players[count++] = client;
		}
	}
	
	return count;
}

GetPlayerPoints(points[], const players[], count)
{
	for (new i = 0; i < count; i++)
	{
		points[i] = GetEntProp(i, Prop_Send, "m_iScore");
	}
}

GetPlayerKDR(Float:kdr[], const players[], count)
{
	for (new i = 0; i < count; i++)
	{
		new kills = GetEntProp(i, Prop_Send, "");
		// Avoid divide by 0 by adding 1
		// This works because suicides subtract 1 from kills, not deaths
		new deaths = GetEntProp(i, Prop_Send, "") + 1;
				
		kdr[i] = float(kills) / float(deaths);
	}
}


