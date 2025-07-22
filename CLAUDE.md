# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Commands

### Development Workflow
- `make` - Run formatting, linting, and testing (complete validation)
- `make test` - Run all tests using busted with coverage
- `busted tests/unit/specific_spec.lua` - Run specific test file
- `busted --coverage -v` - Run tests with coverage report

### Code Quality
- `make check` - Check Lua syntax and run luacheck
- `make format` - Format code with stylua (or nix fmt)
- `luacheck lua/ tests/ --no-unused-args --no-max-line-length` - Manual linting

### Development Shell
- `nix develop` - Enter development shell with lint/format/test dependencies
- `make clean` - Remove generated test files

## Architecture Overview

### Core Architecture
This is a pure Lua Neovim plugin that implements the WebSocket-based MCP protocol for Claude Code integration. Zero external dependencies - uses only Neovim built-ins.

### Key Components
**WebSocket Server Stack** - RFC 6455 compliant implementation:
- `/lua/claudecode/server/` - Core WebSocket implementation
- `tcp.lua` - TCP server and port binding
- `handshake.lua` - HTTP upgrade handshakes with authentication
- `frame.lua` - WebSocket frame processing (RFC 6455)
- `client.lua` - Individual connection management

**MCP Tool System** - Tool registration and execution:
- `/lua/claudecode/tools/` - Individual tool implementations
- `open_file.lua` - File opening/selection
- `get_current_selection.lua` - Text selection tracking
- `get_diagnostics.lua` - LSP diagnostic access
- `save_document.lua` - File save operations
- Unified diff operations via native Neovim diff views

**Terminal Integration** - Multi-provider terminal support:
- `native.lua` - Built-in Neovim terminal
- `snacks.lua` - Snacks.nvim terminal provider
- `tmux.lua` - Tmux external terminal
- `external.lua` - Generic external terminal via CLI

### Authentication & Discovery
- **Lock File System**: Creates `~/.claude/ide/[port].lock` with connection details
- **UUID Token Auth**: Generates session tokens for WebSocket authentication
- **Environment Variables**: Sets `CLAUDE_WEBSOCKET_PORT` and `CLAUDE_WEBSOCKET_SECRET`

### Testing Architecture
Three test layers using busted framework:
- **Unit tests** (`tests/unit/`) - Isolated function testing
- **Component tests** - Subsystem validation
- **Integration tests** (`tests/integration/`) - End-to-end MCP workflows
- **Mocks**: Complete vim environment simulation for dependency-free testing

### MCP Protocol Flow
1. `:ClaudeCodeStart` starts WebSocket server on random port
2. Lock file created at `~/.claude/ide/[port].lock`
3. Claude CLI connects via environment variables
4. Real-time selection tracking via `selection.lua`
5. Tools execute in controlled Neovim environment