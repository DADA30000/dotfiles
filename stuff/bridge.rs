use std::env;
use std::fs;
use std::io;
use std::net::{Shutdown, TcpListener, TcpStream};
use std::os::unix::net::{UnixListener, UnixStream};
use std::thread;
use std::time::Duration;

fn handle_connection(tcp_stream: TcpStream, unix_stream: UnixStream) {
    let _ = tcp_stream.set_nodelay(true);

    if let (Ok(mut t_read), Ok(mut u_read)) = (tcp_stream.try_clone(), unix_stream.try_clone()) {
        let mut t_write = tcp_stream;
        let mut u_write = unix_stream;

        thread::spawn(move || {
            let _ = io::copy(&mut t_read, &mut u_write);
            let _ = u_write.shutdown(Shutdown::Write);
        });

        thread::spawn(move || {
            let _ = io::copy(&mut u_read, &mut t_write);
            let _ = t_write.shutdown(Shutdown::Write);
        });
    }
}

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    let mode = args.get(1).expect("Missing mode");
    let listen_addr = args.get(2).expect("Missing listen_addr");
    let connect_addr = args.get(3).expect("Missing connect_addr");

    if mode == "host" {
        let _ = fs::remove_file(listen_addr);
        let listener = UnixListener::bind(listen_addr)?;
        for stream in listener.incoming() {
            if let Ok(unix_stream) = stream {
                let connect_addr = connect_addr.clone();
                thread::spawn(move || {
                    if let Ok(tcp_stream) = TcpStream::connect(&connect_addr) {
                        handle_connection(tcp_stream, unix_stream);
                    }
                });
            }
        }
    } else {
        let listener = TcpListener::bind(listen_addr)?;
        for stream in listener.incoming() {
            if let Ok(tcp_stream) = stream {
                let connect_addr = connect_addr.clone();
                thread::spawn(move || {
                    let mut unix_stream = None;
                    for _ in 0..50 {
                        if let Ok(u) = UnixStream::connect(&connect_addr) {
                            unix_stream = Some(u);
                            break;
                        }
                        thread::sleep(Duration::from_millis(100));
                    }

                    if let Some(u) = unix_stream {
                        handle_connection(tcp_stream, u);
                    }
                });
            }
        }
    }
    Ok(())
}
