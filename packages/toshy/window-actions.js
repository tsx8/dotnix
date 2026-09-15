function hideApplicationWindows(others) {
    var active = workspace.activeWindow;
    if (!active || !active.resourceClass) return;
    workspace.windowList().forEach(function (window) {
        var sameApplication = window.resourceClass === active.resourceClass;
        if (window.minimizable && (others ? !sameApplication : sameApplication)) {
            window.minimized = true;
        }
    });
}

registerShortcut("ToshyHideApplication", "Toshy: Hide application",
    "", function () { hideApplicationWindows(false); });
registerShortcut("ToshyHideOtherApplications", "Toshy: Hide other applications",
    "", function () { hideApplicationWindows(true); });

registerShortcut("ToshyMinimizeApplication", "Toshy: Minimize application",
    "", function () { hideApplicationWindows(false); });
