// rma_/scripts/email_productivity_pane.js
// Opens the Email Assist side pane on rma_emaillog form load and refreshes
// it whenever a new record is loaded.
//
// Wire as form OnLoad handler:
//   Function: RmaEmailAssist.onLoad
//   Pass execution context: yes

if (typeof RmaEmailAssist === "undefined") { var RmaEmailAssist = {}; }

(function(NS){
  // NOTE: bump the pane ID suffix any time you change imageSrc/title — the
  // sidePanes API only sets those at createPane time, not on .navigate().
  // Bumping the ID forces a fresh createPane so the new icon takes effect.
  var PANE_ID = "rma_email_assist_pane_v2";
  var WEB_RESOURCE = "rma_/productivity/rma_email_assist.html";
  var PANE_ICON = "rma_/productivity/email_assist_icon.svg";
  var PANE_TITLE = "Email Assist";
  var PANE_WIDTH = 380;

  NS.onLoad = function(execContext){
    try {
      var formCtx = execContext && execContext.getFormContext ? execContext.getFormContext() : null;
      if (!formCtx) { console.warn("[EmailAssist] No formContext"); return; }

      var recordId = (formCtx.data && formCtx.data.entity && formCtx.data.entity.getId && formCtx.data.entity.getId()) || "";
      recordId = recordId.replace(/[{}]/g, "");

      // sidePanes API only exists in modern UCI
      if (!Xrm || !Xrm.App || !Xrm.App.sidePanes) {
        console.warn("[EmailAssist] sidePanes API not available in this client");
        return;
      }

      if (!recordId) {
        console.log("[EmailAssist] No record id yet — likely a new form. Skipping pane open.");
        return;
      }

      var existing = Xrm.App.sidePanes.getPane(PANE_ID);
      if (existing) {
        // Pane exists — just navigate it to the new record context
        existing.navigate({
          pageType: "webresource",
          webresourceName: WEB_RESOURCE,
          data: recordId
        }).catch(function(e){ console.error("[EmailAssist] navigate failed:", e); });
        try { existing.select(); } catch(e){}
        return;
      }

      Xrm.App.sidePanes.createPane({
        title: PANE_TITLE,
        paneId: PANE_ID,
        canClose: true,
        width: PANE_WIDTH,
        hideHeader: false,
        isSelected: true,
        imageSrc: PANE_ICON
      }).then(function(pane){
        return pane.navigate({
          pageType: "webresource",
          webresourceName: WEB_RESOURCE,
          data: recordId
        });
      }).catch(function(err){
        console.error("[EmailAssist] Failed to open pane:", err);
      });
    } catch(e) {
      console.error("[EmailAssist] onLoad error:", e);
    }
  };
})(RmaEmailAssist);
