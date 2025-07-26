# Phase 1: Foundation Recovery

## Overview
Establish the core modular diff architecture that all other features depend on. This phase converts the monolithic `unified_diff.lua` into a modular system.

## Priority: CRITICAL ⭐
**Start here first** - All other phases depend on this foundation.

## Recovery Confidence: 95-100%
Excellent data quality with exact Edit tool calls and complete file contents available.

## Goals
- [ ] Create modular diff architecture
- [ ] Establish core parsing and rendering modules  
- [ ] Maintain backward compatibility
- [ ] Fix critical WebSocket shutdown issues
- [ ] Implement basic temporary file management

## Files to Recover

### New Files to Create
```
/lua/claudecode/diff/parser.lua      - Diff parsing logic (NEW)
/lua/claudecode/diff/renderer.lua    - Rendering and highlighting (NEW)
```

### Files to Modify
```
/lua/claudecode/diff/modes.lua       - Enhanced with modular integration
/lua/claudecode/unified_diff.lua     - Refactored as backwards-compatible wrapper
/lua/claudecode/server/init.lua      - Fixed shutdown timing
/lua/claudecode/server/client.lua    - Added immediate closure
/lua/claudecode/server/tcp.lua       - Changed WebSocket close codes
/lua/claudecode/lockfile.lua         - Removed cleanup on exit
/lua/claudecode/logger.lua           - Changed to append mode
```

## Recovery Steps

### Step 1: Extract Core Parser Module
**Data Source**: Look for `parser.lua` in conversation logs

**Recovery Command**:
```bash
# Find parser.lua creation in logs
grep -r "parser\.lua" /Users/admin/.claude/projects/-Users-admin--local-share-nvim-lazy-claudecode-nvim/ | head -10
```

**Expected Features**:
- Diff line parsing logic
- Header detection 
- Hunk processing
- Line type classification (+, -, unchanged)

### Step 2: Extract Renderer Module  
**Data Source**: Look for `renderer.lua` in conversation logs

**Expected Features**:
- Syntax highlighting application
- Buffer creation and management
- Line rendering logic
- Integration with diff statistics

### Step 3: Fix WebSocket Shutdown Issues
**Problem**: MCP error -32000 "Connection closed" crashes

**Files to Update**:
- `server/init.lua` - Increase disconnect delay 50ms → 150ms
- `server/client.lua` - Add `close_client_immediate()` function  
- `server/tcp.lua` - Change close codes from 1001 → 1000 (Normal Closure)

**Data Source**: Search logs for "MCP error -32000" and shutdown fixes

### Step 4: Implement Lockfile Persistence
**Change**: Remove lockfile cleanup on exit so Claude CLI can reconnect

**File**: `/lua/claudecode/lockfile.lua`
**Modification**: Comment out or remove lockfile deletion in cleanup functions

### Step 5: Update Logger to Append Mode
**File**: `/lua/claudecode/logger.lua`  
**Change**: Switch from truncating to appending log entries

## Data Extraction Examples

### Finding Parser Module
```bash
# Search for parser.lua Write tool calls
grep -A 50 '"file_path".*parser\.lua' /Users/admin/.claude/projects/*/*.jsonl

# Search for Edit tool calls modifying parsing logic
grep -B 5 -A 20 '"old_string".*parse' /Users/admin/.claude/projects/*/*.jsonl
```

### Finding Renderer Module  
```bash
# Search for renderer.lua creation
grep -A 100 '"file_path".*renderer\.lua' /Users/admin/.claude/projects/*/*.jsonl
```

### Finding WebSocket Fixes
```bash
# Search for server shutdown improvements
grep -B 5 -A 15 "disconnect.*delay\|close.*1000\|immediate" /Users/admin/.claude/projects/*/*.jsonl
```

## Specific Conversation Log References

### Primary Implementation File
**File**: `/Users/admin/.claude/projects/-Users-admin--local-share-nvim-lazy-claudecode-nvim/6f456589-b06e-4c60-9df9-ffdb4c41bf4b.jsonl`

This file contains the most comprehensive implementation details:

1. **parser.lua implementation**
   - Lines: 597-598
   - Contains: Complete parser module with `parse_unified_diff`, `generate_unified_diff`, and `count_diff_changes` functions

2. **renderer.lua implementation**
   - Lines: 594-595  
   - Contains: Complete renderer module with `apply_unified_diff_highlighting`, `setup_unified_diff_folding`, and cleanup functions

3. **WebSocket shutdown fixes**
   - Lines: 599-602
   - Referenced commits:
     - `2ced5e0` - TCP server shutdown handling
     - `f6ce720` - Immediate WebSocket client closure
     - `11e7535` - Graceful shutdown with immediate mode

4. **Lockfile persistence**
   - Line: 601
   - Commit: `41fa612` - Remove lockfile cleanup on exit

### Quick Extraction Commands
```bash
# Extract parser.lua implementation
sed -n '597,598p' /Users/admin/.claude/projects/-Users-admin--local-share-nvim-lazy-claudecode-nvim/6f456589-b06e-4c60-9df9-ffdb4c41bf4b.jsonl

# Extract renderer.lua implementation  
sed -n '594,595p' /Users/admin/.claude/projects/-Users-admin--local-share-nvim-lazy-claudecode-nvim/6f456589-b06e-4c60-9df9-ffdb4c41bf4b.jsonl

# Extract WebSocket fixes
sed -n '599,602p' /Users/admin/.claude/projects/-Users-admin--local-share-nvim-lazy-claudecode-nvim/6f456589-b06e-4c60-9df9-ffdb4c41bf4b.jsonl
```

## Validation Steps

### After Each File Recovery
```bash
# Check Lua syntax
luacheck lua/claudecode/diff/parser.lua
luacheck lua/claudecode/diff/renderer.lua

# Test basic functionality
nvim -c "lua require('claudecode').setup()" -c "quit"
```

### Phase 1 Complete Validation
```bash
# Run full test suite
make test

# Check for syntax errors
make check

# Test diff functionality manually
nvim test_file.lua
# :ClaudeCodeDiff (should work without errors)
```

## Common Issues & Solutions

### Issue: Module Not Found Errors
**Solution**: Ensure new modules are properly required in parent files
```lua
local parser = require('claudecode.diff.parser')
local renderer = require('claudecode.diff.renderer')
```

### Issue: WebSocket Still Crashing
**Solution**: Verify all three server files are updated:
- Check disconnect delays increased
- Confirm close codes changed to 1000
- Ensure immediate closure function exists

### Issue: Backward Compatibility Broken
**Solution**: Keep `unified_diff.lua` as wrapper that calls new modules

## Success Criteria
- [ ] `parser.lua` and `renderer.lua` created successfully
- [ ] WebSocket shutdown crashes eliminated  
- [ ] `make test` passes basic tests
- [ ] No Lua syntax errors in new modules
- [ ] Existing functionality preserved (backward compatibility)
- [ ] Lockfile persists between Neovim sessions

## Next Phase
Once Phase 1 validation passes → **[Phase 2: Enhanced UI](./RECOVERY_PHASE_2.md)**

## Emergency Recovery Notes
If data extraction fails:
1. Check conversation logs from July 22 sessions (major refactoring day)
2. Look for "Phase 2 refactoring" and "Phase 3 refactoring" sessions
3. Files may be split across multiple conversation files
4. Use exact timestamps: `20250722_*` sessions contain core changes