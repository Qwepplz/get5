// TODO: Add translations for this.
// TODO: Add admin top menu integration.
#define SETUP_MENU_CREATE_MATCH            "SETUP_MENU_CREATE_MATCH"
#define SETUP_MENU_FORCE_READY             "SETUP_MENU_FORCE_READY"
#define SETUP_MENU_END_MATCH               "SETUP_MENU_END_MATCH"
#define SETUP_MENU_CONFIRM_END_MATCH_DRAW  "SETUP_MENU_CONFIRM_END_MATCH_DRAW"
#define SETUP_MENU_CONFIRM_END_MATCH_TEAM1 "SETUP_MENU_CONFIRM_END_MATCH_TEAM1"
#define SETUP_MENU_CONFIRM_END_MATCH_TEAM2 "SETUP_MENU_CONFIRM_END_MATCH_TEAM2"
#define SETUP_MENU_LIST_BACKUPS            "SETUP_MENU_LIST_BACKUPS"
#define SETUP_MENU_RINGER                  "SETUP_MENU_RINGER"

#define SETUP_MENU_SELECTION_MATCH_TYPE       "SETUP_MENU_SELECTION_MATCH_TYPE"
#define SETUP_MENU_SELECTION_PLAYERS_PER_TEAM "SETUP_MENU_SELECTION_PLAYERS_PER_TEAM"
#define SETUP_MENU_FRIENDLY_FIRE              "SETUP_MENU_FRIENDLY_FIRE"
#define SETUP_MENU_OVERTIME                   "SETUP_MENU_OVERTIME"
#define SETUP_MENU_CLINCH                     "SETUP_MENU_CLINCH"
#define SETUP_MENU_SERIES_LENGTH              "SETUP_MENU_SERIES_LENGTH"
#define SETUP_MENU_MAP_SELECTION              "SETUP_MENU_MAP_SELECTION"
#define SETUP_MENU_MAP_POOL_SELECTION         "SETUP_MENU_MAP_POOL_SELECTION"
#define SETUP_MENU_SELECTED_MAPS              "SETUP_MENU_SELECTED_MAPS"
#define SETUP_MENU_SIDE_TYPE                  "SETUP_MENU_SIDE_TYPE"
#define SETUP_MENU_TEAM_SELECTION             "SETUP_MENU_TEAM_SELECTION"
#define SETUP_MENU_SELECT_TEAMS               "SETUP_MENU_SELECT_TEAMS"
#define SETUP_MENU_SWAP_TEAMS                 "SETUP_MENU_SWAP_TEAMS"
#define SETUP_MENU_CAPTAINS                   "SETUP_MENU_CAPTAINS"
#define SETUP_MENU_START_MATCH                "SETUP_MENU_START_MATCH"

#define SETUP_MENU_MAP_SELECTION_RESET "SETUP_MENU_MAP_SELECTION_RESET"

#define SETUP_MENU_CAPTAINS_TEAM1 "SETUP_MENU_CAPTAINS_TEAM1"
#define SETUP_MENU_CAPTAINS_TEAM2 "SETUP_MENU_CAPTAINS_TEAM2"
#define SETUP_MENU_CAPTAINS_AUTO  "SETUP_MENU_CAPTAINS_AUTO"

#define SETUP_MENU_TEAMS_TEAM1 "SETUP_MENU_TEAMS_TEAM1"
#define SETUP_MENU_TEAMS_TEAM2 "SETUP_MENU_TEAMS_TEAM2"
#define SETUP_MENU_TEAMS_RESET "SETUP_MENU_TEAMS_RESET"
#define SETUP_MENU_TEAMS_SWAP  "SETUP_MENU_TEAMS_SWAP"

static void FillMenuPageWithBlanks(const Menu menu) {
  while (menu.ItemCount % 6 != 0) {
    menu.AddItem("", "", ITEMDRAW_SPACER);
  }
}

static int GetIndexForPage(const int page) {
  return page * 6;
}

static int GetPageIndexForItem(const int selectedItem) {
  int page = selectedItem / 6;  // Items start at 0 and we floor to int; so 5/6 is 0, 6/6 is 1, 7/6 is still 1 etc.
  return 6 * page;              // Get the first item of the page.
}

static bool IsGet5MenuAdmin(int client) {
  return IsPlayer(client) && CheckCommandAccess(client, "sm_get5", ADMFLAG_CHANGEMAP);
}

static void NormalizeLockedSetupMenuValues() {
  g_SetupMenuWingman = false;
  g_SetupMenuSeriesLength = 1;
  g_SetupMenuMapSelection = Get5SetupMenu_MapSelectionMode_Current;
  g_SetupMenuPlayersPerTeam = 5;
  g_SetupMenuTeamSelection = Get5SetupMenu_TeamSelectionMode_Current;
  g_SetupMenuSideType = MatchSideType_AlwaysKnife;
  g_SetupMenuTeam1Captain = -1;
  g_SetupMenuTeam2Captain = -1;
  if (g_SetupMenuSelectedMaps != INVALID_HANDLE) {
    g_SetupMenuSelectedMaps.Clear();
  }
}

static void NormalizeSetupMenuRoundOptions() {
  if (!g_SetupMenuClinch) {
    g_SetupMenuOvertime = false;
  }
}

static void GetLocalizedText(const char[] phrase, int client, char[] buffer, int len) {
  FormatEx(buffer, len, "%T", phrase, client);
}

static void GetSetupMenuGameModeText(int client, char[] buffer, int len) {
  GetLocalizedText(g_SetupMenuWingman ? "SetupMenuValueWingman" : "SetupMenuValueCompetitive", client, buffer, len);
}

static void GetSetupMenuMapSelectionText(int client, char[] buffer, int len) {
  switch (g_SetupMenuMapSelection) {
    case Get5SetupMenu_MapSelectionMode_PickBan:
      GetLocalizedText("SetupMenuValuePickBan", client, buffer, len);
    case Get5SetupMenu_MapSelectionMode_Current:
      GetLocalizedText("CommonCurrent", client, buffer, len);
    case Get5SetupMenu_MapSelectionMode_Manual:
      GetLocalizedText("CommonManual", client, buffer, len);
  }
}

static void GetSetupMenuTeamSelectionText(int client, char[] buffer, int len) {
  switch (g_SetupMenuTeamSelection) {
    case Get5SetupMenu_TeamSelectionMode_Current:
      GetLocalizedText("CommonCurrent", client, buffer, len);
    case Get5SetupMenu_TeamSelectionMode_Fixed:
      GetLocalizedText("SetupMenuValueFixed", client, buffer, len);
    case Get5SetupMenu_TeamSelectionMode_Scrim:
      GetLocalizedText("SetupMenuValueScrim", client, buffer, len);
  }
}

static void GetSetupMenuSideTypeText(int client, char[] buffer, int len) {
  switch (g_SetupMenuSideType) {
    case MatchSideType_Standard:
      GetLocalizedText("SetupMenuValueStandard", client, buffer, len);
    case MatchSideType_AlwaysKnife:
      GetLocalizedText("SetupMenuValueAlwaysKnife", client, buffer, len);
    case MatchSideType_NeverKnife:
      GetLocalizedText("SetupMenuValueTeam1CT", client, buffer, len);
    case MatchSideType_Random:
      GetLocalizedText("SetupMenuValueRandom", client, buffer, len);
  }
}

static void GetLocalizedOnOffText(bool value, int client, char[] buffer, int len) {
  GetLocalizedText(value ? "CommonOn" : "CommonOff", client, buffer, len);
}

static void GetLocalizedYesNoText(bool value, int client, char[] buffer, int len) {
  GetLocalizedText(value ? "CommonYes" : "CommonNo", client, buffer, len);
}

static void ShowSetupMenu(int client, int displayAt = 0) {
  if (g_SetupMenuSelectedMaps == INVALID_HANDLE) {
    g_SetupMenuSelectedMaps = new ArrayList(PLATFORM_MAX_PATH);
  }
  if (g_SetupMenuMapPool == null) {
    ResetMapPool(client);
    HandleMapPoolAndSeriesLength();
  }
  NormalizeLockedSetupMenuValues();
  NormalizeSetupMenuRoundOptions();
  bool isAdmin = IsGet5MenuAdmin(client);

  Menu menu = new Menu(SetupMenuHandler);
  menu.SetTitle("%T", "SetupMenuTitle", client);
  menu.ExitButton = false;
  menu.ExitBackButton = true;

  char buffer[64];
  char gameModeText[32];
  GetSetupMenuGameModeText(client, gameModeText, sizeof(gameModeText));
  FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuGameModeItem", client, gameModeText);
  menu.AddItem(SETUP_MENU_SELECTION_MATCH_TYPE, buffer, EnabledIf(false));
  FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuSeriesLengthItem", client, g_SetupMenuSeriesLength);
  menu.AddItem(SETUP_MENU_SERIES_LENGTH, buffer, EnabledIf(false));
  char mapSelectionMode[32];
  GetSetupMenuMapSelectionText(client, mapSelectionMode, sizeof(mapSelectionMode));
  FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuMapSelectionItem", client, mapSelectionMode);
  menu.AddItem(SETUP_MENU_MAP_SELECTION, buffer, EnabledIf(false));

  if (g_SetupMenuMapSelection != Get5SetupMenu_MapSelectionMode_Current) {
    FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuMapPoolItem", client, g_SetupMenuSelectedMapPool);
    menu.AddItem(SETUP_MENU_MAP_POOL_SELECTION, buffer);
  }

  if (g_SetupMenuMapSelection == Get5SetupMenu_MapSelectionMode_Manual) {
    char mapsString[PLATFORM_MAX_PATH];
    if (g_SetupMenuSelectedMaps.Length > 0) {
      ImplodeMapArrayToString(g_SetupMenuSelectedMaps, mapsString, sizeof(mapsString), false);
      Format(mapsString, sizeof(mapsString), "%T", "SetupMenuMapsItem", client, mapsString);
    } else {
      FormatEx(mapsString, sizeof(mapsString), "%T", "SetupMenuSelectMaps", client);
    }
    menu.AddItem(SETUP_MENU_SELECTED_MAPS, mapsString);
  }

  FillMenuPageWithBlanks(menu);

  FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuTeamSizeItem", client, g_SetupMenuPlayersPerTeam);
  menu.AddItem(SETUP_MENU_SELECTION_PLAYERS_PER_TEAM, buffer, EnabledIf(false));

  char teamSelectionMode[32];
  GetSetupMenuTeamSelectionText(client, teamSelectionMode, sizeof(teamSelectionMode));
  FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuTeamSelectionItem", client, teamSelectionMode);
  menu.AddItem(SETUP_MENU_TEAM_SELECTION, buffer, EnabledIf(false));

  switch (g_SetupMenuTeamSelection) {
    case Get5SetupMenu_TeamSelectionMode_Fixed: {
      char title[64];
      if (strlen(g_SetupMenuTeamForTeam1) == 0 && strlen(g_SetupMenuTeamForTeam2) == 0) {
        FormatEx(title, sizeof(title), "%T", "SetupMenuSelectTeams", client);
      } else {
        char teamName1[64] = "??";
        char teamName2[64] = "??";
        if (strlen(g_SetupMenuTeamForTeam1) > 0) {
          GetTeamNameFromJson(g_SetupMenuTeamForTeam1, teamName1, sizeof(teamName1), true);
        }
        if (strlen(g_SetupMenuTeamForTeam2) > 0) {
          GetTeamNameFromJson(g_SetupMenuTeamForTeam2, teamName2, sizeof(teamName2), true);
        }
        FormatEx(title, sizeof(title), "%T", "SetupMenuTeamsVersusItem", client, teamName1, teamName2);
      }
      menu.AddItem(SETUP_MENU_SELECT_TEAMS, title);
    }
    case Get5SetupMenu_TeamSelectionMode_Scrim: {
      char title[64];
      char teamName[64] = "??";
      if (strlen(g_SetupMenuTeamForTeam1) > 0) {
        GetTeamNameFromJson(g_SetupMenuTeamForTeam1, teamName, sizeof(teamName), true);
      }
      FormatEx(title, sizeof(title), "%T", "SetupMenuHomeTeamItem", client, teamName);
      menu.AddItem(SETUP_MENU_SELECT_TEAMS, title);
    }
  }

  char sideTypeBuffer[32];
  GetSetupMenuSideTypeText(client, sideTypeBuffer, sizeof(sideTypeBuffer));
  FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuSideTypeItem", client, sideTypeBuffer);
  menu.AddItem(SETUP_MENU_SIDE_TYPE, buffer, EnabledIf(false));

  if (g_SetupMenuTeamSelection == Get5SetupMenu_TeamSelectionMode_Current &&
      g_SetupMenuSideType == MatchSideType_NeverKnife) {
    FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuSwapSides", client);
    menu.AddItem(SETUP_MENU_SWAP_TEAMS, buffer);
  }

  FillMenuPageWithBlanks(menu);

  char toggleText[16];
  GetLocalizedOnOffText(g_SetupMenuFriendlyFire, client, toggleText, sizeof(toggleText));
  FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuFriendlyFireItem", client, toggleText);
  menu.AddItem(SETUP_MENU_FRIENDLY_FIRE, buffer);

  if (g_SetupMenuClinch) {
    GetLocalizedOnOffText(g_SetupMenuOvertime, client, toggleText, sizeof(toggleText));
    FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuOvertimeItem", client, toggleText);
  } else {
    GetLocalizedText("CommonOff", client, toggleText, sizeof(toggleText));
    FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuOvertimeItem", client, toggleText);
  }
  menu.AddItem(SETUP_MENU_OVERTIME, buffer, EnabledIf(g_SetupMenuClinch));

  GetLocalizedYesNoText(!g_SetupMenuClinch, client, toggleText, sizeof(toggleText));
  FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuPlayAllRoundsItem", client, toggleText);
  menu.AddItem(SETUP_MENU_CLINCH, buffer, EnabledIf(isAdmin));

  if (menu.ItemCount % 6 != 0) {
    menu.AddItem("", "", ITEMDRAW_SPACER);
  }

  FormatEx(buffer, sizeof(buffer), "%T", "SetupMenuStartMatch", client);
  menu.AddItem(SETUP_MENU_START_MATCH, buffer);

  menu.DisplayAt(client, displayAt, MENU_TIME_FOREVER);
  g_ActiveSetupMenu = menu;
}

static int SetupMenuHandler(Menu menu, MenuAction action, int client, int param2) {
  if (action == MenuAction_Select) {
    bool isAdmin = IsGet5MenuAdmin(client);
    char infoString[64];
    menu.GetItem(param2, infoString, sizeof(infoString));
    if (StrEqual(infoString, SETUP_MENU_SELECTION_MATCH_TYPE, true) ||
        StrEqual(infoString, SETUP_MENU_SELECTION_PLAYERS_PER_TEAM, true) ||
        StrEqual(infoString, SETUP_MENU_TEAM_SELECTION, true) ||
        StrEqual(infoString, SETUP_MENU_SELECT_TEAMS, true) ||
        StrEqual(infoString, SETUP_MENU_SWAP_TEAMS, true) ||
        StrEqual(infoString, SETUP_MENU_SIDE_TYPE, true) ||
        StrEqual(infoString, SETUP_MENU_SERIES_LENGTH, true) ||
        StrEqual(infoString, SETUP_MENU_MAP_POOL_SELECTION, true) ||
        StrEqual(infoString, SETUP_MENU_MAP_SELECTION, true) ||
        StrEqual(infoString, SETUP_MENU_SELECTED_MAPS, true)) {
      NormalizeLockedSetupMenuValues();
    } else if (StrEqual(infoString, SETUP_MENU_FRIENDLY_FIRE, true)) {
      g_SetupMenuFriendlyFire = !g_SetupMenuFriendlyFire;
    } else if (StrEqual(infoString, SETUP_MENU_CLINCH, true)) {
      if (isAdmin) {
        g_SetupMenuClinch = !g_SetupMenuClinch;
        NormalizeSetupMenuRoundOptions();
      }
    } else if (StrEqual(infoString, SETUP_MENU_OVERTIME, true)) {
      if (g_SetupMenuClinch) {
        g_SetupMenuOvertime = !g_SetupMenuOvertime;
      }
    } else if (StrEqual(infoString, SETUP_MENU_CAPTAINS, true)) {
      if (isAdmin) {
        ShowCaptainsMenu(client);
        return 0;
      }
    } else if (StrEqual(infoString, SETUP_MENU_START_MATCH, true)) {
      if (g_SetupMenuTeamSelection == Get5SetupMenu_TeamSelectionMode_Fixed &&
                 (strlen(g_SetupMenuTeamForTeam1) == 0 || strlen(g_SetupMenuTeamForTeam2) == 0)) {
        Get5_Message(client, "%t", "SetupMenuNeedBothTeams");
      } else if (g_SetupMenuTeamSelection == Get5SetupMenu_TeamSelectionMode_Scrim &&
                 strlen(g_SetupMenuTeamForTeam1) == 0) {
        Get5_Message(client, "%t", "SetupMenuNeedHomeTeam");
      } else if (g_SetupMenuMapSelection == Get5SetupMenu_MapSelectionMode_Manual &&
                 g_SetupMenuSelectedMaps.Length < g_SetupMenuSeriesLength) {
        Get5_Message(client, "%t", "SetupMenuNeedAllMaps", g_SetupMenuSelectedMaps.Length, g_SetupMenuSeriesLength);
      } else {
        CreateMatch(client);
        return 0;
      }
    }
    ShowSetupMenu(client, GetPageIndexForItem(param2));
  } else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
    Command_Get5AdminMenu(client, 0);
  } else if (action == MenuAction_Cancel && (param2 == MenuCancel_Disconnected || param2 == MenuCancel_Interrupted)) {
    menu.Cancel();
  } else if (action == MenuAction_End) {
    if (g_ActiveSetupMenu == menu) {
      g_ActiveSetupMenu = null;
    }
    LogDebug("Ended SetupMenuHandler");
    delete menu;
  }
  return 0;
}

static void GetTeamNameFromJson(const char[] teamKey, char[] name, const int nameLength, bool useTag = false) {
  // First If no name, use the index as team name.
  JSON_Object team = g_SetupMenuAvailableTeams.GetObject(teamKey);
  if (useTag && team.GetString("tag", name, nameLength) && strlen(name) > 0) {
    return;
  } else if (team.GetString("name", name, nameLength) && strlen(name) > 0) {
    return;
  }
  // Use key if no name was provided.
  strcopy(name, nameLength, teamKey);
}

static void ShowCaptainsMenu(int client) {
  Menu menu = new Menu(CaptainsMenuHandler);
  menu.SetTitle("%T", "CaptainsMenuTitle", client);

  // Check that captains are still valid:
  if (g_SetupMenuTeam1Captain > 0) {
    if (!IsPlayer(g_SetupMenuTeam1Captain) ||
        view_as<Get5Side>(GetClientTeam(g_SetupMenuTeam1Captain)) != Get5Side_CT) {
      g_SetupMenuTeam1Captain = -1;
    }
  }
  if (g_SetupMenuTeam2Captain > 0) {
    if (!IsPlayer(g_SetupMenuTeam2Captain) || view_as<Get5Side>(GetClientTeam(g_SetupMenuTeam2Captain)) != Get5Side_T) {
      g_SetupMenuTeam2Captain = -1;
    }
  }

  char playerName[64];
  if (g_SetupMenuTeam1Captain > 0) {
    char captainName[64];
    FormatEx(captainName, sizeof(captainName), "%N", g_SetupMenuTeam1Captain);
    FormatEx(playerName, sizeof(playerName), "%T", "CaptainsMenuTeamItem", client, 1, captainName);
    menu.AddItem(SETUP_MENU_CAPTAINS_TEAM1, playerName);
  } else {
    FormatEx(playerName, sizeof(playerName), "%T", "CaptainsMenuTeamAuto", client, 1);
    menu.AddItem(SETUP_MENU_CAPTAINS_TEAM1, playerName);
  }
  if (g_SetupMenuTeam2Captain > 0) {
    char captainName[64];
    FormatEx(captainName, sizeof(captainName), "%N", g_SetupMenuTeam2Captain);
    FormatEx(playerName, sizeof(playerName), "%T", "CaptainsMenuTeamItem", client, 2, captainName);
    menu.AddItem(SETUP_MENU_CAPTAINS_TEAM2, playerName);
  } else {
    FormatEx(playerName, sizeof(playerName), "%T", "CaptainsMenuTeamAuto", client, 2);
    menu.AddItem(SETUP_MENU_CAPTAINS_TEAM2, playerName);
  }

  menu.ExitButton = false;
  menu.ExitBackButton = true;
  menu.Display(client, MENU_TIME_FOREVER);
  g_ActiveSetupMenu = menu;
}

static int CaptainsMenuHandler(Menu menu, MenuAction action, int client, int param2) {
  if (action == MenuAction_Select) {
    char selectedTeam[PLATFORM_MAX_PATH];
    menu.GetItem(param2, selectedTeam, sizeof(selectedTeam));
    if (StrEqual(selectedTeam, SETUP_MENU_CAPTAINS_TEAM1, true)) {
      ShowCaptainSelectionForTeamMenu(client, Get5Team_1);
    } else if (StrEqual(selectedTeam, SETUP_MENU_CAPTAINS_TEAM2, true)) {
      ShowCaptainSelectionForTeamMenu(client, Get5Team_2);
    }
  } else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
    ShowSetupMenu(client, GetIndexForPage(1));
  } else if (action == MenuAction_Cancel && (param2 == MenuCancel_Disconnected || param2 == MenuCancel_Interrupted)) {
    menu.Cancel();
  } else if (action == MenuAction_End) {
    if (g_ActiveSetupMenu == menu) {
      g_ActiveSetupMenu = null;
    }
    LogDebug("Ended ShowCaptainsMenu");
    delete menu;
  }
  return 0;
}

static void ShowCaptainSelectionForTeamMenu(int client, Get5Team team) {
  Menu menu = new Menu(team == Get5Team_1 ? CaptainSelectionForTeam1MenuHandler : CaptainSelectionForTeam2MenuHandler);
  menu.SetTitle("%T", "CaptainSelectionMenuTitle", client, view_as<int>(team) + 1);

  char clientIndex[16];
  char playerName[64];
  Get5Side side;
  LOOP_CLIENTS(i) {
    if (IsPlayer(i)) {
      side = view_as<Get5Side>(GetClientTeam(i));
      if ((team == Get5Team_1 && side == Get5Side_CT) || (team == Get5Team_2 && side == Get5Side_T)) {
        IntToString(i, clientIndex, sizeof(clientIndex));
        FormatEx(playerName, sizeof(playerName), "%N", i);
        menu.AddItem(clientIndex, playerName);
      }
    }
  }

  if (menu.ItemCount % 6 != 0) {
    menu.AddItem("", "", ITEMDRAW_SPACER);
  }
  char autoText[32];
  FormatEx(autoText, sizeof(autoText), "%T", "CommonAuto", client);
  menu.AddItem(SETUP_MENU_CAPTAINS_AUTO, autoText);

  menu.ExitButton = false;
  menu.ExitBackButton = true;
  menu.Display(client, MENU_TIME_FOREVER);
  g_ActiveSetupMenu = menu;
}

static int CaptainSelectionForTeamMenuHandler(Menu menu, MenuAction action, int client, int param2, Get5Team team) {
  if (action == MenuAction_Select) {
    char selection[PLATFORM_MAX_PATH];
    menu.GetItem(param2, selection, sizeof(selection));
    if (StrEqual(selection, SETUP_MENU_CAPTAINS_AUTO, false)) {
      if (team == Get5Team_1) {
        g_SetupMenuTeam1Captain = -1;
      } else {
        g_SetupMenuTeam2Captain = -1;
      }
      ShowCaptainsMenu(client);
      return 0;
    } else {
      int selectedPlayerClient = StringToInt(selection);
      if (IsPlayer(selectedPlayerClient)) {
        Get5Side side = view_as<Get5Side>(GetClientTeam(selectedPlayerClient));
        if (side == Get5Side_CT && team == Get5Team_1) {
          g_SetupMenuTeam1Captain = selectedPlayerClient;
          ShowCaptainsMenu(client);
          return 0;
        } else if (side == Get5Side_T && team == Get5Team_2) {
          g_SetupMenuTeam2Captain = selectedPlayerClient;
          ShowCaptainsMenu(client);
          return 0;
        }
      }
    }
    // If invalid or set to auto; show the captain menu again.
    ShowCaptainSelectionForTeamMenu(client, team);
  } else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
    ShowCaptainsMenu(client);
  } else if (action == MenuAction_Cancel && (param2 == MenuCancel_Disconnected || param2 == MenuCancel_Interrupted)) {
    menu.Cancel();
  } else if (action == MenuAction_End) {
    if (g_ActiveSetupMenu == menu) {
      g_ActiveSetupMenu = null;
    }
    LogDebug("Ended ShowCaptainSelectionForTeamMenu");
    delete menu;
  }
  return 0;
}

static int CaptainSelectionForTeam1MenuHandler(Menu menu, MenuAction action, int client, int param2) {
  return CaptainSelectionForTeamMenuHandler(menu, action, client, param2, Get5Team_1);
}

static int CaptainSelectionForTeam2MenuHandler(Menu menu, MenuAction action, int client, int param2) {
  return CaptainSelectionForTeamMenuHandler(menu, action, client, param2, Get5Team_2);
}

static void HandleMapPoolAndSeriesLength() {
  // If we increase series length, switch "current" map selection to "pick/ban"
  if (g_SetupMenuSeriesLength > 1 && g_SetupMenuMapSelection == Get5SetupMenu_MapSelectionMode_Current) {
    g_SetupMenuMapSelection = Get5SetupMenu_MapSelectionMode_PickBan;
  }

  JSON_Array maps = GetMapsFromSelectedPool();
  // Make sure the map pool is large enough to support the series length
  if (maps.Length <= g_SetupMenuSeriesLength) {
    if (g_SetupMenuMapSelection == Get5SetupMenu_MapSelectionMode_PickBan) {
      // In pick/ban, the pool must be 1 larger than the series length.
      g_SetupMenuSeriesLength = maps.Length - 1;
      if (g_SetupMenuSeriesLength < 1) {
        g_SetupMenuSeriesLength = 1;
        g_SetupMenuMapSelection = Get5SetupMenu_MapSelectionMode_Manual;
      }
    } else if (g_SetupMenuSeriesLength > maps.Length) {
      // In manual mode, the map pool must at least the series length. Set to 1 to allow cycling.
      g_SetupMenuSeriesLength = 1;
    }
  }
}

static void ResetMapPool(int client, bool showReloadMessage = false) {
  json_cleanup_and_delete(g_SetupMenuMapPool);
  char error[PLATFORM_MAX_PATH];
  g_SetupMenuMapPool = LoadMapsFile(error);
  if (g_SetupMenuMapPool == null) {
    g_SetupMenuMapPool = new JSON_Object();
    g_SetupMenuSelectedMapPool = DEFAULT_CONFIG_KEY;
    g_SetupMenuMapPool.SetObject(g_SetupMenuSelectedMapPool, CreateDefaultMapPool());
    if (IsValidClient(client)) {
      Get5_Message(client, "%t", "MenuFailedLoadMapsGeneratingDefault", error);
    }
  } else {
    // File will not load if empty, so it's safe to do this.
    if (strlen(g_SetupMenuSelectedMapPool) == 0 || !g_SetupMenuMapPool.HasKey(g_SetupMenuSelectedMapPool)) {
      g_SetupMenuMapPool.GetKey(0, g_SetupMenuSelectedMapPool, sizeof(g_SetupMenuSelectedMapPool));
    }
    if (showReloadMessage && IsValidClient(client)) {
      Get5_Message(client, "%t", "MenuReloadedMapsFoundPools", g_SetupMenuMapPool.Length);
    }
  }
}

static JSON_Array GetMapsFromSelectedPool() {
  return view_as<JSON_Array>(g_SetupMenuMapPool.GetObject(g_SetupMenuSelectedMapPool));
}

static int EnabledIf(bool cond) {
  return cond ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED;
}

static void CreateMatch(int client) {
  if (g_GameState != Get5State_None) {
    Get5_Message(client, "%t", "MenuMatchAlreadyLoaded");
    return;
  }
  NormalizeLockedSetupMenuValues();
  NormalizeSetupMenuRoundOptions();

  char serverId[SERVER_ID_LENGTH];
  g_ServerIdCvar.GetString(serverId, sizeof(serverId));
  char path[PLATFORM_MAX_PATH];
  FormatEx(path, sizeof(path), TEMP_MATCHCONFIG_JSON, serverId);
  DeleteFileIfExists(path);

  JSON_Object match = new JSON_Object();
  match.SetString("matchid", "manual");
  match.SetInt("num_maps", g_SetupMenuSeriesLength);
  match.SetBool("skip_veto", g_SetupMenuMapSelection != Get5SetupMenu_MapSelectionMode_PickBan);
  match.SetInt("players_per_team", g_SetupMenuPlayersPerTeam);
  match.SetBool("clinch_series", true);
  match.SetBool("wingman", g_SetupMenuWingman);
  match.SetBool("scrim", g_SetupMenuTeamSelection == Get5SetupMenu_TeamSelectionMode_Scrim);

  char sideType[32];
  MatchSideTypeToString(g_SetupMenuSideType, sideType, sizeof(sideType));
  match.SetString("side_type", sideType);

  JSON_Array mapList;
  char mapName[PLATFORM_MAX_PATH];
  if (g_SetupMenuMapSelection == Get5SetupMenu_MapSelectionMode_PickBan) {
    mapList = GetMapsFromSelectedPool().DeepCopy();
  } else {
    mapList = new JSON_Array();
    if (g_SetupMenuMapSelection == Get5SetupMenu_MapSelectionMode_Current) {
      GetCurrentMap(mapName, sizeof(mapName));
      mapList.PushString(mapName);
    } else {  // else manual
      int l = g_SetupMenuSelectedMaps.Length;
      for (int i = 0; i < l; i++) {
        g_SetupMenuSelectedMaps.GetString(i, mapName, sizeof(mapName));
        mapList.PushString(mapName);
      }
    }
  }
  match.SetObject("maplist", mapList);

  if (g_SetupMenuTeamSelection == Get5SetupMenu_TeamSelectionMode_Current) {

    match.SetObject("team1", GetTeamObjectFromCurrentPlayers(Get5Side_CT, g_SetupMenuTeam1Captain));
    match.SetObject("team2", GetTeamObjectFromCurrentPlayers(Get5Side_T, g_SetupMenuTeam2Captain));

  } else if (g_SetupMenuTeamSelection == Get5SetupMenu_TeamSelectionMode_Fixed) {

    // Important to copy the teams here as to not mess up the menu handles.
    match.SetObject("team1", g_SetupMenuAvailableTeams.GetObject(g_SetupMenuTeamForTeam1).DeepCopy());
    match.SetObject("team2", g_SetupMenuAvailableTeams.GetObject(g_SetupMenuTeamForTeam2).DeepCopy());

  } else {

    // Scrim by deduction
    match.SetObject("team1", g_SetupMenuAvailableTeams.GetObject(g_SetupMenuTeamForTeam1).DeepCopy());
  }

  JSON_Object spectators = GetTeamObjectFromCurrentPlayers(Get5Side_Spec);
  if (view_as<JSON_Array>(spectators.GetObject("players")).Length > 0) {
    match.SetObject("spectators", spectators);
  } else {
    // Don't need this if empty.
    json_cleanup_and_delete(spectators);
  }

  char error[PLATFORM_MAX_PATH];
  JSON_Object cvars = LoadCvarsFile(error, DEFAULT_CONFIG_KEY);
  if (cvars == null) {
    Get5_Message(client, "%t", "MenuErrorLoadingCvars", error);
    json_cleanup_and_delete(match);
    return;
  }

  cvars.SetString("mp_friendlyfire", g_SetupMenuFriendlyFire ? "1" : "0");
  cvars.SetString("mp_match_can_clinch", g_SetupMenuClinch ? "1" : "0");
  cvars.SetString("mp_overtime_enable", g_SetupMenuOvertime ? "1" : "0");
  match.SetObject("cvars", cvars);

  if (!match.WriteToFile(path)) {
    Get5_Message(client, "%t", "MenuFailedWriteMatchConfigFile", path);
  } else {
    if (!LoadMatchConfig(path, error)) {
      Get5_Message(client, "%t", "MenuFailedStartMatch", error);
    } else {
      DeleteFileIfExists(path);
    }
  }
  json_cleanup_and_delete(match);
}

Action Command_Get5AdminMenu(int client, int args) {
  if (!IsPlayer(client)) {
    ReplyToCommand(client, "%t", "MenuCommandInGameOnly");
    return Plugin_Handled;
  }
  GiveAdminMenu(client);
  return Plugin_Handled;
}

static void GiveAdminMenu(int client) {
  bool isAdmin = IsGet5MenuAdmin(client);
  Menu menu = new Menu(AdminMenuHandler);
  menu.SetTitle("%T", "AdminMenuTitle", client);

  char buffer[64];
  FormatEx(buffer, sizeof(buffer), "%T", "AdminMenuCreateMatch", client);
  menu.AddItem(SETUP_MENU_CREATE_MATCH, buffer, EnabledIf(g_GameState == Get5State_None));
  FormatEx(buffer, sizeof(buffer), "%T", "AdminMenuForceReadyAll", client);
  menu.AddItem(SETUP_MENU_FORCE_READY, buffer,
               EnabledIf(isAdmin && (g_GameState == Get5State_Warmup || g_GameState == Get5State_PreVeto ||
                                     g_GameState == Get5State_PendingRestore)));
  FormatEx(buffer, sizeof(buffer), "%T", "AdminMenuEndMatch", client);
  menu.AddItem(SETUP_MENU_END_MATCH, buffer, EnabledIf(isAdmin && g_GameState != Get5State_None));
  FormatEx(buffer, sizeof(buffer), "%T", "AdminMenuAddScrimRinger", client);
  menu.AddItem(SETUP_MENU_RINGER, buffer, EnabledIf(isAdmin && g_InScrimMode && g_GameState != Get5State_None));
  FormatEx(buffer, sizeof(buffer), "%T", "AdminMenuLoadBackup", client);
  menu.AddItem(SETUP_MENU_LIST_BACKUPS, buffer, EnabledIf(false));

  menu.Pagination = MENU_NO_PAGINATION;
  menu.ExitButton = true;

  menu.Display(client, MENU_TIME_FOREVER);
}

static int AdminMenuHandler(Menu menu, MenuAction action, int client, int param2) {
  if (action == MenuAction_Select) {
    bool isAdmin = IsGet5MenuAdmin(client);
    char infoString[64];
    menu.GetItem(param2, infoString, sizeof(infoString));
    if (StrEqual(infoString, SETUP_MENU_CREATE_MATCH)) {
      if (g_ActiveSetupMenu != null) {
        Get5_Message(client, "%t", "MenuAnotherPlayerSettingUpMatch");
      } else if (g_GameState != Get5State_None) {
        Get5_Message(client, "%t", "MenuCannotUseSetupWhileMatchLoaded");
      } else {
        if (!InWarmup()) {
          StartWarmup();  // So players can "coach ct/t" after joining their team.
        }
        ShowSetupMenu(client);
      }
    } else if (isAdmin && StrEqual(infoString, SETUP_MENU_FORCE_READY)) {
      FakeClientCommand(client, "get5_forceready");
    } else if (isAdmin && StrEqual(infoString, SETUP_MENU_END_MATCH)) {
      GiveConfirmEndMatchMenu(client);
    } else if (isAdmin && IsBackupSystemEnabled() && StrEqual(infoString, SETUP_MENU_LIST_BACKUPS)) {
      GiveBackupMenu(client);
    } else if (isAdmin && StrEqual(infoString, SETUP_MENU_RINGER)) {
      GiveRingerMenu(client);
    }
  } else if (action == MenuAction_Cancel && (param2 == MenuCancel_Disconnected || param2 == MenuCancel_Interrupted)) {
    menu.Cancel();
  } else if (action == MenuAction_End) {
    LogDebug("Ended GiveAdminMenu");
    delete menu;
  }
  return 0;
}

static void GiveConfirmEndMatchMenu(int client) {
  Menu menu = new Menu(ConfirmEndMatchMenuHandler);
  menu.SetTitle("%T", "AdminMenuSelectOutcome", client);
  char teamName[64];
  strcopy(teamName, sizeof(teamName), g_TeamNames[Get5Team_1]);
  if (strlen(teamName) > 0) {
    Format(teamName, sizeof(teamName), "%T", "AdminMenuOutcomeTeamWinsNamed", client, 1, teamName);
  } else {
    FormatEx(teamName, sizeof(teamName), "%T", "AdminMenuOutcomeTeamWins", client, 1);
  }
  menu.AddItem(SETUP_MENU_CONFIRM_END_MATCH_TEAM1, teamName);

  strcopy(teamName, sizeof(teamName), g_TeamNames[Get5Team_2]);
  if (strlen(teamName) > 0) {
    Format(teamName, sizeof(teamName), "%T", "AdminMenuOutcomeTeamWinsNamed", client, 2, teamName);
  } else {
    FormatEx(teamName, sizeof(teamName), "%T", "AdminMenuOutcomeTeamWins", client, 2);
  }
  menu.AddItem(SETUP_MENU_CONFIRM_END_MATCH_TEAM2, teamName);

  FormatEx(teamName, sizeof(teamName), "%T", "CommonDraw", client);
  menu.AddItem(SETUP_MENU_CONFIRM_END_MATCH_DRAW, teamName);
  menu.ExitButton = false;
  menu.ExitBackButton = true;
  menu.Display(client, MENU_TIME_FOREVER);
}

static int ConfirmEndMatchMenuHandler(Menu menu, MenuAction action, int client, int param2) {
  if (action == MenuAction_Select) {
    char infoString[64];
    menu.GetItem(param2, infoString, sizeof(infoString));
    if (StrEqual(infoString, SETUP_MENU_CONFIRM_END_MATCH_DRAW)) {
      FakeClientCommand(client, "get5_endmatch");
    } else if (StrEqual(infoString, SETUP_MENU_CONFIRM_END_MATCH_TEAM1)) {
      FakeClientCommand(client, "get5_endmatch team1");
    } else if (StrEqual(infoString, SETUP_MENU_CONFIRM_END_MATCH_TEAM2)) {
      FakeClientCommand(client, "get5_endmatch team2");
    }
  } else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
    GiveAdminMenu(client);
  } else if (action == MenuAction_Cancel && (param2 == MenuCancel_Disconnected || param2 == MenuCancel_Interrupted)) {
    menu.Cancel();
  } else if (action == MenuAction_End) {
    LogDebug("Ended GiveConfirmEndMatchMenu");
    delete menu;
  }
  return 0;
}

static void GiveBackupMenu(int client) {
  Menu menu = new Menu(ListBackupsMenuHandler);
  menu.SetTitle("%T", "AdminMenuSelectBackup", client);

  if (!IsBackupSystemEnabled()) {
    char disabledText[64];
    FormatEx(disabledText, sizeof(disabledText), "%T", "BackupSystemDisabled", client);
    menu.AddItem("", disabledText, EnabledIf(false));
    menu.ExitBackButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
    return;
  }

  char lastBackup[PLATFORM_MAX_PATH];
  g_LastGet5BackupCvar.GetString(lastBackup, sizeof(lastBackup));
  char buffer[64];
  FormatEx(buffer, sizeof(buffer), "%T", "CommonLatest", client);
  menu.AddItem(lastBackup, buffer, EnabledIf(!StrEqual(lastBackup, "")));

  ArrayList backups = GetBackups(g_MatchID);
  if (backups == null || backups.Length == 0) {
    FormatEx(buffer, sizeof(buffer), "%T", "AdminMenuNoBackupsFound", client);
    menu.AddItem("", buffer, EnabledIf(false));
  } else {
    char backupInfo[64];
    char filename[PLATFORM_MAX_PATH];
    int length = backups.Length;
    for (int i = 0; i < length; i++) {
      backups.GetString(i, filename, sizeof(filename));
      if (GetRoundInfoFromBackupFile(filename, backupInfo, sizeof(backupInfo), g_GameState == Get5State_None)) {
        menu.AddItem(filename, backupInfo);
      }
    }
  }
  delete backups;
  menu.ExitBackButton = true;
  menu.Display(client, MENU_TIME_FOREVER);
}

static int ListBackupsMenuHandler(Menu menu, MenuAction action, int client, int param2) {
  if (action == MenuAction_Select) {
    char backupFileString[PLATFORM_MAX_PATH];
    char error[PLATFORM_MAX_PATH];
    menu.GetItem(param2, backupFileString, sizeof(backupFileString));
    if (!RestoreFromBackup(backupFileString, error)) {
      Get5_Message(client, "%t", "MenuFailedLoadBackup", error);
    }
  } else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
    GiveAdminMenu(client);
  } else if (action == MenuAction_Cancel && (param2 == MenuCancel_Disconnected || param2 == MenuCancel_Interrupted)) {
    menu.Cancel();
  } else if (action == MenuAction_End) {
    LogDebug("Ended GiveBackupMenu");
    delete menu;
  }
  return 0;
}

static void GiveRingerMenu(int client) {
  Menu menu = new Menu(RingerMenuHandler);
  menu.SetTitle("%T", "AdminMenuSelectPlayer", client);
  menu.ExitButton = true;
  menu.ExitBackButton = true;

  LOOP_CLIENTS(i) {
    if (IsPlayer(i)) {
      char infoString[64];
      IntToString(GetClientUserId(i), infoString, sizeof(infoString));
      char displayString[64];
      FormatEx(displayString, sizeof(displayString), "%N", i);
      menu.AddItem(infoString, displayString);
    }
  }
  menu.Display(client, MENU_TIME_FOREVER);
}

static int RingerMenuHandler(Menu menu, MenuAction action, int client, int param2) {
  if (action == MenuAction_Select) {
    char infoString[64];
    menu.GetItem(param2, infoString, sizeof(infoString));
    int userId = StringToInt(infoString);
    int choiceClient = GetClientOfUserId(userId);
    if (IsPlayer(choiceClient)) {
      char choiceName[64];
      FormatEx(choiceName, sizeof(choiceName), "%N", choiceClient);
      if (SwapScrimTeamStatus(choiceClient)) {
        Get5_Message(client, "%t", "MenuSwappedPlayer", choiceName);
        GiveAdminMenu(client);
      } else {
        Get5_Message(client, "%t", "MenuFailedSwapPlayer", choiceName);
        GiveRingerMenu(client);
      }
    } else {
      Get5_Message(client, "%t", "MenuInvalidSelection");
      GiveRingerMenu(client);
    }
  } else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) {
    GiveAdminMenu(client);
  } else if (action == MenuAction_Cancel && (param2 == MenuCancel_Disconnected || param2 == MenuCancel_Interrupted)) {
    menu.Cancel();
  } else if (action == MenuAction_End) {
    LogDebug("Ended GiveRingerMenu");
    delete menu;
  }
  return 0;
}
