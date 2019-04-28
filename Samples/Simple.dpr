program Simple;

{$IFDEF MSWINDOWS}
 {$APPTYPE CONSOLE}
{$ENDIF}

uses
  SysUtils,
  Classes,
  Generics.Collections,
  LightweightMREWSynchronizer in '../Source/LightweightMREWSynchronizer.pas';

const
  THREAD_COUNT = 50;

var
  RWS: IReadWriteSync;
  Resource: TDictionary<string, string>;

type
  TThreadTest = class(TThread)
  private
    FChanged: Boolean;
  protected
    procedure Execute; override;
    procedure DoSyncInfo;
    procedure DoSyncLog;
  public
    constructor Create; virtual;
  end;

constructor TThreadTest.Create;
begin
  inherited Create(True);
  FreeOnTerminate := False;
end;

procedure TThreadTest.DoSyncInfo;
begin
  WriteLn('Thread ', ThreadID, ' changed key to 456', #9, '[',
    FormatDateTime('hh:nn:ss.zzz', Now), ']');
end;

procedure TThreadTest.DoSyncLog;
begin
  WriteLn('Thread', #9, ThreadID, #9, Resource['Key'], #9, '[',
    FormatDateTime('hh:nn:ss.zzz', Now), ']');
end;

procedure TThreadTest.Execute;
begin
  RWS.BeginRead;
  try
    if not Resource.ContainsKey('Key') then
    begin
      RWS.BeginWrite;
      try
        Resource.Add('Key', '123');
      finally
        RWS.EndWrite
      end;
    end;
    if FChanged then
    begin
      RWS.BeginWrite;
      try
        Resource['Key'] := '456';
        Synchronize(DoSyncInfo);
      finally
        RWS.EndWrite;
      end;
    end;
    Synchronize(DoSyncLog);
  finally
    RWS.EndRead;
  end;
end;

var
  TS: TList<TThreadTest>;
  T: TThreadTest;
  I: Integer;
begin
{$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
{$ENDIF}
  RWS := TLightweightMREWSynchronizer.Create(lmpBoth);
  TS := TList<TThreadTest>.Create;
  Resource := TDictionary<string, string>.Create;
  try
    for I := 1 to THREAD_COUNT do
    begin
      T := TThreadTest.Create;
      if I = 3 then
        T.FChanged := True;
      TS.Add(T);
      T.Start;
    end;
    for T in TS do
    begin
      T.WaitFor;
      T.Free;
    end;
    WriteLn;
{$IFDEF MSWINDOWS}
    Writeln('Press any key to exit ...');
    Readln;
{$ENDIF}
  finally
    Resource.Free;
    TS.Free;
    RWS := nil;
  end;
end.