{
  lib,
  config,
  inputs,
  pkgs,
  user,
  ...
}@args:
let
  cfg = config.amd-ai;
  xrt = pkgs.callPackage "${inputs.nix-amd-ai}/pkgs/xrt" { };
  ik_llama-cpp = pkgs.cudaPackages.backendStdenv.mkDerivation {
    pname = "ik-llama-cpp";
    version = "latest";

    src = inputs.llama-cpp;

    nativeBuildInputs = [
      pkgs.cmake
      pkgs.ninja
      pkgs.pkg-config
      pkgs.autoAddDriverRunpath
      pkgs.cudaPackages.cuda_nvcc
    ];

    buildInputs = [
      pkgs.curl
      pkgs.cudaPackages.cuda_cudart
      pkgs.cudaPackages.libcublas
    ];

    cmakeFlags = [
      "-DGGML_NATIVE=ON"
      "-DGGML_CUDA=ON"
      "-DGGML_BLAS=OFF"
      "-DLLAMA_BUILD_SERVER=ON"
      "-DCMAKE_CUDA_ARCHITECTURES=120"
    ];

    preConfigure = ''
      export NIX_ENFORCE_NO_NATIVE=0
    '';
  };
in
{
  options.amd-ai = {
    enable = lib.mkEnableOption "amd ai stuff";
    heavy.enable = lib.mkEnableOption "heavy general ai stuff";
  };

  imports = [
    (import "${inputs.nix-amd-ai}/modules/amd-npu.nix" (
      args
      // {
        pkgs = pkgs // {
          inherit xrt;
          fastflowlm = pkgs.callPackage "${inputs.nix-amd-ai}/pkgs/fastflowlm" { inherit xrt; };
          xrt-plugin-amdxdna = pkgs.callPackage "${inputs.nix-amd-ai}/pkgs/xrt-plugin-amdxdna" {
            inherit xrt;
          };
        };
      }
    ))
  ];

  config = lib.mkIf cfg.enable {
    # boot.kernelParams = [ "amd_iommu=off" ];
    environment.systemPackages = [
      xrt
    ]
    ++ lib.optionals cfg.heavy.enable [
      pkgs.alpaca
      ik_llama-cpp
    ];
    hardware.amd-npu = {
      enableNPU = true;
      enable = true;
      enableFastFlowLM = true;
      enableLemonade = false;
    };
    systemd.services.llama-server = lib.mkIf cfg.heavy.enable {
      description = "ik_llama.cpp local API server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = ''
          ${ik_llama-cpp}/bin/llama-server \
            --model /var/lib/llama-cpp/models/Qwen3.6-35B-A3B-abliterated-Q4_K_M.gguf \
            --ctx-size 98304 \
            --batch-size 2048 \
            --ubatch-size 128 \
            --ctx-checkpoints 4 \
            --fit \
            --fit-margin 384 \
            --cache-type-k q8_0 \
            --cache-type-v q8_0 \
            --flash-attn on \
            --jinja \
            --threads 8 \
            --host 127.0.0.1 \
            --port 8080
        '';
        Restart = "always";
        User = user;
      };
    };
    services = {
      searx = {
        enable = true;
        redisCreateLocally = true;
        environmentFile = "/var/lib/searx-secret";
        settings = {
          search.formats = [
            "html"
            "json"
          ];
          server = {
            port = 8000;
            bind_address = "127.0.0.1";
            limiter = false;
          };

          outgoing = {
            request_timeout = 1.0;
            max_request_timeout = 1.5;
            keepalive = true;
          };

          engines = [
            {
              name = "google";
              engine = "google";
              shortcut = "g";
            }
            {
              name = "duckduckgo";
              engine = "duckduckgo";
              shortcut = "ddg";
            }
            {
              name = "wikipedia";
              engine = "wikipedia";
              shortcut = "wp";
            }
            {
              name = "wikidata";
              engine = "wikidata";
              shortcut = "wd";
            }
          ];
        };
      };

      open-webui = lib.mkIf cfg.heavy.enable {
        enable = true;
        host = "127.0.0.1";
        port = 8070;
        environment = {
          WEBUI_AUTH = "False";
          ENABLE_OLLAMA_API = "False";
          OPENAI_API_BASE_URLS = "http://127.0.0.1:8080/v1";
          OPENAI_API_KEYS = "dummy-key";
          ENABLE_RAG_WEB_SEARCH = "True";
          RAG_WEB_SEARCH_ENGINE = "searxng";
          SEARXNG_QUERY_URL = "http://127.0.0.1:8000/search?q=<query>";
          BYPASS_WEB_SEARCH_WEB_LOADER = "True";
          BYPASS_EMBEDDING_AND_RETRIEVAL = "True";
          RAG_WEB_SEARCH_RESULT_COUNT = "3";
        };
      };
    };
  };
}
