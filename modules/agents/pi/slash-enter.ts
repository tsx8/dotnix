// Command drafts (starting with "/") submit directly on Enter; plain text keeps Enter as newline.
// With the autocomplete open, Tab first accepts the selected item, then submits (for /-prefix completions
// the built-in editor already "accepts and passes through"; the passed-through key lands on the
// newline binding, hence the takeover here).
// SUBMIT_SEQUENCE must stay in sync with tui.input.submit in keybindings.json:
// the kitty CSI u form is parsed under both legacy (Zed injection) and kitty (native Konsole) protocols.
import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { matchesKey } from "@earendil-works/pi-tui";

const SUBMIT_SEQUENCE = "\x1b[13;5u"; // ctrl+enter

class CommandEnterEditor extends CustomEditor {
  handleInput(data: string): void {
    // Under the legacy protocol a bare "\n" (the bytes Ctrl+J/Shift+Enter actually send) also matches
    // matchesKey("enter"); pass it through to the newLine binding so / drafts can break lines manually.
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

// Since pi 0.86 the spinner is embedded in the editor border by default; custom editors must opt in explicitly.
export default function (pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.setEditorComponent((tui, theme, keybindings) =>
      new CommandEnterEditor(tui, theme, keybindings, { embedWorkingStatus: true })
    );
  });
}
