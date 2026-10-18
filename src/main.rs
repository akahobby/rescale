#![cfg_attr(windows, windows_subsystem = "windows")]

#[cfg(not(windows))]
fn main() {
    eprintln!("Rescale runs on Windows only.");
}

#[cfg(windows)]
mod windows_app {
    use std::{env, fs, mem, path::PathBuf, ptr};
    use std::ffi::c_void;
    use std::sync::OnceLock;

    type HWND = *mut c_void;
    type HINSTANCE = *mut c_void;
    type HBRUSH = *mut c_void;
    type HMENU = *mut c_void;
    type WPARAM = usize;
    type LPARAM = isize;
    type LRESULT = isize;

    const WM_CTLCOLORSTATIC: u32 = 0x0138;
    const WM_CTLCOLOREDIT: u32 = 0x0133;
    const WM_CTLCOLORBTN: u32 = 0x0135;
    const WM_DRAWITEM: u32 = 0x002B;
    const BS_OWNERDRAW: u32 = 0x0000000B;
    const TRANSPARENT: i32 = 1;
    const OPAQUE: i32 = 2;
    const DT_CENTER: u32 = 1;
    const DT_VCENTER: u32 = 4;
    const DT_SINGLELINE: u32 = 0x20;
    const DWMWA_USE_IMMERSIVE_DARK_MODE: u32 = 20;
    const BG: u32 = 0x00201813; // COLORREF: #131820
    const SURFACE: u32 = 0x00302A24; // #242A30
    const BUTTON: u32 = 0x003D342C; // #2C343D
    const ACCENT: u32 = 0x00EBAC57; // #57ACEB
    const TEXT: u32 = 0x00F3EDE8; // #E8EDF3
    const WS_OVERLAPPED: u32 = 0;
    const WS_CAPTION: u32 = 0x00C00000;
    const WS_SYSMENU: u32 = 0x00080000;
    const WS_MINIMIZEBOX: u32 = 0x00020000;
    const WS_VISIBLE: u32 = 0x10000000;
    const WS_CHILD: u32 = 0x40000000;
    const WS_TABSTOP: u32 = 0x00010000;
    const WS_BORDER: u32 = 0x00800000;
    const ES_NUMBER: u32 = 0x2000;
    const CBS_DROPDOWNLIST: u32 = 0x0003;
    const WS_VSCROLL: u32 = 0x00200000;
    const BS_PUSHBUTTON: u32 = 0;
    const CW_USEDEFAULT: i32 = i32::MIN;
    const SW_SHOW: i32 = 5;
    const WM_DESTROY: u32 = 0x0002;
    const WM_COMMAND: u32 = 0x0111;
    const WM_SETFONT: u32 = 0x0030;
    const EM_SETLIMITTEXT: u32 = 0x00C5;
    const CB_ADDSTRING: u32 = 0x0143;
    const CB_SETCURSEL: u32 = 0x014E;
    const CB_GETCURSEL: u32 = 0x0147;
    const CBN_SELCHANGE: usize = 1;
    const MB_OK: u32 = 0;
    const MB_ICONERROR: u32 = 0x10;
    const MB_ICONINFORMATION: u32 = 0x40;
    const MB_ICONWARNING: u32 = 0x30;
    const DEFAULT_GUI_FONT: i32 = 17;
    const ENUM_CURRENT_SETTINGS: i32 = -1;
    const DM_BITSPERPEL: u32 = 0x00040000;
    const DM_PELSWIDTH: u32 = 0x00080000;
    const DM_PELSHEIGHT: u32 = 0x00100000;
    const DM_DISPLAYFREQUENCY: u32 = 0x00400000;
    const CDS_TEST: u32 = 2;

    const ID_CAPTURE: usize = 101;
    const ID_PRESETS: usize = 102;
    const ID_WIDTH: usize = 103;
    const ID_HEIGHT: usize = 104;
    const ID_SAVE: usize = 105;
    const ID_GAME: usize = 106;
    const ID_DESKTOP: usize = 107;
    const ID_NATIVE_LABEL: usize = 108;
    const ID_CURRENT_LABEL: usize = 109;

    const PRESETS: [(&str, u32, u32); 8] = [
        ("1440 x 1080  (4:3)", 1440, 1080),
        ("1280 x 960", 1280, 960),
        ("1024 x 768", 1024, 768),
        ("1728 x 1080  (stretched)", 1728, 1080),
        ("1280 x 1024  (5:4)", 1280, 1024),
        ("1152 x 864  (4:3)", 1152, 864),
        ("960 x 720", 960, 720),
        ("1680 x 1050", 1680, 1050),
    ];

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct Point { x: i32, y: i32 }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct Msg {
        hwnd: HWND, message: u32, w_param: WPARAM, l_param: LPARAM,
        time: u32, pt: Point, l_private: u32,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct Rect { left: i32, top: i32, right: i32, bottom: i32 }
    #[repr(C)]
    struct DrawItem {
        ctl_type: u32, ctl_id: u32, item_id: u32, item_action: u32,
        item_state: u32, hwnd_item: HWND, hdc: *mut c_void,
        rc_item: Rect, item_data: usize,
    }
    #[repr(C)]
    struct WndClassW {
        style: u32,
        wnd_proc: Option<unsafe extern "system" fn(HWND, u32, WPARAM, LPARAM) -> LRESULT>,
        cls_extra: i32,
        wnd_extra: i32,
        instance: HINSTANCE,
        icon: *mut c_void,
        cursor: *mut c_void,
        background: HBRUSH,
        menu_name: *const u16,
        class_name: *const u16,
    }

    // Unicode DEVMODEW with its display-only union arm laid out explicitly.
    // Setting dmSize is essential for EnumDisplaySettingsW.
    #[repr(C)]
    struct DevModeW {
        device_name: [u16; 32],
        spec_version: u16,
        driver_version: u16,
        size: u16,
        driver_extra: u16,
        fields: u32,
        position_x: i32,
        position_y: i32,
        orientation: u32,
        fixed_output: u32,
        color: i16,
        duplex: i16,
        y_resolution: i16,
        tt_option: i16,
        collate: i16,
        form_name: [u16; 32],
        log_pixels: u16,
        bits_per_pel: u32,
        pels_width: u32,
        pels_height: u32,
        display_flags: u32,
        display_frequency: u32,
        icm_method: u32,
        icm_intent: u32,
        media_type: u32,
        dither_type: u32,
        reserved1: u32,
        reserved2: u32,
        panning_width: u32,
        panning_height: u32,
    }

    #[link(name = "user32")]
    extern "system" {
        fn RegisterClassW(cls: *const WndClassW) -> u16;
        fn CreateWindowExW(ex: u32, class: *const u16, title: *const u16, style: u32,
            x: i32, y: i32, w: i32, h: i32, parent: HWND, menu: HMENU,
            instance: HINSTANCE, param: *mut c_void) -> HWND;
        fn DefWindowProcW(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT;
        fn ShowWindow(hwnd: HWND, cmd: i32) -> i32;
        fn UpdateWindow(hwnd: HWND) -> i32;
        fn GetMessageW(msg: *mut Msg, hwnd: HWND, min: u32, max: u32) -> i32;
        fn TranslateMessage(msg: *const Msg) -> i32;
        fn DispatchMessageW(msg: *const Msg) -> LRESULT;
        fn PostQuitMessage(code: i32);
        fn SendMessageW(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT;
        fn SetWindowTextW(hwnd: HWND, text: *const u16) -> i32;
        fn GetWindowTextW(hwnd: HWND, text: *mut u16, max: i32) -> i32;
        fn MessageBoxW(hwnd: HWND, text: *const u16, title: *const u16, flags: u32) -> i32;
        fn EnumDisplaySettingsW(device: *const u16, mode: i32, dm: *mut DevModeW) -> i32;
        fn ChangeDisplaySettingsExW(device: *const u16, dm: *mut DevModeW,
            hwnd: HWND, flags: u32, param: *mut c_void) -> i32;
        fn LoadIconW(instance: HINSTANCE, name: *const u16) -> *mut c_void;
        fn FillRect(dc: *mut c_void, rect: *const Rect, brush: HBRUSH) -> i32;
        fn FrameRect(dc: *mut c_void, rect: *const Rect, brush: HBRUSH) -> i32;
        fn DrawTextW(dc: *mut c_void, text: *const u16, length: i32, rect: *mut Rect, format: u32) -> i32;
        fn LoadCursorW(instance: HINSTANCE, cursor: *const u16) -> *mut c_void;
    }
    #[link(name = "kernel32")]
    extern "system" { fn GetModuleHandleW(name: *const u16) -> HINSTANCE; }
    #[link(name = "gdi32")]
    extern "system" {
        fn GetStockObject(object: i32) -> *mut c_void;
        fn CreateSolidBrush(color: u32) -> HBRUSH;
        fn SetTextColor(dc: *mut c_void, color: u32) -> u32;
        fn SetBkColor(dc: *mut c_void, color: u32) -> u32;
        fn SetBkMode(dc: *mut c_void, mode: i32) -> i32;
    }
    #[link(name = "dwmapi")]
    extern "system" { fn DwmSetWindowAttribute(hwnd: HWND, attribute: u32, value: *const i32, size: u32) -> i32; }
    #[link(name = "uxtheme")]
    extern "system" { fn SetWindowTheme(hwnd: HWND, subapp: *const u16, subid: *const u16) -> i32; }
    static mut BG_BRUSH: HBRUSH = ptr::null_mut();
    static mut SURFACE_BRUSH: HBRUSH = ptr::null_mut();
    static mut BUTTON_BRUSH: HBRUSH = ptr::null_mut();
    static mut ACCENT_BRUSH: HBRUSH = ptr::null_mut();

    fn wide(s: &str) -> Vec<u16> { s.encode_utf16().chain(std::iter::once(0)).collect() }

    #[derive(Clone, Copy, Debug)]
    struct Config { native_w: u32, native_h: u32, game_w: u32, game_h: u32 }

    // Accepts the JSON format used by the PowerShell edition, including BOM and whitespace.
    fn read_json_number(json: &str, key: &str) -> Option<u32> {
        let marker = format!("\"{}\"", key);
        let (_, after) = json.split_once(&marker)?;
        let (_, after) = after.split_once(':')?;
        let digits: String = after.trim_start().chars().take_while(|c| c.is_ascii_digit()).collect();
        digits.parse().ok()
    }

    impl Config {
        fn from_json(text: &str) -> Option<Self> {
            let config = Self {
                native_w: read_json_number(text, "NativeWidth")?,
                native_h: read_json_number(text, "NativeHeight")?,
                game_w: read_json_number(text, "GameWidth")?,
                game_h: read_json_number(text, "GameHeight")?,
            };
            if config.native_w < 640 || config.native_h < 480 ||
               config.game_w < 640 || config.game_h < 480 { return None; }
            Some(config)
        }
        fn json(&self) -> String {
            format!("{{\"NativeWidth\":{},\"NativeHeight\":{},\"GameWidth\":{},\"GameHeight\":{}}}\n",
                self.native_w, self.native_h, self.game_w, self.game_h)
        }
    }

    fn app_dir() -> PathBuf {
        env::current_exe().ok().and_then(|p| p.parent().map(|p| p.to_path_buf()))
            .unwrap_or_else(|| PathBuf::from("."))
    }
    fn config_path() -> PathBuf { app_dir().join("rescale.config.json") }
    fn load_config() -> Option<Config> {
        let text = fs::read_to_string(config_path()).ok()?;
        Config::from_json(text.trim_start_matches('\u{feff}'))
    }
    fn save_config(cfg: Config) -> Result<(), String> {
        fs::write(config_path(), cfg.json()).map_err(|e| e.to_string())?;
        // Existing shortcut workflow, now pointing to the native executable.
        for (name, argument) in [
            ("Switch to Game Resolution.bat", "--game"),
            ("Switch to Desktop Resolution.bat", "--desktop"),
        ] {
            let text = format!("@echo off\r\n\"%~dp0rescale.exe\" {}\r\nif errorlevel 1 pause\r\n", argument);
            fs::write(app_dir().join(name), text).map_err(|e| e.to_string())?;
        }
        Ok(())
    }

    fn current_mode() -> Result<DevModeW, String> {
        let mut dm: DevModeW = unsafe { mem::zeroed() };
        dm.size = mem::size_of::<DevModeW>() as u16;
        if unsafe { EnumDisplaySettingsW(ptr::null(), ENUM_CURRENT_SETTINGS, &mut dm) } == 0 {
            return Err("Unable to read primary display settings.".into());
        }
        Ok(dm)
    }

    fn change_resolution(width: u32, height: u32) -> Result<(), String> {
        if !(640..=8192).contains(&width) || !(480..=8192).contains(&height) {
            return Err("Width must be 640–8192 and height must be 480–8192.".into());
        }
        let mut mode = current_mode()?;
        mode.pels_width = width;
        mode.pels_height = height;
        // Match the original app: retain the current color depth and refresh rate.
        mode.fields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL | DM_DISPLAYFREQUENCY;
        let test = unsafe { ChangeDisplaySettingsExW(ptr::null(), &mut mode, ptr::null_mut(), CDS_TEST, ptr::null_mut()) };
        if test != 0 { return Err(display_error(test)); }
        let result = unsafe { ChangeDisplaySettingsExW(ptr::null(), &mut mode, ptr::null_mut(), 0, ptr::null_mut()) };
        if result != 0 { return Err(display_error(result)); }
        Ok(())
    }
    fn display_error(code: i32) -> String {
        match code {
            1 => "Windows requires a restart to use this display mode.".into(),
            -1 => "Windows could not enumerate or apply display settings.".into(),
            -2 => "Display mode unavailable. Add it in NVIDIA Control Panel or CRU first. The current refresh rate may also be unsupported at this resolution.".into(),
            -3 => "Display settings could not be saved.".into(),
            -4 => "Unsupported display flags.".into(),
            -5 => "Display settings contain invalid parameters.".into(),
            -6 => "The system is in a display mode that prevents this change.".into(),
            _ => format!("Windows display API returned error code {}.", code),
        }
    }

    fn alert(owner: HWND, msg: &str, flags: u32) {
        unsafe { MessageBoxW(owner, wide(msg).as_ptr(), wide("Rescale").as_ptr(), MB_OK | flags); }
    }

    struct Ui { native_w: u32, native_h: u32, width: HWND, height: HWND, presets: HWND, native: HWND, current: HWND }
    static mut UI: Option<Ui> = None;
    static INSTANCE: OnceLock<usize> = OnceLock::new();

    unsafe fn control(parent: HWND, class: &str, text: &str, style: u32,
                      x: i32, y: i32, w: i32, h: i32, id: usize) -> HWND {
        let hwnd = CreateWindowExW(0, wide(class).as_ptr(), wide(text).as_ptr(),
            WS_VISIBLE | WS_CHILD | if class == "BUTTON" { (style & !0xF) | BS_OWNERDRAW } else { style }, x, y, w, h, parent, id as HMENU,
            *INSTANCE.get().unwrap() as HINSTANCE, ptr::null_mut());
        let font = GetStockObject(DEFAULT_GUI_FONT);
        SendMessageW(hwnd, WM_SETFONT, font as usize, 1);
        if class == "COMBOBOX" || class == "EDIT" {
            SetWindowTheme(hwnd, wide("DarkMode_Explorer").as_ptr(), ptr::null());
        }
        hwnd
    }
    unsafe fn set_text(hwnd: HWND, value: &str) { SetWindowTextW(hwnd, wide(value).as_ptr()); }
    unsafe fn get_number(hwnd: HWND) -> Result<u32, String> {
        let mut buf = [0u16; 32];
        GetWindowTextW(hwnd, buf.as_mut_ptr(), buf.len() as i32);
        let s = String::from_utf16_lossy(&buf[..buf.iter().position(|&c| c == 0).unwrap_or(buf.len())]);
        s.trim().parse::<u32>().map_err(|_| "Enter a valid number for width and height.".into())
    }
    unsafe fn update_labels() {
        if let Some(ui) = UI.as_ref() {
            set_text(ui.native, &format!("Saved desktop: {} x {}", ui.native_w, ui.native_h));
            if let Ok(dm) = current_mode() {
                set_text(ui.current, &format!("Current display: {} x {}  ·  {} Hz", dm.pels_width, dm.pels_height, dm.display_frequency));
            }
        }
    }
    unsafe fn init_controls(hwnd: HWND) {
        control(hwnd, "STATIC", "RESCALE", 0, 25, 18, 350, 26, 0);
        control(hwnd, "STATIC", "Switch your primary monitor between desktop and game modes.", 0, 25, 48, 455, 22, 0);
        let current = control(hwnd, "STATIC", "Current display:", 0, 25, 88, 455, 23, ID_CURRENT_LABEL);
        let native = control(hwnd, "STATIC", "Saved desktop:", 0, 25, 116, 455, 23, ID_NATIVE_LABEL);
        control(hwnd, "BUTTON", "Capture current as desktop", WS_TABSTOP | BS_PUSHBUTTON, 25, 148, 450, 35, ID_CAPTURE);
        control(hwnd, "STATIC", "GAME RESOLUTION", 0, 25, 209, 300, 20, 0);
        control(hwnd, "STATIC", "Width", 0, 25, 242, 80, 20, 0);
        control(hwnd, "STATIC", "Height", 0, 260, 242, 80, 20, 0);
        let width = control(hwnd, "EDIT", "1440", WS_TABSTOP | WS_BORDER | ES_NUMBER, 25, 266, 205, 29, ID_WIDTH);
        let height = control(hwnd, "EDIT", "1080", WS_TABSTOP | WS_BORDER | ES_NUMBER, 260, 266, 215, 29, ID_HEIGHT);
        SendMessageW(width, EM_SETLIMITTEXT, 4, 0);
        SendMessageW(height, EM_SETLIMITTEXT, 4, 0);
        control(hwnd, "STATIC", "Stretched presets", 0, 25, 316, 260, 20, 0);
        let presets = control(hwnd, "COMBOBOX", "", WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWNLIST,
            25, 341, 450, 260, ID_PRESETS);
        for (label, _, _) in PRESETS { SendMessageW(presets, CB_ADDSTRING, 0, wide(label).as_ptr() as isize); }
        control(hwnd, "STATIC", "Custom modes must be available in your GPU driver (NVIDIA / CRU).", 0, 25, 387, 475, 27, 0);
        control(hwnd, "BUTTON", "Save settings + shortcuts", WS_TABSTOP, 25, 431, 450, 38, ID_SAVE);
        control(hwnd, "BUTTON", "Switch to game", WS_TABSTOP, 25, 482, 216, 41, ID_GAME);
        control(hwnd, "BUTTON", "Restore desktop", WS_TABSTOP, 259, 482, 216, 41, ID_DESKTOP);

        let cfg = load_config();
        let (nw, nh) = if let Some(c) = cfg { (c.native_w, c.native_h) }
            else { current_mode().map(|dm| (dm.pels_width, dm.pels_height)).unwrap_or((0, 0)) };
        if let Some(c) = cfg {
            set_text(width, &c.game_w.to_string());
            set_text(height, &c.game_h.to_string());
        }
        UI = Some(Ui { native_w: nw, native_h: nh, width, height, presets, native, current });
        update_labels();
    }
    unsafe fn handle_command(hwnd: HWND, id: usize, notification: usize) {
        if id == ID_PRESETS && notification == CBN_SELCHANGE {
            if let Some(ui) = UI.as_ref() {
                let index = SendMessageW(ui.presets, CB_GETCURSEL, 0, 0);
                if index >= 0 {
                    if let Some((_, w, h)) = PRESETS.get(index as usize) {
                        set_text(ui.width, &w.to_string());
                        set_text(ui.height, &h.to_string());
                    }
                }
            }
            return;
        }
        match id {
            ID_CAPTURE => {
                match current_mode() {
                    Ok(dm) => {
                        if let Some(ui) = UI.as_mut() {
                            ui.native_w = dm.pels_width;
                            ui.native_h = dm.pels_height;
                        }
                        update_labels();
                    }
                    Err(e) => alert(hwnd, &e, MB_ICONERROR),
                }
            }
            ID_SAVE | ID_GAME | ID_DESKTOP => {
                let Some(ui) = UI.as_ref() else { return; };
                let outcome = (|| -> Result<(), String> {
                    if ui.native_w < 640 || ui.native_h < 480 {
                        return Err("Capture a desktop resolution first.".into());
                    }
                    if id == ID_DESKTOP { return change_resolution(ui.native_w, ui.native_h); }
                    let gw = get_number(ui.width)?;
                    let gh = get_number(ui.height)?;
                    if !(640..=8192).contains(&gw) || !(480..=8192).contains(&gh) {
                        return Err("Game resolution must be at least 640 x 480, up to 8192 x 8192.".into());
                    }
                    if id == ID_GAME { return change_resolution(gw, gh); }
                    save_config(Config { native_w: ui.native_w, native_h: ui.native_h, game_w: gw, game_h: gh })
                })();
                match outcome {
                    Err(e) => alert(hwnd, &e, MB_ICONERROR),
                    Ok(()) if id == ID_SAVE => alert(hwnd, "Saved settings and created two launch shortcuts beside rescale.exe.", MB_ICONINFORMATION),
                    Ok(()) => update_labels(),
                }
            }
            _ => {}
        }
    }
    unsafe extern "system" fn window_proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
        match msg {
            WM_CTLCOLORSTATIC | WM_CTLCOLORBTN => {
                let dc = wp as *mut c_void;
                SetTextColor(dc, TEXT);
                SetBkMode(dc, TRANSPARENT);
                BG_BRUSH as LRESULT
            }
            WM_CTLCOLOREDIT => {
                let dc = wp as *mut c_void;
                SetTextColor(dc, TEXT);
                SetBkColor(dc, SURFACE);
                SetBkMode(dc, OPAQUE);
                SURFACE_BRUSH as LRESULT
            }
            WM_DRAWITEM => {
                let item = &*(lp as *const DrawItem);
                if item.ctl_type == 4 { // ODT_BUTTON
                    let primary = item.ctl_id == ID_SAVE as u32;
                    let color = if primary { ACCENT_BRUSH } else { BUTTON_BRUSH };
                    FillRect(item.hdc, &item.rc_item, color);
                    FrameRect(item.hdc, &item.rc_item, SURFACE_BRUSH);
                    SetTextColor(item.hdc, if primary { BG } else { TEXT });
                    SetBkMode(item.hdc, TRANSPARENT);
                    let mut buf = [0u16; 128];
                    let len = GetWindowTextW(item.hwnd_item, buf.as_mut_ptr(), buf.len() as i32);
                    let mut rect = item.rc_item;
                    DrawTextW(item.hdc, buf.as_ptr(), len, &mut rect, DT_SINGLELINE | DT_CENTER | DT_VCENTER);
                    return 1;
                }
                0
            }
            WM_COMMAND => { handle_command(hwnd, wp & 0xFFFF, (wp >> 16) & 0xFFFF); 0 }
            WM_DESTROY => { PostQuitMessage(0); 0 }
            _ => DefWindowProcW(hwnd, msg, wp, lp),
        }
    }

    fn start_ui() -> Result<(), String> {
        unsafe {
            let instance = GetModuleHandleW(ptr::null());
            BG_BRUSH = CreateSolidBrush(BG);
            SURFACE_BRUSH = CreateSolidBrush(SURFACE);
            BUTTON_BRUSH = CreateSolidBrush(BUTTON);
            ACCENT_BRUSH = CreateSolidBrush(ACCENT);
            INSTANCE.set(instance as usize).ok();
            let class_name = wide("RescaleNativeWindow");
            let wc = WndClassW {
                style: 0, wnd_proc: Some(window_proc), cls_extra: 0, wnd_extra: 0,
                instance, icon: LoadIconW(instance, 1usize as *const u16), cursor: LoadCursorW(ptr::null_mut(), 32512usize as *const u16),
                background: BG_BRUSH, menu_name: ptr::null(), class_name: class_name.as_ptr(),
            };
            if RegisterClassW(&wc) == 0 { return Err("Unable to register the application window.".into()); }
            let hwnd = CreateWindowExW(0, class_name.as_ptr(), wide("Rescale | Resolution Switcher").as_ptr(),
                WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT,
                520, 595, ptr::null_mut(), ptr::null_mut(), instance, ptr::null_mut());
            if hwnd.is_null() { return Err("Unable to create the application window.".into()); }
            let dark: i32 = 1;
            DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, mem::size_of::<i32>() as u32);
            init_controls(hwnd);
            ShowWindow(hwnd, SW_SHOW);
            UpdateWindow(hwnd);
            let mut msg: Msg = mem::zeroed();
            while GetMessageW(&mut msg, ptr::null_mut(), 0, 0) > 0 {
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }
        Ok(())
    }

    pub fn run() {
        let args: Vec<String> = env::args().skip(1).collect();
        let mode = args.iter().find_map(|s| match s.to_ascii_lowercase().as_str() {
            "--game" | "-game" => Some("game"),
            "--desktop" | "-desktop" => Some("desktop"),
            _ => None,
        });
        if let Some(which) = mode {
            let result = load_config().ok_or_else(|| "No valid configuration. Open Rescale to save your settings first.".to_string())
                .and_then(|c| if which == "game" { change_resolution(c.game_w, c.game_h) }
                          else { change_resolution(c.native_w, c.native_h) });
            if let Err(err) = result { alert(ptr::null_mut(), &err, MB_ICONERROR); std::process::exit(1); }
        } else if let Err(err) = start_ui() {
            alert(ptr::null_mut(), &err, MB_ICONERROR);
            std::process::exit(1);
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        #[test] fn parses_existing_config() {
            let cfg = Config::from_json("\u{feff}{\"NativeWidth\":2560,\"NativeHeight\":1440,\"GameWidth\":1440,\"GameHeight\":1080}");
            assert!(cfg.is_some()); // Parser handles a leading UTF-8 BOM.
            let cfg = Config::from_json("{\"NativeWidth\":2560,\"NativeHeight\":1440,\"GameWidth\":1440,\"GameHeight\":1080}").unwrap();
            assert_eq!((cfg.native_w, cfg.game_h), (2560, 1080));
            assert!(Config::from_json(&cfg.json()).is_some());
        }
    }
}

#[cfg(windows)]
fn main() { windows_app::run(); }
