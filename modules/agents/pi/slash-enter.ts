// 命令草稿（"/" 开头）用 Enter 直接提交，普通文本保持 Enter 换行。
// 补全打开时先以 Tab 接受选中项再提交（内置编辑器对 / 前缀补全本就
// “接受并放行”，放行后落到换行绑定，故在此接管）。
// SUBMIT_SEQUENCE 须与 keybindings.json 的 tui.input.submit 保持一致：
// kitty CSI u 形式在 legacy（Zed 注入）与 kitty（Konsole 原生）下均被解析。
import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { matchesKey } from "@earendil-works/pi-tui";

const SUBMIT_SEQUENCE = "\x1b[13;5u"; // ctrl+enter

class CommandEnterEditor extends CustomEditor {
  handleInput(data: string): void {
    // legacy 协议下裸 "\n"（Ctrl+J/Shift+Enter 实际发送的字节）也命中
    // matchesKey("enter")，放行给 newLine 绑定，/ 草稿才能手动换行。
    if (
      matchesKey(data, "enter") &&
      data !== "\n" &&
      this.getText().trimStart().startsWith("/")
    ) {
      if (this.isShowingAutocomplete()) {
        super.handleInput("\t");
      }
      super.handleInput(SUBMIT_SEQUENCE);
      return;
    }
    super.handleInput(data);
  }
}

// pi 0.86 起默认将 spinner 内嵌编辑器边框，自定义编辑器需显式 opt-in。
export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.setEditorComponent((tui, theme, keybindings) =>
      new CommandEnterEditor(tui, theme, keybindings, { embedWorkingStatus: true })
    );
  });
}
