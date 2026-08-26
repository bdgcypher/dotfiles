// Rebalance a pywal palette: dark neutral background, contrasty accents.
// Extracts colors, rebuilds palette, writes colors.json, and regenerates
// templates — all in one process without a scratch dir.
//
// Usage:
//   rebalance-pywal-colorscheme <image>            -> write ~/.cache/wal/colors.json + run wal
//   rebalance-pywal-colorscheme <image> <out.json> -> write to <out.json> only (no wal run)

use serde_json::{json, Map, Value};
use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, Stdio};

fn hex2rgb(h: &str) -> (f64, f64, f64) {
    let h = h.trim_start_matches('#');
    let r = u8::from_str_radix(&h[0..2], 16).unwrap_or(0) as f64;
    let g = u8::from_str_radix(&h[2..4], 16).unwrap_or(0) as f64;
    let b = u8::from_str_radix(&h[4..6], 16).unwrap_or(0) as f64;
    (r, g, b)
}

// round_ties_even matches Python's round() (banker's rounding), keeping the
// palette byte-for-byte identical to the original script.
fn rgb2hex(r: f64, g: f64, b: f64) -> String {
    format!(
        "#{:02x}{:02x}{:02x}",
        r.round_ties_even() as u8,
        g.round_ties_even() as u8,
        b.round_ties_even() as u8
    )
}

// colorsys.rgb_to_hsv / hsv_to_rgb equivalents, channels in 0..=1.
fn to_hsv((r, g, b): (f64, f64, f64)) -> (f64, f64, f64) {
    let (r, g, b) = (r / 255.0, g / 255.0, b / 255.0);
    let maxc = r.max(g).max(b);
    let minc = r.min(g).min(b);
    let v = maxc;
    if minc == maxc {
        return (0.0, 0.0, v);
    }
    let s = (maxc - minc) / maxc;
    let rc = (maxc - r) / (maxc - minc);
    let gc = (maxc - g) / (maxc - minc);
    let bc = (maxc - b) / (maxc - minc);
    let h = if r == maxc {
        bc - gc
    } else if g == maxc {
        2.0 + rc - bc
    } else {
        4.0 + gc - rc
    };
    ((h / 6.0).rem_euclid(1.0), s, v)
}

fn from_hsv(h: f64, s: f64, v: f64) -> String {
    if s == 0.0 {
        return rgb2hex(v * 255.0, v * 255.0, v * 255.0);
    }
    let i = (h * 6.0) as i32;
    let f = h * 6.0 - i as f64;
    let p = v * (1.0 - s);
    let q = v * (1.0 - s * f);
    let t = v * (1.0 - s * (1.0 - f));
    let (r, g, b) = match i.rem_euclid(6) {
        0 => (v, t, p),
        1 => (q, v, p),
        2 => (p, v, t),
        3 => (p, q, v),
        4 => (t, p, v),
        _ => (v, p, q),
    };
    rgb2hex(r * 255.0, g * 255.0, b * 255.0)
}

fn lighten(hexc: &str, amt: f64) -> String {
    let (r, g, b) = hex2rgb(hexc);
    rgb2hex(r + (255.0 - r) * amt, g + (255.0 - g) * amt, b + (255.0 - b) * amt)
}

fn hue_deg(hexc: &str) -> f64 {
    to_hsv(hex2rgb(hexc)).0 * 360.0
}

fn hue_dist(a: f64, b: f64) -> f64 {
    let d = (a - b).abs() % 360.0;
    d.min(360.0 - d)
}

fn accent_score(hexc: &str) -> f64 {
    let (_, s, v) = to_hsv(hex2rgb(hexc));
    s * v
}

// Pick accent colors with hue diversity (port of the Python algorithm).
fn pick_accents(hexes: &[String]) -> Vec<String> {
    let n = 6usize;
    let threshold = 30.0f64;
    let quality = 0.6f64;

    let mut cands: Vec<String> = hexes
        .iter()
        .filter(|h| to_hsv(hex2rgb(h)).2 >= 0.45)
        .cloned()
        .collect();
    cands.sort_by(|a, b| accent_score(b).partial_cmp(&accent_score(a)).unwrap());
    let mut rest: Vec<String> = hexes
        .iter()
        .filter(|h| !cands.contains(h))
        .cloned()
        .collect();
    rest.sort_by(|a, b| to_hsv(hex2rgb(b)).2.partial_cmp(&to_hsv(hex2rgb(a)).2).unwrap());

    let mut pool: Vec<String> = cands;
    pool.extend(rest);
    let mut selected: Vec<String> = vec![pool.remove(0)];

    for _ in 1..n {
        if pool.is_empty() {
            break;
        }
        let best_overall = pool
            .iter()
            .max_by(|a, b| accent_score(a).partial_cmp(&accent_score(b)).unwrap())
            .unwrap()
            .clone();
        let far: Vec<String> = pool
            .iter()
            .filter(|h| {
                selected
                    .iter()
                    .map(|s| hue_dist(hue_deg(h), hue_deg(s)))
                    .fold(f64::INFINITY, f64::min)
                    >= threshold
            })
            .cloned()
            .collect();
        let pick;
        if !far.is_empty() {
            let best_far = far
                .iter()
                .max_by(|a, b| accent_score(a).partial_cmp(&accent_score(b)).unwrap())
                .unwrap()
                .clone();
            let near_best = pool
                .iter()
                .filter(|h| !far.contains(h))
                .map(|h| accent_score(h))
                .fold(0.0f64, f64::max);
            pick = if accent_score(&best_far) >= quality * near_best {
                best_far
            } else {
                best_overall
            };
        } else {
            pick = best_overall;
        }
        if let Some(pos) = pool.iter().position(|x| *x == pick) {
            pool.remove(pos);
        }
        selected.push(pick);
    }
    selected
}

// Scan for every #RRGGBB token (same semantics as the Python regex).
fn extract_hexes(s: &str) -> Vec<String> {
    let bytes = s.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i + 7 <= bytes.len() {
        if bytes[i] == b'#' && s[i + 1..i + 7].bytes().all(|b| b.is_ascii_hexdigit()) {
            out.push(s[i..i + 7].to_string());
            i += 7;
        } else {
            i += 1;
        }
    }
    out
}

// Single ImageMagick call: 16-color palette then 1x1 average.
// Splits on the IM header to parse each block separately.
fn extract_all(img: &str) -> (Vec<String>, String) {
    let out = Command::new("convert")
        .arg(img)
        .args([
            "(", "+clone", "-resize", "25%", "-colors", "16", "-unique-colors", "+write",
            "txt:-", "+delete", ")",
        ])
        .args(["-resize", "1x1!", "txt:-"])
        .stderr(Stdio::null())
        .output()
        .unwrap_or_else(|_| {
            eprintln!("error: could not run ImageMagick convert");
            std::process::exit(1);
        });
    let text = String::from_utf8_lossy(&out.stdout).to_string();
    let blocks: Vec<&str> = text.split("# ImageMagick pixel enumeration:").collect();
    if blocks.len() < 3 {
        eprintln!("error: ImageMagick output parsing failed");
        std::process::exit(1);
    }
    let mut seen = HashSet::new();
    let hexes16: Vec<String> = extract_hexes(blocks[1])
        .into_iter()
        .filter(|h| seen.insert(h.clone()))
        .take(16)
        .collect();
    let avg = extract_hexes(blocks[2]).into_iter().next();
    match (hexes16.is_empty(), avg) {
        (false, Some(avg)) => (hexes16, avg),
        _ => {
            eprintln!("error: failed to extract colors from image");
            std::process::exit(1);
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: rebalance-pywal-colorscheme <image> [colors.json]");
        std::process::exit(1);
    }
    let img = &args[1];

    let default_out = env::var("HOME")
        .map(|h| PathBuf::from(h).join(".cache/wal/colors.json"))
        .unwrap_or_else(|_| PathBuf::from("colors.json"));
    let out_path = args.get(2).map(PathBuf::from).unwrap_or(default_out);
    let run_wal = args.get(2).is_none();

    let (hexes, avg_color) = extract_all(img);
    let h_avg = to_hsv(hex2rgb(&avg_color)).0;

    // Background: dominant hue, low saturation, very dark
    let bg = from_hsv(h_avg, 0.18, 0.09);

    // Accents: vivid colors with hue diversity
    let accents = pick_accents(&hexes);

    let mut colors: Map<String, Value> = Map::new();
    colors.insert("color0".into(), Value::String(bg.clone()));
    for (i, c) in accents.iter().take(6).enumerate() {
        colors.insert(format!("color{}", i + 1), Value::String(c.clone()));
    }
    colors.insert("color7".into(), Value::String(lighten(&bg, 0.55)));
    colors.insert("color8".into(), Value::String(lighten(&bg, 0.35)));
    colors.insert("color15".into(), Value::String(lighten(&bg, 0.75)));
    for (i, c) in accents.iter().take(6).enumerate() {
        colors.insert(format!("color{}", 9 + i), Value::String(lighten(c, 0.25)));
    }

    let fg = lighten(&bg, 0.75);
    let data = json!({
        "wallpaper": fs::canonicalize(img).map(|p| p.to_string_lossy().to_string()).unwrap_or_else(|_| img.to_string()),
        "alpha": "100",
        "colors": Value::Object(colors),
        "special": {
            "background": bg,
            "foreground": fg,
            "cursor": fg,
        },
    });

    if let Some(parent) = out_path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let json = serde_json::to_string_pretty(&data).unwrap();
    fs::write(&out_path, json).unwrap_or_else(|e| {
        eprintln!("error: could not write {}: {}", out_path.display(), e);
        std::process::exit(1);
    });

    // Regenerate all templates from the rebalanced palette (apply path only).
    if run_wal {
        let status = Command::new("wal")
            .args(["--theme", out_path.to_str().unwrap_or(""), "-n"])
            .status();
        if !status.map(|s| s.success()).unwrap_or(false) {
            std::process::exit(1);
        }
    }

    let acc: Vec<String> = accents.iter().map(|a| format!("'{}'", a)).collect();
    println!("rebalanced: bg={}, accents=[{}]", bg, acc.join(", "));
}
