.PHONY: help install install-git install-ssh install-nix check-deps setup

# Default target
help:
	@echo "Dotfiles Initial Setup"
	@echo "======================"
	@echo ""
	@echo "Available targets:"
	@echo "  help        - Show this help message"
	@echo "  install     - Install all dependencies (git, ssh, nix)"
	@echo "  install-git - Install Git"
	@echo "  install-ssh - Install SSH"
	@echo "  install-nix - Install Nix package manager"
	@echo "  check-deps  - Check if dependencies are installed"
	@echo "  setup       - Full setup (install + initial configuration)"
	@echo ""

# Detect OS
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Main installation target
install: install-git install-ssh install-nix
	@echo "✅ All dependencies installed successfully!"

# Install Git
install-git:
	@echo "🔧 Installing Git..."
ifeq ($(UNAME_S),Darwin)
	@if ! command -v git >/dev/null 2>&1; then \
		if command -v brew >/dev/null 2>&1; then \
			brew install git; \
		else \
			echo "❌ Homebrew not found. Please install Homebrew first or install Git manually."; \
			exit 1; \
		fi \
	else \
		echo "✅ Git is already installed"; \
	fi
else ifeq ($(UNAME_S),Linux)
	@if ! command -v git >/dev/null 2>&1; then \
		if command -v apt-get >/dev/null 2>&1; then \
			sudo apt-get update && sudo apt-get install -y git; \
		else \
			echo "❌ Unsupported package manager. Please install Git manually."; \
			exit 1; \
		fi \
	else \
		echo "✅ Git is already installed"; \
	fi
else
	@echo "❌ Unsupported operating system: $(UNAME_S)"
	@exit 1
endif

# Install SSH
install-ssh:
	@echo "🔧 Installing SSH..."
ifeq ($(UNAME_S),Darwin)
	@if ! command -v ssh >/dev/null 2>&1; then \
		echo "❌ SSH should be pre-installed on macOS. Please check your system."; \
		exit 1; \
	else \
		echo "✅ SSH is already available"; \
	fi
else ifeq ($(UNAME_S),Linux)
	@if ! command -v ssh >/dev/null 2>&1; then \
		if command -v apt-get >/dev/null 2>&1; then \
			sudo apt-get update && sudo apt-get install -y openssh-client; \
		else \
			echo "❌ Unsupported package manager. Please install SSH manually."; \
			exit 1; \
		fi \
	else \
		echo "✅ SSH is already installed"; \
	fi
endif

# Install Nix
install-nix:
	@echo "🔧 Installing Nix package manager..."
	@if ! command -v nix >/dev/null 2>&1; then \
		echo "📥 Downloading and installing Nix..."; \
		curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh; \
		echo ""; \
		echo "⚠️  Please restart your shell or run:"; \
		echo "    source ~/.nix-profile/etc/profile.d/nix.sh"; \
		echo ""; \
	else \
		echo "✅ Nix is already installed"; \
		nix --version; \
	fi

# Check if all dependencies are installed
check-deps:
	@echo "🔍 Checking dependencies..."
	@echo -n "Git: "
	@if command -v git >/dev/null 2>&1; then \
		echo "✅ $(shell git --version)"; \
	else \
		echo "❌ Not installed"; \
	fi
	@echo -n "SSH: "
	@if command -v ssh >/dev/null 2>&1; then \
		echo "✅ $(shell ssh -V 2>&1 | head -n1)"; \
	else \
		echo "❌ Not installed"; \
	fi
	@echo -n "Nix: "
	@if command -v nix >/dev/null 2>&1; then \
		echo "✅ $(shell snix --version)"; \
	else \
		echo "❌ Not installed"; \
	fi

# Full setup process
setup: install
	@echo ""
	@echo "🎉 Initial setup completed!"
	@echo ""
	@echo "Next steps:"
	@echo "1. Restart your shell or source Nix profile"
	@echo "2. Clone your dotfiles repository"
	@echo "3. Run your Nix-based configuration"
	@echo ""
	@if ! command -v nix >/dev/null 2>&1; then \
		echo "⚠️  Don't forget to source Nix:"; \
		echo "    source ~/.nix-profile/etc/profile.d/nix.sh"; \
		echo ""; \
	fi

# Clean up (if needed)
clean:
	@echo "🧹 Nothing to clean in initial setup"
