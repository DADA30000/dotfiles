{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  vencord-web = (inputs.nur.legacyPackages.${pkgs.system}.repos.rycee.firefox-addons.buildFirefoxXpiAddon {
    pname = "vencord-web";
    version = "1.10.9";
    addonId = "{ccb34031-d8e9-49c0-a795-60560b0db6c9}";
    url = "https://github.com/DADA30000/dotfiles/raw/refs/heads/main/stuff/vencord-sth.xpi";
    sha256 = "0774c1ee50a9e06ec86e7cafd423980964e6120b0bd92fbf18ec75553e870798";
    meta = {};
  });
  cfg = config.firefox;
in
{
  options.firefox = {
    enable = mkEnableOption "Enable firefox customization";
  };

  config = mkIf cfg.enable {
    programs.firefox = {
      enable = true;
      nativeMessagingHosts = [ inputs.pipewire-screenaudio.packages.${pkgs.system}.default ];
      profiles.kek = {
        extensions = with inputs.nur.legacyPackages.${pkgs.system}.repos.rycee.firefox-addons; [ bitwarden ublock-origin privacy-badger sponsorblock darkreader  vencord-web ];
        userChrome = ''
          /* imports */

          :root {
          --bg: #00000044;
          --tabpanel-background-color: #00000044 !important;
          }

          /*window transparency*/
          #main-window {
          background: var(--bg) !important;
          }

          #browser:not(.browser-toolbox-background) {
            background-color: var(--bg) !important;
            color: var(--bg) !important;
          }

          /*current tab*/
          tab.tabbrowser-tab[selected="true"] stack.tab-stack vbox.tab-background {
          background: #FFFFFF22 !important;
          }

          /*hover tab*/
          tab.tabbrowser-tab:hover stack.tab-stack vbox.tab-background {
          background: #FFFFFF22 !important;
          }

          /*tab selection*/
          tab.tabbrowser-tab[pending="true"] {
          color: #FFFFFFcc !important;
          }

          /*hibernated*/
          tab.tabbrowser-tab stack.tab-stack vbox.tab-background {
          background: transparent !important;
          }

          /*bookmarks*/
          toolbar {
          background: transparent !important;
          }

          /*idk*/
          #nav-bar {
          background: transparent  !important;
          }

          /*idk but keep*/
          #navigator-toolbox {
          background: transparent !important;
          border: none !important;
          }

          /*urlbar*/
          #urlbar-background {
/          background: #00000044 !important;
          }

          /*suggestions dropdown*/
          #urlbar:is([open]) hbox#urlbar-background {
          background: #42414D !important;
          }

          /*little contextual buttons at left of urlbar*/
          #urlbar box#identity-box box {
          background: inherit !important;
          }
          #urlbar box#identity-box box:hover {
          background: #FFFFFF22 !important;
          }
          #urlbar box#identity-box box:active {
          background: #FFFFFF44 !important;
          }
        '';
        userContent = ''
          /* imports */

          @-moz-document url-prefix("about:"), url-prefix("chrome:"){

            /* accent color */
            :root, panel, dialog, window{
              --in-content-primary-button-background-active: var(--shy-color) !important;
              --in-content-primary-button-background-hover:  var(--shy-color) !important;
              --lwt-toolbarbutton-icon-fill-attention:       var(--shy-color) !important;
              --in-content-primary-button-background:        var(--shy-color) !important;
              --toolbarbutton-icon-fill-attention:           var(--shy-color) !important;
              --fxview-primary-action-background:            var(--shy-color) !important;
              --toolbar-field-focus-border-color:            var(--shy-color) !important;
              --button-primary-active-bgcolor:               var(--shy-color) !important;
              --button-primary-hover-bgcolor:                var(--shy-color) !important;
              --uc-checkbox-checked-bgcolor:                 var(--shy-color) !important;
              --color-accent-primary-active:                 var(--shy-color) !important;
              --color-accent-primary-hover:                  var(--shy-color) !important;
              --checkbox-checked-bgcolor:                    var(--shy-color) !important;
              --in-content-accent-color:                     var(--shy-color) !important;
              --button-primary-bgcolor:                      var(--shy-color) !important;
              --in-content-link-color:                       var(--shy-color) !important;
              --color-accent-primary:                        var(--shy-color) !important;
              --focus-outline-color:                         var(--shy-color) !important;
              --input-border-color:                          var(--shy-color) !important;
            }
            
            .primary-button{
               --primary-button-background-color: var(--shy-color) !important;
               --primary-button-hover-background-color: color-mix(in srgb, white 10%, var(--shy-color)) !important;
               --primary-button-active-background-color: color-mix(in srgb, white 20%, var(--shy-color)) !important;
            }
            
            :is(.icon, img)[src="chrome://global/skin/icons/info-filled.svg"] {fill: var(--shy-color) !important;}
            moz-message-bar {background-color: var(--in-content-button-background) !important;}
            
            .cpu{
              background: linear-gradient(
                to left,
                var(--shy-color) 
                calc(var(--bar-width) * 1%),
                transparent 
                calc(var(--bar-width) * 1%)
              ) !important;
            }
            
            button[role="tab"][selected]::before {display: none !important;}
            
            /* big rounded corners */
            .menupopup-arrowscrollbox,     moz-message-bar,
            .addon-detail-contribute,      panel-list,
            .trr-message-container,
            .web-appearance-choice,        body[dir],
            .sidebar-footer-link,          menupopup,
            .info-box-container,           section,
            .sidebar-item--tall,           details,
            .info-box-content,
            .sidebar-item,
            .qr-code-box,                  select,
            .action-box,                   table,
            .dialogBox,                    tree,
            .info-box,
            .category,
            .toolbar,
            .modal,
            .card,

            #ping-picker,
            #reportBox,
            #reportBox #comments,
            #migrationWizardDialog,
            #translations-manage-install-list
            
            {border-radius: var(--big-rounding) !important;}
            
            /* small rounded corners */
            button:not(
              :is(
                [class*="devtools"],
                [class*="search"],
                [class*="tab"]
              )
            ),
            
            input:not([type="checkbox"]),
            
            .search-container,
            .study-icon,
            
            search-textbox,
            menulist,
            span,
            a, 
            
            .tooltip-container .tooltip-panel,
            
            #activeLanguages
            
            {border-radius: var(--rounding) !important;}
            
            /* only top or bottom corners */
            .card-heading-image{
              border-top-left-radius: var(--big-rounding) !important;
              border-top-right-radius: var(--big-rounding) !important;
            }
            
            listheader{
              border-top-left-radius: var(--rounding) !important;
              border-top-right-radius: var(--rounding) !important;
            }
            
            richlistbox{
              border-bottom-left-radius: var(--rounding) !important;
              border-bottom-right-radius: var(--rounding) !important;
            }
            
            /* dropdown menu margin */
            .tooltip-container .tooltip-panel .menuitem,
            panel-list[role="menu"] panel-item {margin-inline: 5px}
            
          }

          /* about:debugging thin mode */
          @-moz-document url-prefix("about:debugging") {
            @media (max-width: 700px) {
              .sidebar{
                width: 45px !important;
                img{margin: none !important;}
                
                .sidebar-item:has(.qa-sidebar-no-devices),
                .sidebar__adb-status,
                .sidebar__refresh-usb,
                .sidebar__footer__support-help span,
                .ellipsis-text {display: none}
              }
              
              sidebar__footer__support-help, .sidebar-item__link{width: 23px !important;}
              .sidebar-item:has(.sidebar__footer__support-help) {width: 14px !important;}
              .sidebar-fixed-item__icon{margin-right: 0px !important;}
              .app{display: flex !important;}
            }
          }

          @-moz-document url-prefix("moz-extension:"){
            body {border-radius: var(--big-rounding) !important;}
          }

          /* screenshots */

          #screenshots-component{
            button {border-radius: var(--rounding) !important;}
            #buttons-container {border-radius: var(--big-rounding) !important;}

            .screenshots-button {
              --in-content-primary-button-background: var(--shy-color) !important;
              --in-content-primary-button-background-hover: color-mix(in oklab, var(--in-content-primary-button-background), white 10%) !important;
              --in-content-primary-button-background-active: color-mix(in oklab, var(--in-content-primary-button-background), white 20%) !important;
              --in-content-focus-outline-color: var(--shy-color) !important;
            }
          }

          /* simple translate icon */
          @media (-moz-bool-pref: "shyfox.enable.ext.mono.context.icons") {
            .simple-translate-button {
              background-image: none !important;
              &::before {
                content: "";
                position: absolute;
                
                background-color: var(--simple-translate-main-text);
                mask-image: url("icons/translate.svg");
                mask-repeat: no-repeat;
                mask-position: center;
                
                width: inherit !important;
                height: inherit !important;
              }
            }
          }

          /* simple translate */
          .simple-translate-panel{
            border-radius: var(--big-rounding) !important;
            border: 1px solid color-mix(in srgb, var(--simple-translate-main-bg) 90%, var(--simple-translate-main-text)) !important;
          }

          .simple-translate-button{
            border-radius: 7px !important;
            border: 1px solid color-mix(in srgb, var(--simple-translate-main-bg) 65%, var(--simple-translate-main-text)) !important;
          }

          /* Adaptive Tab Bar Color settings accent */
          @-moz-document url("moz-extension://d6e33c37-61b0-488f-9899-bf896d64db63/options.html"){
            * {
              --color-link: var(--shy-color) !important;
              --color-accent: var(--shy-color) !important;
              --color-link-hover: color-mix(in srgb, var(--shy-color) 60%, var(--color)) !important;
              --color-link-active: color-mix(in srgb, var(--shy-color) 30%, var(--color)) !important;
            }
          }

          :root, #screenshots-component *{
            /* accent color */
            --shy-accent-color: #3584E4;
            --in-content-page-background: #00000000 !important;
            --in-content-box-background: #00000088 !important;
            /* window border thickness and size of many margins */
            --margin: 0.8rem;
            
            /* rounded corners radius of most elements */
            --rounding: 11.5px;
            --big-rounding: 15px;
            --bigger-rounding: 20px;
            --giant-rounding: 30px;
            
            /* animations time */
            --trans-dur: 0.25s;
            
            /* width of some elements. 1vw is one hundredth of the screen width */
            --sdbr-wdt: 300px;
            
            --navbar-wdt: 60vw;
            
            --findbar-wdt: 70vw;
            
            /* intensity of blur (new tab) */
            --blur-radius: 10px;
            
            /* brightness of inactive window elements */
            --inactive-opct: 0.7;
            
            /* transparency of indicator bars showing the position of hidden panels */
            --hide-bar-opct: 0.2;
            &:-moz-window-inactive{--hide-bar-opct: 0.1;}
            
            /* how much shorter these bars than panels */
            --hide-bar-wdt-pad: 10px;
            
            /* size of the panel hitbox outside the window border */
            --panel-hide-ldg: 1px;            /* f11 fullscreen   */
            &:not([inFullscreen="true"]){
              --panel-hide-ldg: 0px;          /* maximized window */ 
              &[sizemode="normal"]:not([titlepreface*="‍"]){
                --panel-hide-ldg: 9px;        /* floating window  */
              }
            }
            
            /* colors */
            --shadow-col:  #00000020;    /* color of the translucent outline that imitates a shadow     */
            --private-col: #6e00bc80;    /* private mode outline color                                  */
            --debug-col: transparent;    /* rgba(0, 0, 255, 0.2); color of hidden panels hover hitboxes */
            --debug-col-2: transparent;  /* rgba(0, 255, 0, 0.2); color of window dragging hitboxes     */
          }


          /* accent color toggle */
          :root{--shy-color: var(--shy-accent-color)}

          @media (-moz-bool-pref: "shyfox.fill.accent.with.icons.fill.color"){
            :root{--shy-color: var(--toolbar-color, var(--shy-accent-color)) !important;}
          }

          /* 

          --- VARIABLES ----------------------------------------------------------------------------------------------------------------------------------

          Reserved values and all sorts of dynamic variables. You should not touch them.

          */

          :root{
            
            --ActiveCaption: ActiveCaption;
            
            /* pick browser colors */                                           /* used for:          */ 
            --bg-col: var(--lwt-accent-color, var(--ActiveCaption, tomato));    /* darker background  */       /* tomato is the fallback color */
            --tb-col: var(--toolbar-bgcolor, tomato);                           /* lighter background */       /* meaning something went wrong */
            --bt-col: var(--toolbarbutton-icon-fill);                           /* text or icons      */
            --pp-col: var(--arrowpanel-background);                             /* popup color        */
            
            /* dynamic opacity */
            --dyn-opct: 1;
            &:-moz-window-inactive{--dyn-opct: var(--inactive-opct);}
            
            /* shared shortcuts for commonly used parameters */
            --outline: 1px solid var(--arrowpanel-background);      /* outline around almost anything              */
            --shadow: 2px solid var(--shadow-col);                  /* translucent outline that imitates a shadow  */
            --transition: all var(--trans-dur) ease-out;            /* animation for smooth transitions            */
            
            /* constant variables */
            --toolbar-item-hgt: 40px;       /* height of all panels elements: buttons, urlbar, etc.                                   */
            --toolbar-button-wdt: 45px;     /* width of all panels buttons                                                            */
            --hide-bar-padding: 3px;        /* how much indicator bars showing the position of hidden panels is thinner than --margin */
            --screenshot-tool-hgt: 145px;   /* height of `ctrl + shift + s` tool buttons  */
            
            /* hiding the window border in fullscreen mode and assigning --margin to it in windowed mode */
            --left-margin:   0px;
            --right-margin:  0px;
            --top-margin:    0px;
            --bottom-margin: 0px; 
            
            &:not(:is([inFullscreen="true"], [inDOMFullscreen="true"], [titlepreface*="‍"]:is([sizemode="maximized"], [gtktiledwindow="true"]))){
              --left-margin:   var(--margin);
              --right-margin:  var(--margin);
              --top-margin:    var(--margin);
              --bottom-margin: var(--margin);
            }
            
            /* hide indication bars in fullscreen or clean mode */
            &:is([inFullscreen="true"], [inDOMFullscreen="true"], [titlepreface*="‍"]){
              --hide-bar-opct: 0 !important;
            }
            
            /* override built-in roundings with custom */
            --arrowpanel-border-radius: var(--big-rounding) !important;
            --panel-border-radius:      var(--big-rounding) !important;
            
            --arrowpanel-menuitem-border-radius: var(--rounding) !important;
            --toolbarbutton-border-radius:       var(--rounding) !important;
            --button-border-radius:              var(--rounding) !important;
            --border-radius-small:               var(--rounding) !important;
            --tab-border-radius:                 var(--rounding) !important;
            
            /* override one padding in navbar to match style */
            --toolbar-start-end-padding: calc(var(--margin) / 2) !important;
          }

          /* current tab loading progress */
          #main-window{
            &:has(.tabbrowser-tab[selected][busy]                        ){--shy-tab-load-pcent: 20%;}
            &:has(.tabbrowser-tab[selected][busy][pendingicon]           ){--shy-tab-load-pcent: 50%;}
            &:has(.tabbrowser-tab[selected][busy][pendingicon][progress] ){--shy-tab-load-pcent: 85%;}
            &:has(.tabbrowser-tab[selected][busy][progress]              ){--shy-tab-load-pcent: 95%;}
          }

          /* globalise download percentages (yes, i am a clown) */
          #main-window{
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 0%;"]){--shy-download-pcent: 0%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 1%;"]){--shy-download-pcent: 1%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 2%;"]){--shy-download-pcent: 2%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 3%;"]){--shy-download-pcent: 3%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 4%;"]){--shy-download-pcent: 4%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 5%;"]){--shy-download-pcent: 5%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 6%;"]){--shy-download-pcent: 6%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 7%;"]){--shy-download-pcent: 7%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 8%;"]){--shy-download-pcent: 8%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 9%;"]){--shy-download-pcent: 9%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 10%;"]){--shy-download-pcent: 10%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 11%;"]){--shy-download-pcent: 11%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 12%;"]){--shy-download-pcent: 12%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 13%;"]){--shy-download-pcent: 13%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 14%;"]){--shy-download-pcent: 14%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 15%;"]){--shy-download-pcent: 15%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 16%;"]){--shy-download-pcent: 16%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 17%;"]){--shy-download-pcent: 17%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 18%;"]){--shy-download-pcent: 18%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 19%;"]){--shy-download-pcent: 19%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 20%;"]){--shy-download-pcent: 20%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 21%;"]){--shy-download-pcent: 21%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 22%;"]){--shy-download-pcent: 22%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 23%;"]){--shy-download-pcent: 23%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 24%;"]){--shy-download-pcent: 24%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 25%;"]){--shy-download-pcent: 25%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 26%;"]){--shy-download-pcent: 26%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 27%;"]){--shy-download-pcent: 27%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 28%;"]){--shy-download-pcent: 28%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 29%;"]){--shy-download-pcent: 29%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 30%;"]){--shy-download-pcent: 30%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 31%;"]){--shy-download-pcent: 31%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 32%;"]){--shy-download-pcent: 32%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 33%;"]){--shy-download-pcent: 33%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 34%;"]){--shy-download-pcent: 34%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 35%;"]){--shy-download-pcent: 35%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 36%;"]){--shy-download-pcent: 36%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 37%;"]){--shy-download-pcent: 37%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 38%;"]){--shy-download-pcent: 38%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 39%;"]){--shy-download-pcent: 39%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 40%;"]){--shy-download-pcent: 40%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 41%;"]){--shy-download-pcent: 41%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 42%;"]){--shy-download-pcent: 42%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 43%;"]){--shy-download-pcent: 43%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 44%;"]){--shy-download-pcent: 44%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 45%;"]){--shy-download-pcent: 45%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 46%;"]){--shy-download-pcent: 46%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 47%;"]){--shy-download-pcent: 47%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 48%;"]){--shy-download-pcent: 48%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 49%;"]){--shy-download-pcent: 49%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 50%;"]){--shy-download-pcent: 50%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 51%;"]){--shy-download-pcent: 51%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 52%;"]){--shy-download-pcent: 52%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 53%;"]){--shy-download-pcent: 53%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 54%;"]){--shy-download-pcent: 54%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 55%;"]){--shy-download-pcent: 55%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 56%;"]){--shy-download-pcent: 56%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 57%;"]){--shy-download-pcent: 57%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 58%;"]){--shy-download-pcent: 58%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 59%;"]){--shy-download-pcent: 59%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 60%;"]){--shy-download-pcent: 60%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 61%;"]){--shy-download-pcent: 61%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 62%;"]){--shy-download-pcent: 62%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 63%;"]){--shy-download-pcent: 63%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 64%;"]){--shy-download-pcent: 64%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 65%;"]){--shy-download-pcent: 65%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 66%;"]){--shy-download-pcent: 66%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 67%;"]){--shy-download-pcent: 67%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 68%;"]){--shy-download-pcent: 68%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 69%;"]){--shy-download-pcent: 69%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 70%;"]){--shy-download-pcent: 70%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 71%;"]){--shy-download-pcent: 71%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 72%;"]){--shy-download-pcent: 72%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 73%;"]){--shy-download-pcent: 73%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 74%;"]){--shy-download-pcent: 74%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 75%;"]){--shy-download-pcent: 75%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 76%;"]){--shy-download-pcent: 76%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 77%;"]){--shy-download-pcent: 77%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 78%;"]){--shy-download-pcent: 78%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 79%;"]){--shy-download-pcent: 79%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 80%;"]){--shy-download-pcent: 80%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 81%;"]){--shy-download-pcent: 81%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 82%;"]){--shy-download-pcent: 82%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 83%;"]){--shy-download-pcent: 83%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 84%;"]){--shy-download-pcent: 84%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 85%;"]){--shy-download-pcent: 85%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 86%;"]){--shy-download-pcent: 86%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 87%;"]){--shy-download-pcent: 87%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 88%;"]){--shy-download-pcent: 88%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 89%;"]){--shy-download-pcent: 89%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 90%;"]){--shy-download-pcent: 90%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 91%;"]){--shy-download-pcent: 91%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 92%;"]){--shy-download-pcent: 92%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 93%;"]){--shy-download-pcent: 93%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 94%;"]){--shy-download-pcent: 94%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 95%;"]){--shy-download-pcent: 95%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 96%;"]){--shy-download-pcent: 96%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 97%;"]){--shy-download-pcent: 97%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 98%;"]){--shy-download-pcent: 98%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 99%;"]){--shy-download-pcent: 99%;}
            &:has(#downloads-indicator-progress-inner[style="--download-progress-pcent: 100%;"]){--shy-download-pcent: 100%;}
          }
        '';
        settings = {
          "content.notify.interval" = 100000;
          "gfx.canvas.accelerated.cache-items" = 4096;
          "gfx.canvas.accelerated.cache-size" = 512;
          "gfx.content.skia-font-cache-size" = 20;
          "browser.cache.jsbc_compression_level" = 3;
          "media.memory_cache_max_size" = 65536;
          "media.cache_readahead_limit" = 7200;
          "media.cache_resume_threshold" = 3600;
          "image.mem.decode_bytes_at_a_time" = 32768;
          "network.buffer.cache.size" = 262144;
          "network.buffer.cache.count" = 128;
          "network.http.max-connections" = 1800;
          "network.http.max-persistent-connections-per-server" = 10;
          "network.http.max-urgent-start-excessive-connections-per-host" = 5;
          "network.http.pacing.requests.enabled" = false;
          "network.dnsCacheExpiration" = 3600;
          "network.dns.max_high_priority_threads" = 8;
          "network.ssl_tokens_cache_capacity" = 10240;
          "network.dns.disablePrefetch" = true;
          "network.prefetch-next" = false;
          "network.predictor.enabled" = false;
          "layout.css.grid-template-masonry-value.enabled" = true;
          "dom.enable_web_task_scheduling" = true;
          "layout.css.has-selector.enabled" = true;
          "dom.security.sanitizer.enabled" = true;
          "browser.contentblocking.category" = "strict";
          "urlclassifier.trackingSkipURLs" = "*.reddit.com, *.twitter.com, *.twimg.com, *.tiktok.com";
          "urlclassifier.features.socialtracking.skipURLs" = "*.instagram.com, *.twitter.com, *.twimg.com";
          "network.cookie.sameSite.noneRequiresSecure" = true;
          "browser.download.start_downloads_in_tmp_dir" = true;
          "browser.helperApps.deleteTempFileOnExit" = true;
          "browser.uitour.enabled" = false;
          "privacy.globalprivacycontrol.enabled" = true;
          "security.OCSP.enabled" = 0;
          "security.remote_settings.crlite_filters.enabled" = true;
          "security.pki.crlite_mode" = 2;
          "security.ssl.treat_unsafe_negotiation_as_broken" = true;
          "browser.xul.error_pages.expert_bad_cert" = true;
          "security.tls.enable_0rtt_data" = false;
          "browser.privatebrowsing.forceMediaMemoryCache" = true;
          "browser.sessionstore.interval" = 60000;
          "privacy.history.custom" = true;
          "browser.search.separatePrivateDefault.ui.enabled" = true;
          "browser.urlbar.update2.engineAliasRefresh" = true;
          "browser.search.suggest.enabled" = false;
          "browser.urlbar.suggest.quicksuggest.sponsored" = false;
          "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
          "browser.formfill.enable" = false;
          "security.insecure_connection_text.enabled" = true;
          "security.insecure_connection_text.pbmode.enabled" = true;
          "network.IDN_show_punycode" = true;
          "dom.security.https_first" = true;
          "dom.security.https_first_schemeless" = true;
          "signon.formlessCapture.enabled" = false;
          "signon.privateBrowsingCapture.enabled" = false;
          "network.auth.subresource-http-auth-allow" = 1;
          "editor.truncate_user_pastes" = false;
          "security.mixed_content.block_display_content" = true;
          "security.mixed_content.upgrade_display_content" = true;
          "security.mixed_content.upgrade_display_content.image" = true;
          "pdfjs.enableScripting" = false;
          "extensions.postDownloadThirdPartyPrompt" = false;
          "network.http.referer.XOriginTrimmingPolicy" = 2;
          "privacy.userContext.ui.enabled" = true;
          "media.peerconnection.ice.proxy_only_if_behind_proxy" = true;
          "media.peerconnection.ice.default_address_only" = true;
          "browser.safebrowsing.downloads.remote.enabled" = false;
          "permissions.default.desktop-notification" = 2;
          "permissions.default.geo" = 2;
          "geo.provider.network.url" =
            "https://location.services.mozilla.com/v1/geolocate?key=%MOZILLA_API_KEY%";
          "permissions.manager.defaultsUrl" = "";
          "webchannel.allowObject.urlWhitelist" = "";
          "datareporting.policy.dataSubmissionEnabled" = false;
          "datareporting.healthreport.uploadEnabled" = false;
          "toolkit.telemetry.unified" = false;
          "toolkit.telemetry.enabled" = false;
          "toolkit.telemetry.server" = "data:,";
          "toolkit.telemetry.archive.enabled" = false;
          "toolkit.telemetry.newProfilePing.enabled" = false;
          "toolkit.telemetry.shutdownPingSender.enabled" = false;
          "toolkit.telemetry.updatePing.enabled" = false;
          "toolkit.telemetry.bhrPing.enabled" = false;
          "toolkit.telemetry.firstShutdownPing.enabled" = false;
          "toolkit.telemetry.coverage.opt-out" = true;
          "toolkit.coverage.opt-out" = true;
          "toolkit.coverage.endpoint.base" = "";
          "browser.ping-centre.telemetry" = false;
          "browser.newtabpage.activity-stream.feeds.telemetry" = false;
          "browser.newtabpage.activity-stream.telemetry" = false;
          "app.shield.optoutstudies.enabled" = false;
          "app.normandy.enabled" = false;
          "app.normandy.api_url" = "";
          "breakpad.reportURL" = "";
          "browser.tabs.crashReporting.sendReport" = false;
          "browser.crashReports.unsubmittedCheck.autoSubmit2" = false;
          "captivedetect.canonicalURL" = "";
          "network.captive-portal-service.enabled" = false;
          "network.connectivity-service.enabled" = false;
          "browser.privatebrowsing.vpnpromourl" = "";
          "extensions.getAddons.showPane" = false;
          "extensions.htmlaboutaddons.recommendations.enabled" = false;
          "browser.discovery.enabled" = false;
          "browser.shell.checkDefaultBrowser" = false;
          "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = false;
          "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;
          "browser.preferences.moreFromMozilla" = false;
          "browser.tabs.tabmanager.enabled" = false;
          "browser.aboutConfig.showWarning" = false;
          "browser.aboutwelcome.enabled" = false;
          "browser.compactmode.show" = true;
          "browser.display.focus_ring_on_anything" = true;
          "browser.display.focus_ring_style" = 0;
          "browser.display.focus_ring_width" = 0;
          "layout.css.prefers-color-scheme.content-override" = 2;
          "browser.privateWindowSeparation.enabled" = false;
          "cookiebanners.service.mode" = 1;
          "cookiebanners.service.mode.privateBrowsing" = 1;
          "full-screen-api.transition-duration.enter" = "0 0";
          "full-screen-api.transition-duration.leave" = "0 0";
          "full-screen-api.warning.delay" = -1;
          "full-screen-api.warning.timeout" = 0;
          "browser.urlbar.trimHttps" = true;
          "browser.urlbar.trimURLs" = true;
          "browser.urlbar.suggest.calculator" = true;
          "browser.urlbar.unitConversion.enabled" = true;
          "browser.urlbar.trending.featureGate" = false;
          "browser.newtabpage.activity-stream.feeds.topsites" = false;
          "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
          "extensions.pocket.enabled" = false;
          "browser.download.always_ask_before_handling_new_types" = false;
          "browser.download.manager.addToRecentDocs" = false;
          "browser.download.open_pdf_attachments_inline" = true;
          "browser.download.alwaysOpenPanel" = true;
          "browser.bookmarks.openInTabClosesMenu" = false;
          "browser.menu.showViewImageInfo" = true;
          "findbar.highlightAll" = true;
          "layout.word_select.eat_space_to_next_word" = false;
          "mousewheel.min_line_scroll_amount" = 10;
          "extensions.webextensions.restrictedDomains" = "";
          "general.smoothScroll.mouseWheel.durationMinMS" = 80;
          "mousewheel.default.delta_multiplier_y" = 300;
          "apz.overscroll.enabled" = true;
          "privacy.resistFingerprinting.block_mozAddonManager" = true;
          "general.smoothScroll" = true;
          "general.smoothScroll.msdPhysics.continuousMotionMaxDeltaMS" = 12;
          "general.smoothScroll.msdPhysics.enabled" = true;
          "general.smoothScroll.msdPhysics.motionBeginSpringConstant" = 600;
          "general.smoothScroll.msdPhysics.regularSpringConstant" = 650;
          "general.smoothScroll.msdPhysics.slowdownMinDeltaMS" = 25;
          "general.smoothScroll.msdPhysics.slowdownMinDeltaRatio" = 2.0;
          "general.smoothScroll.msdPhysics.slowdownSpringConstant" = 250;
          "general.smoothScroll.currentVelocityWeighting" = 1.0;
          "general.smoothScroll.stopDecelerationWeighting" = 1.0;
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
          "browser.uidensity" = 0;
          "svg.context-properties.content.enabled" = true;
          "browser.theme.dark-private-windows" = false;
          "widget.gtk.rounded-bottom-corners.enabled" = true;
          "gfx.webrender.all" = true;
          "gfx.webrender.enabled" = true;
          "browser.newtabpage.enabled" = false;
          "browser.tabs.allow_transparent_browser" = true;
          "dom.security.https_only_mode_ever_enabled" = true;
          "dom.security.https_only_mode" = true;
          "general.autoScroll" = true;
          "network.http.http3.enable" = false;
          "browser.startup.page" = 3;
          "browser.startup.homepage" = "chrome://browser/content/blanktab.html";
          "intl.accept_languages" = "ru,en-us";
          "intl.locale.requested" = "ru,en-US";
          "extensions.autoDisableScopes" = 0;
          "intl.regional_prefs.use_os_locales" = true;
        };
        bookmarks = [
          {
            url = "https://mail.google.com/mail/u/0/#inbox";
            name = "first gmail";
          }
          {
            url = "https://mail.google.com/mail/u/1/#inbox";
            name = "second gmail";
          }
          {
            url = "https://home-manager-options.extranix.com/";
            name = "Home Manager - Option Search";
          }
          {
            url = "https://search.nixos.org/options";
            name = "NixOS Search - Options";
          }
          {
            url = "https://nixpk.gs/pr-tracker.html";
            name = "Nixpkgs PR status";
          }
          {
            url = "https://youtube.com";
            name = "";
          }
          {
            url = "https://cartoonsub.com/";
            name = "";
          }
          {
            url = "https://diakov.net/";
            name = "";
          }
          {
            url = "https://d-obmen.cc/CreateOrder.aspx?s=ADVC-RUB&t=QIWI-RUB";
            name = "";
          }
          {
            url = "https://unix.stackexchange.com/questions/48235/can-i-watch-the-progress-of-a-sync-operation";
            name = "";
          }
          {
            url = "https://ggntw.com/steam";
            name = "";
          }
          {
            url = "https://freevpn4you.net/ru/locations/sweden.php";
            name = "";
          }
          {
            url = "https://forums.unraid.net/topic/127639-easy-anti-cheat-launch-error-cannot-run-under-virtual-machine/";
            name = "";
          }
          {
            url = "https://auto.creavite.co/animated-banners";
            name = "";
          }
          {
            url = "https://positiverecords.ru/";
            name = "";
          }
          {
            url = "https://github.com/Codeusa/Borderless-Gaming/releases";
            name = "";
          }
          {
            url = "https://free-mp3-download.net/";
            name = "";
          }
          {
            url = "https://www.reddit.com/r/LinuxCrackSupport/comments/13vorsd/comment/jtfas0n/";
            name = "";
          }
          {
            url = "https://minecraft-serverlist.com/tools/offline-uuid";
            name = "";
          }
          {
            url = "https://use10.thegood.cloud/apps/files/?dir=/&fileid=10482827";
            name = "";
          }
          {
            url = "https://discourse.nixos.org/t/set-default-application-for-mime-type-with-home-manager/17190";
            name = "";
          }
          {
            url = "https://ryantm.github.io/nixpkgs/using/overlays/#chap-overlays";
            name = "";
          }
          {
            url = "https://ryantm.github.io/nixpkgs/using/overrides/#chap-overrides";
            name = "";
          }
          {
            url = "https://nixos.wiki/index.php?title=Ubuntu_vs._NixOS&useskin=vector";
            name = "";
          }
          {
            url = "https://www.3dgifmaker.com/ClockwiseSpin";
            name = "";
          }
        ];
      };
    };
  };
}
