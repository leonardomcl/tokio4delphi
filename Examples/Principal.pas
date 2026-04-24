unit Principal;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.Classes,
  System.Threading,
  System.JSON,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.Math,
  System.Zip,
  System.IOUtils,
  AnsiStrings,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Menus,
  Tokio.Async.Bridge,
  System.Generics.Collections;

type
  // Registro para os dados do Dashboard
  PDashData = ^TDashData;

  TDashData = record
    Valor: Currency;
    Texto: string;
  end;

type
  TFPrincipal = class(TForm)
    MLog: TMemo;
    ProgressBar1: TProgressBar;
    Label1: TLabel;
    PopupMenu1: TPopupMenu;
    CLEAR1: TMenuItem;
    PageControl1: TPageControl;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    FlowPanel1: TFlowPanel;
    BtnAwait: TButton;
    BtnAsync: TButton;
    BtnRetryAsync: TButton;
    BtnAll: TButton;
    BtnAllAsync: TButton;
    BtnRace: TButton;
    BtnRaceAsync: TButton;
    BtnDelayAsync: TButton;
    BtnWithTimeout: TButton;
    BtnWhenAllComplete: TButton;
    BtnParallel: TButton;
    FlowPanel2: TFlowPanel;
    btnFetchAll: TButton;
    BtnRunWithProgress: TButton;
    BtnFindId: TButton;
    BtnFindRandomId: TButton;
    BtnSeries: TButton;
    BtnSeriesAsync: TButton;
    btnProcess: TButton;
    BtnLoadDashboard: TButton;
    GroupBox1: TGroupBox;
    BtnStrVarTasks: TButton;
    BtnStopVrsTasks: TButton;
    EdtId: TEdit;
    Button3: TButton;
    Button4: TButton;
    procedure FormCreate(Sender: TObject);
    procedure BtnAwaitClick(Sender: TObject);
    procedure BtnAllClick(Sender: TObject);
    procedure BtnRaceClick(Sender: TObject);
    procedure BtnAllAsyncClick(Sender: TObject);
    procedure BtnRaceAsyncClick(Sender: TObject);
    procedure BtnAsyncClick(Sender: TObject);
    procedure BtnRetryAsyncClick(Sender: TObject);
    procedure BtnDelayAsyncClick(Sender: TObject);
    procedure BtnWithTimeoutClick(Sender: TObject);
    procedure BtnWhenAllCompleteClick(Sender: TObject);
    procedure BtnParallelClick(Sender: TObject);
    procedure BtnRunWithProgressClick(Sender: TObject);
    procedure btnFetchAllClick(Sender: TObject);
    procedure CLEAR1Click(Sender: TObject);
    procedure BtnFindIdClick(Sender: TObject);
    procedure BtnFindRandomIdClick(Sender: TObject);
    procedure BtnSeriesClick(Sender: TObject);
    procedure BtnSeriesAsyncClick(Sender: TObject);
    procedure btnProcessClick(Sender: TObject);
    procedure BtnLoadDashboardClick(Sender: TObject);
    procedure BtnStrVarTasksClick(Sender: TObject);
    procedure BtnStopVrsTasksClick(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FLista: TArray<Integer>;
    FGlobalToken: ICancelToken;
    FTarefasAtivas: TDictionary<Integer, ICancelToken>;

    function GetMaxListSize: Integer;

    /// <summary>
    /// Loga uma mensagem com timestamp no topo do Memo.
    /// Thread-safe: detecta se já está na main thread antes de enfileirar.
    /// </summary>
    procedure MessageLog(const Msg: string);

    /// <summary>
    /// Atualiza a ProgressBar e o hint. Sempre enfileira na main thread.
    /// </summary>
    procedure UpdateProgress(Percent: Double; const Msg: string);

    /// <summary>
    /// Exibe resultados de múltiplas tasks e libera todos os DataPtr.
    /// </summary>
    procedure ShowResults(const Results: TArray<TTaskResult>);

    /// <summary>
    /// Exibe o resultado de uma única task e libera seu DataPtr.
    /// </summary>
    procedure ShowResult(const Resultado: TTaskResult);

    /// <summary>
    /// Fábrica de TAsyncAction para busca paralela em blocos da FLista.
    /// Captura BlocoIdx, StartIdx, EndIdx e TargetID por valor.
    /// </summary>
    function MakeBlocoAction(BlocoIdx, StartIdx, EndIdx, TargetID: Integer)
      : TAsyncAction;

    /// <summary>
    /// Callback final do btnProcess: exibe resultados e libera DataPtrs.
    /// </summary>
    procedure OnProcessFinished(Results: TArray<TTaskResult>);

    /// <summary>
    /// Lógica compartilhada de busca paralela em FLista.
    /// Usado por BtnFindIdClick e BtnFindRandomIdClick.
    /// </summary>
    procedure ExecuteParallelSearch(TargetID: Integer; BtnToRestore: TButton);
  public
    FDownloadFolder: string;
    FZipFileName: string;
    FExtractFolder: string;

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  FPrincipal: TFPrincipal;

implementation

{$R *.dfm}

type
  TDownloadHandler = class
  private
    FLastUpdateTick: UInt64;
  public
    CancelToken: ICancelToken;
    FormRef: TFPrincipal;
    procedure OnReceiveData(const Sender: TObject;
      ContentLength, ReadCount: Int64; var Abort: Boolean);
  end;

procedure TDownloadHandler.OnReceiveData(const Sender: TObject;
  ContentLength, ReadCount: Int64; var Abort: Boolean);
var
  Percent: Double;
  Msg: string;
  CurrentTick: UInt64;
begin
  if ContentLength > 0 then
  begin
    Percent := (ReadCount / ContentLength) * 100;
    Msg := Format('Download: %.1f%% concluído', [Percent]);
  end
  else
  begin
    Percent := 0;
    Msg := Format('Baixando: %.2f MB recebidos...',
      [ReadCount / (1024 * 1024)]);
  end;

  CurrentTick := GetTickCount64;
  // Throttling de 50 ms para não saturar a fila de mensagens da UI
  if (CurrentTick - FLastUpdateTick >= 50) or (ReadCount = ContentLength) then
  begin
    FLastUpdateTick := CurrentTick;
    TThread.Queue(nil,
      procedure
      begin
        if Assigned(FormRef) then
          FormRef.UpdateProgress(Percent, Msg);
      end);
  end;

  // Aborta o download se o token foi cancelado
  if Assigned(CancelToken) and CancelToken.IsCancelled then
    Abort := True;
end;

procedure SlowTask(Res: PTaskResult);
begin
  Res^.InputID := 2;
  Sleep(2000);
  Res^.Success := True;
end;

procedure FastTask(Res: PTaskResult);
begin
  Res^.InputID := 1;
  Sleep(300);
  Res^.Success := True;
end;

procedure FailedTask(Res: PTaskResult);
begin
  Res^.InputID := 3;
  Sleep(500);
  raise Exception.Create('Erro proposital na tarefa executada');
end;

/// <summary>
/// Fábrica de closures para All/AllAsync com InputID e tempo configuráveis.
/// </summary>
function CriarTarefa(Valor, Tempo: Integer): TAsyncAction;
begin
  Result := procedure(Res: PTaskResult)
    begin
      Sleep(Tempo);
      Res^.Success := True;
      Res^.InputID := Valor;
    end;
end;

constructor TFPrincipal.Create(AOwner: TComponent);
var
  I, ListSize: Integer;
begin
  inherited;
  FDownloadFolder := ExtractFilePath(ParamStr(0)) + 'downloads\';
  FExtractFolder := ExtractFilePath(ParamStr(0)) + 'extracted\';
  FZipFileName := FDownloadFolder + 'exemplo.zip';
  ForceDirectories(FDownloadFolder);
  ForceDirectories(FExtractFolder);

  ListSize := GetMaxListSize;
  SetLength(FLista, ListSize);
  for I := 0 to High(FLista) do
    FLista[I] := I + 1;

  MessageLog(Format('Lista gerada com %d elementos (%.2f MB)',
    [ListSize, ListSize * SizeOf(Integer) / (1024 * 1024)]));
end;

destructor TFPrincipal.Destroy;
begin
  inherited;
end;

procedure TFPrincipal.FormCreate(Sender: TObject);
begin
  FTarefasAtivas := TDictionary<Integer, ICancelToken>.Create;
  ProgressBar1.Position := 0;
  Label1.Caption := '';
end;

procedure TFPrincipal.FormDestroy(Sender: TObject);
begin
  // Primeiro cancelamos todas as tarefas pendentes (opcional, mas recomendado)
  if Assigned(FTarefasAtivas) then
  begin
    for var LToken in FTarefasAtivas.Values do
      LToken.Cancel;

    // Depois liberamos o dicionário da memória
    FTarefasAtivas.Free;
  end;
end;

function TFPrincipal.GetMaxListSize: Integer;
var
  MemStatus: TMemoryStatusEx;
begin
  MemStatus.dwLength := SizeOf(MemStatus);
  GlobalMemoryStatusEx(MemStatus);

  // 25% da memória física disponível em número de Integers (4 bytes cada)
  Result := Integer(MemStatus.ullAvailPhys div 4 div 4);

  // Limites razoáveis: mínimo 100 000, máximo 30 000 000 (120 MB)
  Result := Max(100000, Min(Result, 30000000));
end;

procedure TFPrincipal.MessageLog(const Msg: string);
var
  Line: string;
begin

  Line := FormatDateTime('[hh:nn:ss] ', Now) + Msg;

  if TThread.CurrentThread.ThreadID = MainThreadID then
    MLog.Lines.Insert(0, Line)
  else
    TThread.Queue(nil,
      procedure
      begin
        MLog.Lines.Insert(0, Line);
      end);
end;

procedure TFPrincipal.UpdateProgress(Percent: Double; const Msg: string);
begin
  // Sempre enfileira — pode ser chamado de qualquer thread
  TThread.Queue(nil,
    procedure
    begin
      ProgressBar1.Hint := Msg;
      ProgressBar1.ShowHint := True;

      if Percent > 0 then
      begin
        ProgressBar1.Style := pbstNormal;
        ProgressBar1.Position := Round(Percent);
      end
      else
      begin
        ProgressBar1.Style := pbstMarquee;
        ProgressBar1.MarqueeInterval := 30;
      end;
    end);
end;

procedure TFPrincipal.ShowResult(const Resultado: TTaskResult);
begin

  if Resultado.Success then
  begin
    if Resultado.DataPtr <> nil then
      MessageLog(Format('ID %d encontrado! %s', [Resultado.InputID,
        string(PAnsiChar(Resultado.DataPtr))]))
    else
      MessageLog(Format('ID %d encontrado!', [Resultado.InputID]));

    if Resultado.DataPtr <> nil then
      AnsiStrings.StrDispose(PAnsiChar(Resultado.DataPtr));
  end
  else
    MessageLog('Erro: ' + string(Resultado.ErrorMessage));

  UpdateProgress(0, 'Pronto.');
end;

procedure TFPrincipal.ShowResults(const Results: TArray<TTaskResult>);
var
  R: TTaskResult;
begin
  for R in Results do
  begin
    if R.Success then
    begin
      if R.DataPtr <> nil then
        MessageLog(Format('API %d: Sucesso! Dados: %s',
          [R.InputID, string(PAnsiChar(R.DataPtr))]))
      else
        MessageLog(Format('API %d: Sucesso! (sem dados)', [R.InputID]));
    end
    else
      MessageLog(Format('API %d: Falha - %s',
        [R.InputID, string(R.ErrorMessage)]));

    // Libera DataPtr independentemente do sucesso — evita leak
    if R.DataPtr <> nil then
      AnsiStrings.StrDispose(PAnsiChar(R.DataPtr));
  end;

  MessageLog('Todas as consultas concluídas.');
  btnFetchAll.Enabled := True;
end;

procedure TFPrincipal.OnProcessFinished(Results: TArray<TTaskResult>);
var
  R: TTaskResult;
begin
  for R in Results do
  begin
    // FIX: verifica DataPtr antes de logar — evita exibir lixo em falhas
    if R.Success then
    begin
      if R.DataPtr <> nil then
        MessageLog(Format(' Etapa %d: %s',
          [R.InputID, string(PAnsiChar(R.DataPtr))]))
      else
        MessageLog(Format(' Etapa %d: concluída', [R.InputID]));
    end
    else
      MessageLog(Format(' Etapa %d falhou: %s',
        [R.InputID, string(R.ErrorMessage)]));

    // Libera sempre, independente de sucesso ou falha
    if R.DataPtr <> nil then
      AnsiStrings.StrDispose(PAnsiChar(R.DataPtr));
  end;

  UpdateProgress(100, 'Processo concluído.');
  btnProcess.Enabled := True;
end;

function TFPrincipal.MakeBlocoAction(BlocoIdx, StartIdx, EndIdx,
  TargetID: Integer): TAsyncAction;
begin
  // Todos os parâmetros são capturados por valor (passados como argumentos),
  // garantindo isolamento correto entre closures de iterações distintas.
  Result := procedure(Res: PTaskResult)
    var
      J: Integer;
    begin
      for J := StartIdx to EndIdx do
      begin
        if FLista[J] = TargetID then
        begin
          Res^.Success := True;
          Res^.InputID := TargetID;
          Res^.DataPtr := AnsiStrings.StrNew
            (PAnsiChar(AnsiString(Format('Bloco %d (índices %d..%d)',
            [BlocoIdx, StartIdx, EndIdx]))));
          Exit;
        end;
      end;

      Res^.Success := False;
      Res^.ErrorMessage := UTF8String(Format('ID não encontrado no bloco %d',
        [BlocoIdx]));
    end;
end;

/// <summary>
/// Lógica compartilhada entre BtnFindIdClick e BtnFindRandomIdClick.
/// Cria chunks, executa AllAsync e processa todos os resultados com
/// liberação correta de DataPtr em múltiplos blocos bem-sucedidos.
/// </summary>
procedure TFPrincipal.ExecuteParallelSearch(TargetID: Integer;
BtnToRestore: TButton);
var
  Chunks: TArray<TAsyncAction>;
  I, StartIdx, EndIdx: Integer;
  ChunkSize, Total, ChunkCount: Integer;
begin
  Total := Length(FLista);
  ChunkSize := Max(500, Total div Integer(async_worker_count * 4));
  ChunkCount := (Total + ChunkSize - 1) div ChunkSize;

  MessageLog(Format('Procurando ID: %d | Chunks: %d | Chunk size: %d',
    [TargetID, ChunkCount, ChunkSize]));

  SetLength(Chunks, ChunkCount);
  for I := 0 to ChunkCount - 1 do
  begin
    StartIdx := I * ChunkSize;
    EndIdx := Min(StartIdx + ChunkSize - 1, Total - 1);
    Chunks[I] := MakeBlocoAction(I, StartIdx, EndIdx, TargetID);
  end;

  TTokio.AllAsync(Chunks,
    procedure(Results: TArray<TTaskResult>)
    var
      R: TTaskResult;
      Vencedora: TTaskResult;
      Found: Boolean;
    begin
      Found := False;

      for R in Results do
      begin
        if R.Success then
        begin
          if not Found then
          begin
            // Guarda o primeiro bloco vencedor para exibir
            Vencedora := R;
            Found := True;
            // DataPtr do vencedor será liberado após o log abaixo
          end
          else
          begin
            // Blocos adicionais que também encontraram o ID
            // devem ter seus DataPtrs liberados — caso contrário, leak garantido.
            if R.DataPtr <> nil then
              AnsiStrings.StrDispose(PAnsiChar(R.DataPtr));
          end;
        end;
      end;

      if Found then
      begin
        MessageLog(Format(' ID %d encontrado! %s', [Vencedora.InputID,
          string(PAnsiChar(Vencedora.DataPtr))]));
        if Vencedora.DataPtr <> nil then
          AnsiStrings.StrDispose(PAnsiChar(Vencedora.DataPtr));
      end
      else
        MessageLog('Erro: ID não encontrado em nenhum bloco.');

      UpdateProgress(100, 'Busca concluída.');

      if Assigned(BtnToRestore) then
        BtnToRestore.Enabled := True;
    end);
end;

procedure TFPrincipal.BtnAwaitClick(Sender: TObject);
begin
  // TAsync.Await bloqueia a thread chamadora — NUNCA chamar da main thread.
  // Substituído por RunAsync (não bloqueante).
  BtnAwait.Enabled := False;
  TTokio.RunAsync(
    procedure(Res: PTaskResult)
    begin
      Sleep(3500);
      Res^.Success := True;
    end,
    procedure(R: TTaskResult)
    begin
      if R.Success then
        ShowMessage('OK')
      else
        ShowMessage('Erro: ' + string(R.ErrorMessage));
      BtnAwait.Enabled := True;
    end, 100);
end;

procedure TFPrincipal.BtnAllClick(Sender: TObject);
begin
  // TAsync.All bloqueia a thread chamadora — NUNCA chamar da main thread.
  // Substituído por AllAsync (não bloqueante).
  BtnAll.Enabled := False;
  TTokio.AllAsync([CriarTarefa(1, 1000), CriarTarefa(2, 3500)],
    procedure(Results: TArray<TTaskResult>)
    begin
      ShowMessage('FINISH ALL');
      BtnAll.Enabled := True;
    end);
end;

procedure TFPrincipal.BtnAllAsyncClick(Sender: TObject);
begin
  TTokio.AllAsync([CriarTarefa(1, 1000), CriarTarefa(2, 3500)],
    procedure(Results: TArray<TTaskResult>)
    begin
      ShowMessage('FINISH ALL');
    end);
end;

procedure TFPrincipal.BtnRaceClick(Sender: TObject);
var
  Vencedora: TTaskResult;
begin
  // Race é bloqueante: deve rodar em thread separada para não travar a UI.
  BtnRace.Enabled := False;

  Vencedora := TTokio.Race([FastTask, SlowTask]);
  TThread.Queue(nil,
    procedure
    begin
      if Vencedora.Success then
        ShowMessage('Vencedora ID: ' + Vencedora.InputID.ToString)
      else
        ShowMessage('Erro na corrida: ' + string(Vencedora.ErrorMessage));
      BtnRace.Enabled := True;
    end);
end;

procedure TFPrincipal.BtnRaceAsyncClick(Sender: TObject);
begin
  TTokio.RaceAsync([FastTask, SlowTask],
    procedure(Vencedora: TTaskResult)
    begin
      if Vencedora.Success then
        ShowMessage('Vencedora ID: ' + Vencedora.InputID.ToString)
      else
        ShowMessage('Erro na corrida: ' + string(Vencedora.ErrorMessage));
    end);
end;

procedure TFPrincipal.BtnAsyncClick(Sender: TObject);
begin
  BtnAsync.Enabled := False;
  TTokio.RunAsync(
    procedure(Res: PTaskResult)
    begin
      Sleep(2000);
      Res^.Success := True;
    end,
    procedure(Resultado: TTaskResult)
    begin
      if Resultado.Success then
        ShowMessage('Dado carregado!')
      else
        ShowMessage('Erro: ' + string(Resultado.ErrorMessage));
      BtnAsync.Enabled := True;
    end, 99);
end;

procedure TFPrincipal.BtnRetryAsyncClick(Sender: TObject);
begin
  MessageLog('Iniciando processo de conexão...');
  TTokio.RetryAsync(
    procedure(Res: PTaskResult; Attempt: Integer)
    begin
      // TThread.Synchronize bloqueia a thread worker aguardando a main thread.
      // Se a main thread estiver ocupada (ex: dentro de BtnAwaitClick com Await),
      // isso causa deadlock. TThread.Queue é não-bloqueante e seguro.
      TThread.Queue(nil,
        procedure
        begin
          MessageLog(Format('Tentativa %d de 3...', [Attempt]));
        end);

      Sleep(500);

      if Random(12) > 7 then
        Res^.Success := True
      else
        raise Exception.Create('Falha na comunicação.');
    end, 3,
    procedure(Resultado: TTaskResult)
    begin
      if Resultado.Success then
        MessageLog('Sucesso absoluto!')
      else
        MessageLog('Tentativas esgotadas! Erro final: ' +
          string(Resultado.ErrorMessage));
    end, 1500);
end;

procedure TFPrincipal.BtnWithTimeoutClick(Sender: TObject);
begin
  MessageLog('Iniciando tarefa _WithTimeout_, tempo máximo: 1 seg');
  TTokio.WithTimeout(
    procedure(Res: PTaskResult)
    begin
      Sleep(3000);
      Res^.Success := True;
      Res^.InputID := 123;
    end, 1000,
    procedure(R: TTaskResult)
    begin
      if R.Success then
        MessageLog('Tarefa concluída a tempo! ID: ' + R.InputID.ToString)
      else
        MessageLog('Timeout! Erro: ' + string(R.ErrorMessage));
    end);
end;

procedure TFPrincipal.BtnStrVarTasksClick(Sender: TObject);
begin
  FGlobalToken := TTokio.CreateCancelToken;
  MLog.Clear;
  MessageLog('Disparando 5 tarefas via ParallelFor...');

  TTokio.ParallelFor(1, 5,
    procedure(Idx: Integer; Res: PTaskResult)
    begin
      while not FGlobalToken.IsCancelled do
      begin
        TThread.Queue(nil,
          procedure
          begin
            MessageLog('Tarefa paralela rodando: (id) ' + Idx.ToString);
          end);

        Sleep(1000);

        if FGlobalToken.IsCancelled then
        begin
          Res^.Success := False;
          Exit;
        end;

        // Simulação: termina após um ciclo para o exemplo não ser infinito
        // Break;
      end;

      Res^.Success := True;
    end,
    procedure(Results: TArray<TTaskResult>)
    begin
      MessageLog('O processamento paralelo terminou ou foi cancelado.');
    end);

  MessageLog('Iniciando tarefa de 2 minutos (cancelável)...');

  TTokio.RaceAsync([
  // Task 1: A sua operação real
    procedure(Res: PTaskResult)
    begin
      // Simulação de tarefa longa com verificação de cancelamento
      for var I := 1 to 120 do
      begin
        if FGlobalToken.IsCancelled then
          Exit;
        Sleep(1000);
      end;
      Res^.Success := True;
      Res^.InputID := 123;
    end,

  // Task 2: O Cronômetro de Timeout (também observa o LToken)
  procedure(Res: PTaskResult)var Elapsed: Integer; begin Elapsed := 0;
  while (Elapsed < 120000) and not FGlobalToken.IsCancelled do begin Sleep(100);
  Inc(Elapsed, 100); end;

  if not FGlobalToken.IsCancelled then begin Res^.Success := False;
  Res^.ErrorMessage := 'Timeout atingido!'; end; end],
    procedure(R: TTaskResult)
    begin
      if R.Success then
        MessageLog('Tarefa Timeout Concluída a tempo! ID: ' +
          R.InputID.ToString)
      else
        MessageLog('Tarefa Timeout Interrompida: ' + string(R.ErrorMessage));
    end);
end;

procedure TFPrincipal.BtnStopVrsTasksClick(Sender: TObject);
begin
  if Assigned(FGlobalToken) then
  begin
    FGlobalToken.Cancel;
    MessageLog('Todas as tarefas foram sinalizadas para parar!');
  end;
end;

procedure TFPrincipal.Button3Click(Sender: TObject);
var
  MeuToken: ICancelToken;
  LId: Integer;
begin

  LId := StrToIntDef(EdtId.Text, 0);

  MeuToken := TTokio.CreateCancelToken;

  FTarefasAtivas.AddOrSetValue(LId, MeuToken);
  MessageLog(Format('Adicionando tarefa id: %d!', [LId]));
  TTokio.WithTimeout(
    procedure(Res: PTaskResult)
    begin

      while not(Res^.Success) do
      begin
        if MeuToken.IsCancelled then
        begin
          Exit;
        end;

        // Simulação de processamento

        MessageLog('Processando task id: ' + LId.ToString);
        Sleep(1000);
      end;

      // Se chegou aqui sem ser cancelado, marca como sucesso
      Res^.Success := True;
      Res^.InputID := LId;
    end, 25000, // Timeout de 25 seg
    procedure(R: TTaskResult)
    begin
      // Este bloco executa na Main Thread (UI)
      try
        // Verificamos se a tarefa realmente finalizou com sucesso
        // Se R.Success for False, significa que deu Timeout ou foi Cancelada
        if R.Success then
        begin
          MessageLog(Format('Tarefa %d finalizada com sucesso!', [LId]));
        end
        else
        begin
          MessageLog
            (Format('Tarefa %d finalizada por timeout/cancelada!', [LId]));
        end;
      finally
        // Independente do resultado, removemos do dicionário para não vazar memória
        FTarefasAtivas.Remove(LId);
      end;
    end);
end;

procedure TFPrincipal.Button4Click(Sender: TObject);
var
  LId: Integer;
  LToken: ICancelToken;
begin
  LId := StrToIntDef(EdtId.Text, 0);
  if FTarefasAtivas.TryGetValue(LId, LToken) then
  begin
    MessageLog('Cancelando tarefa id: ' + LId.ToString);
    LToken.Cancel; // Isso fará o R.Success ser False no callback acima
  end;

end;

procedure TFPrincipal.BtnLoadDashboardClick(Sender: TObject);
begin
  MessageLog('Carregando Dashboard com dados...');

  TTokio.WhenAllComplete([
  // Tarefa 1: Saldo
    procedure(Res: PTaskResult)
    var
      Data: PDashData;
    begin
      Sleep(1000);
      New(Data); // Aloca memória no heap
      Data^.Valor := 1500.50;
      Data^.Texto := 'Saldo em Conta';

      Res^.InputID := 100; // ID identificador
      Res^.DataPtr := Data; // Passa o ponteiro para o resultado
      Res^.Success := True;
    end,

  // Tarefa 2: Vendas
    procedure(Res: PTaskResult)
    var
      Data: PDashData;
    begin
      Sleep(1500);
      New(Data);
      Data^.Valor := 42;
      Data^.Texto := 'Vendas Realizadas';

      Res^.InputID := 200;
      Res^.DataPtr := Data;
      Res^.Success := True;
    end,
  procedure(Res: PTaskResult)begin Res^.InputID := 300; Sleep(800);
  raise Exception.Create('Servidor de Alertas Offline'); end],
    procedure(Results: TArray<TTaskResult>)
    var
      R: TTaskResult;
      Data: PDashData;
    begin
      for R in Results do
      begin
        if R.Success and Assigned(R.DataPtr) then
        begin
          Data := PDashData(R.DataPtr); // Cast do ponteiro para o tipo correto

          try
            MessageLog(Format('%s: %f', [Data^.Texto, Data^.Valor]));
          finally
            // IMPORTANTE: Como usamos New(), precisamos liberar a memória
            // para evitar Memory Leak, já que o DataPtr é de propriedade do chamador.
            Dispose(Data);
          end;
        end
        else if not R.Success then
          MessageLog('Erro no ID ' + R.InputID.ToString + ': ' +
            string(R.ErrorMessage));
      end;
    end);
end;

procedure TFPrincipal.BtnWhenAllCompleteClick(Sender: TObject);
begin
  MessageLog('Iniciando tarefa _WhenAllComplete_');
  TTokio.WhenAllComplete([FastTask, SlowTask, FailedTask],
    procedure(Results: TArray<TTaskResult>)
    var
      R: TTaskResult;
    begin
      for R in Results do
      begin
        if R.Success then
          MessageLog(Format('Tarefa (ID %d): OK', [R.InputID]))
        else
          MessageLog(Format('Tarefa (ID %d): ERRO - %s',
            [R.InputID, string(R.ErrorMessage)]));
      end;
    end);
  MessageLog('Aguardando resultado _WhenAllComplete_');
end;

procedure TFPrincipal.BtnDelayAsyncClick(Sender: TObject);
begin
  MessageLog('Iniciando DelayAsync de 2 segundos...');
  TTokio.DelayAsync(2000,
    procedure
    begin
      MessageLog('DelayAsync concluído!');
    end);
  MessageLog('Comando registrado, aguardando callback...');
end;

procedure TFPrincipal.BtnParallelClick(Sender: TObject);
var
  Lista: TArray<Integer>;
  SomaEsperada: Int64;
  I: Integer;
begin
  SetLength(Lista, 1000);
  for I := 0 to High(Lista) do
    Lista[I] := I + 1;

  SomaEsperada := 0;
  for I := 0 to High(Lista) do
    Inc(SomaEsperada, Lista[I]);
  SomaEsperada := SomaEsperada * 2;

  MessageLog('Soma esperada: ' + SomaEsperada.ToString);

  TTokio.ParallelFor(0, High(Lista),
    procedure(Idx: Integer; Res: PTaskResult)
    begin
      Res^.InputID := Lista[Idx] * 2;
      Res^.Success := True;
      Lista[Idx] := Res^.InputID;
    end,
    procedure(Results: TArray<TTaskResult>)
    var
      Soma: Int64;
      R: TTaskResult;
    begin
      Soma := 0;
      for R in Results do
        if R.Success then
          Inc(Soma, R.InputID);

      MessageLog('Soma obtida: ' + Soma.ToString);
      if Soma = SomaEsperada then
        MessageLog('Correto!')
      else
        MessageLog('Erro: valor diferente do esperado.');
    end);
end;

procedure TFPrincipal.BtnRunWithProgressClick(Sender: TObject);
begin
  MessageLog('Iniciando processamento pesado...');
  TTokio.RunWithProgress(
    procedure(Res: PTaskResult; Report: TProgressReport)
    var
      I: Integer;
    begin
      for I := 1 to 100 do
      begin
        Sleep(30);
        Report(I, Format('Item %d/100', [I]));
      end;
      Res^.Success := True;
    end,
    procedure(Percent: Double; const Msg: string)
    begin
      ProgressBar1.Position := Round(Percent);
      Label1.Caption := Msg;
    end,
    procedure(R: TTaskResult)
    begin
      ShowMessage('Fim');
    end);
end;

procedure TFPrincipal.BtnFindIdClick(Sender: TObject);
var
  MidIndex, Offset, TargetID: Integer;
begin
  BtnFindId.Enabled := False;
  MLog.Clear;
  ProgressBar1.Position := 0;
  UpdateProgress(0, 'Preparando busca paralela...');

  MidIndex := Length(FLista) div 2;
  Randomize;
  Offset := Random(Length(FLista) div 10) - (Length(FLista) div 20);
  TargetID := FLista[MidIndex + Offset];

  ExecuteParallelSearch(TargetID, BtnFindId);
end;

procedure TFPrincipal.BtnFindRandomIdClick(Sender: TObject);
var
  TargetID: Integer;
begin

  BtnFindRandomId.Enabled := False;
  MLog.Clear;
  ProgressBar1.Position := 0;
  UpdateProgress(0, 'Preparando busca paralela...');

  Randomize;
  TargetID := Random(Length(FLista)) + 1; // FLista[I] = I+1, nunca zero

  ExecuteParallelSearch(TargetID, BtnFindRandomId);
end;

procedure TFPrincipal.BtnSeriesClick(Sender: TObject);
begin
  // Series é bloqueante — deve rodar em thread separada para não travar a UI.
  // Aqui mantemos como demonstração da API bloqueante, mas isolado em thread.
  BtnSeries.Enabled := False;
  TThread.CreateAnonymousThread(
    procedure
    var
      Results: TArray<TTaskResult>;
    begin
      Results := TTokio.Series([FastTask, SlowTask]);
      TThread.Queue(nil,
        procedure
        begin
          ShowMessage(Format('Series concluída: %d etapas', [Length(Results)]));
          BtnSeries.Enabled := True;
        end);
    end).Start;
end;

procedure TFPrincipal.BtnSeriesAsyncClick(Sender: TObject);
begin
  TTokio.SeriesAsync([
  // Etapa 1 — sucesso
    procedure(Res: PTaskResult)
    begin
      Sleep(300);
      Res^.Success := True;
      Res^.InputID := 1;
    end,

  // Etapa 2 — falha proposital (interrompe a série)
    procedure(Res: PTaskResult)
    begin
      Sleep(300);
      raise Exception.Create('Erro ao conectar no banco de dados!');
    end,

  // Etapa 3 — nunca executada por causa da falha anterior
  procedure(Res: PTaskResult)begin Res^.Success := True; Res^.InputID := 3;
  Res^.DataPtr := AnsiStrings.StrNew('Query executada com sucesso'); end],
    procedure(Results: TArray<TTaskResult>)
    var
      R: TTaskResult;
    begin
      for R in Results do
      begin
        if R.Success then
          MessageLog(Format('Tarefa %d OK', [R.InputID]))
        else
          MessageLog(Format('Falha na tarefa: %s', [string(R.ErrorMessage)]));

        // FIX: libera DataPtr de todas as etapas — a etapa 1 pode ter DataPtr
        // preenchido e não era liberado na versão anterior.
        if R.DataPtr <> nil then
          AnsiStrings.StrDispose(PAnsiChar(R.DataPtr));
      end;
    end);
end;

procedure TFPrincipal.btnFetchAllClick(Sender: TObject);
var
  TaskPosts, TaskDogs, TaskJokes: TAsyncAction;
begin
  btnFetchAll.Enabled := False;
  MLog.Clear;
  ProgressBar1.Position := 0;
  Label1.Caption := 'Iniciando consultas...';

  TaskPosts := procedure(Res: PTaskResult)
    var
      Http: THTTPClient;
      Response: IHTTPResponse;
    begin
      Http := THTTPClient.Create;
      try
        Response := Http.Get('https://jsonplaceholder.typicode.com/posts/1');
        if Response.StatusCode = 200 then
        begin
          Res^.DataPtr := AnsiStrings.StrNew
            (PAnsiChar(AnsiString(Response.ContentAsString)));
          Res^.Success := True;
          Res^.InputID := 1;
        end
        else
          raise Exception.CreateFmt('HTTP %d', [Response.StatusCode]);
      finally
        Http.Free;
      end;
    end;

  TaskDogs := procedure(Res: PTaskResult)
    var
      Http: THTTPClient;
      Response: IHTTPResponse;
      JsonObj: TJSONObject;
    begin
      Http := THTTPClient.Create;
      try
        Response := Http.Get('https://dog.ceo/api/breeds/image/random');
        if Response.StatusCode = 200 then
        begin
          JsonObj := TJSONObject.ParseJSONValue(Response.ContentAsString)
            as TJSONObject;
          try
            Res^.DataPtr := AnsiStrings.StrNew
              (PAnsiChar(AnsiString(JsonObj.GetValue<string>('message'))));
            Res^.Success := True;
            Res^.InputID := 2;
          finally
            JsonObj.Free;
          end;
        end
        else
          raise Exception.CreateFmt('HTTP %d', [Response.StatusCode]);
      finally
        Http.Free;
      end;
    end;

  TaskJokes := procedure(Res: PTaskResult)
    var
      Http: THTTPClient;
      Response: IHTTPResponse;
      JsonObj: TJSONObject;
    begin
      Http := THTTPClient.Create;
      try
        Response := Http.Get('https://api.chucknorris.io/jokes/random');
        if Response.StatusCode = 200 then
        begin
          JsonObj := TJSONObject.ParseJSONValue(Response.ContentAsString)
            as TJSONObject;
          try
            Res^.DataPtr := AnsiStrings.StrNew
              (PAnsiChar(AnsiString(JsonObj.GetValue<string>('value'))));
            Res^.Success := True;
            Res^.InputID := 3;
          finally
            JsonObj.Free;
          end;
        end
        else
          raise Exception.CreateFmt('HTTP %d', [Response.StatusCode]);
      finally
        Http.Free;
      end;
    end;

  TTokio.AllAsync([
  // API 1: JSONPlaceholder
    TaskPosts,

  // API 2: Dog CEO (imagem aleatória)
  TaskDogs,

  // API 3: Chuck Norris Joke
  TaskJokes],
    procedure(Results: TArray<TTaskResult>)
    begin
      ShowResults(Results);
    end);
end;

procedure TFPrincipal.btnProcessClick(Sender: TObject);
const
  ZIP_URL = 'https://www.gutenberg.org/cache/epub/78530/pg78530-h.zip';
var
  CancelToken: ICancelToken;
begin
  btnProcess.Enabled := False;
  MLog.Clear;
  ProgressBar1.Position := 0;
  UpdateProgress(0, 'Preparando...');

  CancelToken := TTokio.CreateCancelToken;

  TTokio.SeriesAsync([
  // ------------------------------------------------------------------
  // Etapa 1: Download com progresso real
  // ------------------------------------------------------------------
    procedure(Res: PTaskResult)
    var
      Http: TNetHTTPClient;
      Stream: TFileStream;
      Handler: TDownloadHandler;
    begin
      Handler := TDownloadHandler.Create;
      Http := TNetHTTPClient.Create(nil);
      try
        Handler.CancelToken := CancelToken;
        Handler.FormRef := Self;
        Http.OnReceiveData := Handler.OnReceiveData;

        ForceDirectories(ExtractFilePath(FZipFileName));
        Stream := TFileStream.Create(FZipFileName, fmCreate);
        try
          Http.Get(ZIP_URL, Stream);
        finally
          Stream.Free;
        end;

        if CancelToken.IsCancelled then
          raise Exception.Create('Download cancelado pelo usuário');

        Res^.Success := True;
        Res^.InputID := 1;
        Res^.DataPtr := AnsiStrings.StrNew('Download OK');
      finally
        Http.Free;
        Handler.Free;
      end;
    end,

  // ------------------------------------------------------------------
  // Etapa 2: Descompactar com progresso simulado
  // ------------------------------------------------------------------
    procedure(Res: PTaskResult)
    var
      Zip: TZipFile;
      TotalFiles, I: Integer;
    begin
      if not FileExists(FZipFileName) then
        raise Exception.Create('Arquivo ZIP não encontrado');

      Zip := TZipFile.Create;
      try
        Zip.Open(FZipFileName, zmRead);
        TotalFiles := Zip.FileCount;
        if TotalFiles = 0 then
          raise Exception.Create('Arquivo ZIP vazio');

        Zip.ExtractAll(FExtractFolder);

        for I := 1 to TotalFiles do
        begin
          // Captura I por valor via parâmetro de closure auxiliar
          TThread.Queue(nil,
            procedure
            begin
              UpdateProgress((I / TotalFiles) * 100,
                Format('Descompactando: %d/%d arquivos', [I, TotalFiles]));
            end);
          Sleep(5);
        end;
      finally
        Zip.Free;
      end;

      Res^.Success := True;
      Res^.InputID := 2;
      Res^.DataPtr := AnsiStrings.StrNew('Descompactação OK');
    end,

  // ------------------------------------------------------------------
  // Etapa 3: Deletar o ZIP
  // ------------------------------------------------------------------
  procedure(Res: PTaskResult)begin if FileExists(FZipFileName)
  then begin DeleteFile(FZipFileName); Res^.Success := True; Res^.InputID := 3;
  Res^.DataPtr := AnsiStrings.StrNew('Arquivo ZIP deletado');
  end else begin Res^.Success := False;
  Res^.ErrorMessage := 'Arquivo ZIP não encontrado para deletar'; end; end],
    procedure(Results: TArray<TTaskResult>)
    begin
      OnProcessFinished(Results);
    end);
end;

procedure TFPrincipal.CLEAR1Click(Sender: TObject);
begin
  MLog.Clear;
end;

end.
