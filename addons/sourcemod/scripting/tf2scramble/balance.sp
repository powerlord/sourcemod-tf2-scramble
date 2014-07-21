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
enum BalancingType
{
	Balancing_None,
	Balancing_Normal,
	Balancing_Force
}

new Handle:g_Timer_Autobalance;

new bool:g_bWaitingForPlayers = false;
new BalancingType:g_WeAreBalancing = Balancing_None;

// Store times from GetTime here
new g_LastBalanced[MAXPLAYERS+1] = { 0, ... };

new g_NextBalanceChangeTime = 0;

CreateAutobalanceTimer()
{
	g_Timer_Autobalance = CreateTimer(5.0, Timer_Autobalance, _, TIMER_REPEAT);	
}

RemoveAutobalanceTimer()
{
	CloseHandle(g_Timer_Autobalance);
	g_Timer_Autobalance = INVALID_HANDLE;
}

ClearLastBalancedTime(client)
{
	g_LastBalanced[client] = 0;
}

public Action:Timer_Autobalance(Handle:Timer)
{
	// Are we in a position to allow balancing?
	if (!ShouldAllowBalance())
	{
		return Plugin_Continue;
	}
	
	// Should we switch balance modes?
	if (g_NextBalanceChangeTime > 0 && g_NextBalanceChangeTime <= GetTime())
	{
		if (g_WeAreBalancing == Balancing_None)
		{
			g_WeAreBalancing = Balancing_Normal;
			g_NextBalanceChangeTime = GetTime() + GetConVarInt(g_Cvar_Autobalance_ForceTime) - GetConVarInt(g_Cvar_Autobalance_Time);
		}
		else
		if (g_WeAreBalancing == Balancing_Normal)
		{
			g_WeAreBalancing = Balancing_Force;
			g_NextBalanceChangeTime = 0;
		}
	}
	
	// We already determined teams were unbalanced and are waiting the delay period
	// This logic should probably move to its OWN timer, which is just checked to see if it needs canceling here.
	if (g_WeAreBalancing == Balancing_Normal)
	{
		BalanceTeams();
	}
	else
	if (g_WeAreBalancing == Balancing_Force)
	{
		BalanceTeams(true);
	}
	else
	if (!AreTeamsBalanced())
	{
		decl String:timeStr[5];
		// Teams are now unbalanced
		new time = GetConVarInt(g_Cvar_Autobalance_Time);
		IntToString(time, timeStr, sizeof(timeStr));
		g_NextBalanceChangeTime = GetTime() + time;
		PrintValveTranslationToAll(HUD_PRINTTALK, "#game_auto_team_balance_in", timeStr);
	}
	
	return Plugin_Continue;
}

bool:ShouldAllowBalance()
{
	if (g_bWaitingForPlayers)
	{
		return false;
	}
	
	// Only run if round is running.  This has a side effect of not running during Sudden Death or Arena (which counts as Sudden Death)
	new RoundState:state = GameRules_GetRoundState();
	if (state != RoundState_RoundRunning)
	{
		return false;
	}
	
	new timelimit = GetConVarInt(g_Cvar_Timeleft);
	// CTF / 5CP maps, which end immediately when map time expires
	if (g_RoundEndType == RoundEnd_Immediate)
	{
		new timeleft;
		GetMapTimeLeft(timeleft);
		if (timeleft < timelimit)
		{
			return false;
		}
	}

	new timer = -1;
	new bool:found = false;
	// Maps may have multiple timers, e.g. tc_hydro
	while (!found && (timer = FindEntityByClassname(timer, "team_round_timer")) != -1)
	{
		// Check if this is the active timer
		new bool:bShowInHUD = bool:GetEntProp(timer, Prop_Send, "m_bShowInHUD");
		if (bShowInHUD)
		{
			// It IS the active timer
			// Check if we're in Setup
			if (GetEntProp(timer, Prop_Send, "m_nState") == TimerState_Setup)
			{
				return false;
			}
			
			// Check the time remaining
			found = true;
			new timeRemaining = GetTimeRemaining(timer);
			if (timeRemaining < timelimit)
			{
				return false;
			}
		}
	}
	
	return true;	
}

bool:AreTeamsBalanced()
{
	new unbalanceLimit = GetConVarInt(g_Cvar_Mp_TeamsUnbalance);
	if (unbalanceLimit == 0)
	{
		return true;
	}

	new teamNum = GetTeamCount();
	new teamCounts[teamNum];
	GetTeamCounts(teamCounts, teamNum);
	
	// > 2 is so that we only process where i isn't the last team
	// Since 0 and 1 aren't player teams... unassigned and spectator...
	// For TF2, this will only loop once (for team 3)
	for (new team1 = teamNum - 1; team1 > 2 ; team1--)
	{
		// We need to compare all player teams (in case there are more than two)
		// For TF2 this will only loop once (for team 2)
		for (new team2 = team1 - 1; team2 >= 2; team2--)
		{
			new diff = 0;

			if (teamCounts[team1] > teamCounts[team2])
			{
				diff = teamCounts[team1] - teamCounts[team2];
			}
			else
			{
				diff = teamCounts[team2] - teamCounts[team1];
			}
			
			if (diff > unbalanceLimit)
			{
				return false;
			}
		}
	}
		
	return true;
}

// If we called this, teams were determined to be unbalanced already
BalanceTeams(bool:force = false)
{
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
		new players[MaxClients][2];
		new count = GetPlayerBalanceValues(sortedTeamCounts[0][Sorted_TeamNum], players, force);
		new balanceCount = (sortedTeamCounts[0][Sorted_TeamCount] - sortedTeamCounts[1][Sorted_TeamCount]) / 2; // We switch half as many players
		
		if (count <= balanceCount)
		{
			// Balance everyone we have
			for (new i = 0; i < count; i++)
			{
				BalancePlayer(players[i][Player_Index], sortedTeamCounts[1][Sorted_TeamNum]);
			}
			
			if (count == balanceCount)
			{
				// We had exactly enough players
				g_WeAreBalancing = Balancing_None;
			}
		}
		else
		{
			// We have more players than we need, so this will stop the balancing
			g_WeAreBalancing = Balancing_None;
			SortCustom2D(players, count, SortPlayerValuesDesc);
			
			new last = 132412;
			new collector[count];
			new collate = 0;
			new curStart = 0;
			for (new i = 0; i < count; i++)
			{
				// Never process this block for the first item
				if (players[i][Player_Value] != last && i != 0)
				{
					// This is actually an optimization so that we don't attempt to randomize
					// when we are going to use all the values
					if (i <= balanceCount)
					{
						for (new j = 0; j < collate; j++)
						{
							BalancePlayer(collector[j], sortedTeamCounts[1][Sorted_TeamNum]);
							collector[j] = 0;
						}
						collate = 0;
						
						// Say, if we are on index 4 and we want 4 items, we need to break here
						// because 4 is the fifth index and collector will have 4 items already.
						// (or it could have had 2 and 2, or 1 and 3, etc...)
						if (i == balanceCount)
						{
							break;
						}
					}
					else
					{
						ShuffleArray(collector, collate);
						
						for (new j = 0; j < (i - 1 - curStart); j++)
						{
							BalancePlayer(collector[j], sortedTeamCounts[1][Sorted_TeamNum]);
							collector[j] = 0;
						}
						
						// Also, break since we have all the people we need
						break;
					}
					curStart = i;
				}
				collector[collate++] = players[i][Player_Index];
				last = players[i][Player_Value];
			}
		}
	}
	else
	{
		// Hmm, more than two teams means trickier logic, we'll deal with it later.	
	}
}

BalancePlayer(client, team)
{
	ChangeClientTeam(client, team);
	g_LastBalanced[client] = GetTime();
	
	new Handle:event = CreateEvent("teamplay_teambalanced_player");
	if (event != INVALID_HANDLE)
	{
		SetEventInt(event, "player", client);
		SetEventInt(event, "team", team);
		FireEvent(event);
	}
	
	decl String:name[MAX_NAME_LENGTH+1];
	GetClientName(client, name, sizeof(name));
	
	PrintValveTranslationToAll(HUD_PRINTTALK, "#game_player_was_team_balanced", name);
}

/*
 * This idea is stolen from GScramble (which stole it from Valve's 
 * CBaseMultiplayerPlayer::CalculateTeamBalanceScore
 * Higher player value means more likely to be autobalanced.
 * Dead players with no time-based immunity should get the highest value
 * 
 * players should be MaxClients size.  Failure to do so means you're an idiot.
 * Yes, I know mp_teams_unbalance_limit should prevent everyone being on one team. No, that isn't an excuse.
 * (Yes, I'm calling myself an idiot if I change this value later)
 */
GetPlayerBalanceValues(team, players[][], bool:force = false)
{
	new count = 0;

	// Calculate building owners first
	new Handle:buildingOwners = FindBuildingOwners();

	new teamMedicCount = 0;
	
	if (g_EngineVersion == Engine_TF2)
	{
		for (new client = 1; client <= MaxClients; client++)
		{
			if (IsClientInGame(client) && GetClientTeam(client) == team && TF2_GetPlayerClass(client) == TFClass_Medic)
			{
				teamMedicCount++;
			}
		}
	}
	
	for (new client = 1; client <= MaxClients; client++)
	{
		new immunityTime = GetConVarInt(g_Cvar_Immunity_Time);
		
		if (!IsClientInGame(client) || GetClientTeam(client) != team)
		{
			continue;
		}
		
		// Yes, this is meant to be ++, index is the OLD value
		// Dead players are always counted
		if (!IsPlayerAlive(client))
		{
			new index = count++;
			players[index][Player_Index] = client;

			if (g_EngineVersion == Engine_TF2 && GetConVarBool(g_Cvar_Immunity_Class) && TF2_GetPlayerClass(client) == TFClass_Engineer && FindValueInArray(buildingOwners, client) != -1)
			{
				if (!force)
				{
					// Don't balance dead engies with buildings if not forcing
					// Undo counter increment and index assignment
					count--;
					players[index][Player_Index] = 0;
					continue;
				}
				

				// Slightly more likely than living engies with level 2s to be balanced
				players[index][Player_Value] = -25;
#if defined LOG
				LogMessage("%N: %d.  Dead, but has level 2+ buildings", players[index][Player_Index], -25);
#endif
			}
			else
			if (g_EngineVersion == Engine_TF2 && GetConVarBool(g_Cvar_Immunity_Class) && TF2_GetPlayerClass(client) == TFClass_Medic && teamMedicCount == 1)
			{
				// They're the only medic on their team, don't balance them unless you have to
				if (!force)
				{
					count--;
					players[index][Player_Index] = 0;
					continue;
				}
				players[index][Player_Value] = -50;
#if defined LOG
				LogMessage("%N: %d.  Dead, but the only Medic on their team", players[index][Player_Index], -50);
#endif
			}
			else
			if (GetConVarBool(g_Cvar_Immunity_Duel) && TF2_IsPlayerInDuel(client))
			{
				// Set their score lower if they're in a duel
				players[index][Player_Value] = -20;
#if defined LOG
				LogMessage("%N: %d.  Dead, but in a duel", players[index][Player_Index], -20);
#endif
			}
			else
			if (g_LastBalanced[client] - GetTime() > immunityTime)
			{
				// Dead players with no immunity get a very high value
				players[index][Player_Value] = 100;
#if defined LOG
				LogMessage("%N: %d.  Dead, no immunity.", players[index][Player_Index], 100);
#endif
			}
			// All other dead players
			else
			{
				// They have time immunity
				if (!force)
				{
					count--;
					players[index][Player_Index] = 0;
					continue;
				}

				players[index][Player_Value] = -5;
#if defined LOG
				LogMessage("%N: %d.  Dead, time immunity.", players[index][Player_Index], -5);
#endif
			}
		}
		else if (force)
		{
			// force chooses living players as well.

			new index = count++; 
			players[index][Player_Index] = client;

			if (g_LastBalanced[client] - GetTime() <= immunityTime)
			{
				// Living players in the immunity time get a fair bit of immunity, lower than dead
				players[index][Player_Value] = -20;
#if defined LOG
				LogMessage("%N: %d.  Alive, time immunity.", players[index][Player_Index], -20);
#endif
			}
			
			if (g_EngineVersion == Engine_TF2)
			{
				if (GetConVarBool(g_Cvar_Immunity_Class) && TF2_GetPlayerClass(client) == TFClass_Engineer && FindValueInArray(buildingOwners, client) != -1)
				{
					// Yes, this is higher than Medic as Medic Uber is transitory while buildings last even after death
					players[index][Player_Value] = -50;
#if defined LOG
					LogMessage("%N: %d.  Alive, but has level 2+ buildings", players[index][Player_Index], -50);
#endif
				}
				else
				if (GetConVarBool(g_Cvar_Immunity_Class) && TF2_GetPlayerClass(client) == TFClass_Medic)
				{
					// This totally won't work for Randomizer.  Well, won't be useful at any rate.
					if (teamMedicCount == 1)
					{
						// Only Medic on team, this value is so low they should never be balanced
						players[index][Player_Value] = -100;
#if defined LOG
						LogMessage("%N: %d.  Alive, only Medic on team.", players[index][Player_Index], -100);
#endif
					}
					else
					// Medic is ubering, assign them a slightly lower value than they'd have if > 50% uber
					if (TF2_IsPlayerInCondition(client, TFCond_Ubercharged) ||
						TF2_IsPlayerInCondition(client, TFCond_UberchargeFading) ||
						TF2_IsPlayerInCondition(client, TFCond_Kritzkrieged) ||
						TF2_IsPlayerInCondition(client, TFCond_MegaHeal))
					{
						players[index][Player_Value] = -50;
#if defined LOG
						LogMessage("%N: %d.  Alive, Medic in Uber.", players[index][Player_Index], -50);
#endif
					}
					else
					{
						new medigun = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);

						// Necessary for Medieval
						if (IsValidEntity(medigun))
						{
							new String:classname[64];
							GetEntityClassname(medigun, classname, sizeof(classname));
							if (StrEqual(classname, "tf_weapon_medigun") && GetEntProp(medigun, Prop_Send, "m_iItemDefinitionIndex") != VACCINATOR 
								&& GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel") > 0.50)
							{
								players[index][Player_Value] = -40;
#if defined LOG
								LogMessage("%N: %d.  Alive, Medic with >50% Uber.", players[index][Player_Index], -40);
#endif
							}
						}
					}
				}
				else
				// Player is being ubered, assigned them a lower value
				// Note how the Vaccinator uber isn't here?  That's intentional due to how quickly it builds.
				if (TF2_IsPlayerInCondition(client, TFCond_Ubercharged) ||
					TF2_IsPlayerInCondition(client, TFCond_UberchargeFading) ||
					TF2_IsPlayerInCondition(client, TFCond_Kritzkrieged) ||
					TF2_IsPlayerInCondition(client, TFCond_MegaHeal))
				{
					players[index][Player_Value] = -30;
#if defined LOG
					LogMessage("%N: %d.  Alive, currently in Uber.", players[index][Player_Index], -30);
#endif
				}
				else
				if (GetConVarBool(g_Cvar_Immunity_Duel) && TF2_IsPlayerInDuel(client))
				{
					// Set their score lower if they're in a duel, too
					players[index][Player_Value] = -20;
#if defined LOG
					LogMessage("%N: %d.  Alive, currently in Duel.", players[index][Player_Index], -20);
#endif
				}
			}
#if defined LOG
			LogMessage("%N: %d.  Alive, no immunity.", players[index][Player_Index], 0);
#endif
		}
	}
	
	CloseHandle(buildingOwners);
	
	return count;
}

#if defined DEBUG
public Action:Cmd_ListImmunity(client, args)
{
	new teamCount = GetTeamCount();
	ReplyToCommand(client, "Immunity Values");
	
	for (new team = 2; team < teamCount; team++)
	{
		ReplyToCommand(client, "Team %d", team);
		new players[MaxClients][2];
		new playerCount = GetPlayerBalanceValues(team, players, true);
		for (new player = 0; player < playerCount; player++)
		{
			new String:livingStatus[6];
			if (IsPlayerAlive(players[player][Player_Index]))
			{
				livingStatus = "alive";
			}
			else
			{
				livingStatus = "dead";
			}
			
			ReplyToCommand(client, "%d. %N (%s): %d", players[player][Player_Index], players[player][Player_Index], livingStatus, players[player][Player_Value]);
		}
	}
}
#endif

Handle:FindBuildingOwners()
{
	new Handle:buildingOwners = CreateArray();
	new building = -1;
	while ((building = FindEntityByClassname(building, "obj_*")) != -1)
	{
		if (TF2_GetObjectType(building) == TFObject_Sapper)
		{
			continue;
		}
		
		new target = GetEntPropEnt(building, Prop_Send, "m_hOwnerEntity");
		if (target > 0 && target <= MaxClients && GetEntProp(building, Prop_Send, "m_iUpgradeLevel") >= 2)
		{
#if defined LOG
			LogMessage("Found level 2+ building owner: %N", target);
#endif
			// We don't care about duplicates
			PushArrayCell(buildingOwners, target);
		}
	}

	return buildingOwners;
}
