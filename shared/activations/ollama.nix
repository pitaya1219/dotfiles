{ config, pkgs, lib, ... }:

{
  home.activation.setupOllama = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Create ollama models directory if it doesn't exist
    mkdir -p ~/.ollama/models
    
    # Check if ollama service is running
    if ! ps aux | grep -v grep | grep 'ollama serve' > /dev/null; then
      echo "Starting ollama service in background..."
      ${pkgs.ollama}/bin/ollama serve &
      sleep 2
    fi
    
    echo "Ollama setup completed"
  '';
}
