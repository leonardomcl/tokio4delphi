use std::ffi::c_void;
use std::sync::Arc;
use std::thread::available_parallelism;

use futures::future::join_all;
use futures::future::select_all;
use once_cell::sync::Lazy;
use tokio::runtime::Runtime;
use tokio::sync::Semaphore;
use tokio::task::JoinHandle;

// ============================================================================
// 1. WRAPPER SEGURO PARA PONTEIROS (*mut c_void)
// ============================================================================

/// Wrapper newtype que implementa Send + Sync para ponteiros brutos vindos
/// do Delphi. A segurança é garantida pelo contrato com o chamador: o
/// ponteiro deve permanecer válido e exclusivo durante toda a execução da
/// task (async_wait_all / async_wait_any devem ser chamados antes de
/// qualquer liberação de memória no lado Delphi).
#[derive(Copy, Clone)]
struct SendPtr(*mut c_void);

// SAFETY: ver comentário acima.
unsafe impl Send for SendPtr {}
unsafe impl Sync for SendPtr {}

// ============================================================================
// 2. SEMÁFORO GLOBAL DE CONCORRÊNCIA
// ============================================================================

/// Limita o número de tasks executando em spawn_blocking simultaneamente
/// a 2× o número de CPUs lógicas, evitando thrashing de threads.
static SEMAPHORE: Lazy<Arc<Semaphore>> = Lazy::new(|| {
    let cpus = available_parallelism().map(|n| n.get()).unwrap_or(4);
    Arc::new(Semaphore::new(cpus * 2))
});

// ============================================================================
// 3. RUNTIME TOKIO (singleton por processo)
// ============================================================================

static RUNTIME: Lazy<Runtime> = Lazy::new(|| {
    let cpus = available_parallelism().map(|n| n.get()).unwrap_or(4);

    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(cpus)
        .thread_name("delphi-async")
        .enable_all()
        .build()
        .expect("Falha ao criar runtime Tokio")
});

// ============================================================================
// 4. ESTRUTURA TaskHandle (opaca para o Delphi)
// ============================================================================

pub struct TaskHandle {
    /// JoinHandle consumido por async_wait_all / async_wait_any.
    /// None indica que já foi consumido.
    handle: Option<JoinHandle<()>>,
    /// AbortHandle independente — permanece válido mesmo após handle ser None,
    /// permitindo async_cancel a qualquer momento.
    abort_handle: tokio::task::AbortHandle,
}

// ============================================================================
// 5. HELPER: invoca a callback C dentro de spawn_blocking
// ============================================================================

/// Mantém o SendPtr dentro do wrapper durante a chamada, evitando que o
/// ponteiro bruto (*mut c_void) seja movido isoladamente (o que violaria
/// as regras de Send do compilador).
#[inline]
fn call_with_ptr(cb: extern "C" fn(*mut c_void), ptr: SendPtr) {
    cb(ptr.0);
}

// ============================================================================
// 6. async_spawn
// ============================================================================

/// Cria e agenda uma nova task assíncrona no runtime Tokio.
///
/// # Parâmetros
/// - `cb`  : ponteiro para a função callback Delphi (cdecl).
/// - `ctx` : ponteiro opaco passado de volta à callback (TAsyncTask* no Delphi).
///
/// # Retorno
/// Ponteiro para um TaskHandle alocado no heap. Deve ser liberado com
/// `async_free_handle` após o uso. Nunca retorna null em condições normais
/// (panic em falha de alocação).
#[unsafe(no_mangle)]
pub extern "C" fn async_spawn(cb: extern "C" fn(*mut c_void), ctx: *mut c_void) -> *mut TaskHandle {
    let ctx = SendPtr(ctx);
    let sem = Arc::clone(&SEMAPHORE);

    let join_handle = RUNTIME.spawn(async move {
        // Aguarda permissão do semáforo antes de ocupar uma thread de blocking.
        let _permit = sem.acquire_owned().await.unwrap();

        let result = tokio::task::spawn_blocking(move || {
            call_with_ptr(cb, ctx);
        })
        .await;

        if let Err(e) = result {
            eprintln!("[async_bridge] Erro em spawn_blocking: {:?}", e);
        }
    });

    let abort_handle = join_handle.abort_handle();

    Box::into_raw(Box::new(TaskHandle {
        handle: Some(join_handle),
        abort_handle,
    }))
}

// ============================================================================
// 7. async_wait_all
// ============================================================================

/// Bloqueia a thread chamadora até que **todas** as tasks do array concluam.
///
/// # Segurança
/// - `handles_ptr` deve apontar para um array contíguo de `count` ponteiros.
/// - Cada ponteiro do array deve ser não-nulo e válido.
/// - Após o retorno, os JoinHandles internos foram consumidos (handle = None),
///   mas os TaskHandles ainda devem ser liberados via `async_free_handle`.
#[unsafe(no_mangle)]
pub extern "C" fn async_wait_all(handles_ptr: *const *mut TaskHandle, count: usize) {
    if handles_ptr.is_null() || count == 0 {
        return;
    }

    let mut join_handles = Vec::with_capacity(count);

    unsafe {
        let slice = std::slice::from_raw_parts(handles_ptr, count);
        for &h_ptr in slice {
            if !h_ptr.is_null() {
                if let Some(jh) = (*h_ptr).handle.take() {
                    join_handles.push(jh);
                }
            }
        }
    }

    RUNTIME.block_on(async {
        join_all(join_handles).await;
    });
}

// ============================================================================
// 8. async_wait_any
// ============================================================================

/// Bloqueia a thread chamadora até que a **primeira** task do array conclua.
///
/// # Retorno
/// - Índice (0-based) no array original da task vencedora.
/// - `count` como sentinela de erro (handle nulo, já consumido, ou array vazio).
///   O chamador Delphi deve sempre verificar `Result < Count` antes de usar.
///
/// # Contrato com o chamador
/// - Todos os handles devem ser válidos e não consumidos antes da chamada.
/// - O JoinHandle do **vencedor** é consumido internamente (handle = None).
///   O TaskHandle em si ainda deve ser liberado via `async_free_handle`.
/// - Os JoinHandles dos **perdedores** são dropados (detached), mas as tasks
///   Tokio subjacentes continuam rodando. O chamador DEVE invocar
///   `async_cancel` + `async_free_handle` em cada perdedor para interrompê-los
///   e liberar memória.
#[unsafe(no_mangle)]
pub extern "C" fn async_wait_any(handles_ptr: *const *mut TaskHandle, count: usize) -> usize {
    if handles_ptr.is_null() || count == 0 {
        return count; // sentinela de erro
    }

    // --- Fase 1: valida todos os handles SEM modificar estado algum ---
    // Se qualquer handle for inválido, retornamos antes de consumir qualquer um,
    // mantendo o estado do array intacto para o chamador.
    unsafe {
        for i in 0..count {
            let h_ptr = *handles_ptr.add(i);
            if h_ptr.is_null() {
                eprintln!("[async_bridge] async_wait_any: handle[{}] é nulo", i);
                return count;
            }
            if (*h_ptr).handle.is_none() {
                eprintln!(
                    "[async_bridge] async_wait_any: handle[{}] já foi consumido",
                    i
                );
                return count;
            }
        }
    }

    // --- Fase 2: extrai os JoinHandles (todos válidos, conforme fase 1) ---
    let mut join_handles: Vec<JoinHandle<()>> = Vec::with_capacity(count);
    unsafe {
        for i in 0..count {
            let h_ptr = *handles_ptr.add(i);
            // unwrap() é seguro: is_some() foi verificado na fase 1.
            join_handles.push((*h_ptr).handle.take().unwrap());
        }
    }

    // --- Fase 3: aguarda o primeiro a concluir ---
    // select_all retorna (output, índice_no_vec, restantes).
    // Os handles restantes são dropados aqui — drop de JoinHandle em Tokio
    // faz DETACH (não cancela). O chamador deve chamar async_cancel nos
    // perdedores para realmente interrompê-los.
    let winner_index = RUNTIME.block_on(async {
        let (result, index, _remaining) = select_all(join_handles).await;

        if let Err(ref e) = result {
            eprintln!(
                "[async_bridge] async_wait_any: task[{}] encerrou com erro: {:?}",
                index, e
            );
        }

        index
    });

    winner_index
}

// ============================================================================
// 9. async_free_handle
// ============================================================================

/// Libera a memória de um TaskHandle e aborta a task se ainda estiver ativa.
///
/// Seguro chamar mesmo se o JoinHandle já foi consumido (handle = None),
/// pois o AbortHandle é independente e a operação de abort é idempotente.
#[unsafe(no_mangle)]
pub extern "C" fn async_free_handle(handle: *mut TaskHandle) {
    if !handle.is_null() {
        unsafe {
            let task = Box::from_raw(handle);
            task.abort_handle.abort();
            drop(task);
        }
    }
}

// ============================================================================
// 10. async_cancel
// ============================================================================

/// Sinaliza o cancelamento de uma task em execução.
/// A task será interrompida na próxima yield point do runtime Tokio.
/// Não bloqueia. Seguro chamar múltiplas vezes (idempotente).
/// O TaskHandle ainda deve ser liberado com `async_free_handle` após o uso.
#[unsafe(no_mangle)]
pub extern "C" fn async_cancel(handle: *mut TaskHandle) {
    if !handle.is_null() {
        unsafe {
            (*handle).abort_handle.abort();
        }
    }
}

// ============================================================================
// 11. DIAGNÓSTICO
// ============================================================================

/// Retorna o número de threads worker do runtime Tokio.
#[unsafe(no_mangle)]
pub extern "C" fn async_worker_count() -> usize {
    RUNTIME.handle().metrics().num_workers()
}

/// Retorna true se o runtime foi inicializado com sucesso.
/// Em condições normais sempre retorna true — o Lazy inicializa no primeiro
/// acesso e entra em panic em falha, impedindo a execução de chegar aqui.
#[unsafe(no_mangle)]
pub extern "C" fn async_available() -> bool {
    true
}
