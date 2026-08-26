// Watch Hyprland events and signal waybar to refresh the tiling-direction and
// workspace-layout indicators on focus, window, and workspace changes.
// Also handles the scrolling "consume next" flag: when armed for a workspace,
// the next tiled window that opens there is moved into the active column
// (directly below the previously focused window) instead of a new column.

use std::env;
use std::fs;
use std::io::{BufRead, BufReader, ErrorKind};
use std::os::unix::net::UnixStream;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

const CONSUME_FILE: &str = "/tmp/scrolling-consume";

// Events that can affect the tiling/layout indicators. windowtitle is
// deliberately excluded — it fires constantly and would hammer waybar.
const RELEVANT: &[&str] = &[
    "activewindow",
    "activewindowv2",
    "openwindow",
    "closewindow",
    "movewindow",
    "workspace",
    "fullscreen",
    "changefloatingmode",
];

fn uid() -> u32 {
    fs::read_to_string("/proc/self/status")
        .unwrap_or_default()
        .lines()
        .find_map(|l| l.strip_prefix("Uid:"))
        .and_then(|s| s.split_whitespace().next())
        .and_then(|s| s.parse().ok())
        .unwrap_or(1000)
}

fn signal_waybar() {
    for sig in ["-RTMIN+10", "-RTMIN+11"] {
        let _ = Command::new("pkill")
            .arg(sig)
            .arg("waybar")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
    }
}

fn eval_cmd(lua: &str) {
    let _ = Command::new("hyprctl")
        .arg("eval")
        .arg(lua)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

fn query_clients() -> Vec<serde_json::Value> {
    let out = Command::new("hyprctl")
        .args(["clients", "-j"])
        .output();
    match out {
        Ok(o) if o.status.success() => serde_json::from_slice(&o.stdout).unwrap_or_default(),
        _ => Vec::new(),
    }
}

fn norm_addr(a: &str) -> String {
    a.trim().to_lowercase().trim_start_matches("0x").to_string()
}

fn is_armed(ws: i64) -> bool {
    fs::read_to_string(CONSUME_FILE)
        .map(|s| s.lines().any(|l| l.trim() == ws.to_string()))
        .unwrap_or(false)
}

fn unarm(ws: i64) {
    if let Ok(contents) = fs::read_to_string(CONSUME_FILE) {
        let remaining: Vec<&str> = contents
            .lines()
            .filter(|l| l.trim() != ws.to_string())
            .collect();
        let text = remaining.join("\n");
        let _ = fs::write(CONSUME_FILE, if text.is_empty() { String::new() } else { text + "\n" });
    }
}

fn cursor_pos() -> Option<(i64, i64)> {
    let out = Command::new("hyprctl").arg("cursorpos").output().ok()?;
    let s = String::from_utf8_lossy(&out.stdout);
    let (x, y) = s.trim().split_once(',')?;
    Some((x.trim().parse().ok()?, y.trim().parse().ok()?))
}

fn consume_new_window(new_addr: &str, ws: i64, anchor_addr: &str) {
    thread::sleep(Duration::from_millis(150)); // let the new window map and the layout place it

    let wins = query_clients();
    let new_addr = norm_addr(new_addr);
    let anchor_addr = norm_addr(anchor_addr);

    let new_win = wins
        .iter()
        .find(|w| norm_addr(w["address"].as_str().unwrap_or("")) == new_addr);
    let Some(new_win) = new_win else {
        return; // window gone — keep the flag armed
    };
    if new_win["floating"].as_bool().unwrap_or(false) {
        return; // floating — keep the flag armed
    }
    if anchor_addr.is_empty() || anchor_addr == new_addr {
        return; // no reliable anchor — keep the flag armed
    }

    let anchor = wins
        .iter()
        .find(|w| norm_addr(w["address"].as_str().unwrap_or("")) == anchor_addr);
    let Some(anchor) = anchor else {
        return; // anchor gone — keep the flag armed
    };
    if anchor["floating"].as_bool().unwrap_or(false) {
        return; // anchor floating — keep the flag armed
    }
    if anchor["workspace"]["id"].as_i64() != Some(ws) {
        return; // anchor not on the armed workspace — keep the flag armed
    }

    let (Some(ax), Some(ay)) = (
        anchor["at"].get(0).and_then(|v| v.as_i64()),
        anchor["at"].get(1).and_then(|v| v.as_i64()),
    ) else {
        return;
    };
    let (Some(sx), Some(sy)) = (
        anchor["size"].get(0).and_then(|v| v.as_i64()),
        anchor["size"].get(1).and_then(|v| v.as_i64()),
    ) else {
        return;
    };
    let cx = ax + sx / 2;
    let cy = ay + sy / 2;

    // Save the cursor, warp it to the anchor's center (the column insert uses
    // the cursor height), move the new window into the anchor's column, then
    // restore the cursor.
    let orig = cursor_pos();
    eval_cmd(&format!("hl.dispatch(hl.dsp.cursor.move({{ x = {cx}, y = {cy} }}))"));
    thread::sleep(Duration::from_millis(50));
    eval_cmd(&format!(
        "hl.dispatch(hl.dsp.window.move({{ direction = 'l', window = 'address:0x{new_addr}' }}))"
    ));
    thread::sleep(Duration::from_millis(100));
    if let Some((ox, oy)) = orig {
        eval_cmd(&format!("hl.dispatch(hl.dsp.cursor.move({{ x = {ox}, y = {oy} }}))"));
    }

    unarm(ws);
    signal_waybar();
}

// Debounces bursts of related events (e.g. openwindow + activewindow fire
// together) into a single signal, trailing-edge so the module reads the
// settled state. Scheduling again flips the previous timer's flag so it
// bails instead of firing.
struct Debouncer {
    handle: Mutex<Option<(Arc<AtomicBool>, thread::JoinHandle<()>)>>,
}

impl Debouncer {
    fn new() -> Self {
        Self {
            handle: Mutex::new(None),
        }
    }

    fn schedule(&self) {
        if let Some((flag, _handle)) = self.handle.lock().unwrap().take() {
            flag.store(false, Ordering::SeqCst);
        }
        let flag = Arc::new(AtomicBool::new(true));
        let f = flag.clone();
        let handle = thread::spawn(move || {
            thread::sleep(Duration::from_millis(150));
            if f.load(Ordering::SeqCst) {
                signal_waybar();
            }
        });
        *self.handle.lock().unwrap() = Some((flag, handle));
    }
}

fn main() {
    let inst = env::var("HYPRLAND_INSTANCE_SIGNATURE").unwrap_or_default();
    let sock_path = format!("/run/user/{}/hypr/{}/.socket2.sock", uid(), inst);

    let debouncer = Debouncer::new();
    let mut last_active = String::new();

    loop {
        let sock = match UnixStream::connect(&sock_path) {
            Ok(s) => s,
            Err(_) => {
                thread::sleep(Duration::from_secs(1));
                continue;
            }
        };
        let _ = sock.set_read_timeout(Some(Duration::from_secs(30)));
        let mut reader = BufReader::new(sock);
        let mut line = String::new();
        loop {
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) => break, // EOF — reconnect
                Ok(_) => {}
                Err(e) => {
                    if e.kind() == ErrorKind::WouldBlock || e.kind() == ErrorKind::TimedOut {
                        continue; // read timeout — no-op, keep listening
                    }
                    break;
                }
            }
            let trimmed = line.trim_end();
            let (event, args) = match trimmed.split_once(">>") {
                Some((e, a)) => (e.to_string(), a.to_string()),
                None => (trimmed.to_string(), String::new()),
            };

            if event == "activewindowv2" && !args.is_empty() {
                last_active = args.trim().to_string();
            } else if event == "openwindow" && !args.is_empty() {
                // openwindow>>address,workspace,class,title
                let fields: Vec<&str> = args.split(',').collect();
                if fields.len() >= 2 {
                    let new_addr = fields[0].trim().to_string();
                    if let Ok(ws) = fields[1].trim().parse::<i64>() {
                        if is_armed(ws) {
                            let anchor = last_active.clone();
                            thread::spawn(move || consume_new_window(&new_addr, ws, &anchor));
                        }
                    }
                }
            }

            if RELEVANT.contains(&event.as_str()) {
                debouncer.schedule();
            }
        }
    }
}
