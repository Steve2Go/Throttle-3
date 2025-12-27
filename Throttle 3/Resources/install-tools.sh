#!/bin/bash
set -e

# Throttle 3 - Install dufs and ffmpeg
# This script detects the OS and architecture, then downloads
# dufs and ffmpeg binaries to ~/.throttle3/bin/

INSTALL_DIR="$HOME/.throttle3/bin"
TEMP_DIR="/tmp/throttle3-install-$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to download a file
download_file() {
    local url="$1"
    local output="$2"
    
    echo_info "Downloading from $url"
    
    if command -v curl &>/dev/null; then
        curl -L -f -S --retry 3 -o "$output" "$url"
    elif command -v wget &>/dev/null; then
        wget -O "$output" "$url"
    else
        echo_error "Neither curl nor wget is available"
        return 1
    fi
}

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)     echo "linux";;
        Darwin*)    echo "macos";;
        *)          echo "unknown";;
    esac
}

# Detect architecture
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)   echo "x86_64";;
        aarch64|arm64)  echo "aarch64";;
        armv7l)         echo "armv7";;
        armv6l)         echo "armv6";;
        *)              echo "$arch";;
    esac
}

# Create directories
setup_directories() {
    echo_info "Creating installation directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$TEMP_DIR"
}

# Install dufs
install_dufs() {
    local os=$1
    local arch=$2
    
    echo_info "Installing dufs for $os-$arch..."
    
    # Map to dufs release naming (e.g., x86_64-unknown-linux-musl, aarch64-apple-darwin)
    local dufs_target=""
    
    case "$os-$arch" in
        linux-x86_64)
            dufs_target="x86_64-unknown-linux-musl"
            ;;
        linux-aarch64)
            dufs_target="aarch64-unknown-linux-musl"
            ;;
        linux-armv7)
            dufs_target="armv7-unknown-linux-musleabihf"
            ;;
        linux-armv6)
            dufs_target="arm-unknown-linux-musleabihf"
            ;;
        macos-x86_64)
            dufs_target="x86_64-apple-darwin"
            ;;
        macos-aarch64)
            dufs_target="aarch64-apple-darwin"
            ;;
        *)
            echo_error "Unsupported OS/architecture combination for dufs: $os-$arch"
            return 1
            ;;
    esac
    
    # Use exact URLs from GitHub releases
    local download_url=""
    local dufs_filename=""
    
    case "$dufs_target" in
        x86_64-unknown-linux-musl)
            download_url="https://github.com/sigoden/dufs/releases/download/v0.45.0/dufs-v0.45.0-x86_64-unknown-linux-musl.tar.gz"
            dufs_filename="dufs-v0.45.0-x86_64-unknown-linux-musl.tar.gz"
            ;;
        aarch64-apple-darwin)
            download_url="https://github.com/sigoden/dufs/releases/download/v0.45.0/dufs-v0.45.0-aarch64-apple-darwin.tar.gz"
            dufs_filename="dufs-v0.45.0-aarch64-apple-darwin.tar.gz"
            ;;
        aarch64-unknown-linux-musl)
            download_url="https://github.com/sigoden/dufs/releases/download/v0.45.0/dufs-v0.45.0-aarch64-unknown-linux-musl.tar.gz"
            dufs_filename="dufs-v0.45.0-aarch64-unknown-linux-musl.tar.gz"
            ;;
        armv7-unknown-linux-musleabihf)
            download_url="https://github.com/sigoden/dufs/releases/download/v0.45.0/dufs-v0.45.0-armv7-unknown-linux-musleabihf.tar.gz"
            dufs_filename="dufs-v0.45.0-armv7-unknown-linux-musleabihf.tar.gz"
            ;;
        arm-unknown-linux-musleabihf)
            download_url="https://github.com/sigoden/dufs/releases/download/v0.45.0/dufs-v0.45.0-arm-unknown-linux-musleabihf.tar.gz"
            dufs_filename="dufs-v0.45.0-arm-unknown-linux-musleabihf.tar.gz"
            ;;
        x86_64-apple-darwin)
            download_url="https://github.com/sigoden/dufs/releases/download/v0.45.0/dufs-v0.45.0-x86_64-apple-darwin.tar.gz"
            dufs_filename="dufs-v0.45.0-x86_64-apple-darwin.tar.gz"
            ;;
        *)
            echo_error "No URL mapped for target: $dufs_target"
            return 1
            ;;
    esac
    
    echo_info "Using URL: $download_url"
    
    cd "$TEMP_DIR"
    
    # Download the file
    if download_file "$download_url" "$dufs_filename"; then
        # Verify we got a real file
        if [ ! -s "$dufs_filename" ]; then
            echo_error "Downloaded file is empty"
            return 1
        fi
        
        local filesize=$(stat -f%z "$dufs_filename" 2>/dev/null || stat -c%s "$dufs_filename" 2>/dev/null)
        echo_info "Downloaded $filesize bytes"
        
        echo_info "Extracting dufs..."
        tar -xzf "$dufs_filename"
        
        # Find the dufs binary and move it
        if [ -f "dufs" ]; then
            mv dufs "$INSTALL_DIR/dufs"
            chmod +x "$INSTALL_DIR/dufs"
            echo_info "dufs installed successfully to $INSTALL_DIR/dufs"
        else
            echo_error "dufs binary not found in archive"
            return 1
        fi
    else
        echo_error "Failed to download dufs"
        return 1
    fi
}

# Install ffmpeg
install_ffmpeg() {
    local os=$1
    local arch=$2
    
    echo_info "Installing ffmpeg for $os-$arch..."
    
    cd "$TEMP_DIR"
    
    if [ "$os" = "linux" ]; then
        # Use John Van Sickle's static builds for Linux
        local ffmpeg_arch=""
        case "$arch" in
            x86_64)
                ffmpeg_arch="amd64"
                ;;
            aarch64)
                ffmpeg_arch="arm64"
                ;;
            armv7)
                ffmpeg_arch="armhf"
                ;;
            armv6)
                ffmpeg_arch="armel"
                ;;
        esac
        
        if [ -z "$ffmpeg_arch" ]; then
            echo_error "Unsupported architecture for ffmpeg: $arch"
            return 1
        fi
        
        echo_info "Downloading ffmpeg static build for Linux $ffmpeg_arch..."
        local download_url="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-${ffmpeg_arch}-static.tar.xz"
        
        if download_file "$download_url" "ffmpeg.tar.xz"; then
            # Verify download
            if [ ! -s "ffmpeg.tar.xz" ]; then
                echo_error "Downloaded ffmpeg file is empty"
                return 1
            fi
            
            echo_info "Extracting ffmpeg..."
            tar -xJf ffmpeg.tar.xz
            
            # Find the ffmpeg binary (it's in a versioned directory)
            local ffmpeg_dir=$(find . -type d -name "ffmpeg-*-${ffmpeg_arch}-static" | head -n 1)
            if [ -n "$ffmpeg_dir" ] && [ -f "$ffmpeg_dir/ffmpeg" ]; then
                mv "$ffmpeg_dir/ffmpeg" "$INSTALL_DIR/ffmpeg"
                mv "$ffmpeg_dir/ffprobe" "$INSTALL_DIR/ffprobe" 2>/dev/null || true
                chmod +x "$INSTALL_DIR/ffmpeg"
                [ -f "$INSTALL_DIR/ffprobe" ] && chmod +x "$INSTALL_DIR/ffprobe"
                echo_info "ffmpeg installed successfully to $INSTALL_DIR/ffmpeg"
            else
                echo_error "ffmpeg binary not found in archive"
                return 1
            fi
        else
            echo_error "Failed to download ffmpeg"
            return 1
        fi
        
    elif [ "$os" = "macos" ]; then
        # Use evermeet.cx static builds for macOS
        echo_info "Downloading ffmpeg static build for macOS..."
        
        # evermeet.cx provides universal binaries - use zip format for easier extraction
        if download_file "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip" "ffmpeg.zip"; then
            # Verify download
            if [ ! -s "ffmpeg.zip" ]; then
                echo_error "Downloaded ffmpeg file is empty"
                return 1
            fi
            
            echo_info "Extracting ffmpeg..."
            unzip -q ffmpeg.zip
            
            if [ -f "ffmpeg" ]; then
                mv ffmpeg "$INSTALL_DIR/ffmpeg"
                chmod +x "$INSTALL_DIR/ffmpeg"
                echo_info "ffmpeg installed successfully to $INSTALL_DIR/ffmpeg"
            else
                echo_error "ffmpeg binary not found in archive"
                return 1
            fi
        else
            echo_error "Failed to download ffmpeg"
            return 1
        fi
        
        # Also get ffprobe
        echo_info "Downloading ffprobe..."
        if download_file "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip" "ffprobe.zip"; then
            if [ -s "ffprobe.zip" ]; then
                unzip -q ffprobe.zip
                if [ -f "ffprobe" ]; then
                    mv ffprobe "$INSTALL_DIR/ffprobe"
                    chmod +x "$INSTALL_DIR/ffprobe"
                    echo_info "ffprobe installed successfully"
                fi
            fi
        fi
    fi
}

# Cleanup
cleanup() {
    echo_info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Main installation
main() {
    echo_info "Throttle 3 - Tools Installation Script"
    echo_info "========================================"
    
    local os=$(detect_os)
    local arch=$(detect_arch)
    
    echo_info "Detected OS: $os"
    echo_info "Detected Architecture: $arch"
    
    if [ "$os" = "unknown" ]; then
        echo_error "Unsupported operating system"
        exit 1
    fi
    
    setup_directories
    
    # Install tools
    install_dufs "$os" "$arch"
    install_ffmpeg "$os" "$arch"
    
    cleanup
    
    echo_info ""
    echo_info "========================================"
    echo_info "Installation complete!"
    echo_info "Binaries installed to: $INSTALL_DIR"
    echo_info ""
    echo_info "Installed tools:"
    [ -f "$INSTALL_DIR/dufs" ] && echo_info "  - dufs: $INSTALL_DIR/dufs"
    [ -f "$INSTALL_DIR/ffmpeg" ] && echo_info "  - ffmpeg: $INSTALL_DIR/ffmpeg"
    [ -f "$INSTALL_DIR/ffprobe" ] && echo_info "  - ffprobe: $INSTALL_DIR/ffprobe"
    echo_info "========================================"
}

# Run main function
main
