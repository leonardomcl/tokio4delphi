unit Tokio.Async.Bridge;

// =============================================================================
// TOKIO4DELPHI — High-Performance Async Library for Delphi
// =============================================================================
// Bridging Delphi with Rust's Tokio Runtime
//
// Arquitetura:
// - DLL Rust: Expõe funções C (cdecl) encapsulando um runtime Tokio
//   multi-thread persistente (Singleton por processo).
// - Abstração: Esta unit provê bindings de baixo nível e a API de alto nível
//   TTokio, inspirada no modelo de Promises/async-await.
//
// Regras de Gestão de Memória:
// - Heap Allocation: Toda task recebe um ponteiro TAsyncTask alocado no heap.
// - Ciclo de Vida: O ponteiro é válido até async_wait_all/any retornar E
//   async_free_handle ser chamado (ordem obrigatória).
// - Propriedade de Dados: O campo DataPtr em TTaskResult pertence ao chamador.
//   Se utilizado, deve ser liberado manualmente pelo receptor do resultado.
//
// Segurança de Thread (Thread-safety):
// - Background Workers: Callbacks de execução rodam no pool do Tokio.
//   É terminantemente PROIBIDO acessar VCL/FMX nesses blocos.
// - Main Thread Sync: Callbacks de finalização (OnFinish) são enfileirados
//   via TThread.Queue, sendo seguros para manipulação de interface (UI).
// =============================================================================

interface

uses
  System.SysUtils,
  System.Classes;

const
{$IFDEF MSWINDOWS}
{$IFDEF CPU64}
  /// <summary>Nome da DLL para Windows 64 bits</summary>
  DLL_NAME = 'tokio4delphi_x64.dll';
{$ELSE}
  /// <summary>Nome da DLL para Windows 32 bits</summary>
  DLL_NAME = 'tokio4delphi_x86.dll';
{$ENDIF}
{$ENDIF}
{$IFDEF LINUX}
  /// <summary>Nome da biblioteca compartilhada para Linux</summary>
  DLL_NAME = 'libtokio4delphi.so';
{$ENDIF}

type
  /// <summary>Ponteiro opaco para um TaskHandle gerenciado pelo Rust</summary>
  PTaskHandle = Pointer;

  /// <summary>Callback cdecl de baixo nível invocada pelo runtime Rust</summary>
  TAsyncCallback = procedure(Ctx: Pointer); cdecl;

  /// <summary>Ponteiro para TTaskResult</summary>
  PTaskResult = ^TTaskResult;

  /// <summary>
  /// Resultado de uma tarefa assíncrona.
  /// DataPtr é um ponteiro opaco de propriedade do chamador: se não-nil,
  /// deve ser interpretado e liberado por quem receber o resultado.
  /// </summary>
  TTaskResult = record
    /// <summary>Identificador numérico definido pelo chamador</summary>
    InputID: Integer;
    /// <summary>Dado arbitrário produzido pela task (ex: PString, TMemoryStream*)</summary>
    DataPtr: Pointer;
    /// <summary>True se a task concluiu sem exceções e definiu Success := True</summary>
    Success: Boolean;
    /// <summary>Mensagem de erro UTF-8 preenchida em caso de falha</summary>
    ErrorMessage: UTF8String;
  end;

  /// <summary>Closure assíncrona básica. Preenche Res^ com o resultado da operação.</summary>
  TAsyncAction = reference to procedure(Res: PTaskResult);

  /// <summary>Closure com suporte a retentativas. Attempt começa em 1.</summary>
  TRetryAction = reference to procedure(Res: PTaskResult; Attempt: Integer);

  /// <summary>Corpo de um loop paralelo. Index é o índice da iteração atual.</summary>
  TAsyncLoopBody = reference to procedure(Index: Integer; Res: PTaskResult);

  // -----------------------------------------------------------------------------
  // Bindings de baixo nível — funções exportadas pela DLL Rust
  // -----------------------------------------------------------------------------

  /// <summary>
  /// Cria e agenda uma nova task no runtime Tokio.
  /// Retorna um TaskHandle que deve ser liberado com async_free_handle.
  /// </summary>
function async_spawn(Cb: TAsyncCallback; Ctx: Pointer): PTaskHandle; cdecl;
  external DLL_NAME;

/// <summary>
/// Bloqueia a thread atual até que TODAS as tasks do array concluam.
/// Os JoinHandles internos são consumidos; os TaskHandles ainda devem
/// ser liberados com async_free_handle.
/// </summary>
procedure async_wait_all(Handles: PPointer; Count: NativeUInt); cdecl;
  external DLL_NAME;

/// <summary>
/// Bloqueia a thread atual até que a PRIMEIRA task do array conclua.
/// Retorna o índice (0-based) do vencedor, ou Count em caso de erro.
/// Os handles PERDEDORES ainda estão ativos: o chamador deve chamar
/// async_cancel + async_free_handle em cada um deles.
/// O handle VENCEDOR teve seu JoinHandle consumido internamente, mas ainda
/// requer async_free_handle para liberar o TaskHandle.
/// </summary>
function async_wait_any(Handles: PPointer; Count: NativeUInt): NativeUInt;
  cdecl; external DLL_NAME;

/// <summary>
/// Libera a memória do TaskHandle e aborta a task se ainda estiver ativa.
/// Deve ser chamado exatamente uma vez para cada handle retornado por async_spawn.
/// Seguro chamar após async_cancel (idempotente).
/// </summary>
procedure async_free_handle(Handle: PTaskHandle); cdecl; external DLL_NAME;

/// <summary>
/// Sinaliza o cancelamento de uma task. Não bloqueia. Idempotente.
/// A task é interrompida na próxima yield point do runtime Tokio.
/// O handle ainda deve ser liberado com async_free_handle após o uso.
/// </summary>
procedure async_cancel(Handle: PTaskHandle); cdecl; external DLL_NAME;

/// <summary>Retorna o número de threads worker do runtime Tokio</summary>
function async_worker_count: NativeUInt; cdecl; external DLL_NAME;

/// <summary>Retorna True se o runtime Tokio foi inicializado com sucesso</summary>
function async_available: Boolean; cdecl; external DLL_NAME;

// -----------------------------------------------------------------------------
// API de alto nível
// -----------------------------------------------------------------------------

type
  /// <summary>Assinatura para reporte de progresso: (Percentual, Mensagem)</summary>
  TProgressReport = reference to procedure(Percent: Double; const Msg: string);

  /// <summary>Closure que aceita o resultado e um callback de progresso</summary>
  TAsyncActionWithProgress = reference to procedure(Res: PTaskResult;
    ReportProgress: TProgressReport);

  /// <summary>
  /// Token de cancelamento thread-safe baseado em interface (TInterfacedObject).
  /// O objeto permanece vivo enquanto qualquer closure que o capturou existir,
  /// eliminando use-after-free em cenários onde closures sobrevivem à função
  /// que as criou (ex: WithTimeout passando closures para RaceAsync).
  /// </summary>
  ICancelToken = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    procedure Cancel;
    function IsCancelled: Boolean;
  end;

  /// <summary>
  /// API de alto nível para programação assíncrona estilo Promise/JavaScript.
  /// Todos os métodos *Async retornam imediatamente (não bloqueiam a UI).
  /// Os callbacks OnFinish são sempre executados na main thread.
  /// </summary>
  TTokio = record
  public
    /// <summary>
    /// Executa N tasks em paralelo e bloqueia a thread atual até todas terminarem.
    /// Use AllAsync para a versão não-bloqueante.
    /// </summary>
    class function All(const Actions: array of TAsyncAction)
      : TArray<TTaskResult>; static;

    /// <summary>
    /// Executa N tasks em paralelo sem bloquear a thread chamadora.
    /// OnFinish é chamado na main thread quando todas as tasks concluírem.
    /// Em caso de falha de spawn, OnFinish recebe um array com um único
    /// resultado sintético (Success=False, InputID=-1) — nunca é silenciado.
    /// </summary>
    class procedure AllAsync(const Actions: array of TAsyncAction;
      OnFinish: TProc < TArray < TTaskResult >> ); static;

    /// <summary>
    /// Executa uma única task e bloqueia a thread atual até ela terminar.
    /// Use RunAsync para a versão não-bloqueante.
    /// </summary>
    class function Await(Action: TAsyncAction; InputID: Integer = 0)
      : TTaskResult; static;

    /// <summary>
    /// Encadeia duas tasks sequencialmente: executa Action e, somente se
    /// bem-sucedida (Success=True), executa Next. OnFinish recebe o resultado final.
    /// </summary>
    class procedure ContinueWith(Action: TAsyncAction; Next: TAsyncAction;
      OnFinish: TProc<TTaskResult>); static;

    /// <summary>
    /// Aguarda MS milissegundos sem bloquear a thread chamadora.
    /// Equivalente a setTimeout no JavaScript.
    /// </summary>
    class procedure DelayAsync(MS: Integer; OnFinish: TProc); static;

    /// <summary>
    /// Executa o intervalo StartIdx..EndIdx em paralelo, uma task por índice.
    /// OnFinish recebe os resultados de todas as iterações.
    /// </summary>
    class procedure ParallelFor(StartIdx, EndIdx: Integer; Body: TAsyncLoopBody;
      OnFinish: TProc < TArray < TTaskResult >> ); static;

    /// <summary>
    /// Executa N tasks em paralelo e retorna o resultado da primeira a terminar.
    /// Bloqueia a thread atual. As demais tasks são canceladas.
    /// Usa async_wait_any internamente: uma única chamada bloqueante,
    /// sem threads auxiliares nem locks.
    /// </summary>
    class function Race(const Actions: array of TAsyncAction)
      : TTaskResult; static;

    /// <summary>
    /// Versão não-bloqueante de Race.
    /// OnFinish é chamado na main thread com o resultado do vencedor.
    /// </summary>
    class procedure RaceAsync(const Actions: array of TAsyncAction;
      OnFinish: TProc<TTaskResult>); static;

    /// <summary>
    /// Executa Action até MaxRetries vezes. Para na primeira tentativa bem-sucedida.
    /// DelayMS é o intervalo entre tentativas (padrão: 1000ms). Não bloqueia a UI.
    /// OnFinish recebe o resultado da última tentativa (bem-sucedida ou não).
    /// </summary>
    class procedure RetryAsync(Action: TRetryAction; MaxRetries: Integer;
      OnFinish: TProc<TTaskResult>; DelayMS: Integer = 1000;
      InputID: Integer = 0); static;

    /// <summary>
    /// Executa uma única task de forma assíncrona sem bloquear a thread chamadora.
    /// OnFinish é chamado na main thread com o resultado.
    /// </summary>
    class procedure RunAsync(Action: TAsyncAction; OnFinish: TProc<TTaskResult>;
      InputID: Integer = 0); static;

    /// <summary>
    /// Executa uma tarefa com suporte a progresso. A tarefa pode chamar ReportProgress
    /// (que é thread-safe e sincroniza com a main thread) a qualquer momento.
    /// O callback OnProgress é executado na main thread (seguro para UI).
    /// </summary>
    class procedure RunWithProgress(Action: TAsyncActionWithProgress;
      OnProgress: TProgressReport; OnFinish: TProc<TTaskResult>;
      InputID: Integer = 0); static;

    /// <summary>
    /// Executa uma lista de tarefas em série (uma após a outra, na ordem do array).
    /// Se alguma tarefa falhar (Success = False), a série é interrompida e as tarefas
    /// seguintes não são executadas. O array de resultados terá o mesmo tamanho,
    /// com as posições não executadas marcadas como falha.
    /// Bloqueia a thread atual.
    /// </summary>
    class function Series(const Actions: array of TAsyncAction)
      : TArray<TTaskResult>; static;

    /// <summary>
    /// Versão assíncrona de Series (não bloqueia a thread chamadora).
    /// OnFinish é chamado na main thread após a conclusão (ou interrupção) da série.
    /// </summary>
    class procedure SeriesAsync(const Actions: array of TAsyncAction;
      OnFinish: TProc < TArray < TTaskResult >> ); static;

    /// <summary>
    /// Executa N tasks em paralelo e aguarda TODAS terminarem, mesmo as que falharem.
    /// Nunca cancela tasks. OnFinish recebe todos os resultados (incluindo erros).
    /// Não bloqueia a thread chamadora.
    /// </summary>
    class procedure WhenAllComplete(const Actions: array of TAsyncAction;
      OnFinish: TProc < TArray < TTaskResult >> ); static;

    /// <summary>
    /// Executa Action com um tempo máximo de TimeoutMS milissegundos.
    /// Se Action não concluir a tempo, OnFinish recebe Success=False com
    /// ErrorMessage indicando timeout. Não bloqueia a thread chamadora.
    /// </summary>
    class procedure WithTimeout(Action: TAsyncAction; TimeoutMS: Integer;
      OnFinish: TProc<TTaskResult>); static;

    /// <summary>Cria um novo token de cancelamento para uso em tasks customizadas</summary>
    class function CreateCancelToken: ICancelToken; static;
  end;

implementation

uses
  System.SyncObjs,
  System.Threading;

// =============================================================================
// Tipos internos
// =============================================================================

type
  PAsyncTask = ^TAsyncTask;

  /// <summary>
  /// Unidade de trabalho passada ao Rust via ponteiro opaco (Ctx).
  /// Alocada no heap (New/Dispose) para que o ponteiro permaneça válido
  /// independentemente da stack frame que iniciou a task.
  /// </summary>
  TAsyncTask = record
    Action: TAsyncAction;
    Result: TTaskResult;
  end;

  /// <summary>
  /// Implementação de ICancelToken.
  /// TInterlocked garante que Cancel e IsCancelled sejam seguros para chamada
  /// simultânea de múltiplas threads sem necessidade de locks explícitos.
  /// </summary>
  TCancelToken = class(TInterfacedObject, ICancelToken)
  private
    // 0 = não cancelado | 1 = cancelado.
    // Integer garante alinhamento de 4 bytes requerido pelas ops atômicas.
    FCancelled: Integer;
  public
    constructor Create;
    procedure Cancel;
    function IsCancelled: Boolean;
  end;

  { TCancelToken }

constructor TCancelToken.Create;
begin
  inherited Create;
  FCancelled := 0;
end;

procedure TCancelToken.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
end;

function TCancelToken.IsCancelled: Boolean;
begin
  // CompareExchange(addr, exchange, comparand):
  // Se *addr = comparand → troca por exchange e retorna comparand.
  // Usando exchange=0, comparand=0: não altera nada, mas lê atomicamente.
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) = 1;
end;

// =============================================================================
// InternalCallback — ponto de entrada invocado pelo Rust
// =============================================================================

/// <summary>
/// Função cdecl invocada pelo runtime Rust (spawn_blocking) para cada task.
/// Executa em thread do pool Tokio — não acesse VCL/FMX aqui.
/// </summary>
procedure InternalCallback(Ctx: Pointer); cdecl;
var
  Task: PAsyncTask;
begin
  if not Assigned(Ctx) then
    Exit;

  Task := PAsyncTask(Ctx);

  if not Assigned(Task^.Action) then
  begin
    Task^.Result.Success := False;
    Task^.Result.ErrorMessage := 'Action não atribuída';
    Exit;
  end;

  try
    Task^.Action(@Task^.Result);
  except
    on E: Exception do
    begin
      Task^.Result.Success := False;
      Task^.Result.ErrorMessage := UTF8String(E.Message);
    end;
  end;
end;

// =============================================================================
// Helpers internos
// =============================================================================

/// <summary>
/// Cria uma TAsyncAction que captura Idx por valor (parâmetro de função),
/// garantindo que cada closure de loop tenha seu próprio índice independente.
/// Sem isso, todas as closures do loop compartilhariam a mesma variável de
/// iteração e leriam apenas seu valor final.
/// </summary>
function MakeLoopAction(Body: TAsyncLoopBody; Idx: Integer): TAsyncAction;
begin
  Result := procedure(Res: PTaskResult)
    begin
      Body(Idx, Res);
    end;
end;

/// <summary>
/// Aguarda e libera exatamente Count handles já spawnados.
/// Usado em caminhos de erro (spawn parcial) para garantir que o Rust
/// não escreva em memória já liberada pelo Delphi (use-after-free).
/// </summary>
procedure WaitAndFreeHandles(const Handles: TArray<PTaskHandle>;
  const RawHandles: TArray<Pointer>; Count: Integer);
var
  I: Integer;
begin
  if Count <= 0 then
    Exit;
  async_wait_all(@RawHandles[0], Count);
  for I := 0 to Count - 1 do
    async_free_handle(Handles[I]);
end;

// =============================================================================
// TAsync — implementação
// =============================================================================

{ TAsync }

class function TTokio.CreateCancelToken: ICancelToken;
begin
  Result := TCancelToken.Create;
end;

// ---------------------------------------------------------------------------
// All
// ---------------------------------------------------------------------------
class function TTokio.All(const Actions: array of TAsyncAction)
  : TArray<TTaskResult>;
var
  Count, I, SpawnedCount: Integer;
  Tasks: TArray<TAsyncTask>;
  Handles: TArray<PTaskHandle>;
  RawHandles: TArray<Pointer>;
begin
  Count := Length(Actions);
  SetLength(Result, Count);
  if Count = 0 then
    Exit;

  SetLength(Tasks, Count);
  SetLength(Handles, Count);
  SetLength(RawHandles, Count);
  SpawnedCount := 0;

  try
    for I := 0 to Count - 1 do
    begin
      Tasks[I].Action := Actions[I];
      Initialize(Tasks[I].Result);
      Tasks[I].Result.InputID := I;
      Tasks[I].Result.Success := False;

      Handles[I] := async_spawn(@InternalCallback, @Tasks[I]);
      if Handles[I] = nil then
        raise Exception.CreateFmt('Falha ao criar tarefa %d', [I]);

      RawHandles[I] := Handles[I];
      Inc(SpawnedCount);
    end;

    async_wait_all(@RawHandles[0], Count);

  except
    // Aguarda as tasks já spawnadas antes de deixar Tasks sair de escopo,
    // evitando que o Rust escreva em memória liberada (use-after-free).
    WaitAndFreeHandles(Handles, RawHandles, SpawnedCount);
    raise;
  end;

  for I := 0 to Count - 1 do
  begin
    Result[I] := Tasks[I].Result;
    async_free_handle(Handles[I]);
    Finalize(Tasks[I].Result);
  end;
end;

// ---------------------------------------------------------------------------
// AllAsync
// ---------------------------------------------------------------------------
class procedure TTokio.AllAsync(const Actions: array of TAsyncAction;
  OnFinish: TProc < TArray < TTaskResult >> );
var
  ActionsCopy: TArray<TAsyncAction>;
  I: Integer;
begin
  SetLength(ActionsCopy, Length(Actions));
  for I := 0 to High(Actions) do
    ActionsCopy[I] := Actions[I];

  TThread.CreateAnonymousThread(
    procedure
    var
      Results: TArray<TTaskResult>;
    begin
      try
        Results := TTokio.All(ActionsCopy);
      except
        on E: Exception do
        begin
          // Garante que OnFinish seja SEMPRE chamado com um resultado
          // sintético — nunca silencia a falha deixando o caller esperando.
          SetLength(Results, 1);
          Results[0] := Default (TTaskResult);
          Results[0].Success := False;
          Results[0].InputID := -1;
          Results[0].ErrorMessage := UTF8String(E.Message);
        end;
      end;

      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnFinish) then
            OnFinish(Results);
        end);
    end).Start;
end;

// ---------------------------------------------------------------------------
// Await
// ---------------------------------------------------------------------------
class function TTokio.Await(Action: TAsyncAction; InputID: Integer)
  : TTaskResult;
var
  Task: PAsyncTask;
  Handle: PTaskHandle;
begin
  // Alocação no heap: garante que o ponteiro passado ao Rust permaneça
  // válido independentemente de reorganizações de stack ou inlining.
  New(Task);
  try
    Task^.Action := Action;
    Initialize(Task^.Result);
    Task^.Result.InputID := InputID;
    Task^.Result.Success := False;

    Handle := async_spawn(@InternalCallback, Task);
    if Handle = nil then
      raise Exception.Create('Falha ao criar tarefa');

    async_wait_all(@Handle, 1);

    Result := Task^.Result;
    async_free_handle(Handle);

    // NÃO chamar Finalize(Task^.Result) aqui.
    // Dispose(Task) já executa Finalize implicitamente em todos os campos
    // managed do record (incluindo ErrorMessage: UTF8String). Chamar
    // Finalize explicitamente antes causaria double-free no refcount → crash.
  finally
    Dispose(Task);
  end;
end;

// ---------------------------------------------------------------------------
// ContinueWith
// ---------------------------------------------------------------------------
class procedure TTokio.ContinueWith(Action: TAsyncAction; Next: TAsyncAction;
OnFinish: TProc<TTaskResult>);
begin
  TTokio.RunAsync(Action,
    procedure(FirstResult: TTaskResult)
    begin
      if not FirstResult.Success then
      begin
        if Assigned(OnFinish) then
          OnFinish(FirstResult);
        Exit;
      end;
      TTokio.RunAsync(Next, OnFinish);
    end);
end;

// ---------------------------------------------------------------------------
// DelayAsync
// ---------------------------------------------------------------------------
class procedure TTokio.DelayAsync(MS: Integer; OnFinish: TProc);
begin
  TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(MS);
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnFinish) then
            OnFinish();
        end);
    end).Start;
end;

// ---------------------------------------------------------------------------
// ParallelFor
// ---------------------------------------------------------------------------
class procedure TTokio.ParallelFor(StartIdx, EndIdx: Integer;
Body: TAsyncLoopBody; OnFinish: TProc < TArray < TTaskResult >> );
var
  Actions: TArray<TAsyncAction>;
  I: Integer;
begin
  if EndIdx < StartIdx then
  begin
    if Assigned(OnFinish) then
      OnFinish(nil);
    Exit;
  end;

  SetLength(Actions, EndIdx - StartIdx + 1);
  for I := 0 to High(Actions) do
    Actions[I] := MakeLoopAction(Body, StartIdx + I);

  TTokio.AllAsync(Actions, OnFinish);
end;

// ---------------------------------------------------------------------------
// Race
//
// Usa async_wait_any: uma única chamada bloqueante no Rust, eliminando a
// abordagem anterior de N threads auxiliares + TCountdownEvent + TMonitor.
// Resultado: menos overhead, sem risco de use-after-free em Lock/Event.
// ---------------------------------------------------------------------------
class function TTokio.Race(const Actions: array of TAsyncAction): TTaskResult;
var
  Count, I, SpawnedCount: Integer;
  WinnerIdx: NativeUInt;
  Tasks: TArray<TAsyncTask>;
  Handles: TArray<PTaskHandle>;
  RawHandles: TArray<Pointer>;
begin
  Count := Length(Actions);
  if Count = 0 then
    raise Exception.Create('Nenhuma ação para Race');

  SetLength(Tasks, Count);
  SetLength(Handles, Count);
  SetLength(RawHandles, Count);
  SpawnedCount := 0;

  // --- Fase 1: spawn de todas as tasks ---
  try
    for I := 0 to Count - 1 do
    begin
      Tasks[I].Action := Actions[I];
      Initialize(Tasks[I].Result);
      Tasks[I].Result.InputID := I;
      Tasks[I].Result.Success := False;

      Handles[I] := async_spawn(@InternalCallback, @Tasks[I]);
      if Handles[I] = nil then
        raise Exception.CreateFmt('Falha ao criar tarefa %d', [I]);

      RawHandles[I] := Handles[I];
      Inc(SpawnedCount);
    end;
  except
    WaitAndFreeHandles(Handles, RawHandles, SpawnedCount);
    raise;
  end;

  // --- Fase 2: aguarda o primeiro a terminar ---
  // Uma única chamada bloqueante no Rust (select_all interno).
  WinnerIdx := async_wait_any(@RawHandles[0], Count);

  if WinnerIdx >= NativeUInt(Count) then
  begin
    // Falha interna: aguarda e libera tudo para não vazar memória.
    WaitAndFreeHandles(Handles, RawHandles, Count);
    raise Exception.Create
      ('async_wait_any retornou índice inválido — handle nulo ou já consumido');
  end;

  Result := Tasks[WinnerIdx].Result;

  // --- Fase 3: cancela perdedores e libera todos os handles ---
  // O handle do vencedor já teve seu JoinHandle consumido pelo Rust,
  // mas async_free_handle ainda é necessário para liberar o TaskHandle.
  for I := 0 to Count - 1 do
  begin
    if NativeUInt(I) <> WinnerIdx then
      async_cancel(Handles[I]); // interrompe a task Tokio
    async_free_handle(Handles[I]); // libera memória do TaskHandle
    Finalize(Tasks[I].Result); // decrementa refcount de ErrorMessage etc.
  end;
end;

// ---------------------------------------------------------------------------
// RaceAsync
// ---------------------------------------------------------------------------
class procedure TTokio.RaceAsync(const Actions: array of TAsyncAction;
OnFinish: TProc<TTaskResult>);
var
  ActionsCopy: TArray<TAsyncAction>;
  I: Integer;
begin
  SetLength(ActionsCopy, Length(Actions));
  for I := 0 to High(Actions) do
    ActionsCopy[I] := Actions[I];

  TThread.CreateAnonymousThread(
    procedure
    var
      Res: TTaskResult;
    begin
      try
        Res := TTokio.Race(ActionsCopy);
      except
        on E: Exception do
        begin
          Res := Default (TTaskResult);
          Res.Success := False;
          Res.ErrorMessage := UTF8String(E.Message);
          Res.InputID := -1;
        end;
      end;

      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnFinish) then
            OnFinish(Res);
        end);
    end).Start;
end;

// ---------------------------------------------------------------------------
// RetryAsync
// ---------------------------------------------------------------------------
class procedure TTokio.RetryAsync(Action: TRetryAction; MaxRetries: Integer;
OnFinish: TProc<TTaskResult>; DelayMS: Integer; InputID: Integer);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Attempt: Integer;
      FinalResult: TTaskResult;
    begin
      // Default() respeita managed types (strings, interfaces) —
      // nunca usar FillChar em records que contenham campos managed.
      FinalResult := Default (TTaskResult);
      FinalResult.InputID := InputID;
      FinalResult.Success := False;
      FinalResult.ErrorMessage := 'Máximo de tentativas atingido';

      for Attempt := 1 to MaxRetries do
      begin
        FinalResult := TTokio.Await(
          procedure(Res: PTaskResult)
          begin
            Action(Res, Attempt);
          end, InputID);

        if FinalResult.Success then
          Break;

        if Attempt < MaxRetries then
          Sleep(DelayMS);
      end;

      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnFinish) then
            OnFinish(FinalResult);
        end);
    end).Start;
end;

// ---------------------------------------------------------------------------
// RunAsync
// ---------------------------------------------------------------------------
class procedure TTokio.RunAsync(Action: TAsyncAction;
OnFinish: TProc<TTaskResult>; InputID: Integer);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Res: TTaskResult;
    begin
      try
        Res := TTokio.Await(Action, InputID);
      except
        on E: Exception do
        begin
          Res := Default (TTaskResult);
          Res.Success := False;
          Res.ErrorMessage := UTF8String(E.Message);
          Res.InputID := InputID;
        end;
      end;

      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnFinish) then
            OnFinish(Res);
        end);
    end).Start;
end;

class procedure TTokio.RunWithProgress(Action: TAsyncActionWithProgress;
OnProgress: TProgressReport; OnFinish: TProc<TTaskResult>; InputID: Integer);
begin
  TTokio.RunAsync(
    procedure(Res: PTaskResult)
    begin
      Action(Res, OnProgress); // <-- passa o callback diretamente
    end, OnFinish, InputID);
end;

// ---------------------------------------------------------------------------
// Series (bloqueante) – interrompe na primeira falha
// ---------------------------------------------------------------------------
class function TTokio.Series(const Actions: array of TAsyncAction)
  : TArray<TTaskResult>;
var
  I: Integer;
  TaskResult: TTaskResult;
begin
  SetLength(Result, Length(Actions));
  for I := 0 to High(Actions) do
  begin
    TaskResult := TTokio.Await(Actions[I]);
    Result[I] := TaskResult;
    if not TaskResult.Success then
    begin
      // Preenche as tarefas restantes com erro de "não executado"
      for var J := I + 1 to High(Actions) do
      begin
        Result[J] := Default (TTaskResult);
        Result[J].Success := False;
        Result[J].ErrorMessage :=
          'Tarefa não executada devido a falha anterior';
      end;
      Break;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// SeriesAsync (não bloqueante)
// ---------------------------------------------------------------------------
class procedure TTokio.SeriesAsync(const Actions: array of TAsyncAction;
OnFinish: TProc < TArray < TTaskResult >> );
var
  ActionsCopy: TArray<TAsyncAction>;
  I: Integer;
begin
  SetLength(ActionsCopy, Length(Actions));
  for I := 0 to High(Actions) do
    ActionsCopy[I] := Actions[I];

  TThread.CreateAnonymousThread(
    procedure
    var
      Results: TArray<TTaskResult>;
    begin
      try
        Results := TTokio.Series(ActionsCopy);
      except
        on E: Exception do
        begin
          // Em caso de exceção não capturada, retorna um resultado sintético
          SetLength(Results, 1);
          Results[0] := Default (TTaskResult);
          Results[0].Success := False;
          Results[0].InputID := -1;
          Results[0].ErrorMessage := UTF8String(E.Message);
        end;
      end;
      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnFinish) then
            OnFinish(Results);
        end);
    end).Start;
end;

// ---------------------------------------------------------------------------
// WhenAllComplete
// ---------------------------------------------------------------------------
class procedure TTokio.WhenAllComplete(const Actions: array of TAsyncAction;
OnFinish: TProc < TArray < TTaskResult >> );
var
  Count, I, SpawnedCount: Integer;
  Tasks: TArray<TAsyncTask>;
  Handles: TArray<PTaskHandle>;
  RawHandles: TArray<Pointer>;
begin
  Count := Length(Actions);
  if Count = 0 then
  begin
    if Assigned(OnFinish) then
      OnFinish(nil);
    Exit;
  end;

  SetLength(Tasks, Count);
  SetLength(Handles, Count);
  SetLength(RawHandles, Count);
  SpawnedCount := 0;

  // Fase de spawn tratada antes de criar a thread — exceção aqui é limpa.
  try
    for I := 0 to Count - 1 do
    begin
      Tasks[I].Action := Actions[I];
      Initialize(Tasks[I].Result);
      Tasks[I].Result.InputID := I;
      Tasks[I].Result.Success := False;

      Handles[I] := async_spawn(@InternalCallback, @Tasks[I]);
      if Handles[I] = nil then
        raise Exception.CreateFmt('Falha ao criar tarefa %d', [I]);

      RawHandles[I] := Handles[I];
      Inc(SpawnedCount);
    end;
  except
    WaitAndFreeHandles(Handles, RawHandles, SpawnedCount);
    raise;
  end;

  // async_wait_all fica DENTRO da thread para não bloquear o caller.
  // Tasks e Handles são capturados por valor (dynamic arrays são ref-counted)
  // e permanecem vivos até a thread terminar.
  TThread.CreateAnonymousThread(
    procedure
    var
      J: Integer;
      Results: TArray<TTaskResult>;
    begin
      try
        async_wait_all(@RawHandles[0], Count);
      except
        on E: Exception do
        begin
          SetLength(Results, 1);
          Results[0] := Default (TTaskResult);
          Results[0].Success := False;
          Results[0].InputID := -1;
          Results[0].ErrorMessage := UTF8String('Falha em async_wait_all: ' +
            E.Message);
          TThread.Queue(nil,
            procedure
            begin
              if Assigned(OnFinish) then
                OnFinish(Results);
            end);
          Exit;
        end;
      end;

      SetLength(Results, Count);
      for J := 0 to Count - 1 do
      begin
        Results[J] := Tasks[J].Result;
        async_free_handle(Handles[J]);
        Finalize(Tasks[J].Result);
      end;

      TThread.Queue(nil,
        procedure
        begin
          if Assigned(OnFinish) then
            OnFinish(Results);
        end);
    end).Start;
end;

// ---------------------------------------------------------------------------
// WithTimeout
// ---------------------------------------------------------------------------
class procedure TTokio.WithTimeout(Action: TAsyncAction; TimeoutMS: Integer;
OnFinish: TProc<TTaskResult>);
var
  Actions: array of TAsyncAction;
  Token: ICancelToken;
begin
  // Token é uma interface (heap) capturada por ambas as closures abaixo.
  // O refcount mantém o objeto vivo enquanto qualquer closure existir,
  // eliminando o use-after-free que ocorreria com Boolean na stack local
  // (RaceAsync retorna imediatamente, mas as closures continuam executando).
  Token := TCancelToken.Create;

  SetLength(Actions, 2);

  // Closure 0: executa a action real e sinaliza ao timeout para parar.
  Actions[0] := procedure(Res: PTaskResult)
    begin
      Action(Res);
      Token.Cancel;
    end;

  // Closure 1: sleep cancelável em fatias de 50ms.
  // Sleep(TimeoutMS) único manteria a thread de spawn_blocking ocupada
  // pelo tempo total mesmo após o vencedor ser determinado — desperdício.
  Actions[1] := procedure(Res: PTaskResult)
    var
      Elapsed: Integer;
    const
      STEP_MS = 50;
    begin
      Elapsed := 0;
      while (Elapsed < TimeoutMS) and not Token.IsCancelled do
      begin
        Sleep(STEP_MS);
        Inc(Elapsed, STEP_MS);
      end;

      Res^.Success := False;
      if not Token.IsCancelled then
      begin
        // Action real não terminou a tempo.
        Res^.ErrorMessage := UTF8String(Format('Timeout após %d ms',
          [TimeoutMS]));
        Res^.InputID := -1;
      end;
      // Se IsCancelled=True: a action real venceu a corrida e Race
      // descartará este resultado (usa apenas o do vencedor).
    end;

  TTokio.RaceAsync(Actions, OnFinish);
  // Token sai de escopo local aqui, mas refcount ainda > 0 pelas closures.
  // Será liberado somente quando RaceAsync encerrar e descartar as closures.
end;

// =============================================================================
// Inicialização
// =============================================================================

initialization

if not async_available then
  raise Exception.CreateFmt
    ('DLL "%s" não encontrada ou runtime Tokio falhou ao inicializar.',
    [DLL_NAME]);

end.
