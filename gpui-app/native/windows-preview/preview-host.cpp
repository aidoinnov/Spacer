// Read-only preview adapter. No document is launched or executed.
// Registered shell handlers run through their out-of-process COM server.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlwapi.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <propsys.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <atomic>
#include <algorithm>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>
using Microsoft::WRL::ComPtr;

namespace {
std::wstring native_path(const std::wstring& path) {
    if(path.rfind(L"\\\\?\\",0)==0) return path;
    if(path.rfind(L"\\\\",0)==0) return L"\\\\?\\UNC\\"+path.substr(2);
    if(path.size()>2 && path[1]==L':') return L"\\\\?\\"+path;
    return path;
}
HWND owner_window(DWORD parent) {
    struct Search {DWORD parent;HWND result=nullptr;} search{parent};
    EnumWindows([](HWND window,LPARAM value)->BOOL {
        auto& current=*reinterpret_cast<Search*>(value);DWORD process=0;
        GetWindowThreadProcessId(window,&process);
        if(process==current.parent && IsWindowVisible(window) && !GetWindow(window,GW_OWNER)) {current.result=window;return FALSE;}
        return TRUE;
    },reinterpret_cast<LPARAM>(&search));
    return search.result;
}
constexpr size_t text_limit = 1024 * 1024;
constexpr uint64_t pixel_limit = 32ull * 1024 * 1024;
constexpr wchar_t preview_iid[] = L"{8895b1c6-b41f-4c1c-a562-0d564250836f}";

struct Handle {
    HANDLE value = nullptr;
    explicit Handle(HANDLE value = nullptr) : value(value) {}
    ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
    Handle(const Handle&) = delete;
    Handle& operator=(const Handle&) = delete;
};
struct ComApartment {
    HRESULT result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    ~ComApartment() { if (SUCCEEDED(result)) CoUninitialize(); }
};
class PreviewSite final : public IPreviewHandlerFrame, public IOleWindow {
    std::atomic<ULONG> refs{1};
    HWND window;
public:
    explicit PreviewSite(HWND window) : window(window) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (iid == IID_IUnknown || iid == __uuidof(IPreviewHandlerFrame)) *out = static_cast<IPreviewHandlerFrame*>(this);
        else if (iid == IID_IOleWindow) *out = static_cast<IOleWindow*>(this);
        else return E_NOINTERFACE;
        AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
    ULONG STDMETHODCALLTYPE Release() override { const auto count = --refs; if (!count) delete this; return count; }
    HRESULT STDMETHODCALLTYPE GetWindowContext(PREVIEWHANDLERFRAMEINFO* info) override {
        if (!info) return E_POINTER;
        info->haccel = nullptr; info->cAccelEntries = 0; return S_OK;
    }
    HRESULT STDMETHODCALLTYPE TranslateAccelerator(MSG* message) override {
        if (message && message->message == WM_KEYDOWN && (message->wParam == VK_ESCAPE || message->wParam == VK_SPACE)) {
            PostMessageW(window, WM_CLOSE, 0, 0); return S_OK;
        }
        return S_FALSE;
    }
    HRESULT STDMETHODCALLTYPE GetWindow(HWND* out) override { if (!out) return E_POINTER; *out = window; return S_OK; }
    HRESULT STDMETHODCALLTYPE ContextSensitiveHelp(BOOL) override { return E_NOTIMPL; }
};
class ShellPreview {
    ComPtr<IPreviewHandler> handler;
    ComPtr<IObjectWithSite> object_site;
    ComPtr<PreviewSite> site;
    ComPtr<IStream> stream;
    bool initialized = false;
public:
    ~ShellPreview() { unload(); }
    void unload() {
        if (handler && initialized) handler->Unload();
        if (object_site) object_site->SetSite(nullptr);
        object_site.Reset(); handler.Reset(); stream.Reset(); site.Reset(); initialized = false;
    }
    bool show(HWND parent, const std::wstring& path) {
        wchar_t identifier[128]{}; DWORD length = ARRAYSIZE(identifier);
        if (FAILED(AssocQueryStringW(ASSOCF_INIT_DEFAULTTOSTAR, ASSOCSTR_SHELLEXTENSION,
                                    PathFindExtensionW(path.c_str()), preview_iid, identifier, &length))) return false;
        CLSID clsid{};
        if (FAILED(CLSIDFromString(identifier, &clsid))) return false;
        // Do not load a registered preview DLL into either GPUI or this host.
        if (FAILED(CoCreateInstance(clsid, nullptr, CLSCTX_LOCAL_SERVER, IID_PPV_ARGS(&handler)))) return false;
        ComPtr<IInitializeWithStream> by_stream;
        if (SUCCEEDED(handler.As(&by_stream))) {
            if (FAILED(SHCreateStreamOnFileEx(native_path(path).c_str(), STGM_READ | STGM_SHARE_DENY_NONE, FILE_ATTRIBUTE_NORMAL, FALSE, nullptr, &stream)) ||
                FAILED(by_stream->Initialize(stream.Get(), STGM_READ))) { unload(); return false; }
        } else {
            ComPtr<IInitializeWithFile> by_file;
            if (FAILED(handler.As(&by_file)) || FAILED(by_file->Initialize(native_path(path).c_str(), STGM_READ))) { unload(); return false; }
        }
        initialized = true;
        site.Attach(new PreviewSite(parent));
        if (SUCCEEDED(handler.As(&object_site))) object_site->SetSite(static_cast<IPreviewHandlerFrame*>(site.Get()));
        ComPtr<IPreviewHandlerVisuals> visuals;
        if (SUCCEEDED(handler.As(&visuals))) { visuals->SetBackgroundColor(RGB(14,19,24)); visuals->SetTextColor(RGB(220,227,231)); }
        RECT rect{}; GetClientRect(parent, &rect);
        if (FAILED(handler->SetWindow(parent, &rect)) || FAILED(handler->DoPreview())) { unload(); return false; }
        return true;
    }
    void resize(const RECT& rect) { if (handler) handler->SetRect(&rect); }
};
struct Image {
    UINT width = 0, height = 0;
    std::vector<BYTE> pixels;
    bool load(const std::wstring& path) {
        ComPtr<IWICImagingFactory> factory; ComPtr<IWICBitmapDecoder> decoder;
        ComPtr<IWICBitmapFrameDecode> frame; ComPtr<IWICFormatConverter> converter;
        if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory))) ||
            FAILED(factory->CreateDecoderFromFilename(native_path(path).c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder)) ||
            FAILED(decoder->GetFrame(0, &frame)) || FAILED(frame->GetSize(&width, &height))) return false;
        if (!width || !height || uint64_t(width)*height > pixel_limit) return false;
        if (FAILED(factory->CreateFormatConverter(&converter)) ||
            FAILED(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppBGR, WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom))) return false;
        pixels.resize(size_t(width)*height*4);
        return SUCCEEDED(converter->CopyPixels(nullptr, width*4, static_cast<UINT>(pixels.size()), pixels.data()));
    }
    void paint(HDC dc, const RECT& rect) const {
        const auto scale = (std::min)(double(rect.right)/width, double(rect.bottom)/height);
        const int w = (std::max)(1,int(width*scale)), h = (std::max)(1,int(height*scale));
        BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = width; info.bmiHeader.biHeight = -LONG(height);
        info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
        SetStretchBltMode(dc, HALFTONE);
        StretchDIBits(dc, (rect.right-w)/2, (rect.bottom-h)/2, w,h, 0,0,width,height,pixels.data(),&info,DIB_RGB_COLORS,SRCCOPY);
    }
};
bool text_extension(const std::wstring& path) {
    std::wstring ext = PathFindExtensionW(path.c_str());
    std::transform(ext.begin(),ext.end(),ext.begin(),towlower);
    const wchar_t* types[] = {L".txt",L".md",L".rs",L".swift",L".c",L".h",L".cpp",L".hpp",L".json",L".toml",L".yaml",L".yml",L".xml",L".csv",L".log",L".css",L".js",L".ts",L".tsx",L".jsx",L".html",L".py",L".go",L".ini",L".sql"};
    for (auto type : types) if (ext == type) return true;
    return false;
}
bool read_text(const std::wstring& path, std::wstring& text) {
    Handle file(CreateFileW(native_path(path).c_str(), GENERIC_READ, FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
    if (file.value == INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER size{}; if (!GetFileSizeEx(file.value,&size) || size.QuadPart < 0) return false;
    std::vector<char> bytes((std::min)(uint64_t(size.QuadPart),uint64_t(text_limit)));
    DWORD count = 0; if (!bytes.empty() && !ReadFile(file.value,bytes.data(),DWORD(bytes.size()),&count,nullptr)) return false;
    bytes.resize(count);
    if(bytes.empty()) {text.clear();return true;}
    if (count >= 2 && ((BYTE(bytes[0])==0xff && BYTE(bytes[1])==0xfe) || (BYTE(bytes[0])==0xfe && BYTE(bytes[1])==0xff))) {
        const bool little = BYTE(bytes[0])==0xff;
        for (size_t i=2;i+1<bytes.size();i+=2) text.push_back(wchar_t(little ? BYTE(bytes[i])|(BYTE(bytes[i+1])<<8) : (BYTE(bytes[i])<<8)|BYTE(bytes[i+1])));
    } else {
        size_t offset = count>=3 && BYTE(bytes[0])==0xef && BYTE(bytes[1])==0xbb && BYTE(bytes[2])==0xbf ? 3 : 0;
        int length=int(bytes.size()-offset), units=0;
        for (int trim=0;trim<4 && length>=0;++trim,--length) {
            units=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,bytes.data()+offset,length,nullptr,0);
            if (units || length==0 || uint64_t(size.QuadPart)<=text_limit) break;
        }
        if (!units && length) return false;
        text.resize(units);
        if (units) MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,bytes.data()+offset,length,text.data(),units);
    }
    if (text.find(L'\0')!=std::wstring::npos) return false;
    if (uint64_t(size.QuadPart)>text_limit) text += L"\r\n\r\n[미리보기는 처음 1 MiB까지 표시합니다.]";
    std::wstring normalized; normalized.reserve(text.size());
    for (size_t i=0;i<text.size();++i) { if(text[i]==L'\n' && (!i || text[i-1]!=L'\r')) normalized+=L'\r'; normalized+=text[i]; }
    text=std::move(normalized); return true;
}
std::wstring metadata(const std::wstring& path) {
    std::wstring result = path + L"\r\n\r\n";
    WIN32_FILE_ATTRIBUTE_DATA info{};
    if (!GetFileAttributesExW(native_path(path).c_str(),GetFileExInfoStandard,&info)) return result+L"파일 정보를 읽을 수 없습니다.";
    if (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
        result += L"폴더 · 처음 100개 항목\r\n\r\n";
        WIN32_FIND_DATAW entry{}; const auto glob=native_path(path)+L"\\*";
        HANDLE search=FindFirstFileW(glob.c_str(),&entry);
        if (search!=INVALID_HANDLE_VALUE) {
            int count=0;
            do { if (wcscmp(entry.cFileName,L".") && wcscmp(entry.cFileName,L"..")) {result+=entry.cFileName;result+=L"\r\n";++count;} } while(count<100 && FindNextFileW(search,&entry));
            FindClose(search);
        }
    } else {
        result += std::to_wstring((uint64_t(info.nFileSizeHigh)<<32)|info.nFileSizeLow)+L" bytes\r\n\r\n이 파일 형식의 콘텐츠 미리보기를 제공하는 처리기가 없습니다.";
    }
    return result;
}
struct PreviewWindow {
    std::wstring path;
    HWND window=nullptr, editor=nullptr;
    HFONT font=nullptr;
    ShellPreview shell;
    Image image;
    std::string renderer="metadata";
    bool ready=false;
    HANDLE parent=nullptr;
    explicit PreviewWindow(std::wstring path,HANDLE parent):path(std::move(path)),parent(parent) {}
    ~PreviewWindow() { shell.unload(); if(font)DeleteObject(font); }
    void initialize() {
        std::wstring text;
        // Bounded built-in readers provide consistent text/image support even
        // when no optional shell handler is registered.
        if (text_extension(path) && read_text(path,text)) renderer="text";
        else if (image.load(path)) renderer="image";
        else if (shell.show(window,path)) renderer="shell";
        else text=metadata(path);
        if (renderer=="text" || renderer=="metadata") {
            editor=CreateWindowExW(0,L"EDIT",text.c_str(),WS_CHILD|WS_VISIBLE|WS_VSCROLL|WS_HSCROLL|ES_MULTILINE|ES_READONLY|ES_AUTOVSCROLL,0,0,0,0,window,nullptr,GetModuleHandleW(nullptr),nullptr);
            font=CreateFontW(-16,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,FF_MODERN,L"Consolas");
            SendMessageW(editor,WM_SETFONT,reinterpret_cast<WPARAM>(font),TRUE);
            SendMessageW(editor,EM_SETLIMITTEXT,0,0);
        }
        RECT rect{};GetClientRect(window,&rect);resize(rect);ready=true;
        InvalidateRect(window,nullptr,TRUE);UpdateWindow(window);
        std::cout << "{\"type\":\"ready\",\"renderer\":\"" << renderer << "\",\"visible\":" << (IsWindowVisible(window)?"true":"false") << ",\"width\":" << rect.right << ",\"height\":" << rect.bottom << ",\"hwnd\":" << uint64_t(reinterpret_cast<uintptr_t>(window)) << "}" << std::endl;
    }
    void resize(const RECT& rect) { if(editor)MoveWindow(editor,12,12,(std::max)(0L,rect.right-24),(std::max)(0L,rect.bottom-24),TRUE);shell.resize(rect); }
};
LRESULT CALLBACK window_proc(HWND hwnd,UINT message,WPARAM w,LPARAM l) {
    auto* view=reinterpret_cast<PreviewWindow*>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));
    if(message==WM_NCCREATE) {view=static_cast<PreviewWindow*>(reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams);view->window=hwnd;SetWindowLongPtrW(hwnd,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(view));}
    if(!view)return DefWindowProcW(hwnd,message,w,l);
    switch(message) {
    case WM_SIZE: {RECT rect{};GetClientRect(hwnd,&rect);view->resize(rect);InvalidateRect(hwnd,nullptr,TRUE);return 0;}
    case WM_PAINT: {PAINTSTRUCT paint{};HDC dc=BeginPaint(hwnd,&paint);RECT rect{};GetClientRect(hwnd,&rect);FillRect(dc,&rect,reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));if(!view->ready){SetBkMode(dc,TRANSPARENT);SetTextColor(dc,RGB(220,227,231));DrawTextW(dc,L"미리보기를 준비하는 중...",-1,&rect,DT_CENTER|DT_VCENTER|DT_SINGLELINE);}if(view->renderer=="image")view->image.paint(dc,rect);EndPaint(hwnd,&paint);return 0;}
    case WM_KEYDOWN: if(w==VK_ESCAPE || w==VK_SPACE) {DestroyWindow(hwnd);return 0;}break;
    case WM_TIMER: if(view->parent && WaitForSingleObject(view->parent,0)==WAIT_OBJECT_0)DestroyWindow(hwnd);return 0;
    case WM_CLOSE: DestroyWindow(hwnd);return 0;
    case WM_DESTROY: view->shell.unload();PostQuitMessage(0);return 0;
    }
    return DefWindowProcW(hwnd,message,w,l);
}
} // namespace

int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR,int) {
    int argc=0;wchar_t** args=CommandLineToArgvW(GetCommandLineW(),&argc);
    if(!args || (argc!=3 && argc!=4)) {if(args)LocalFree(args);return 64;}
    const std::wstring path=args[1];const auto parent_id=wcstoul(args[2],nullptr,10);const bool quiet=argc==4 && wcscmp(args[3],L"quiet")==0;LocalFree(args);
    Handle parent(OpenProcess(SYNCHRONIZE,FALSE,parent_id));
    if(!parent.value)return 65;
    ComApartment apartment;if(FAILED(apartment.result))return 66;
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    WNDCLASSW klass{};klass.lpfnWndProc=window_proc;klass.hInstance=instance;klass.lpszClassName=L"SpaceSnifferPreviewHost";klass.hCursor=LoadCursorW(nullptr,IDC_ARROW);
    if(!RegisterClassW(&klass))return 67;
    PreviewWindow view(path,parent.value);
    const auto title=std::wstring(L"Space Sniffer — 미리보기 · ")+PathFindFileNameW(path.c_str());
    HWND window=CreateWindowExW(WS_EX_TOOLWINDOW,klass.lpszClassName,title.c_str(),WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,900,700,owner_window(parent_id),nullptr,instance,&view);
    if(!window)return 68;
    ShowWindow(window,quiet ? SW_SHOWNOACTIVATE : SW_SHOWNORMAL);UpdateWindow(window);SetTimer(window,1,100,nullptr);
    view.initialize();
    MSG message{};
    while(GetMessageW(&message,nullptr,0,0)>0) {
        if(message.message==WM_KEYDOWN && (message.wParam==VK_ESCAPE || message.wParam==VK_SPACE)) {PostMessageW(window,WM_CLOSE,0,0);continue;}
        TranslateMessage(&message);DispatchMessageW(&message);
    }
    return 0;
}
