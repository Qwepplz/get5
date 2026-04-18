Action StartKnifeRound(Handle timer) {
  g_HasKnifeRoundStarted = false;
  if (g_KnifeChangedCvars != INVALID_HANDLE) {
    CloseCvarStorage(g_KnifeChangedCvars);
  }
  char knifeConfig[PLATFORM_MAX_PATH];
  g_KnifeCfgCvar.GetString(knifeConfig, sizeof(knifeConfig));
  g_KnifeChangedCvars = ExecuteAndSaveCvars(knifeConfig);

  Get5_MessageToAll("%t", "KnifeIn5SecInfoMessage");
  StartWarmup(5);
  g_KnifeCountdownTimer = CreateTimer(10.0, Timer_AnnounceKnife);
  return Plugin_Handled;
}

static Action Timer_AnnounceKnife(Handle timer) {
  g_KnifeCountdownTimer = INVALID_HANDLE;
  if (g_GameState == Get5State_None) {
    return Plugin_Handled;
  }
  AnnouncePhaseChange("{GREEN}%t", "KnifeInfoMessage");

  Get5KnifeRoundStartedEvent knifeEvent = new Get5KnifeRoundStartedEvent(g_MatchID, g_MapNumber);

  LogDebug("Calling Get5_OnKnifeRoundStarted()");

  Call_StartForward(g_OnKnifeRoundStarted);
  Call_PushCell(knifeEvent);
  Call_Finish();

  EventLogger_LogAndDeleteEvent(knifeEvent);

  g_HasKnifeRoundStarted = true;
  return Plugin_Handled;
}

void StartKnifeTimer() {
  float knifeDecisionTime = g_TeamTimeToKnifeDecisionCvar.FloatValue;
  if (knifeDecisionTime > 0.0) {
    if (knifeDecisionTime < 10.0) {
      knifeDecisionTime = 10.0;
    }
    g_KnifeDecisionTimer = CreateTimer(knifeDecisionTime, Timer_ForceKnifeDecision);
  }
}

void StartKnifeDecisionReminderTimer() {
  if (g_KnifeDecisionReminderTimer != INVALID_HANDLE) {
    delete g_KnifeDecisionReminderTimer;
  }

  g_KnifeDecisionReminderTimer =
    CreateTimer(5.0, Timer_KnifeDecisionReminder, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

static Action Timer_KnifeDecisionReminder(Handle timer) {
  if (timer != g_KnifeDecisionReminderTimer) {
    return Plugin_Stop;
  }

  if (g_GameState != Get5State_WaitingForKnifeRoundDecision || g_KnifeWinnerTeam == Get5Team_None) {
    g_KnifeDecisionReminderTimer = INVALID_HANDLE;
    return Plugin_Stop;
  }

  PromptForKnifeDecision();
  return Plugin_Continue;
}

void PromptForKnifeDecision() {
  if (g_KnifeWinnerTeam == Get5Team_None) {
    // Handle waiting for knife decision. Also check g_KnifeWinnerTeam as there is a small delay between
    // selecting a side and the game state changing, during which this message should not be printed.
    return;
  }

  bool pureBotWinner = CountHumanMatchTeamClients(g_KnifeWinnerTeam, true, false, true) == 0;
  if (pureBotWinner) {
    if (g_BotKnifeDecisionTimer == INVALID_HANDLE) {
      float botDecisionDelay = GetRandomFloat(10.0, 30.0);
      LogDebug("Scheduling automatic knife decision for pure-bot team %d in %f seconds.",
               g_KnifeWinnerTeam, botDecisionDelay);
      g_BotKnifeDecisionTimer = CreateTimer(botDecisionDelay, Timer_AutoKnifeDecision, _, TIMER_FLAG_NO_MAPCHANGE);
    }
  } else if (g_BotKnifeDecisionTimer != INVALID_HANDLE) {
    LogDebug("Cancelling automatic knife decision because a human on team %d can now choose.",
             g_KnifeWinnerTeam);
    delete g_BotKnifeDecisionTimer;
  }

  char formattedStayCommand[64];
  GetChatAliasForCommand(Get5ChatCommand_Stay, formattedStayCommand, sizeof(formattedStayCommand), true);
  char formattedSwapCommand[64];
  GetChatAliasForCommand(Get5ChatCommand_Swap, formattedSwapCommand, sizeof(formattedSwapCommand), true);
  Get5_MessageToAll("%t", "WaitingForEnemySwapInfoMessage", g_FormattedTeamNames[g_KnifeWinnerTeam],
                    formattedStayCommand, formattedSwapCommand);
}

static void PerformSideSwap(bool swap) {
  if (swap) {
    int tmp = g_TeamSide[Get5Team_2];
    g_TeamSide[Get5Team_2] = g_TeamSide[Get5Team_1];
    g_TeamSide[Get5Team_1] = tmp;

    Get5Side currentSide;
    Get5Side coachingSide;
    LOOP_CLIENTS(i) {
      if (!IsValidClient(i) || IsClientSourceTV(i) || IsClientReplay(i)) {
        continue;
      }
      currentSide = view_as<Get5Side>(GetClientTeam(i));
      if (currentSide == Get5Side_T) {
        SwitchPlayerTeam(i, Get5Side_CT, false);
      } else if (currentSide == Get5Side_CT) {
        SwitchPlayerTeam(i, Get5Side_T, false);
      } else {
        coachingSide = GetClientCoachingSide(i);
        if (coachingSide != Get5Side_None) {
          SetClientCoaching(i, coachingSide == Get5Side_CT ? Get5Side_T : Get5Side_CT, false);
        }
      }
    }
    // Make sure g_MapSides has the correct values as well,
    // that way set starting teams won't swap on round 0,
    // since a temp valve backup does not exist.
    if (g_TeamSide[Get5Team_1] == CS_TEAM_CT)
      g_MapSides.Set(g_MapNumber, SideChoice_Team1CT);
    else
      g_MapSides.Set(g_MapNumber, SideChoice_Team1T);
  } else {
    g_TeamSide[Get5Team_1] = TEAM1_STARTING_SIDE;
    g_TeamSide[Get5Team_2] = TEAM2_STARTING_SIDE;
  }

  g_TeamStartingSide[Get5Team_1] = g_TeamSide[Get5Team_1];
  g_TeamStartingSide[Get5Team_2] = g_TeamSide[Get5Team_2];
  SetMatchTeamCvars();
}

static void EndKnifeRound(bool swap) {
  PerformSideSwap(swap);

  Get5KnifeRoundWonEvent knifeEvent = new Get5KnifeRoundWonEvent(
    g_MatchID, g_MapNumber, g_KnifeWinnerTeam, view_as<Get5Side>(g_TeamStartingSide[g_KnifeWinnerTeam]), swap);

  LogDebug("Calling Get5_OnKnifeRoundWon()");

  Call_StartForward(g_OnKnifeRoundWon);
  Call_PushCell(knifeEvent);
  Call_Finish();

  if (g_KnifeDecisionTimer != INVALID_HANDLE) {
    LogDebug("Stopped knife decision timer as a choice was made before it expired.");
    delete g_KnifeDecisionTimer;
  }
  if (g_KnifeDecisionReminderTimer != INVALID_HANDLE) {
    LogDebug("Stopped knife decision reminder timer as a choice was made before it expired.");
    delete g_KnifeDecisionReminderTimer;
  }
  if (g_BotKnifeDecisionTimer != INVALID_HANDLE) {
    LogDebug("Stopped automatic bot knife decision timer as a choice was made before it expired.");
    delete g_BotKnifeDecisionTimer;
  }

  EventLogger_LogAndDeleteEvent(knifeEvent);
  g_KnifeWinnerTeam = Get5Team_None;
  StartGoingLive();
}

static bool AwaitingKnifeDecision(int client) {
  if (g_GameState != Get5State_WaitingForKnifeRoundDecision || g_KnifeWinnerTeam == Get5Team_None) {
    return false;
  }
  bool onWinningTeam = IsPlayer(client) && GetClientMatchTeam(client) == g_KnifeWinnerTeam;
  return onWinningTeam || (client == 0);
}

Action Command_Stay(int client, int args) {
  if (AwaitingKnifeDecision(client)) {
    Get5_MessageToAll("%t", "TeamDecidedToStayInfoMessage", g_FormattedTeamNames[g_KnifeWinnerTeam]);
    EndKnifeRound(false);
  }
  return Plugin_Handled;
}

Action Command_Swap(int client, int args) {
  if (AwaitingKnifeDecision(client)) {
    Get5_MessageToAll("%t", "TeamDecidedToSwapInfoMessage", g_FormattedTeamNames[g_KnifeWinnerTeam]);
    EndKnifeRound(true);
  } else if (g_GameState == Get5State_Warmup && g_InScrimMode && GetClientMatchTeam(client) == Get5Team_1) {
    PerformSideSwap(true);
  }
  return Plugin_Handled;
}

static Action Timer_ForceKnifeDecision(Handle timer) {
  g_KnifeDecisionTimer = INVALID_HANDLE;
  if (g_GameState == Get5State_WaitingForKnifeRoundDecision && g_KnifeWinnerTeam != Get5Team_None) {
    Get5_MessageToAll("%t", "TeamLostTimeToDecideInfoMessage", g_FormattedTeamNames[g_KnifeWinnerTeam]);
    EndKnifeRound(false);
  }
  return Plugin_Handled;
}

static Action Timer_AutoKnifeDecision(Handle timer) {
  if (timer != g_BotKnifeDecisionTimer) {
    return Plugin_Stop;
  }

  g_BotKnifeDecisionTimer = INVALID_HANDLE;
  if (g_GameState != Get5State_WaitingForKnifeRoundDecision || g_KnifeWinnerTeam == Get5Team_None) {
    return Plugin_Stop;
  }

  if (CountHumanMatchTeamClients(g_KnifeWinnerTeam, true, false, true) > 0) {
    LogDebug("Skipping automatic knife decision because team %d now has human players on the winning side.",
             g_KnifeWinnerTeam);
    return Plugin_Stop;
  }

  Get5Side currentSide = view_as<Get5Side>(g_TeamSide[g_KnifeWinnerTeam]);
  char mapName[64];
  GetCurrentMap(mapName, sizeof(mapName));
  bool chooseT = StrContains(mapName, "de_anubis", false) != -1;
  Get5Side desiredSide = chooseT ? Get5Side_T : Get5Side_CT;
  bool swap = currentSide != desiredSide;
  LogDebug("Auto-selecting knife decision for pure-bot team %d after delay on map %s: force %s via %s.",
           g_KnifeWinnerTeam, mapName, desiredSide == Get5Side_CT ? "ct" : "t", swap ? "swap" : "stay");

  if (swap) {
    Get5_MessageToAll("%t", "TeamDecidedToSwapInfoMessage", g_FormattedTeamNames[g_KnifeWinnerTeam]);
  } else {
    Get5_MessageToAll("%t", "TeamDecidedToStayInfoMessage", g_FormattedTeamNames[g_KnifeWinnerTeam]);
  }
  EndKnifeRound(swap);
  return Plugin_Stop;
}
