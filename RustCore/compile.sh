#!/bin/bash

# Cria a pasta de saída se não existir
mkdir -p ./dist

echo "1/3 Compilando para Windows 64-bit..."
cargo build --release --target x86_64-pc-windows-gnu
cp target/x86_64-pc-windows-gnu/release/tokio4delphi.dll ./dist/tokio4delphi_x64.dll

echo "2/3 Compilando para Windows 32-bit..."
cargo build --release --target i686-pc-windows-gnu
cp target/i686-pc-windows-gnu/release/tokio4delphi.dll ./dist/tokio4delphi_x86.dll

echo "3/3 Compilando para Linux 64-bit..."
cargo build --release --target x86_64-unknown-linux-gnu
cp target/x86_64-unknown-linux-gnu/release/libtokio4delphi.so ./dist/libtokio4delphi.so

echo "--------------------------------------------------"
echo "Concluído! Verifique a pasta ./dist/"
ls -lh ./dist/