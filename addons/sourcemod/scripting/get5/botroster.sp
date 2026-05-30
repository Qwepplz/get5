bool g_BotRosterFrozen = false;
int g_FrozenBotQuota = 0;
int g_FrozenBotSnapshotCount = 0;
char g_FrozenBotNames[MAXPLAYERS + 1][MAX_NAME_LENGTH];
Get5Side g_FrozenBotSides[MAXPLAYERS + 1];

void ResetBotRosterState() {
  g_BotRosterFrozen = false;
  g_FrozenBotQuota = 0;
  g_FrozenBotSnapshotCount = 0;

  for (int i = 0; i <= MAXPLAYERS; i++) {
    g_FrozenBotNames[i][0] = '\0';
    g_FrozenBotSides[i] = Get5Side_None;
  }
}

bool ShouldEnforceFrozenBotQuota() {
  return g_GameState != Get5State_None && g_GameState != Get5State_PostGame;
}

static void CaptureFrozenBotRoster() {
  ResetBotRosterState();

  LOOP_CLIENTS(i) {
    if (!IsValidClient(i) || !IsFakeClient(i)) {
      continue;
    }

    int team = GetClientTeam(i);
    if (team != CS_TEAM_T && team != CS_TEAM_CT) {
      continue;
    }

    GetClientName(i, g_FrozenBotNames[g_FrozenBotSnapshotCount], MAX_NAME_LENGTH);
    g_FrozenBotSides[g_FrozenBotSnapshotCount] = view_as<Get5Side>(team);
    g_FrozenBotSnapshotCount++;
    g_FrozenBotQuota++;
  }

  g_BotRosterFrozen = true;
}

void ApplyFrozenBotQuota() {
  SetConVarStringSafe("bot_quota_mode", "normal");
  SetConVarIntSafe("bot_quota", g_FrozenBotQuota);
  SetConVarIntSafe("bot_join_after_player", 0);
}

void EnsureFrozenBotQuotaAfterMatchCfgExec() {
  if (!ShouldEnforceFrozenBotQuota()) {
    return;
  }

  if (!g_BotRosterFrozen) {
    CaptureFrozenBotRoster();
  }

  ApplyFrozenBotQuota();
}
