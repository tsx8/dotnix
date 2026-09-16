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
    if (matchesKey(data, "enter") && this.getText().trimStart().startsWith("/")) {
      if (this.isShowingAutocomplete()) {
        super.handleInput("\t");
      }
      super.handleInput(SUBMIT_SEQUENCE);
      return;
    }
    super.handleInput(data);
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.setEditorComponent((tui, theme, keybindings) =>
      new CommandEnterEditor(tui, theme, keybindings)
    );
  });
}
