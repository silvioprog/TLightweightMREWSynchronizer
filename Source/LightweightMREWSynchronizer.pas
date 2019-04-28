{
  TLightweightMREWSynchronizer allows multiple threads to read from the
  protected memory simultaneously, while ensuring that any thread writing to
  the memory has exclusive access.

  Adapted from JEDI project.
}

unit LightweightMREWSynchronizer;

interface

uses
  SysUtils,
  Classes,
  SyncObjs;

type

  { TLightweightMREWPriority }

  TLightweightMREWPriority = (lmpReadings, lmpWritings, lmpBoth);

  { TLightweightMREWItem }

  TLightweightMREWItem = packed record
    ID: TThreadID;
    RWCount: Cardinal;
    RW: Boolean;
    constructor Create(AID: TThreadID; ARWCount: Cardinal; ARW: Boolean);
  end;

  { TLightweightMREWList }

  TLightweightMREWList = array of TLightweightMREWItem;

  { TLightweightMREWSynchronizer }

  TLightweightMREWSynchronizer = class(TInterfacedObject, IReadWriteSync)
  private
    FSemaphoreR: TSemaphore;
    FSemaphoreW: TSemaphore;
    FCS: TCriticalSection;
    FItems: TLightweightMREWList;
    FPriority: TLightweightMREWPriority;
    FReleaseCount: Integer;
    FReadings: Integer;
    FWritings: Integer;
    procedure AddItem(AID: TThreadID; ARW: Boolean); inline;
    procedure RemoveItem(AIndex: Integer); inline;
    function IndexByID(AID: TThreadID): Integer; inline;
    procedure ReleaseW(AReading: Boolean); inline;
    procedure EndRW; inline;
  protected
    function CreateSemaphoreR: TSemaphore; virtual;
    function CreateSemaphoreW: TSemaphore; virtual;
    function CreateCS: TCriticalSection; virtual;
  public
    constructor Create(APriority: TLightweightMREWPriority); overload; virtual;
    constructor Create; overload; virtual;
    destructor Destroy; override;
    procedure BeginRead; virtual;
    procedure BeginWrite; virtual;
    procedure EndRead; virtual;
    procedure EndWrite; virtual;
  end;

implementation

{ TLightweightMREWItem }

constructor TLightweightMREWItem.Create(AID: TThreadID; ARWCount: Cardinal;
  ARW: Boolean);
begin
  ID := AID;
  RWCount := ARWCount;
  RW := ARW;
end;

{ TLightweightMREWSynchronizer }

constructor TLightweightMREWSynchronizer.Create(
  APriority: TLightweightMREWPriority);
begin
  inherited Create;
  FSemaphoreR := CreateSemaphoreR;
  FSemaphoreW := CreateSemaphoreW;
  FCS := CreateCS;
  FPriority := APriority;
end;

constructor TLightweightMREWSynchronizer.Create;
begin
  Create(lmpReadings);
end;

destructor TLightweightMREWSynchronizer.Destroy;
begin
  FSemaphoreR.Free;
  FSemaphoreW.Free;
  FCS.Free;
  inherited Destroy;
end;

function TLightweightMREWSynchronizer.CreateSemaphoreR: TSemaphore;
begin
  Result := TSemaphore.Create(nil, 0, MaxInt, '');
end;

function TLightweightMREWSynchronizer.CreateSemaphoreW: TSemaphore;
begin
  Result := TSemaphore.Create(nil, 0, MaxInt, '');
end;

function TLightweightMREWSynchronizer.CreateCS: TCriticalSection;
begin
  Result := TCriticalSection.Create;
end;

procedure TLightweightMREWSynchronizer.AddItem(AID: TThreadID; ARW: Boolean);
var
  L: Integer;
begin
  L := Length(FItems);
  SetLength(FItems, Succ(L));
  FItems[L] := TLightweightMREWItem.Create(AID, 1, ARW);
end;

procedure TLightweightMREWSynchronizer.RemoveItem(AIndex: Integer);
var
  L: Integer;
begin
  L := Pred(Length(FItems));
  if AIndex < L then
    Move(FItems[Succ(AIndex)], FItems[AIndex],
      (L - AIndex) * SizeOf(TLightweightMREWItem));
  SetLength(FItems, L);
end;

function TLightweightMREWSynchronizer.IndexByID(AID: TThreadID): Integer;
begin
  for Result := 0 to Pred(Length(FItems)) do
    if FItems[Result].ID = AID then
      Exit;
  Result := -1;
end;

procedure TLightweightMREWSynchronizer.ReleaseW(AReading: Boolean);
var
  P: TLightweightMREWPriority;
begin
  P := lmpBoth;
  case FPriority of
    lmpReadings:
      if FReadings > 0 then
        P := lmpReadings
      else if FWritings > 0 then
        P := lmpWritings;
    lmpWritings:
      if FWritings > 0 then
        P := lmpWritings
      else if FReadings > 0 then
        P := lmpReadings;
    lmpBoth:
      if AReading then
      begin
        if FWritings > 0 then
          P := lmpWritings
        else if FReadings > 0 then
          P := lmpReadings;
      end
      else
        if FReadings > 0 then
          P := lmpReadings
        else if FWritings > 0 then
          P := lmpWritings;
  end;
  case P of
    lmpReadings:
    begin
      FReleaseCount := FReadings;
      FReadings := 0;
      FSemaphoreR.Release(FReleaseCount);
    end;
    lmpWritings:
    begin
      FReleaseCount := -1;
      Dec(FWritings);
      FSemaphoreW.Release(1);
    end;
  end;
end;

procedure TLightweightMREWSynchronizer.EndRW;
var
  T: TThreadID;
  I: Integer;
  R: Boolean;
begin
  T := TThread.Current.ThreadId;
  FCS.Acquire;
  try
    I := IndexByID(T);
    if I >= 0 then
    begin
      Dec(FItems[I].RWCount);
      if FItems[I].RWCount = 0 then
      begin
        R := FItems[I].RW;
        if R then
          Dec(FReleaseCount)
        else
          FReleaseCount := 0;
        RemoveItem(I);
        if FReleaseCount = 0 then
          ReleaseW(R);
      end;
    end;
  finally
    FCS.Release;
  end;
end;

procedure TLightweightMREWSynchronizer.BeginRead;
var
  T: TThreadID;
  I: Integer;
  W: Boolean;
begin
  W := False;
  T := TThread.Current.ThreadId;
  FCS.Acquire;
  try
    I := IndexByID(T);
    if I >= 0 then
      Inc(FItems[I].RWCount)
    else
    begin
      AddItem(T, True);
      if FReleaseCount >= 0 then
      begin
        if (FPriority = lmpReadings) or (FWritings = 0) then
          Inc(FReleaseCount)
        else
        begin
          Inc(FReadings);
          W := True;
        end;
      end
      else
      begin
        Inc(FReadings);
        W := True;
      end;
    end;
  finally
    FCS.Release;
  end;
  if W then
    FSemaphoreR.WaitFor(INFINITE);
end;

procedure TLightweightMREWSynchronizer.EndRead;
begin
  EndRW;
end;

procedure TLightweightMREWSynchronizer.BeginWrite;
var
  T: TThreadID;
  I: Integer;
  W: Boolean;
begin
  W := False;
  FCS.Acquire;
  try
    T := TThread.Current.ThreadID;
    I := IndexByID(T);
    if I < 0 then
    begin
      AddItem(T, False);
      if FReleaseCount = 0 then
        FReleaseCount := -1
      else
      begin
        Inc(FWritings);
        W := True;
      end;
    end
    else
      if FItems[I].RW then
      begin
        Inc(FItems[I].RWCount);
        FItems[I].RW := False;
        Dec(FReleaseCount);
        if FReleaseCount = 0 then
          FReleaseCount := -1
        else
        begin
          W := True;
          Inc(FWritings);
        end;
      end
      else
        Inc(FItems[I].RWCount);
  finally
    FCS.Release;
  end;
  if W then
    FSemaphoreW.WaitFor(INFINITE);
end;

procedure TLightweightMREWSynchronizer.EndWrite;
begin
  EndRW;
end;

end.