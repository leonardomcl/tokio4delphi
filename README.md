# 🚀 Tokio4Delphi

**High-Performance Async/Await Library for Delphi, powered by Rust's Tokio Runtime.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Delphi Supported Versions](https://img.shields.io/badge/Delphi-Tokyo%2010.2%20and%20newer-red.svg)](https://www.embarcadero.com/)
[![Rust](https://img.shields.io/badge/Rust-Tokio-orange.svg)](https://tokio.rs/)

**Tokio4Delphi** brings the power of modern asynchronous programming to Delphi. By bridging Delphi with Rust's industry-leading `tokio` runtime, it provides a safe, multi-threaded, and high-performance environment to execute background tasks without freezing your VCL or FMX applications.

## ✨ Features

* **No UI Freezing:** True asynchronous execution using a persistent Rust thread pool.
* **Modern Syntax:** JavaScript-like Promises/Async-Await style using Delphi anonymous methods.
* **Memory Safe:** Built-in `ICancelToken` to prevent Access Violations when closing forms with pending tasks.
* **Advanced Routing:** Support for `ParallelFor`, `RaceAsync`, `WithTimeout`, and `Series`.
* **Zero Overhead:** FFI bindings to a C-compatible ABI ensures lightning-fast context switching.

## 📦 Installation

1. Download the latest pre-compiled DLLs from the [Releases](#) tab.
2. Place the DLL (`tokio4delphi_32.dll` or `tokio4delphi_64.dll`) in your application's executable folder.
3. Add the `Source/` folder to your Delphi Library Path, or add `Tokio.Async.Bridge.pas` directly to your project.

## 🚀 Quick Start

Drop a Button on a Form and start running non-blocking tasks:

```pascal
uses
  Tokio.Async.Bridge;

procedure TForm1.Button1Click(Sender: TObject);
begin
  Button1.Enabled := False;

  TTokio.RunAsync(
    // 1. This block runs in the Rust Background Thread Pool
    // NEVER access VCL/FMX UI elements here!
    procedure(Res: PTaskResult)
    begin
      Sleep(3000); // Simulate heavy workload
      Res^.Success := True;
    end,

    // 2. This block is queued back to the Delphi Main Thread
    // It is 100% safe to update your UI here.
    procedure(Result: TTaskResult)
    begin
      Button1.Enabled := True;
      if Result.Success then
        ShowMessage('Task completed successfully in background!');
    end
  );
end; 
```

📚 Advanced Usage Examples

1. Parallel For (Data Processing)
Need to process hundreds of items at the same time? ParallelFor distributes the workload across the Tokio thread pool automatically.

```pascal
procedure TForm1.BtnParallelClick(Sender: TObject);
begin
  // Process items from index 1 to 5 concurrently
  TTokio.ParallelFor(1, 5,
    procedure(Idx: Integer; Res: PTaskResult)
    begin
      // Idx is safely captured for each worker
      Sleep(1000 * Idx); 
      Res^.Success := True;
    end,
    procedure(Results: TArray<TTaskResult>)
    begin
      ShowMessage('All parallel tasks finished!');
    end
  );
end;
```
2. Task with Timeout
Prevent your application from waiting forever if an external API or database stops responding.

```pascal
procedure TForm1.BtnTimeoutClick(Sender: TObject);
begin
  TTokio.WithTimeout(
    procedure(Res: PTaskResult)
    begin
      Sleep(5000); // Simulating a very slow task
      Res^.Success := True;
    end, 
    2000, // Maximum wait time in milliseconds (2 seconds)
    procedure(R: TTaskResult)
    begin
      if R.Success then
        ShowMessage('Finished in time!')
      else
        ShowMessage('Task failed or timed out: ' + string(R.ErrorMessage));
    end
  );
end;
```

3. Manual Cancellation (Cancel Tokens)
You can cancel ongoing tasks at any time, which is especially useful when the user closes a form or clicks a "Cancel" button.

```pascal
var
  MyToken: ICancelToken; // Declare globally or in your Form class

procedure TForm1.BtnStartClick(Sender: TObject);
begin
  MyToken := TTokio.CreateCancelToken;

  TTokio.RunAsync(
    procedure(Res: PTaskResult)
    var
      I: Integer;
    begin
      for I := 1 to 100 do
      begin
        // Check if the user requested a cancellation
        if MyToken.IsCancelled then Exit;
        Sleep(50); 
      end;
      Res^.Success := True;
    end,
    procedure(R: TTaskResult)
    begin
      if R.Success then
        ShowMessage('Completed!')
      else
        ShowMessage('Cancelled by the user.');
    end
  );
end;

procedure TForm1.BtnCancelClick(Sender: TObject);
begin
  if Assigned(MyToken) then
    MyToken.Cancel; // Signals the Rust thread to stop
end;
```

🏗️ Architecture & Memory Rules
  
  Rust Core: Exposes C-compatible functions (cdecl) that encapsulate a persistent Tokio runtime (Singleton).

  Delphi Abstraction: Tokio.Async.Bridge.pas provides high-level APIs that manage closures, heap allocations, and thread synchronization via TThread.Queue.


⚠️ Important Rules
  
  Thread-Safety: Never manipulate VCL/FMX components inside the background closure (Res: PTaskResult). Only touch the UI in the OnFinish callback.

  Data Ownership: If you pass custom data via Res^.DataPtr, the caller is responsible for freeing that memory in the OnFinish callback.

  Form Destruction: Always call .Cancel on your active ICancelTokens in your Form's OnDestroy event to ensure background threads gracefully exit.


🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the issues page.
To compile the Rust core yourself, you will need to install Rust and run:
cargo build --release inside the RustCore/ directory.
