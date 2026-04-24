# 🚀 Tokio4Delphi

**High-Performance Async/Await Library for Delphi, powered by Rust's Tokio Runtime.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Delphi](https://img.shields.io/badge/Delphi-Tokyo%2010.2%2B-red.svg)](https://www.embarcadero.com/)
[![Rust](https://img.shields.io/badge/Rust-Tokio-orange.svg)](https://tokio.rs/)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-lightgrey.svg)]()

---

**Tokio4Delphi** brings modern asynchronous programming to Delphi by bridging it with Rust's battle-tested [`tokio`](https://tokio.rs/) runtime. Run CPU-intensive or I/O-bound work on a persistent, high-performance thread pool — without ever freezing your VCL or FMX UI.

The API was designed to feel familiar: `RunAsync`, `All`, `Race`, `Series`, `WithTimeout` — the same patterns developers know from JavaScript Promises and C# Tasks, in native Delphi anonymous methods.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🚫 No UI Freezing | True background execution on a Rust-managed thread pool |
| ⚡ High Performance | Persistent `tokio` runtime — zero startup cost per task |
| 🔒 Memory Safe | Heap-allocated tasks + `ICancelToken` prevent access violations |
| 🎯 JavaScript-style API | `RunAsync`, `All`, `Race`, `Series`, `WithTimeout`, `RetryAsync` |
| 🔁 Parallel Loops | `ParallelFor` distributes iterations across all available CPU cores |
| ⏱️ Timeout Support | Automatically cancel tasks that exceed a time limit |
| 🔀 Race | Run multiple strategies simultaneously and use whichever finishes first |
| 📦 Zero Dependencies | Pure FFI bridge — no third-party Delphi libraries required |

---

## 📦 Installation

**1.** Download the latest pre-compiled DLLs from the [Releases](https://github.com/leonardomcl/tokio4delphi/releases) page.

**2.** Place the correct file next to your application's executable:

| Target | File |
|---|---|
| Windows 64-bit | `tokio4delphi_x64.dll` |
| Windows 32-bit | `tokio4delphi_x86.dll` |
| Linux | `libtokio4delphi.so` |

**3.** Add `Source/Tokio.Async.Bridge.pas` to your project, or add the `Source/` folder to your Delphi Library Path.

**4.** Add `Tokio.Async.Bridge` to the `uses` clause of any unit where you need async functionality.

---

## ⚠️ Three Rules You Must Know

> **Rule 1 — Thread Safety**
> The background closure (`Res: PTaskResult`) executes on a Rust worker thread.
> **Never** access VCL/FMX controls inside it. Only touch the UI in the `OnFinish` callback,
> which is always dispatched to the Delphi main thread automatically.

> **Rule 2 — Data Ownership**
> If you store data in `Res^.DataPtr`, **you** are responsible for freeing it
> in the `OnFinish` callback. The library will not free it for you.

> **Rule 3 — Form Destruction**
> Call `.Cancel` on all active `ICancelToken`s inside your form's `OnDestroy` event.
> This signals background threads to exit gracefully before the form's memory is released,
> preventing access violations on pending callbacks.

---

## 🚀 Quick Start

```pascal
uses Tokio.Async.Bridge;

procedure TForm1.Button1Click(Sender: TObject);
begin
  Button1.Enabled := False;

  TTokio.RunAsync(
    // Runs on a Rust background thread — do NOT touch the UI here
    procedure(Res: PTaskResult)
    begin
      Sleep(3000); // Simulate a slow HTTP request, file read, etc.
      Res^.Success := True;
    end,

    // Automatically queued back to the Delphi main thread
    procedure(R: TTaskResult)
    begin
      Button1.Enabled := True;
      if R.Success then
        ShowMessage('Done!')
      else
        ShowMessage('Error: ' + string(R.ErrorMessage));
    end
  );
end;
```

---

## 📚 API Reference & Examples

### `RunAsync` — Run a single background task

The most common pattern. Executes one closure on the background thread pool and calls `OnFinish` on the main thread when complete.

```pascal
TTokio.RunAsync(
  procedure(Res: PTaskResult)
  begin
    // Simulate a slow database query
    Sleep(2000);
    Res^.Success := True;
    Res^.InputID := 42; // Optional: identify this task by ID
  end,
  procedure(R: TTaskResult)
  begin
    if R.Success then
      ShowMessage('Query completed! Task ID: ' + R.InputID.ToString)
    else
      ShowMessage('Query failed: ' + string(R.ErrorMessage));
  end
);
```

---

### `All` / `AllAsync` — Run multiple tasks in parallel

Launches all tasks simultaneously and waits for **every one** to complete before calling `OnFinish`. The results are returned in the same order as the input actions.

Use `AllAsync` to avoid blocking the main thread (recommended for UI applications).

```pascal
TTokio.AllAsync(
  [
    // Task 0: fetch user profile
    procedure(Res: PTaskResult)
    begin
      Sleep(800);
      Res^.Success := True;
      Res^.InputID := 0;
    end,

    // Task 1: fetch order history
    procedure(Res: PTaskResult)
    begin
      Sleep(1200);
      Res^.Success := True;
      Res^.InputID := 1;
    end,

    // Task 2: fetch recommendations
    procedure(Res: PTaskResult)
    begin
      Sleep(600);
      Res^.Success := True;
      Res^.InputID := 2;
    end
  ],
  // Called after ALL three finish (total wall time ≈ 1200 ms, not 2600 ms)
  procedure(Results: TArray<TTaskResult>)
  var
    R: TTaskResult;
  begin
    for R in Results do
      if R.Success then
        ShowMessage('Task ' + R.InputID.ToString + ' succeeded')
      else
        ShowMessage('Task ' + R.InputID.ToString + ' failed: ' + string(R.ErrorMessage));
  end
);
```

---

### `Race` / `RaceAsync` — First one wins

Launches all tasks simultaneously and returns the result of whichever finishes **first**. All other tasks are cancelled automatically.

Ideal for fallback strategies: try multiple servers, CDN mirrors, or data sources — and use whichever responds fastest.

Use `RaceAsync` to avoid blocking the main thread (recommended for UI applications).

```pascal
// Example: query two different API endpoints and use whichever responds first
TTokio.RaceAsync(
  [
    // Strategy A: primary server
    procedure(Res: PTaskResult)
    var
      Http: THTTPClient;
      Response: IHTTPResponse;
    begin
      Http := THTTPClient.Create;
      try
        Response := Http.Get('https://api-primary.example.com/data');
        Res^.Success := Response.StatusCode = 200;
        Res^.InputID := 1; // identifies this strategy
      finally
        Http.Free;
      end;
    end,

    // Strategy B: fallback server
    procedure(Res: PTaskResult)
    var
      Http: THTTPClient;
      Response: IHTTPResponse;
    begin
      Http := THTTPClient.Create;
      try
        Response := Http.Get('https://api-fallback.example.com/data');
        Res^.Success := Response.StatusCode = 200;
        Res^.InputID := 2; // identifies this strategy
      finally
        Http.Free;
      end;
    end
  ],
  // Called with the result of whichever server responded first
  procedure(Winner: TTaskResult)
  begin
    if Winner.Success then
      ShowMessage('Got data from server #' + Winner.InputID.ToString)
    else
      ShowMessage('Both servers failed: ' + string(Winner.ErrorMessage));
  end
);
```

> **Tip:** `Race` is also great for UI patterns like "search-as-you-type" — cancel the
> previous request automatically by racing each new keystroke against the last.

---

### `Series` / `SeriesAsync` — Sequential pipeline

Executes a list of tasks **one after another**, in order. If any task fails (`Success = False` or raises an exception), the pipeline stops immediately and all remaining tasks are skipped.

Perfect for multi-step workflows where each step depends on the previous one: download → extract → validate → import.

Use `SeriesAsync` to avoid blocking the main thread (recommended for UI applications).

```pascal
TTokio.SeriesAsync(
  [
    // Step 1: Download the file
    procedure(Res: PTaskResult)
    begin
      ShowMessage('(background) Downloading...');
      Sleep(1000); // Simulate download
      Res^.Success := True;
      Res^.InputID := 1;
    end,

    // Step 2: Extract the archive (only runs if Step 1 succeeded)
    procedure(Res: PTaskResult)
    begin
      Sleep(800); // Simulate extraction
      Res^.Success := True;
      Res^.InputID := 2;
    end,

    // Step 3: Import data into the database (only runs if Step 2 succeeded)
    procedure(Res: PTaskResult)
    begin
      Sleep(1200); // Simulate import
      Res^.Success := True;
      Res^.InputID := 3;
    end
  ],
  // OnFinish: receives results of all executed steps
  // Steps that were skipped due to a failure will have Success=False
  // and ErrorMessage='Task not executed due to previous failure'
  procedure(Results: TArray<TTaskResult>)
  var
    R: TTaskResult;
  begin
    for R in Results do
    begin
      if R.Success then
        ShowMessage('Step ' + R.InputID.ToString + ': OK')
      else
        ShowMessage('Step ' + R.InputID.ToString + ' failed: ' + string(R.ErrorMessage));
    end;
  end
);
```

> **Tip:** Use `Series` to replace fragile chains of nested callbacks or `begin/end` blocks
> that mix UI and background logic. Each step is clean, isolated, and independently testable.

---

### `ParallelFor` — Parallel loop over a range

Distributes loop iterations across the entire thread pool. Each index gets its own background closure, and `OnFinish` is called on the main thread when all iterations complete.

Ideal for bulk data processing, image manipulation, parallel file scanning, or any embarrassingly parallel workload.

```pascal
procedure TForm1.BtnParallelClick(Sender: TObject);
var
  Data: TArray<Integer>;
  I: Integer;
begin
  SetLength(Data, 500);
  for I := 0 to High(Data) do
    Data[I] := I + 1;

  // Multiply every element by 2, in parallel
  TTokio.ParallelFor(0, High(Data),
    procedure(Idx: Integer; Res: PTaskResult)
    begin
      // Idx is safely captured per iteration — no shared variable problem
      Data[Idx]    := Data[Idx] * 2;
      Res^.InputID := Data[Idx];
      Res^.Success := True;
    end,
    procedure(Results: TArray<TTaskResult>)
    var
      Total: Int64;
      R: TTaskResult;
    begin
      Total := 0;
      for R in Results do
        if R.Success then
          Inc(Total, R.InputID);
      ShowMessage('Sum of doubled values: ' + Total.ToString);
    end
  );
end;
```

---

### `WithTimeout` — Set a maximum wait time

Races your task against a timer. If the task does not complete within `TimeoutMS` milliseconds, `OnFinish` is called with `Success=False` and an error message describing the timeout.

```pascal
TTokio.WithTimeout(
  procedure(Res: PTaskResult)
  begin
    Sleep(5000); // Simulating a slow or unresponsive external service
    Res^.Success := True;
  end,
  2000, // Give it 2 seconds max
  procedure(R: TTaskResult)
  begin
    if R.Success then
      ShowMessage('Finished in time!')
    else
      ShowMessage('Timed out: ' + string(R.ErrorMessage));
      // ErrorMessage will contain: "Timeout after 2000 ms"
  end
);
```

---

### `RetryAsync` — Automatic retry with delay

Executes a task up to `MaxRetries` times, stopping as soon as one attempt succeeds. A configurable delay between attempts lets you implement exponential back-off or simple retry policies.

```pascal
TTokio.RetryAsync(
  procedure(Res: PTaskResult; Attempt: Integer)
  begin
    // Attempt starts at 1 and increments on each retry
    if Random(10) > 6 then // 30% success rate simulation
    begin
      Res^.Success := True;
      Res^.InputID := Attempt;
    end
    else
      raise Exception.Create('Service temporarily unavailable');
  end,
  5,   // Try up to 5 times
  procedure(R: TTaskResult)
  begin
    if R.Success then
      ShowMessage('Succeeded on attempt #' + R.InputID.ToString)
    else
      ShowMessage('All retries exhausted: ' + string(R.ErrorMessage));
  end,
  1000 // Wait 1 second between attempts
);
```

---

### `CancelToken` — Manual cancellation

Create a token, pass it into your background closure, and call `.Cancel` from anywhere — a button click, a form close event, or another task.

```pascal
type
  TForm1 = class(TForm)
    // ...
  private
    FToken: ICancelToken; // keep it alive as long as the task might run
  end;

procedure TForm1.BtnStartClick(Sender: TObject);
begin
  FToken := TTokio.CreateCancelToken;

  TTokio.RunAsync(
    procedure(Res: PTaskResult)
    var
      I: Integer;
    begin
      for I := 1 to 100 do
      begin
        if FToken.IsCancelled then
          Exit; // Exit cleanly — do not set Success := True
        Sleep(50);
      end;
      Res^.Success := True;
    end,
    procedure(R: TTaskResult)
    begin
      if R.Success then
        ShowMessage('Completed all 100 steps!')
      else
        ShowMessage('Task was cancelled.');
    end
  );
end;

procedure TForm1.BtnCancelClick(Sender: TObject);
begin
  if Assigned(FToken) then
    FToken.Cancel;
end;

// Always cancel pending tasks when the form closes
procedure TForm1.FormDestroy(Sender: TObject);
begin
  if Assigned(FToken) then
    FToken.Cancel;
end;
```

---

### `ContinueWith` — Chain two tasks

Executes a second task only if the first one succeeded. If the first task fails, `OnFinish` is called immediately with that failure result.

```pascal
TTokio.ContinueWith(
  // Task A: authenticate
  procedure(Res: PTaskResult)
  begin
    Sleep(500);
    Res^.Success := True; // Authentication passed
  end,

  // Task B: load dashboard data (only runs if Task A succeeded)
  procedure(Res: PTaskResult)
  begin
    Sleep(800);
    Res^.Success := True;
  end,

  // OnFinish: called with the result of whichever task ran last
  procedure(R: TTaskResult)
  begin
    if R.Success then
      ShowMessage('Dashboard loaded!')
    else
      ShowMessage('Pipeline failed: ' + string(R.ErrorMessage));
  end
);
```

---

### `WhenAllComplete` — Wait for all, ignore failures

Like `AllAsync`, but **never stops early** — even if some tasks fail. All tasks run to completion and you receive every result, successful or not.

```pascal
TTokio.WhenAllComplete(
  [TaskA, TaskB, TaskC],
  procedure(Results: TArray<TTaskResult>)
  var
    R: TTaskResult;
    Ok, Fail: Integer;
  begin
    Ok   := 0;
    Fail := 0;
    for R in Results do
      if R.Success then Inc(Ok) else Inc(Fail);
    ShowMessage(Format('%d succeeded, %d failed', [Ok, Fail]));
  end
);
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────┐
│                 Your Delphi App                 │
│                                                 │
│  TTokio.RunAsync / AllAsync / RaceAsync / ...   │
│              Tokio.Async.Bridge.pas             │
└───────────────────┬─────────────────────────────┘
                    │ FFI (cdecl)
                    ▼
┌─────────────────────────────────────────────────┐
│              Rust Core  (DLL / .so)             │
│                                                 │
│  async_spawn · async_wait_all · async_wait_any  │
│  async_cancel · async_free_handle               │
│                                                 │
│         Tokio Multi-Thread Runtime              │
│   ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐         │
│   │ W-0  │ │ W-1  │ │ W-2  │ │ W-N  │  workers │
│   └──────┘ └──────┘ └──────┘ └──────┘         │
└─────────────────────────────────────────────────┘
                    │ TThread.Queue
                    ▼
        Delphi Main Thread (VCL/FMX safe)
```

- **Rust Core** manages the thread pool via a process-wide Tokio singleton. Tasks are dispatched using `spawn_blocking`, which prevents blocking the async executor.
- **Delphi Bridge** wraps the C FFI layer with heap-allocated task records, managed reference counting for closures, and `TThread.Queue` to safely deliver results to the main thread.
- **ICancelToken** uses atomic integer operations (`TInterlocked`) — no locks, no deadlocks.

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!
Please check the [issues page](https://github.com/leonardomcl/tokio4delphi/issues) before opening a new one.

To compile the Rust core yourself:

```bash
# Requires Rust stable toolchain (https://rustup.rs)
cd RustCore/
cargo build --release

# Output DLLs will be in RustCore/target/release/
```

---

## 📄 License

Distributed under the [MIT License](https://opensource.org/licenses/MIT).
See `LICENSE` for full text.

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/leonardomcl">leonardomcl</a> · Powered by <a href="https://tokio.rs">Tokio</a> + Delphi
</p>
