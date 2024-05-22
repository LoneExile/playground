use futures_util::{SinkExt, StreamExt};
use nix::pty::{openpty, OpenptyResult};
use nix::unistd::{close, dup2, fork, read, setsid, write, ForkResult};
use std::os::unix::io::OwnedFd;
use std::os::unix::prelude::AsRawFd;
use std::os::unix::process::CommandExt;
use std::process::Command;
use std::sync::{Arc, Mutex};
use tokio::net::TcpListener;
use tokio_tungstenite::accept_async;

use nix::libc::{ioctl, winsize, TIOCSWINSZ};

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
struct ResizeMessage {
    #[serde(rename = "type")]
    msg_type: String,
    cols: u16,
    rows: u16,
}

/// Function to update terminal size using ioctl
fn set_terminal_size(fd: i32, cols: u16, rows: u16) -> nix::Result<()> {
    let ws = winsize {
        ws_row: rows,
        ws_col: cols,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };

    let res = unsafe { ioctl(fd, TIOCSWINSZ, &ws) };
    if res == 0 {
        Ok(())
    } else {
        Err(nix::Error::last())
    }
}

async fn handle_connection(
    master_fd: OwnedFd,
    stream: tokio_tungstenite::WebSocketStream<tokio::net::TcpStream>,
) {
    let (mut ws_sender, mut ws_receiver) = stream.split();
    let master_fd = Arc::new(Mutex::new(master_fd));

    // Spawn a task to read from the pty and send to websocket
    let master_fd_clone = master_fd.clone();
    tokio::spawn(async move {
        let mut buf = [0u8; 1024];
        loop {
            let fd = master_fd_clone.lock().unwrap().as_raw_fd();
            let n = match read(fd, &mut buf) {
                Ok(n) => {
                    println!("Read {} bytes from PTY", n);
                    n
                }
                Err(e) => {
                    eprintln!("Error reading from PTY: {}", e);
                    break;
                }
            };
            if n == 0 {
                println!("PTY read returned 0 bytes, breaking loop");
                break;
            }
            let output = String::from_utf8_lossy(&buf[..n]).to_string();
            println!("Sending to WebSocket: {}", output);
            if ws_sender
                .send(tokio_tungstenite::tungstenite::Message::Text(output))
                .await
                .is_err()
            {
                eprintln!("Error sending to WebSocket");
                break;
            }
        }
    });

    while let Some(Ok(msg)) = ws_receiver.next().await {
        if let tokio_tungstenite::tungstenite::Message::Text(text) = msg {
            if text.starts_with('{') {
                // Check if the message might be JSON
                if let Ok(resize_msg) = serde_json::from_str::<ResizeMessage>(&text) {
                    if resize_msg.msg_type == "resize" {
                        let fd = master_fd.lock().unwrap().as_raw_fd();
                        set_terminal_size(fd, resize_msg.cols, resize_msg.rows)
                            .expect("Resize failed");
                    }
                }
            } else {
                for byte in text.as_bytes() {
                    if let Err(e) = write(&*master_fd.lock().unwrap(), &[*byte]) {
                        eprintln!("Error writing to PTY: {}", e);
                    }
                }
            }
        }
    }
}

#[tokio::main]
async fn main() {
    // Create a TCP listener bound to port 8080
    let listener = TcpListener::bind("127.0.0.1:8080").await.unwrap();
    println!("Listening on: 127.0.0.1:8080");

    while let Ok((stream, _)) = listener.accept().await {
        // Accept the WebSocket connection
        let ws_stream = accept_async(stream).await.expect("Failed to accept");

        // Create a pty
        let OpenptyResult { master, slave } = openpty(None, None).unwrap();
        println!(
            "PTY created with master fd: {:?} and slave fd: {:?}",
            master, slave
        );

        // Fork the process
        match unsafe { fork() }.unwrap() {
            ForkResult::Parent { .. } => {
                // Close the slave fd in the parent process
                close(slave.as_raw_fd()).unwrap();
                // Handle the WebSocket connection
                tokio::spawn(handle_connection(master, ws_stream));
            }
            ForkResult::Child => {
                // Create a new session and set the controlling terminal
                setsid().unwrap();
                // Make the child process the leader of the terminal
                dup2(slave.as_raw_fd(), 0).unwrap();
                dup2(slave.as_raw_fd(), 1).unwrap();
                dup2(slave.as_raw_fd(), 2).unwrap();
                close(slave.as_raw_fd()).unwrap();

                // Execute the shell
                Command::new("bash").exec();
            }
        }
    }
}
