use cairo::{Context, Format, ImageSurface};
use pango::FontDescription;
use pangocairo::functions::create_layout;
use std::env;

fn truncate_to_fit(text: &str, font_desc: &str, max_width_px: i32) -> String {
    let surface = ImageSurface::create(Format::ARgb32, 0, 0).expect("Could not create surface");
    let context = Context::new(&surface).expect("Could not create context");
    let layout = create_layout(&context);

    let desc = FontDescription::from_string(font_desc);
    layout.set_font_description(Some(&desc));
    layout.set_text(text);

    let (width, _) = layout.pixel_size();
    if width <= max_width_px {
        return text.to_string();
    }

    let chars: Vec<char> = text.chars().collect();
    let mut low = 0;
    let mut high = chars.len();
    let mut best_fit = chars.iter().take(1).collect::<String>() + "...";

    while low <= high {
        let mid = usize::midpoint(low, high);
        let candidate = chars.iter().take(mid).collect::<String>() + "...";
        layout.set_text(&candidate);
        let (w, _) = layout.pixel_size();

        if w <= max_width_px {
            best_fit = candidate;
            low = mid + 1;
        } else {
            if mid == 0 {
                break;
            }
            high = mid - 1;
        }
    }

    best_fit
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: notify-trunc <MAX_PX> <FONT> <LINE1> [LINE2 ...]");
        std::process::exit(1);
    }

    let max_px: i32 = args[1].parse().unwrap_or(0);
    let font = &args[2];

    for line in &args[3..] {
        println!("{}", truncate_to_fit(line, font, max_px));
    }
}
