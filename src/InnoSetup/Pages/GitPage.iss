[Code]
{ Copyright 2019-2021 Espressif Systems (Shanghai) CO LTD
  SPDX-License-Identifier: Apache-2.0 }

{ ------------------------------ Find installed copies of Git ------------------------------ }

var
  InstalledGitVersions: TStringList;
  InstalledGitDisplayNames: TStringList;
  InstalledGitExecutables: TStringList;


procedure GitVersionAdd(Version, DisplayName, Executable: String);
begin
  Log('Adding Git version=' + Version + ' name='+DisplayName+' executable='+Executable);
  InstalledGitVersions.Append(Version);
  InstalledGitDisplayNames.Append(DisplayName);
  InstalledGitExecutables.Append(Executable);
end;

function GetVersionOfGitExe(Path: String; var Version: String; var ErrStr: String): Boolean;
var
  VersionOutputFile: String;
  Args: String;
  GitVersionAnsi: AnsiString;
  GitVersion: String;
  GitVersionPrefix: String;
  Err: Integer;
begin
  VersionOutputFile := ExpandConstant('{tmp}\gitver.txt');

  DeleteFile(VersionOutputFile);
  Args := '/C "' + Path + '" --version >gitver.txt';
  Log('Running ' + Args);
  if not ShellExec('', 'cmd.exe', Args,
    ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, Err) then
  begin
    ErrStr := 'Failed to get git version, error=' + IntToStr(err);
    Log(ErrStr);
    Result := False;
    exit;
  end;

  LoadStringFromFile(VersionOutputFile, GitVersionAnsi);
  GitVersion := Trim(String(GitVersionAnsi));
  GitVersionPrefix := 'git version ';
  if Pos(GitVersionPrefix, GitVersion) <> 1 then
  begin
    ErrStr := 'Unexpected git version format: ' + GitVersion;
    Log(ErrStr);
    Result := False;
    exit;
  end;

  Delete(GitVersion, 1, Length(GitVersionPrefix));
  Version := GitVersion;
  Result := True;
end;

procedure FindGitInPath();
var
  Args: String;
  GitListFile: String;
  GitPaths: TArrayOfString;
  GitVersion: String;
  ErrStr: String;
  Err: Integer;
  i: Integer;
begin
  GitListFile := ExpandConstant('{tmp}\gitlist.txt');
  Args := '/C where git.exe >"' + GitListFile + '"';
  if not ShellExec('', 'cmd.exe', Args,
      '', SW_HIDE, ewWaitUntilTerminated, Err) then
  begin
    Log('Failed to find git using "where", error='+IntToStr(Err));
    exit;
  end;

  LoadStringsFromFile(GitListFile, GitPaths);

  for i:= 0 to GetArrayLength(GitPaths) - 1 do
  begin
    Log('Git path: ' + GitPaths[i]);
    if not GetVersionOfGitExe(GitPaths[i], GitVersion, ErrStr) then
      continue;

    Log('Git version: ' + GitVersion);
    GitVersionAdd(GitVersion, GitVersion, GitPaths[i]);
  end;
end;

procedure FindInstalledGitVersions();
begin
  InstalledGitVersions := TStringList.Create();
  InstalledGitDisplayNames := TStringList.Create();
  InstalledGitExecutables := TStringList.Create();

  FindGitInPath();
end;


var
  GitPage: TInputOptionWizardPage;
  GitPath, GitExecutablePath, GitVersion: String;
  GitUseExisting: Boolean;
  GitSelectionInstallIndex: Integer;
  GitSelectionCustomPathIndex: Integer;

function GetGitPath(Unused: String): String;
begin
  Result := GitPath;
end;

function GitInstallRequired(): Boolean;
begin
  Result := not GitUseExisting;
end;

function GitVersionSupported(Version: String): Boolean;
var
  Major, Minor: Integer;
begin
  Result := False;
  if not VersionExtractMajorMinor(Version, Major, Minor) then
  begin
    Log('GitVersionSupported: Could not parse version=' + Version);
    exit;
  end;

  { Need at least git 2.12 for 'git clone --reference' to work with submodules }
  if (Major = 2) and (Minor >= 12) then Result := True;
  if (Major > 2) then Result := True;
end;

procedure GitCustomPathUpdateEnabled();
var
  Enable: Boolean;
begin
  if GitPage.SelectedValueIndex = GitSelectionCustomPathIndex then
    Enable := True;

  ChoicePageSetInputEnabled(GitPage, Enable);
end;

procedure OnGitPagePrepare(Sender: TObject);
var
  Page: TInputOptionWizardPage;
  FullName: String;
  i, Index, FirstEnabledIndex: Integer;
  OfferToInstall: Boolean;
  VersionToInstall: String;
  VersionSupported: Boolean;
begin
  Page := TInputOptionWizardPage(Sender);
  Log('OnGitPagePrepare');
  if Page.CheckListBox.Items.Count > 0 then
    exit;

  FindInstalledGitVersions();

  VersionToInstall := '{#GitVersion}';
  OfferToInstall := True;
  FirstEnabledIndex := -1;

  for i := 0 to InstalledGitVersions.Count - 1 do
  begin
    VersionSupported := GitVersionSupported(InstalledGitVersions[i]);
    FullName := InstalledGitDisplayNames.Strings[i];
    if not VersionSupported then
    begin
      FullName := FullName + ' (unsupported)';
    end;
    FullName := FullName + #13#10 + InstalledGitExecutables.Strings[i];
    Index := Page.Add(FullName);
    if not VersionSupported then
    begin
      Page.CheckListBox.ItemEnabled[Index] := False;
    end else begin
      if FirstEnabledIndex < 0 then FirstEnabledIndex := Index;
    end;
    if InstalledGitVersions[i] = VersionToInstall then
    begin
      OfferToInstall := False;
    end;
  end;

  if OfferToInstall then
  begin
    Index := Page.Add('Install Git ' + VersionToInstall);
    if FirstEnabledIndex < 0 then FirstEnabledIndex := Index;
    GitSelectionInstallIndex := Index;
  end;

  Index := Page.Add('Custom git.exe location');
  if FirstEnabledIndex < 0 then FirstEnabledIndex := Index;
  GitSelectionCustomPathIndex := Index;

  Page.SelectedValueIndex := FirstEnabledIndex;
  GitCustomPathUpdateEnabled();
end;

procedure OnGitSelectionChange(Sender: TObject);
var
  Page: TInputOptionWizardPage;
begin
  Page := TInputOptionWizardPage(Sender);
  Log('OnGitSelectionChange index=' + IntToStr(Page.SelectedValueIndex));
  GitCustomPathUpdateEnabled();
end;

function OnGitPageValidate(Sender: TWizardPage): Boolean;
var
  Page: TInputOptionWizardPage;
  Version, ErrStr: String;
begin
  Page := TInputOptionWizardPage(Sender);
  Log('OnGitPageValidate index=' + IntToStr(Page.SelectedValueIndex));
  if Page.SelectedValueIndex = GitSelectionInstallIndex then
  begin
    GitUseExisting := False;
    GitExecutablePath := '';
    GitPath := '';
    GitVersion := '{#GitVersion}';
    Result := True;
  end else if Page.SelectedValueIndex = GitSelectionCustomPathIndex then
  begin
    GitPath := ChoicePageGetInputText(Page);
    GitExecutablePath := GitPath + '\git.exe';
    if not FileExists(GitExecutablePath) then
    begin
      MsgBox('Can not find git.exe in ' + GitPath, mbError, MB_OK);
      Result := False;
      exit;
    end;

    if not GetVersionOfGitExe(GitExecutablePath, Version, ErrStr) then
    begin
      MsgBox('Can not determine version of git.exe.' + #13#10
             + 'Please check that this copy of git works from cmd.exe.', mbError, MB_OK);
      Result := False;
      exit;
    end;
    Log('Version of ' + GitExecutablePath + ' is ' + Version);
    if not GitVersionSupported(Version) then
    begin
      MsgBox('Selected git version (' + Version + ') is not supported.', mbError, MB_OK);
      Result := False;
      exit;
    end;
    Log('Version of git is supported');
    GitUseExisting := True;
    GitVersion := Version;
  end else begin
    GitUseExisting := True;
    GitExecutablePath := InstalledGitExecutables[Page.SelectedValueIndex];
    GitPath := ExtractFilePath(GitExecutablePath);
    GitVersion := InstalledGitVersions[Page.SelectedValueIndex];
    Result := True;
  end;
end;

procedure GitExecutablePathUpdateAfterInstall();
var
  GitInstallPath: String;
begin
  GitInstallPath := GetInstallPath('SOFTWARE\GitForWindows', 'InstallPath');
  if GitInstallPath = '' then
  begin
    Log('Failed to find Git install path');
    exit;
  end;
  GitPath := GitInstallPath + '\cmd';
  GitExecutablePath := GitPath + '\git.exe';
end;

<event('InitializeWizard')>
procedure CreateGitPage();
begin
  GitPage := ChoicePageCreate(
    wpLicense,
    'Git choice', 'Please choose Git version',
    'Available Git versions',
    'Enter custom location of git.exe',
    True,
    @OnGitPagePrepare,
    @OnGitSelectionChange,
    @OnGitPageValidate);
end;

<event('ShouldSkipPage')>
function ShouldSkipGitPage(PageID: Integer): Boolean;
begin
  if (PageID = GitPage.ID) then begin
    { Skip in case of embedded Python. }
    if (UseEmbeddedGit) then begin
      Result := True;
    end;
  end;
end;
