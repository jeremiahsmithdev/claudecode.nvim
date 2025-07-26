# Phase 2: Enhanced UI Recovery

## Overview
Implement GitHub-style UI enhancements including branded winbar, absolute line numbering, and enhanced diff views.

## Prerequisites
✅ **Phase 1 must be completed first** - Requires modular diff architecture

## Recovery Confidence: 90-95%
Good data quality with detailed UI implementation logs and exact color specifications.

## Goals
- [ ] Implement GitHub-style winbar with Claude branding
- [ ] Add absolute line numbering to diff views
- [ ] Create Claude-themed highlight groups
- [ ] Fix post-diff navigation with winbar offset
- [ ] Enhance diff statistics display

## Files to Recover

### Files to Modify
```
/lua/claudecode/diff/renderer.lua     - Add winbar and line numbering
/lua/claudecode/follow_file_changes.lua - Fix cursor positioning
/lua/claudecode/diff/modes.lua        - Enhanced diff display
```

### Files to Create/Enhance
```
highlight_groups.lua (or integrate into existing files) - Claude theme colors
```

## Recovery Steps

### Step 1: Implement GitHub-Style Winbar
**Feature**: Branded winbar with Claude orange star (✻) and proper styling

**Target Files**: `/lua/claudecode/diff/renderer.lua`

**Expected Implementation**:
```lua
-- Claude highlight groups
vim.api.nvim_set_hl(0, 'ClaudeOrange', { fg = '#FF6B35', bold = true })
vim.api.nvim_set_hl(0, 'ClaudeBrand', { fg = '#E5E7EB' })
vim.api.nvim_set_hl(0, 'ClaudeWinbarBg', { bg = '#1F2937' })

-- Winbar content with Claude branding
local winbar_content = '%#ClaudeOrange#✻%#ClaudeBrand# Claude Code Diff%#Normal#'
vim.wo[winid].winbar = winbar_content
```

**Data Source**:
```bash
# Search for winbar implementation
grep -B 5 -A 15 "winbar\|ClaudeOrange\|✻" /Users/admin/.claude/projects/*/*.jsonl
```

### Step 2: Add Absolute Line Numbering
**Feature**: Show absolute line numbers in diff views instead of relative

**Implementation Details**:
- Calculate proper line numbers for + and - lines
- Display in diff buffers with correct alignment
- Maintain synchronization with original file

**Data Source**:
```bash
# Find absolute line numbering logic
grep -B 10 -A 20 "absolute.*line\|line.*number" /Users/admin/.claude/projects/*/*.jsonl
```

### Step 3: Fix Post-Diff Navigation
**Problem**: With winbars added, cursor navigation was off by 1 row
**Solution**: Add winbar detection and offset adjustment

**Target File**: `/lua/claudecode/follow_file_changes.lua`

**Expected Fix**:
```lua
-- Detect if winbar is present and adjust cursor position
local winbar_offset = vim.wo[winid].winbar and 1 or 0
-- Apply offset to cursor positioning calculations
```

**Data Source**:
```bash
# Find navigation offset fixes
grep -B 5 -A 10 "winbar.*offset\|cursor.*position\|off by 1" /Users/admin/.claude/projects/*/*.jsonl
```

### Step 4: Create Claude Theme Highlight Groups
**Colors to Implement**:
- `ClaudeOrange`: #FF6B35 (bold) - Brand orange for accents
- `ClaudeBrand`: #E5E7EB - Light gray for text  
- `ClaudeWinbarBg`: #1F2937 - Dark background

**Integration**: Add to diff renderer or create separate theme file

### Step 5: Enhanced Diff Statistics
**Feature**: Improved display of diff statistics in UI
- File change counts
- Line addition/deletion stats
- Better visual formatting

## Data Extraction Commands

### Finding UI Enhancement Code
```bash
# Search for winbar implementations
grep -r "winbar" /Users/admin/.claude/feedback-loop/claudecodenvim/ | grep -v Binary

# Search for highlight group definitions  
grep -A 5 -B 5 "nvim_set_hl\|ClaudeOrange\|#FF6B35" /Users/admin/.claude/projects/*/*.jsonl

# Find line numbering changes
grep -A 10 "line.*number\|absolute" /Users/admin/.claude/projects/*/*.jsonl
```

### Finding Navigation Fix
```bash
# Search for cursor positioning fixes
grep -B 10 -A 10 "follow_file_changes\|cursor.*position" /Users/admin/.claude/projects/*/*.jsonl
```

## Expected Session Sources
- `20250722_*` sessions - Major UI implementation  
- `20250724_*` sessions - Navigation fixes and enhancements
- Look for commits mentioning "winbar" and "absolute line numbering"

## Specific Conversation Log References

### Primary Implementation File
**File**: `/Users/admin/.claude/projects/-Users-admin--local-share-nvim-lazy-claudecode-nvim/6f456589-b06e-4c60-9df9-ffdb4c41bf4b.jsonl`

This file contains comprehensive UI implementation details:

1. **Winbar and Claude Highlight Groups**
   - Lines: 586-595
   - Contains: modes.lua changes with complete highlight group definitions:
     ```lua
     vim.api.nvim_set_hl(0, "ClaudeOrange", { fg = "#FF6B35", bold = true })
     vim.api.nvim_set_hl(0, "ClaudeBrand", { fg = "#E5E7EB", bold = true })
     vim.api.nvim_set_hl(0, "ClaudeSubtle", { fg = "#6B7280" })
     vim.api.nvim_set_hl(0, "ClaudeWinbarBg", { bg = "#1F2937" })
     ```

2. **Absolute Line Numbering Implementation**
   - Line: 586 (modes.lua)
   - Contains: Implementation in `create_unified_diff_view` function

3. **Navigation Offset Fixes**
   - Lines: 125-376
   - Contains: Complete `follow_file_changes.lua` with dynamic winbar/fold detection and adjusted positioning

4. **Additional UI Features**
   - ClaudeSubtle highlight group for secondary UI elements
   - Integration with diff statistics display

### Quick Extraction Commands
```bash
# Extract modes.lua UI changes
sed -n '586,595p' /Users/admin/.claude/projects/-Users-admin--local-share-nvim-lazy-claudecode-nvim/6f456589-b06e-4c60-9df9-ffdb4c41bf4b.jsonl

# Extract follow_file_changes.lua navigation fixes
sed -n '125,376p' /Users/admin/.claude/projects/-Users-admin--local-share-nvim-lazy-claudecode-nvim/6f456589-b06e-4c60-9df9-ffdb4c41bf4b.jsonl
```

## Validation Steps

### Visual Validation
```bash
# Start Neovim and test diff view
nvim test_file.lua
# :ClaudeCodeDiff
# Check for:
# - Winbar with Claude orange star (✻)
# - Proper line numbering  
# - Correct cursor positioning after diff navigation
```

### Code Validation
```bash
# Test highlight groups are defined
nvim -c "echo synIDattr(hlID('ClaudeOrange'), 'fg')" -c "quit"
# Should output: #FF6B35

# Check for winbar presence
nvim -c "lua print(vim.wo.winbar)" -c "quit"
```

### Integration Testing
```bash
# Run tests to ensure UI doesn't break functionality
make test

# Check syntax
make check
```

## Common Issues & Solutions

### Issue: Winbar Not Displaying
**Solution**: Ensure winbar is set in correct buffer context
```lua
-- Set winbar for specific window, not globally
vim.wo[winid].winbar = winbar_content
```

### Issue: Colors Not Appearing
**Solution**: Verify highlight groups are set before use
```lua
-- Check if highlight group exists
if vim.fn.hlexists('ClaudeOrange') == 0 then
    vim.api.nvim_set_hl(0, 'ClaudeOrange', { fg = '#FF6B35', bold = true })
end
```

### Issue: Line Numbers Misaligned
**Solution**: Account for different line number widths
```lua
-- Calculate proper padding for line numbers
local max_line = math.max(old_line_num, new_line_num)
local width = string.len(tostring(max_line))
```

### Issue: Navigation Still Off After Winbar Fix
**Solution**: Check all cursor positioning code paths
- Direct cursor jumps  
- Relative movements
- Search result navigation

## Success Criteria
- [ ] Winbar displays with Claude orange star (✻) and proper branding
- [ ] Diff views show absolute line numbers correctly
- [ ] Claude highlight groups defined and working
- [ ] Post-diff navigation positions cursor correctly  
- [ ] Enhanced diff statistics display properly
- [ ] No visual glitches or alignment issues
- [ ] `make test` passes with UI changes

## Performance Considerations
- Winbar updates should not cause visual flickering
- Line number calculations should be efficient for large files
- Highlight group creation should happen once, not repeatedly

## Next Phase  
Once Phase 2 validation passes → **[Phase 3: Advanced Features](./RECOVERY_PHASE_3.md)**

## Emergency Recovery Notes
- UI changes are primarily in `renderer.lua` and `follow_file_changes.lua`
- Look for exact color hex codes: #FF6B35, #E5E7EB, #1F2937
- Winbar content format: `'%#ClaudeOrange#✻%#ClaudeBrand# Claude Code Diff%#Normal#'`
- Cursor offset fix involves detecting `vim.wo[winid].winbar` presence