unit ufrmMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics,
  Controls, Forms, Dialogs, StdCtrls, diocp_tcp_client,
  utils_safeLogger, ComCtrls, diocp_sockets, ExtCtrls, utils_async,
  utils_BufferPool, utils_fileWriter;

type
  TEchoContext = class(TIocpRemoteContext)
    FObjectID:Integer;
    FMaxTick:Cardinal;
    FStartTime:TDateTime;
    FLastTick:Cardinal;
    FLastSendTick:Cardinal;
    FFileWritter: TSingleFileWriter;
  public
    procedure OnDisconnected; override;
  public
    destructor Destroy; override;
    procedure WriteRecvData(pvBuf:Pointer; pvLength:Integer);
  end;

  TfrmMain = class(TForm)
    PageControl1: TPageControl;
    TabSheet1: TTabSheet;
    tsMonitor: TTabSheet;
    mmoRecvMessage: TMemo;
    tsOperator: TTabSheet;
    pnlTop: TPanel;
    btnConnect: TButton;
    edtHost: TEdit;
    edtPort: TEdit;
    btnClose: TButton;
    btnCreate: TButton;
    edtCount: TEdit;
    chkRecvEcho: TCheckBox;
    chkRecvOnLog: TCheckBox;
    btnClear: TButton;
    chkHex: TCheckBox;
    chkCheckHeart: TCheckBox;
    btnSaveHistory: TButton;
    tmrCheckHeart: TTimer;
    chkLogRecvTime: TCheckBox;
    pnlOpera_Top: TPanel;
    btnSendObject: TButton;
    btnFill1K: TButton;
    pnlOpera_Send: TPanel;
    mmoData: TMemo;
    tsEvent: TTabSheet;
    mmoIntervalData: TMemo;
    pnlIntervalTop: TPanel;
    edtInterval: TEdit;
    btnSetInterval: TButton;
    grpOnConnected: TGroupBox;
    grpInterval: TGroupBox;
    chkSendData: TCheckBox;
    mmoOnConnected: TMemo;
    chkIntervalSendData: TCheckBox;
    chkSaveData: TCheckBox;
    procedure btnClearClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure btnConnectClick(Sender: TObject);
    procedure btnCreateClick(Sender: TObject);
    procedure btnFill1KClick(Sender: TObject);
    procedure btnSaveHistoryClick(Sender: TObject);
    procedure btnSendObjectClick(Sender: TObject);
    procedure btnSetIntervalClick(Sender: TObject);
    procedure chkCheckHeartClick(Sender: TObject);
    procedure chkHexClick(Sender: TObject);
    procedure chkIntervalSendDataClick(Sender: TObject);
    procedure chkLogRecvTimeClick(Sender: TObject);
    procedure chkRecvEchoClick(Sender: TObject);
    procedure chkRecvOnLogClick(Sender: TObject);
    procedure chkSaveDataClick(Sender: TObject);
    procedure chkSendDataClick(Sender: TObject);
    procedure tmrCheckHeartTimer(Sender: TObject);
  private
    FSpinLock:Integer;
    
    FSendDataOnConnected:Boolean;
    FSendDataOnRecv:Boolean;
    FLogRecvInfo:Boolean;
    FRecvOnLog:Boolean;
    FRecvOnSaveToFile:Boolean;
    FConvertHex:Boolean;

    FASyncInvoker:TASyncInvoker;
    FSendInterval: Cardinal;
    FSendDataOnInterval:Boolean;

    FFileLogger:TSafeLogger;
    FIocpClientSocket: TDiocpTcpClient;

    procedure DoSend(pvConentxt: TDiocpCustomContext; s: AnsiString);

    procedure OnContextConnected(pvContext: TDiocpCustomContext);

    procedure OnRecvdBuffer(pvContext: TDiocpCustomContext; buf: Pointer; len:
        cardinal; pvErrorCode: Integer);

    procedure OnASyncWork(pvASyncWorker:TASyncWorker);

    procedure WriteHistory;

    procedure ReadHistory;

  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  frmMain: TfrmMain;

implementation

uses
  uFMMonitor, utils_dvalue, utils_DValue_JSON, utils_byteTools;
{$R *.dfm}

{ TfrmMain }

var
  __SN:Integer;

constructor TfrmMain.Create(AOwner: TComponent);
begin
  inherited;
  FASyncInvoker := TASyncInvoker.Create;
  FASyncInvoker.Start(OnASyncWork);
  FFileLogger := TSafeLogger.Create;
  FFileLogger.setAppender(TLogFileAppender.Create(False), true);
  FSendDataOnRecv := chkRecvEcho.Checked;
  FRecvOnLog := chkRecvOnLog.Checked;
  FRecvOnSaveToFile := chkSaveData.Checked;
  FConvertHex := chkHex.Checked;
  sfLogger.setAppender(TStringsAppender.Create(mmoRecvMessage.Lines));
  sfLogger.AppendInMainThread := true;

  FIocpClientSocket := TDiocpTcpClient.Create(Self);
  FIocpClientSocket.createDataMonitor;
  FIocpClientSocket.OnContextConnected := OnContextConnected;
  FIocpClientSocket.OnReceivedBuffer := OnRecvdBuffer;
  FIocpClientSocket.RegisterContextClass(TEchoContext);
  TFMMonitor.createAsChild(tsMonitor, FIocpClientSocket);

  ReadHistory;

end;

destructor TfrmMain.Destroy;
begin
  FASyncInvoker.Terminate;
  FASyncInvoker.WaitForStop;
  FASyncInvoker.Free;
  FIocpClientSocket.Close;
  FIocpClientSocket.Free;
  FFileLogger.Free;
  inherited Destroy;
end;

procedure TfrmMain.btnClearClick(Sender: TObject);
begin
  mmoRecvMessage.Clear;
end;

procedure TfrmMain.btnCloseClick(Sender: TObject);
var
  i: Integer;
begin
  SpinLock(FSpinLock);
  try
    for i := 0 to FIocpClientSocket.Count-1 do
    begin
      FIocpClientSocket.Items[i].AutoReConnect := false;
      FIocpClientSocket.Items[i].Close;
    end;
    FIocpClientSocket.WaitForContext(30000);
    FIocpClientSocket.ClearContexts;
  finally
    SpinUnLock(FSpinLock);
  end;

  Self.Caption := 'diocpv5 echo client[stop]';
end;

procedure TfrmMain.btnConnectClick(Sender: TObject);
var
  lvClient:TIocpRemoteContext;
begin
  SpinLock(FSpinLock);
  try
    FIocpClientSocket.open;

    lvClient := FIocpClientSocket.Add;
    lvClient.Host := edtHost.Text;
    lvClient.Port := StrToInt(edtPort.Text);
    lvClient.AutoReConnect := true;
    lvClient.ConnectASync;
  finally
    SpinUnLock(FSpinLock);
  end;


  mmoRecvMessage.Clear;

  mmoRecvMessage.Lines.Add('start to recv...');
end;

procedure TfrmMain.btnCreateClick(Sender: TObject);
var
  lvClient:TIocpRemoteContext;
  i:Integer;
begin
  chkRecvOnLog.Checked := StrToInt(edtCount.Text) < 10;
  SpinLock(FSpinLock);
  try
    FIocpClientSocket.open;

    for i := 1 to StrToInt(edtCount.Text) do
    begin
      lvClient := FIocpClientSocket.Add;
      lvClient.Host := edtHost.Text;
      lvClient.Port := StrToInt(edtPort.Text);
      lvClient.AutoReConnect := true;
      lvClient.connectASync;
    end;

    Self.Caption := Format('diocpv5 echo client[running:%d]', [StrToInt(edtCount.Text)]);
  finally
    SpinUnLock(FSpinLock);
  end;
end;

procedure TfrmMain.btnFill1KClick(Sender: TObject);
var
  s:AnsiString;
begin
  SetLength(s, 1024);
  FillChar(PAnsiChar(s)^, 1024, 'a');
  mmoData.Lines.Text :=  s;
end;

procedure TfrmMain.btnSaveHistoryClick(Sender: TObject);
begin
  WriteHistory;
end;

procedure TfrmMain.btnSendObjectClick(Sender: TObject);
var
  i, l: Integer;
  lvBytes:TBytes;
  s:AnsiString;
begin
  s := mmoData.Lines.Text;
  for i := 0 to FIocpClientSocket.Count - 1 do
  begin
    DoSend(FIocpClientSocket.Items[i], s);
  end;
end;

procedure TfrmMain.btnSetIntervalClick(Sender: TObject);
var
  lvInterval:Integer;
begin
  lvInterval := StrToIntDef(edtInterval.Text, 0) * 1000;
  if lvInterval <=0 then raise Exception.Create('必须设定大于0的值');
  FSendInterval := lvInterval;
end;

procedure TfrmMain.chkCheckHeartClick(Sender: TObject);
begin
  ;
end;

procedure TfrmMain.chkHexClick(Sender: TObject);
var
  s:AnsiString;
  l:Integer;
  lvBytes:TBytes;
begin
  FConvertHex := chkHex.Checked;
  if chkHex.Tag = 1 then Exit;

  s := mmoData.Lines.Text;
  if FConvertHex then
  begin
    mmoData.Lines.Text := TByteTools.varToHexString(PAnsiChar(s)^, Length(s));
  end else
  begin
    s := StringReplace(s, ' ', '', [rfReplaceAll]);
    s := StringReplace(s, #10, '', [rfReplaceAll]);
    s := StringReplace(s, #13, '', [rfReplaceAll]);
    l := Length(s);
    SetLength(lvBytes, l);
    FillChar(lvBytes[0], l, 0);
    l := TByteTools.HexToBin(s, @lvBytes[0]);
    mmoData.Lines.Text := StrPas(PAnsiChar(@lvBytes[0]));
  end;

  s := mmoOnConnected.Lines.Text;
  if FConvertHex then
  begin
    mmoOnConnected.Lines.Text := TByteTools.varToHexString(PAnsiChar(s)^, Length(s));
  end else
  begin
    s := StringReplace(s, ' ', '', [rfReplaceAll]);
    s := StringReplace(s, #10, '', [rfReplaceAll]);
    s := StringReplace(s, #13, '', [rfReplaceAll]);
    l := Length(s);
    SetLength(lvBytes, l);
    FillChar(lvBytes[0], l, 0);
    l := TByteTools.HexToBin(s, @lvBytes[0]);
    mmoOnConnected.Lines.Text := StrPas(PAnsiChar(@lvBytes[0]));
  end;

  s := mmoIntervalData.Lines.Text;
  if FConvertHex then
  begin
    mmoIntervalData.Lines.Text := TByteTools.varToHexString(PAnsiChar(s)^, Length(s));
  end else
  begin
    s := StringReplace(s, ' ', '', [rfReplaceAll]);
    s := StringReplace(s, #10, '', [rfReplaceAll]);
    s := StringReplace(s, #13, '', [rfReplaceAll]);
    l := Length(s);
    SetLength(lvBytes, l);
    FillChar(lvBytes[0], l, 0);
    l := TByteTools.HexToBin(s, @lvBytes[0]);
    mmoIntervalData.Lines.Text := StrPas(PAnsiChar(@lvBytes[0]));
  end;
end;

procedure TfrmMain.chkIntervalSendDataClick(Sender: TObject);
begin
  FSendDataOnInterval := chkIntervalSendData.Checked;
end;

procedure TfrmMain.chkLogRecvTimeClick(Sender: TObject);
begin
  FLogRecvInfo := chkLogRecvTime.Checked;
end;

procedure TfrmMain.chkRecvEchoClick(Sender: TObject);
begin
  FSendDataOnRecv := chkRecvEcho.Checked;
end;

procedure TfrmMain.chkRecvOnLogClick(Sender: TObject);
begin
  FRecvOnLog := chkRecvOnLog.Checked;
end;

procedure TfrmMain.chkSaveDataClick(Sender: TObject);
begin
  FRecvOnSaveToFile := chkSaveData.Checked;
end;

procedure TfrmMain.chkSendDataClick(Sender: TObject);
begin
  FSendDataOnConnected := chkSendData.Checked;
end;

procedure TfrmMain.DoSend(pvConentxt: TDiocpCustomContext; s: AnsiString);
var
  i, l: Integer;
  lvBytes:TBytes;
begin
  //s := mmoData.Lines.Text;
  if FConvertHex then
  begin
    s := StringReplace(s, ' ', '', [rfReplaceAll]);
    s := StringReplace(s, #10, '', [rfReplaceAll]);
    s := StringReplace(s, #13, '', [rfReplaceAll]);
    l := Length(s);
    SetLength(lvBytes, l);
    FillChar(lvBytes[0], l, 0);
    l := TByteTools.HexToBin(s, @lvBytes[0]);
  end;

  if FConvertHex then
  begin
    pvConentxt.PostWSASendRequest(@lvBytes[0], l);
  end else
  begin
    pvConentxt.PostWSASendRequest(PAnsiChar(s), Length(s));
  end;

end;

procedure TfrmMain.OnASyncWork(pvASyncWorker:TASyncWorker);
var
  i, l: Integer;
  lvBytes:TBytes;
  s:AnsiString;
  lvEchoClient:TEchoContext;
begin
  while not FASyncInvoker.Terminated do
  begin
    if (FSendInterval > 0) and FSendDataOnInterval then
    begin
      s := mmoIntervalData.Lines.Text;
      if s <> '' then
      begin
        SpinLock(FSpinLock);
        try
          for i := 0 to FIocpClientSocket.Count - 1 do
          begin
            if FASyncInvoker.Terminated then Exit;
            
            lvEchoClient := TEchoContext(FIocpClientSocket.Items[i]);
            if lvEchoClient.Active then
            begin
              if tick_diff(lvEchoClient.FLastSendTick, GetTickCount) > FSendInterval  then
              begin
                DoSend(lvEchoClient, s);
                lvEchoClient.FLastSendTick := GetTickCount;
              end;
            end;
          end;
        finally
          SpinUnLock(FSpinLock);
        end;
      end;
    end;

    Sleep(1000);
  end;
end;

procedure TfrmMain.OnContextConnected(pvContext: TDiocpCustomContext);
var
  s:AnsiString;
begin
 

  TEchoContext(pvContext).FStartTime := Now();
  TEchoContext(pvContext).FLastTick := GetTickCount;
  TEchoContext(pvContext).FMaxTick := 0;

  s := mmoOnConnected.Lines.Text;
  if FSendDataOnConnected then
  begin
    DoSend(pvContext, s);
  end;

end;

procedure TfrmMain.OnRecvdBuffer(pvContext: TDiocpCustomContext; buf: Pointer;
    len: cardinal; pvErrorCode: Integer);
var
  lvStr:AnsiString;
  lvContext:TEchoContext;
  lvFmt:String;
  lvTick:Cardinal;
begin
  lvContext := TEchoContext(pvContext);
  if FLogRecvInfo then
  begin
    lvTick := GetTickCount;
    lvFmt := Format('[%d], t: %s, data:%d, delay:%d',
      [lvContext.SocketHandle,
       FormatDateTime('yyyy-MM-dd hh:nn:ss', Now()),
       len,
       lvTick - TEchoContext(pvContext).FLastTick
      ]);


    FFileLogger.logMessage(lvFmt, '连接数据信息');
    TEchoContext(pvContext).FLastTick := lvTick;
    TEchoContext(pvContext).FMaxTick := 0;
  end;
  if len = 0 then
  begin
    sfLogger.logMessage('recv err zero');
  end;
  if pvErrorCode = 0 then
  begin
    if FSendDataOnRecv then
    begin
      Sleep(0);
      pvContext.PostWSASendRequest(buf, len);
    end;
    if FRecvOnLog then
    begin
      lvStr := TByteTools.BufShowAsString(buf, len);
      sfLogger.logMessage(lvStr);
    end;
    if FRecvOnSaveToFile then
    begin
      TEchoContext(pvContext).WriteRecvData(buf, len);
    end;
  end else
  begin
    sfLogger.logMessage('recv err:%d', [pvErrorCode]);
  end;
end;

procedure TfrmMain.ReadHistory;
var
  lvDValue:TDValue;
begin
  lvDValue := TDValue.Create();
  JSONParseFromUtf8NoBOMFile(ChangeFileExt(ParamStr(0), '.history.json'), lvDVAlue);
  edtHost.Text := lvDValue.ForceByName('host').AsString;
  edtPort.Text := lvDValue.ForceByName('port').AsString;
  mmoData.Lines.Text := lvDValue.ForceByName('sendText').AsString;
  chkRecvEcho.Checked := lvDValue.ForceByName('chk_recvecho').AsBoolean;
  chkSaveData.Checked := lvDValue.ForceByName('chk_saveonrecv').AsBoolean;
  chkRecvOnLog.Checked := lvDValue.ForceByName('chk_recvonlog').AsBoolean;
  chkSendData.Checked := lvDValue.ForceByName('chk_send_onconnected').AsBoolean;


  chkHex.Tag := 1;
  chkHex.Checked := lvDValue.ForceByName('chk_send_hex').AsBoolean;
  chkHex.Tag := 0;

  chkCheckHeart.Checked := lvDValue.ForceByName('chk_checkheart').AsBoolean;
  chkLogRecvTime.Checked := lvDValue.ForceByName('chk_LogRecvInfo').AsBoolean;

  chkIntervalSendData.Checked := lvDValue.ForceByName('chk_send_oninterval').AsBoolean;
  edtInterval.Text := IntToStr(lvDValue.ForceByName('send_interval').AsInteger);
  mmoIntervalData.Lines.Text := lvDValue.ForceByName('send_interval_data').AsString;
  mmoOnConnected.Lines.Text := lvDValue.ForceByName('send_onconnected_data').AsString;
  edtCount.Text := lvDValue.ForceByName('client_num').AsString;
  
  lvDValue.Free;

  FSendDataOnConnected := chkSendData.Checked;
  FRecvOnLog := chkRecvOnLog.Checked;
  FRecvOnSaveToFile := chkSaveData.Checked;
  FSendDataOnRecv := chkRecvEcho.Checked;
  FConvertHex := chkHex.Checked;
  FLogRecvInfo := chkLogRecvTime.Checked;
  FSendInterval := StrToIntDef(edtInterval.Text, 0) * 1000;
end;

procedure TfrmMain.tmrCheckHeartTimer(Sender: TObject);
begin
  if chkCheckHeart.Checked then
  begin
    SpinLock(FSpinLock);
    try
      self.FIocpClientSocket.KickOut(30000);
    finally
      SpinUnLock(FSpinLock);
    end;

  end;
end;

procedure TfrmMain.WriteHistory;
var
  lvDValue:TDValue;
begin
  lvDValue := TDValue.Create();
  lvDValue.ForceByName('host').AsString := edtHost.Text;
  lvDValue.ForceByName('port').AsString := edtPort.Text;
  lvDValue.ForceByName('client_num').AsString := edtCount.Text;
  lvDValue.ForceByName('sendText').AsString := mmoData.Lines.Text;
  lvDValue.ForceByName('chk_recvecho').AsBoolean := chkRecvEcho.Checked;
  lvDValue.ForceByName('chk_saveonrecv').AsBoolean := chkSaveData.Checked;
  lvDValue.ForceByName('chk_recvonlog').AsBoolean := chkRecvOnLog.Checked;
  lvDValue.ForceByName('chk_send_onconnected').AsBoolean := chkSendData.Checked;
  lvDValue.ForceByName('chk_send_hex').AsBoolean := chkHex.Checked;
  lvDValue.ForceByName('chk_checkheart').AsBoolean := chkCheckHeart.Checked;
  lvDValue.ForceByName('chk_LogRecvInfo').AsBoolean := chkLogRecvTime.Checked;
  lvDValue.ForceByName('chk_send_oninterval').AsBoolean := chkIntervalSendData.Checked;
  lvDValue.ForceByName('send_interval').AsInteger := StrToIntDef(edtInterval.Text, 0);
  lvDValue.ForceByName('send_interval_data').AsString := mmoIntervalData.Lines.Text;
  lvDValue.ForceByName('send_onconnected_data').AsString := mmoOnConnected.Lines.Text;
  JSONWriteToUtf8NoBOMFile(ChangeFileExt(ParamStr(0), '.history.json'), lvDVAlue);
  lvDValue.Free;
end;

destructor TEchoContext.Destroy;
begin
  if FFileWritter <> nil then
  begin
    FreeAndNil(FFileWritter);
  end;
  inherited Destroy;
end;

procedure TEchoContext.OnDisconnected;
begin
  if FFileWritter <> nil then
  begin
    FFileWritter.Flush;
  end;
  inherited;
end;

procedure TEchoContext.WriteRecvData(pvBuf:Pointer; pvLength:Integer);
begin
  if FObjectID = 0 then
  begin
    FObjectID := InterlockedIncrement(__SN);
  end;
  if FFileWritter = nil then
  begin
    FFileWritter := TSingleFileWriter.Create;
    FFileWritter.FilePreFix := Format('recv_%d_', [FObjectID]);
  end;
  FFileWritter.WriteBuffer(pvBuf, pvLength);
end;

end.
