{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.swaync;
in
{
  options.swaync = {
    enable = mkEnableOption "Enable swaync notification manager";
  };
  


  config = mkIf cfg.enable {
    services.swaync = {
      enable = true;
      settings = {
        positionX = "left";
        positionY = "top";
        layer = "overlay";
        control-center-layer = "overlay";
        layer-shell = true;
        cssPriority = "application";
        control-center-margin-top = 10;
        control-center-margin-bottom = 0;
        control-center-margin-right = 0;
        control-center-margin-left = 10;
        notification-2fa-action = true;
        notification-inline-replies = false;
        notification-icon-size = 64;
        notification-body-image-height = 100;
        notification-body-image-width = 200;
        timeout = 10;
        timeout-low = 5;
        timeout-critical = 0;
        fit-to-screen = false;
        relative-timestamps = true;
        control-center-width = 370;
        control-center-height = 1030;
        notification-window-width = 350;
        keyboard-shortcuts = true;
        image-visibility = "when-available";
        transition-time = 200;
        hide-on-clear = false;
        hide-on-action = true;
        widgets = [
          "inhibitors"
          "title"
          "dnd"
          "notifications"
        ];
        widget-config = {
          inhibitors = {
            text = "Inhibitors";
            button-text = "Очистить";
            clear-all-button = true;
          };
          title = {
            text = "Уведомления";
            clear-all-button = true;
            button-text = "Clear All";
          };
          dnd = {
            text = "Не беспокоить";
          };
          mpris = {
            image-size = 96;
            image-radius = 12;
          };
        };
      };
      style = ''
        /*
        * vim: ft=less
        */
     
        @define-color cc-bg rgba(0, 0, 0, 0.01);
        
        @define-color noti-border-color transparent;
        @define-color noti-bg rgba(0, 0, 0, 0.01);
        @define-color noti-bg-darker rgb(38, 38, 38);
        @define-color noti-bg-hover rgba(56, 56, 56, 0.3);
        @define-color noti-bg-focus rgba(68, 68, 68, 0);
        @define-color noti-close-bg rgba(255, 255, 255, 0.1);
        @define-color noti-close-bg-hover rgba(255, 255, 255, 0.15);
        
        @define-color text-color rgb(255, 255, 255);
        @define-color text-color-disabled rgb(150, 150, 150);
        
        @define-color bg-selected rgb(0, 128, 255);
        .notification-row {
          outline: none;
        }
        * {
          box-shadow: none;
        }
        .notification-row:focus,
        .notification-row:hover {
          background: @noti-bg-focus;
        }
        
        .notification {
          border-radius: 12px;
          margin: 6px 12px;
          border: none;
          padding: 0;
          background: rgba(0,0,0,0.1);
        }
        
        .notification-content {
          background: transparent;
          padding: 6px;
          border-radius: 12px;
        }
        
        .close-button {
          background: @noti-close-bg;
          color: @text-color;
          text-shadow: none;
          padding: 0;
          border-radius: 100%;
          margin-top: 10px;
          margin-right: 16px;
          box-shadow: none;
          border: none;
          min-width: 24px;
          min-height: 24px;
        }
        
        .close-button:hover {
          box-shadow: none;
          background: @noti-close-bg-hover;
          transition: all 0.15s ease-in-out;
          border: none;
        }
        
        .notification-default-action,
        .notification-action {
          padding: 4px;
          margin: 0;
          box-shadow: none;
          background: @noti-bg;
          color: @text-color;
          transition: all 0.15s ease-in-out;
        }
        
        .notification-default-action:hover,
        .notification-action:hover {
          -gtk-icon-effect: none;
          background: @noti-bg-hover;
        }
        
        .notification-default-action {
          border-radius: 12px;
        }
        
        /* When alternative actions are visible */
        .notification-default-action:not(:only-child) {
          border-bottom-left-radius: 0px;
          border-bottom-right-radius: 0px;
        }
        
        .notification-action {
          border-radius: 0px;
          border-top: none;
          border-right: none;
        }
        
        /* add bottom border radius to eliminate clipping */
        .notification-action:first-child {
          border-bottom-left-radius: 10px;
        }
        
        .notification-action:last-child {
          border-bottom-right-radius: 10px;
        }
        
        .inline-reply {
          margin-top: 8px;
        }
        .inline-reply-entry {
          background: @noti-bg-darker;
          color: @text-color;
          caret-color: @text-color;
          border-radius: 12px;
        }
        .inline-reply-button {
          margin-left: 4px;
          background: @noti-bg;
          border-radius: 12px;
          color: @text-color;
        }
        .inline-reply-button:disabled {
          background: initial;
          color: @text-color-disabled;
        }
        .inline-reply-button:hover {
          background: @noti-bg-hover;
        }
        
        .image {
        }
        
        .body-image {
          margin-top: 6px;
          background-color: white;
          border-radius: 12px;
        }
        
        .summary {
          font-size: 16px;
          font-weight: bold;
          background: transparent;
          color: @text-color;
          text-shadow: none;
        }
        
        .time {
          font-size: 16px;
          font-weight: bold;
          background: transparent;
          color: @text-color;
          text-shadow: none;
          margin-right: 18px;
        }
        
        .body {
          font-size: 15px;
          font-weight: normal;
          background: transparent;
          color: @text-color;
          text-shadow: none;
        }
        
        .control-center {
          background: @cc-bg;
        }
        
        .control-center-list {
          background: transparent;
        }
        
        .control-center-list-placeholder {
          opacity: 0.5;
        }
        
        .floating-notifications {
          background: transparent;
        }
        
        /* Window behind control center and on all other monitors */
        .blank-window {
          background: alpha(black, 0);
        }
        
        /*** Widgets ***/
        
        /* Title widget */
        .widget-title {
          margin: 8px;
          font-size: 1.5rem;
        }
        .widget-title > button {
          font-size: initial;
          color: @text-color;
          text-shadow: none;
          background: @noti-bg;
          box-shadow: none;
          border-radius: 12px;
        }
        .widget-title > button:hover {
          background: @noti-bg-hover;
        }
        
        /* DND widget */
        .widget-dnd {
          margin: 8px;
          font-size: 1.1rem;
        }
        .widget-dnd > switch {
          font-size: initial;
          border-radius: 12px;
          background: @noti-bg;
          box-shadow: none;
        }
        .widget-dnd > switch:checked {
          background: @bg-selected;
        }
        .widget-dnd > switch slider {
          background: @noti-bg-hover;
          border-radius: 12px;
        }
        
        /* Label widget */
        .widget-label {
          margin: 8px;
        }
        .widget-label > label {
          font-size: 1.1rem;
        }
        
        /* Mpris widget */
        .widget-mpris {
          /* The parent to all players */
        }
        .widget-mpris-player {
          padding: 8px;
          margin: 8px;
        }
        .widget-mpris-title {
          font-weight: bold;
          font-size: 1.25rem;
        }
        .widget-mpris-subtitle {
          font-size: 1.1rem;
        }
        
        /* Buttons widget */
        .widget-buttons-grid {
          padding: 8px;
          margin: 8px;
          border-radius: 12px;
          background-color: @noti-bg;
        }
        
        .widget-buttons-grid>flowbox>flowboxchild>button{
          background: @noti-bg;
          border-radius: 12px;
        }
        
        /* style given to the active toggle button */
        .widget-buttons-grid>flowbox>flowboxchild>button.toggle:checked {
        }
        
        .widget-buttons-grid>flowbox>flowboxchild>button:hover {
        }
        
        /* Menubar widget */
        .widget-menubar>box>.menu-button-bar>button {
          border: none;
          background: transparent;
        }
        
        /* .AnyName { Name defined in config after #
          background-color: @noti-bg;
          padding: 8px;
          margin: 8px;
          border-radius: 12px;
        }
        
        .AnyName>button {
          background: transparent;
          border: none;
        }
        
        .AnyName>button:hover {
          background-color: @noti-bg-hover;
        } */
        
        .topbar-buttons>button { /* Name defined in config after # */
          border: none;
          background: transparent;
        }
        
        /* Volume widget */
        
        .widget-volume {
          background-color: @noti-bg;
          padding: 8px;
          margin: 8px;
          border-radius: 12px;
        }
        
        .widget-volume>box>button {
          background: transparent;
          border: none;
        }
        
        .per-app-volume {
          background-color: @noti-bg-alt;
          padding: 4px 8px 8px 8px;
          margin: 0px 8px 8px 8px;
          border-radius: 12px;
        }
        
        /* Backlight widget */
        .widget-backlight {
          background-color: @noti-bg;
          padding: 8px;
          margin: 8px;
          border-radius: 12px;
        }
        
        /* Title widget */
        .widget-inhibitors {
          margin: 8px;
          font-size: 1.5rem;
        }
        .widget-inhibitors > button {
          font-size: initial;
          color: @text-color;
          text-shadow: none;
          background: @noti-bg;
          box-shadow: none;
          border-radius: 12px;
        }
        .widget-inhibitors > button:hover {
          background: @noti-bg-hover;
        }
      '';
    };
  };
}
