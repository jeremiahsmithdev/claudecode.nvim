# Phase 3: Advanced Features Recovery

## Overview
Implement advanced features including 3-second highlighting, fold-aware navigation, multi-provider terminal integration, and MCP blocking operations.

## Prerequisites
✅ **Phase 1 & 2 must be completed** - Requires modular diff architecture and UI foundation

## Recovery Confidence: 85-90%
Good data quality with comprehensive feature implementation logs and terminal integration details.

## Goals
- [ ] Implement 3-second changed line highlighting after diff acceptance
- [ ] Add fold-aware navigation and cursor positioning
- [ ] Integrate multi-provider terminal support (native, snacks, tmux, external)
- [ ] Implement MCP blocking diff operations
- [ ] Add file change following with buffer reloading
- [ ] Enhance tmux integration with auto-navigation

## Files to Recover

### Files to Modify
```
/lua/claudecode/diff/blocking.lua       - 3-second highlight sequencing  
/lua/claudecode/diff/renderer.lua       - Track changed lines during rendering
/lua/claudecode/commands.lua            - Tmux auto-navigation after send
/lua/claudecode/follow_file_changes.lua - Fold-aware cursor positioning
/lua/claudecode/terminal/               - Multi-provider terminal integration
```

### Expected New Terminal Files
```
/lua/claudecode/terminal/native.lua     - Built-in Neovim terminal
/lua/claudecode/terminal/snacks.lua     - Snacks.nvim integration  
/lua/claudecode/terminal/tmux.lua       - Tmux external terminal
/lua/claudecode/terminal/external.lua   - Generic external terminal
```

## Recovery Steps

### Step 1: Implement 3-Second Changed Line Highlighting
**Feature**: After accepting diffs, changed lines highlight for 3 seconds in navigated view

**Implementation Flow**:
1. `renderer.lua` tracks + lines in `changed_lines` array during diff rendering
2. Pass `changed_lines` through diff data flow  
3. `blocking.lua` applies highlighting to saved file in navigated view
4. Highlighting auto-clears after 3 seconds

**Target Files**:
- `/lua/claudecode/diff/renderer.lua` - Track changed lines
- `/lua/claudecode/diff/blocking.lua` - Apply highlighting sequence

**Expected Code Pattern**:
```lua
-- In renderer.lua - track changed lines
local changed_lines = {}
for line_num, line_data in pairs(plus_lines) do
    table.insert(changed_lines, line_num)
end

-- In blocking.lua - apply 3-second highlighting
local function highlight_changed_lines(bufnr, lines)
    -- Apply highlighting
    -- Set timer to clear after 3 seconds
    vim.defer_fn(function()
        -- Clear highlighting
    end, 3000)
end
```

### Step 2: Add Fold-Aware Navigation
**Feature**: Cursor positioning that respects fold states and navigates correctly

**Target File**: `/lua/claudecode/follow_file_changes.lua`

**Implementation Details**:
- Detect fold states before navigation
- Adjust cursor positioning calculations
- Handle folded regions gracefully
- Maintain proper view positioning

### Step 3: Multi-Provider Terminal Integration
**Feature**: Support for multiple terminal providers with consistent interface

**Expected Structure**:
```lua
-- Each terminal provider implements:
-- - setup() - initialization
-- - send(content) - send content to terminal
-- - is_available() - check if provider available
-- - get_display_name() - human readable name
```

**Providers to Implement**:
- **Native**: Built-in Neovim terminal (`vim.fn.termopen`)
- **Snacks**: Snacks.nvim terminal integration
- **Tmux**: External tmux session management  
- **External**: Generic external terminal via CLI

### Step 4: Enhance Tmux Integration
**Feature**: Auto-navigate to tmux pane after successful ClaudeSend

**Target File**: `/lua/claudecode/commands.lua`

**Expected Enhancement**:
```lua
-- After successful tmux send
if provider == 'tmux' and send_success then
    -- Automatically switch to tmux pane
    vim.fn.system('tmux select-pane -t ' .. pane_id)
end
```

### Step 5: Implement MCP Blocking Operations
**Feature**: Ensure diff operations complete before MCP returns response

**Target File**: `/lua/claudecode/diff/blocking.lua`

**Implementation**: Synchronous waits and proper async handling for MCP compliance

## Data Extraction Commands

### Finding 3-Second Highlighting
```bash
# Search for highlighting implementation
grep -B 5 -A 15 "3.*second\|highlight.*changed\|defer_fn.*3000" /Users/admin/.claude/projects/*/*.jsonl

# Look for changed_lines tracking
grep -A 10 "changed_lines\|plus_lines" /Users/admin/.claude/projects/*/*.jsonl
```

### Finding Terminal Integration
```bash
# Search for terminal provider implementations
grep -r "terminal\|tmux\|snacks" /Users/admin/.claude/feedback-loop/claudecodenvim/ | grep -v Binary

# Look for multi-provider pattern
grep -B 5 -A 15 "provider.*terminal\|terminal.*provider" /Users/admin/.claude/projects/*/*.jsonl
```

### Finding Fold-Aware Navigation  
```bash
# Search for fold-related code
grep -B 5 -A 10 "fold\|foldlevel\|fold.*aware" /Users/admin/.claude/projects/*/*.jsonl
```

### Finding Tmux Auto-Navigation
```bash
# Search for tmux enhancements
grep -B 5 -A 10 "tmux.*pane\|select-pane\|auto.*navigate" /Users/admin/.claude/projects/*/*.jsonl
```

## Expected Session Sources
- `20250725_*` sessions - 3-second highlighting implementation
- `20250724_*` sessions - Tmux integration enhancements  
- `20250722_*` sessions - Fold-aware navigation and blocking operations
- Look for commits with "highlight", "tmux", "fold-aware"

## Specific Conversation Log References

### Primary Implementation File
**File**: `/Users/admin/.claude/projects/-Users-admin--local-share-nvim-lazy-claudecode-nvim/6f456589-b06e-4c60-9df9-ffdb4c41bf4b.jsonl`

This file contains comprehensive advanced feature implementations:

1. **3-Second Highlighting Implementation**
   - Lines: 125-376
   - Contains: Complete `follow_file_changes.lua` with `highlight_changed_lines_from_diff` function
   - Key feature: 3000ms timeout using `vim.defer_fn`

2. **Changed Lines Data Flow**
   - Line: 589 (blocking.lua) - Adding `changed_lines` to diff state
   - Line: 592 (navigation.lua) - Passing `changed_lines` through navigation
   - Line: 586 (modes.lua) - Storing `changed_lines` in diff_info

3. **Fold-Aware Navigation**
   - Line: 592 (navigation.lua)
   - Contains: `navigate_to_first_change` function with fold handling

4. **Complete Implementation Flow**
   - Diff Creation: renderer.lua tracks + lines in `changed_lines` array
   - Storage: modes.lua stores `changed_lines` in diff_info
   - Registration: blocking.lua registers changed_lines in diff state
   - Navigation: navigation.lua passes changed_lines to follow_file_changes
   - Highlighting: follow_file_changes.lua uses stored lines for 3-second highlighting

### Quick Extraction Commands
```bash
# Extract follow_file_changes.lua with 3-second highlighting
sed -n '125,376p' /Users/admin/.claude/projects/-Users-admin--local-share-nvim-lazy-claudecode-nvim/6f456589-b06e-4c60-9df9-ffdb4c41bf4b.jsonl

# Extract blocking.lua changes
sed -n '589p' /Users/admin/.claude/projects/-Users-admin--local-share-nvim-lazy-claudecode-nvim/6f456589-b06e-4c60-9df9-ffdb4c41bf4b.jsonl

# Extract navigation.lua changes
sed -n '592p' /Users/admin/.claude/projects/-Users-admin--local-share-nvim-lazy-claudecode-nvim/6f456589-b06e-4c60-9df9-ffdb4c41bf4b.jsonl
```

### Terminal Integration References
While the main log file focuses on diff features, terminal integration implementations may be found in separate session files. Search the feedback-loop directory for more details on multi-provider terminal support.

## Validation Steps

### Feature-Specific Testing

#### 3-Second Highlighting Test
```bash
# Manual test procedure:
nvim test_file.lua
# Make a diff, accept it
# Verify changed lines highlight for ~3 seconds
# Confirm highlighting auto-clears
```

#### Terminal Integration Test
```bash
# Test each provider
nvim -c "lua require('claudecode.terminal.native').setup()" -c "quit"
nvim -c "lua require('claudecode.terminal.tmux').setup()" -c "quit"
# etc. for each provider
```

#### Fold-Aware Navigation Test
```bash
# Create file with folds
nvim test_with_folds.lua
# Create some folds: zf
# Test navigation with :ClaudeCodeDiff
# Verify cursor positioning respects folds
```

### Integration Testing
```bash
# Run full test suite
make test

# Test MCP integration
# (Requires Claude CLI connection)
```

## Common Issues & Solutions

### Issue: 3-Second Highlighting Not Working
**Solutions**:
- Check `changed_lines` array is populated correctly
- Verify `vim.defer_fn` is called with proper delay
- Ensure highlighting namespace is unique
- Check buffer is valid when highlighting applied

### Issue: Terminal Provider Not Found
**Solutions**:
- Verify provider availability check works
- Check module paths are correct
- Ensure proper fallback to next available provider
- Test provider setup functions individually

### Issue: Fold Navigation Breaks
**Solutions**:
- Check fold state detection before navigation
- Verify cursor position calculations with folds
- Test with different fold levels
- Ensure `foldopen` events are handled

### Issue: Tmux Auto-Navigation Fails
**Solutions**:
- Verify tmux session/pane exists
- Check `tmux select-pane` command syntax
- Test tmux provider detection
- Ensure proper error handling if tmux unavailable

## Success Criteria
- [ ] 3-second highlighting works after diff acceptance
- [ ] All terminal providers function correctly
- [ ] Fold-aware navigation positions cursor properly
- [ ] Tmux auto-navigation works after ClaudeSend
- [ ] MCP blocking operations prevent race conditions
- [ ] File change following reloads buffers correctly
- [ ] No regressions in basic diff functionality
- [ ] `make test` passes with all new features

## Performance Considerations
- 3-second highlighting should not impact large files
- Terminal provider detection should be cached
- Fold calculations should be efficient
- Tmux commands should not block Neovim UI

## Integration Notes
- All terminal providers should have consistent interface
- 3-second highlighting should work with all diff modes
- Fold-aware navigation should integrate with existing navigation
- Features should gracefully degrade if dependencies unavailable

## Next Phase
Once Phase 3 validation passes → **[Phase 4: Testing & Validation](./RECOVERY_PHASE_4.md)**

## Emergency Recovery Notes
- 3-second highlighting uses `vim.defer_fn(callback, 3000)`
- Terminal providers follow factory pattern with consistent interface
- Fold detection uses `vim.fn.foldlevel()` and related fold functions
- Tmux commands: `tmux select-pane -t <pane_id>`
- MCP blocking uses synchronous waits in appropriate places