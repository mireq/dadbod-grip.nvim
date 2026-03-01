# Database UI Tools Feature Research for dadbod-grip.nvim

**Date:** 2026-02-28
**Purpose:** Identify high-impact features from CLI clients, desktop GUIs, Neovim plugins, modern SQL editors, and data grids that could differentiate dadbod-grip.nvim in the Neovim ecosystem.

---

## Executive Summary

- **Foreign key navigation** is the single highest-impact feature missing from every Neovim database plugin. DataGrip, DBeaver, Postico, and even some TUIs (gobang) offer it. Grip already has PK support, making FK drill-down a natural extension.
- **Column sorting/filtering with server-side queries** is table stakes in every desktop GUI but absent from all Neovim plugins. Grip's adapter architecture makes this feasible without a Go binary.
- **Aggregate status bar** (sum/count/avg of selected cells) -- a DataGrip signature feature -- would be a first in any terminal database tool and maps cleanly to Neovim's virtual text.
- **EXPLAIN plan visualization** in ASCII tree form would be genuinely novel in a Neovim context. No current plugin offers it.
- **Column pinning/freezing** (inspired by pspg and AG Grid) solves a real pain point with wide tables in terminal environments.

---

## 1. Terminal/CLI Database Clients

### 1.1 pgcli / mycli / litecli (dbcli family)

**Source:** [pgcli GitHub](https://github.com/dbcli/pgcli) | [pgcli commands](https://www.pgcli.com/commands) | [pgcli config](https://www.pgcli.com/config)

Standout features:
- **Context-sensitive autocomplete** -- after `SELECT * FROM `, only suggests table names; after `WHERE tbl.`, only suggests columns of that table. Uses the prompt-toolkit library and Pygments for syntax highlighting.
- **Named queries (favorites)** -- `\ns name query` saves a query, `\n name` recalls it, `\nd name` deletes. This is essentially a query snippet manager built into the CLI.
- **Multi-format output** -- 20+ table formats: `psql`, `plain`, `grid`, `fancy_grid`, `pipe`, `ascii`, `github`, `orgtbl`, `csv`, `tsv`, `json`, `vertical`, `latex`, and more. Configurable per-session or in rc file.
- **Auto-vertical output** -- `--auto-vertical-output` flag automatically switches to vertical/expanded display when result width exceeds terminal width. Also `\x auto` for intelligent per-query switching.
- **Backslash metacommands** -- full psql compatibility: `\dt` (tables), `\d+ table` (describe), `\l` (databases), `\e` (external editor), `\i` (execute file), `\!` (shell). Implemented via [pgspecial](https://github.com/dbcli/pgspecial).
- **Refresh completions** -- `\#` reloads autocomplete cache after schema changes.

**Relevance to Grip:** The named queries/favorites system is interesting -- Grip could offer saved filter presets per table. Auto-vertical output is already handled by Grip's row-view transpose (`K`).

### 1.2 pspg (PostgreSQL Pager)

**Source:** [pspg GitHub](https://github.com/okbob/pspg)

This is the most relevant CLI tool for Grip's data grid:
- **Column freezing** -- press number keys (1-9) to freeze N leftmost columns while scrolling horizontally. This is critical for wide tables where you need to keep the PK/name column visible.
- **Row/column/block selection** -- select rectangular regions and export to clipboard.
- **Searchable results** -- standard `/` search within the paged output.
- **Sort by column** -- sort the displayed data by a specific numeric column.
- **Theme support** -- multiple built-in color themes.
- **CSV/TSV viewer mode** -- can be used standalone as a CSV viewer.

**Relevance to Grip:** Column freezing is the single most impactful feature to borrow from pspg. In Neovim, this could be implemented with a split window where the frozen columns render in a narrow left pane synced to the main grid's vertical scroll.

### 1.3 lazysql

**Source:** [lazysql GitHub](https://github.com/jorgerojas26/lazysql) | [Terminal Trove](https://terminaltrove.com/lazysql/)

- **Tab-based connection management** -- multiple database connections in tabs, each with independent state.
- **Full-screen SQL editor** -- `Ctrl+e` opens editor with syntax highlighting; `Ctrl+r` runs query.
- **Vim-like keybindings** -- `j/k` navigation, modal interface.
- **CSV export** with timestamped filenames.
- **Terminal theme respect** -- inherits terminal colors.

### 1.4 sqlit

**Source:** [sqlit GitHub](https://github.com/Maxteabag/sqlit) | [HN discussion](https://news.ycombinator.com/item?id=46276002)

- **Lazygit-style UX** -- context-based keybindings always visible on screen.
- **Modal editing** -- Neovim-like normal/insert modes for query editing.
- **Multi-database** -- PostgreSQL, MySQL, SQLite, SQL Server, Turso, and 10+ more.
- **Docker integration** -- auto-discover databases in running containers.
- **Secure credential storage**.

### 1.5 usql

**Source:** [usql GitHub](https://github.com/xo/usql) | [cybertec review](https://www.cybertec-postgresql.com/en/usql-universal-psql/)

- **Universal driver** -- single binary supports PostgreSQL, MySQL, SQLite3, Oracle, SQL Server, DuckDB, and many NoSQL databases.
- **Smart path detection** -- if URL has no scheme, usql inspects the path: Unix socket -> MySQL, directory -> PostgreSQL, regular file -> SQLite3/DuckDB.
- **Cross-database copy** -- copy data between different database types.
- **Terminal graphics** -- chart/graph rendering in terminal.
- **Full psql backslash command** compatibility plus extensions.

**Relevance to Grip:** usql's smart path detection pattern is elegant. Grip's adapter resolver could adopt similar heuristics for bare file paths.

### 1.6 gobang

**Source:** [gobang GitHub](https://github.com/TaKO8Ki/gobang)

- **Tab-based schema explorer** -- separate tabs for records, columns, constraints, **foreign keys**, and indexes.
- **Foreign key tab** -- dedicated view showing FK relationships of the current table.
- Written in Rust with cross-platform support.

---

## 2. Desktop Database GUIs

### 2.1 DataGrip (JetBrains)

**Source:** [DataGrip features](https://www.jetbrains.com/datagrip/features/) | [Data editor docs](https://www.jetbrains.com/help/datagrip/data-editor-and-viewer.html) | [Completion](https://www.jetbrains.com/datagrip/features/completion.html)

DataGrip is the gold standard. Key features that are feasible in a terminal context:

**Data Editor:**
- **Aggregate view on cell selection** -- select multiple cells, get sum/count/avg/min/max/median in a side panel. One aggregate value displayed in the status bar. Custom aggregate scripts supported.
- **Server-side filtering** -- type a WHERE clause in a filter field under the toolbar. Also quick-filter from cell context menu (filter by this value).
- **Stacked sorting** -- click column header to sort; Alt+click to add secondary sort. Each sort sends a new ORDER BY query to the server.
- **Local text search** -- search/filter within the loaded result set without hitting the DB.
- **Data export** -- multiple formats: CSV, TSV, JSON, XML, SQL INSERT, SQL UPDATE, HTML, Markdown.

**Smart SQL Completion:**
- **JOIN auto-generation** -- complete a whole JOIN clause based on FK relationships.
- **INSERT column list generation** -- auto-generates column list for INSERT statements.
- **Window function awareness** -- auto-adds `OVER()` after window functions.
- **CamelCase/underscore matching** -- type initials to match `long_column_name`.
- **New object completion** -- completes names of objects created in the same DDL script.

**Query Plan:**
- **Visual EXPLAIN** -- tree or diagram view of query execution plan.
- **AI-assisted plan analysis** -- "Analyze SQL Plan with AI" button explains the plan.
- **Plan comparison** -- pin tabs to compare plans from different query runs.

**Schema Features:**
- **Schema diff** -- compare two schemas, generate migration DDL scripts.
- **Database diagrams (ERD)** -- auto-generated from schema with FK relationships drawn.
- **Refactoring** -- rename a table/column and all references update across views, procedures, and functions.

**Foreign Key Navigation:**
- **Related Rows** -- select a cell, click "Related Rows" to navigate to the FK target. Supports both directions: rows that reference this row, and rows this row references.
- **FK-aware completion** -- joins and where clauses suggest FK-connected tables.

**Relevance to Grip:**
The most transferable features (in priority order):
1. **Aggregate view** -- select cells in visual mode, show sum/count/avg in a virtual text line or status area
2. **Server-side filter** -- `f` to open a WHERE clause input, re-runs query with filter appended
3. **Sort by column** -- `s` on a column header to toggle ASC/DESC, re-runs query with ORDER BY
4. **Related Rows (FK navigation)** -- `gf` on a FK cell to open the referenced row in a new grid
5. **Export formats** -- add JSON and SQL INSERT to existing CSV export

### 2.2 DBeaver

**Source:** [DBeaver docs](https://dbeaver.com/docs/dbeaver/) | [Schema compare](https://dbeaver.com/docs/dbeaver/Schema-compare/) | [Visual Query Builder](https://dbeaver.com/docs/dbeaver/Visual-Query-Builder/)

- **Schema compare with Liquibase** -- compare two schemas, output diff as DDL script, Liquibase changelog, diff diagram, or JSON/YAML report. "Migrate" button applies changes.
- **Data compare** -- compare two tables or query results side by side, manually match columns, select key columns, ignore specific columns.
- **Visual Query Builder** -- drag tables, set conditions, customize display with filter/sort/join options. Generates SQL from the visual representation.
- **ERD diagrams** -- auto-generated from schema, editable in real-time.
- **FK navigation in data grid** -- navigate row-to-row with arrows, see related rows in a side pane, sort/edit them inline.

**Relevance to Grip:** Data compare (diff two query results) and schema compare are advanced features that could be implemented as standalone commands (`:GripDiff table1 table2`).

### 2.3 TablePlus

**Source:** [TablePlus docs](https://docs.tableplus.com/) | [Productivity tips](https://tableplus.com/blog/2018/05/11-tips-to-boost-productivity-with-tableplus.html)

TablePlus's UX philosophy is closest to what Grip aims for:
- **Inline editing with commit workflow** -- double-click to edit, changes accumulate with highlights, `Cmd+S` to commit all at once. Preview button shows the SQL. Discard button reverts. **This is exactly Grip's workflow.**
- **Batch row editing** -- select multiple rows, edit a value in the detail pane, save to all selected rows.
- **Right sidebar detail pane** -- toggle with Space key, shows full column-by-column view of selected row. **Similar to Grip's `K` row view.**
- **Code review before commit** -- preview the exact SQL that will be executed.
- **Safe mode** -- changes are highlighted (not saved) until explicit commit.

**Relevance to Grip:** TablePlus validates that Grip's core workflow (stage-preview-apply) is the right UX model. Batch editing of multiple selected rows would be a meaningful addition.

### 2.4 Beekeeper Studio

**Source:** [Beekeeper features](https://www.beekeeperstudio.io/features) | [SQL Editor docs](https://docs.beekeeperstudio.io/user_guide/sql_editor/editor/)

- **Clean tabbed interface** -- dozens of tabs without performance degradation.
- **Sensible autocomplete** -- table/column suggestions without overwhelming popup noise.
- **Saved queries with names** -- save and recall queries with a single click.
- **Multi-query execution** -- run multiple queries, see each result in a separate area.
- **Spreadsheet-like data view** -- browse and edit data in a grid.

### 2.5 Postico 2

**Source:** [Postico 2](https://eggerapps.at/postico2/) | [Documentation](https://eggerapps.at/postico2/documentation/what-is-postico.html)

- **SQL preview before commit** -- shows the exact SQL that will be executed for each edit.
- **Quick filter** -- filter table rows by keywords or complex SQL expressions.
- **Row detail sidebar** -- dedicated view for long/complex row data.
- **Foreign key navigation** -- click FK values to navigate to referenced rows.
- **Unified structure editor** -- columns, indexes, and constraints in a single editor.
- **Transaction handling** -- explicit transaction management in the UI.
- **Export formats** -- JSON, CSV, and SQL.

### 2.6 DbVisualizer

**Source:** [DbVisualizer features](https://www.dbvis.com/features/) | [Explain Plan](https://www.dbvis.com/feature/explain-plan/) | [Data compare](https://www.dbvis.com/docs/ug/comparing-data/)

- **EXPLAIN plan visualization** -- tree, graph, or text format. Color-coded nodes indicate relative cost. Zoom, detail levels, and image export.
- **Plan comparison** -- pin tabs to compare explain plans from different runs.
- **Data comparison** -- compare grids and text data, manually match columns, select key columns, ignore columns.
- **Bookmarks** -- save frequently used SQL as named bookmarks visible in a file tree.

---

## 3. Neovim/Vim Database Plugins

### 3.1 vim-dadbod (tpope)

**Source:** [vim-dadbod GitHub](https://github.com/tpope/vim-dadbod)

The foundation layer:
- Unified `:DB` command with URL-based connections.
- Supports 20+ backends (PostgreSQL, MySQL, SQLite, Redis, MongoDB, BigQuery, Snowflake, DuckDB, etc.).
- Raw query output in plain text buffers.
- **No data editing, no grid view, no structured results** -- this is by design; it's a transport layer.

### 3.2 vim-dadbod-ui (kristijanhusak)

**Source:** [vim-dadbod-ui GitHub](https://github.com/kristijanhusak/vim-dadbod-ui)

- Sidebar tree browser for databases, schemas, tables.
- Saved queries per connection.
- Custom table helpers (user-defined queries per table).
- Bind parameters in queries.
- FK jumping (basic: jump to referenced table, not specific row).
- Nerd font icons.
- Async query execution (via fork branch).
- **Limitations:** No data editing. Results are raw text in `.dbout` buffers. No structured grid. No change staging.

### 3.3 vim-dadbod-completion (kristijanhusak)

**Source:** [vim-dadbod-completion GitHub](https://github.com/kristijanhusak/vim-dadbod-completion)

- Table name autocompletion with automatic quoting.
- Column autocompletion with **alias awareness** (e.g., `SELECT * FROM users u WHERE u.` completes with users columns).
- Works with deoplete, nvim-cmp, blink.cmp, ddc, omnifunc.
- Supports PostgreSQL, MySQL, Oracle, SQLite, SQL Server.

### 3.4 nvim-dbee (kndndrj)

**Source:** [nvim-dbee GitHub](https://github.com/kndndrj/nvim-dbee) | [DeepWiki](https://deepwiki.com/kndndrj/nvim-dbee)

- **Go backend** -- doesn't rely on CLI tools. Direct database drivers.
- **Auto-pagination** -- results automatically split across pages with lazy loading.
- **Visual mode query execution** -- highlight SQL and press BB to run.
- **Connection management** -- multi-connection with persistence.
- **Extensible API** -- core + UI separation for programmatic access.
- **cmp-dbee** -- completion source plugin available.
- **Status:** Alpha software with expected breaking changes.
- **No data editing** -- read-only results only.

### 3.5 sqlua.nvim (Xemptuous)

**Source:** [sqlua.nvim GitHub](https://github.com/Xemptuous/sqlua.nvim)

- **Full SQL IDE** -- aims to be NeoVim's complete SQL IDE.
- Queries folder per connection stored in `~/.local/share/nvim/sqlua/`.
- Configurable keybinds for query execution (default: `<leader>r`).
- Inspired by dadbod/dadbod-ui but written entirely in Lua.
- Aims to eliminate "long load times and multiple vim extensions."

### 3.6 dbout.nvim (zongben)

**Source:** [dbout.nvim GitHub](https://github.com/zongben/dbout.nvim)

- JSON-formatted results (not tabular).
- Secure local credential storage.
- LSP support via sqls language server.
- Commands: OpenConnection, NewConnection, DeleteConnection, EditConnection, AttachConnection.

### 3.7 dadbod-explorer.nvim (tkopets)

**Source:** [dadbod-explorer.nvim GitHub](https://github.com/tkopets/dadbod-explorer.nvim)

- **Actions-based exploration** -- describe objects, sample records, filter, view value distributions.
- **Fuzzy finder integration** -- fzf-lua or telescope-ui-select for picker UI.
- Leverages vim-dadbod for connections.

### 3.8 Ecosystem Gap Analysis

| Feature | dadbod-grip | dadbod-ui | nvim-dbee | sqlua | lazysql |
|---------|-------------|-----------|-----------|-------|---------|
| Cell editing | YES | No | No | No | Yes |
| Change staging | YES | No | No | No | No |
| SQL preview | YES | No | No | No | No |
| FK navigation | No | Basic | No | No | No |
| Sort by column | No | No | No | No | No |
| Filter rows | No | No | No | No | No |
| Aggregate view | No | No | No | No | No |
| EXPLAIN visual | No | No | No | No | No |
| Column freeze | No | No | No | No | No |
| Batch edit | No | No | No | No | No |
| Data diff | No | No | No | No | No |
| Schema browser | No | YES | YES | YES | No |
| Saved queries | No | YES | No | YES | No |
| Auto-pagination | No | No | YES | No | No |

**Every "No" in the Grip column above represents an opportunity.** The features in bold below represent those where Grip would be the **first Neovim plugin** to offer them.

---

## 4. Modern SQL Editor Features

### 4.1 Monaco-based SQL Editors (Supabase, Retool)

**Source:** [Supabase SQL Editor](https://supabase.com/features/sql-editor) | [Supabase Studio 3.0](https://supabase.com/blog/supabase-studio-3-0)

- **Schema-aware autocomplete** -- Monaco with custom providers for tables, columns, functions.
- **AI-assisted SQL** -- natural language to SQL conversion, query optimization suggestions.
- **Execution history** -- searchable log of all previously executed queries.
- **Schema Visualizer** -- interactive ERD diagram.
- **Error detection** -- real-time syntax error highlighting before execution.

### 4.2 Query Plan Visualization Tools

**Source:** [pgMustard blog](https://www.pgmustard.com/blog/postgres-query-plan-visualization-tools) | [explain.dalibo.com](https://explain.dalibo.com/) | [PEV2](https://github.com/dalibo/pev2)

Available approaches for terminal/Neovim:
- **explain.depesz.com** -- paste plan text, get color-coded output with time calculations.
- **explain.dalibo.com / PEV2** -- tree visualization with node highlighting.
- **pt-visual-explain (Percona)** -- ASCII text representation of MySQL plans.

**Terminal-feasible approach for Grip:**
Run `EXPLAIN (FORMAT JSON)` or `EXPLAIN (FORMAT TEXT)`, parse the output, render as an indented tree with:
- Node type and cost on each line
- Color coding: green (low cost) -> yellow -> red (high cost)
- Actual vs estimated row counts when ANALYZE is used
- Total execution time at the root

This could render beautifully in a Neovim buffer with extmarks for colors.

### 4.3 Result Set Diffing

**Source:** [DBeaver data compare](https://dbeaver.com/docs/dbeaver/Data-compare/) | [KS DB Merge Tools](https://ksdbmerge.tools/docs/for-sqlite/tabs-query-result-diff.html)

- Compare two query results side by side.
- Match columns manually or automatically.
- Highlight added/removed/changed rows.
- Generate sync SQL (INSERT/UPDATE/DELETE to make one match the other).

**Terminal-feasible approach for Grip:**
`:GripDiff` command that opens two grids in a vertical split, with diff highlighting (green for additions, red for deletions, yellow for changes). This would use Grip's existing rendering engine twice.

### 4.4 Data Generators

**Source:** [Mockaroo](https://www.mockaroo.com) | [Faker Forge](https://www.productcool.com/product/faker-forge-ai-mock-data-generator)

- Generate realistic fake data matching column types.
- Respect FK constraints and referential integrity.
- Output as SQL INSERT statements.

**Terminal-feasible approach for Grip:** When inserting rows, offer type-aware defaults/suggestions:
- Integer PK: auto-increment suggestion
- VARCHAR: empty string
- TIMESTAMP: current timestamp
- BOOLEAN: false
- UUID: auto-generate
- Email columns (by name heuristic): `user@example.com`

---

## 5. Data Grid Innovations

### 5.1 AG Grid Features

**Source:** [AG Grid Column Pinning](https://www.ag-grid.com/javascript-data-grid/column-pinning/) | [Infinite Scrolling](https://www.ag-grid.com/javascript-data-grid/infinite-scrolling/)

Key features applicable to terminal grids:
- **Column pinning** -- pin columns to left or right edge; they stay visible during horizontal scroll.
- **Infinite scroll** -- lazy-load rows as user scrolls down (server-side model).
- **Row grouping** -- collapse rows by a column value (not compatible with infinite scroll).
- **Row pinning** -- pin specific rows to top/bottom of grid.

### 5.2 Handsontable Features

**Source:** [Handsontable docs](https://handsontable.com/docs/javascript-data-grid/) | [Conditional formatting](https://handsontable.com/docs/javascript-data-grid/conditional-formatting/)

- **Conditional formatting** -- set font, color, typeface based on cell values (e.g., negative numbers in red).
- **Row/column operations** -- sorting, filtering, grouping, freezing, moving, hiding.
- **Custom renderers** -- any cell can have a custom render function.
- **Formula support** -- Excel-compatible formula parser (SUM, AVERAGE, etc.).
- **Validation rules** -- per-cell validation with error indicators.

### 5.3 pspg (Terminal Table Pager)

**Source:** [pspg GitHub](https://github.com/okbob/pspg)

Already covered above, but worth re-emphasizing for grid innovations:
- **Freeze columns with number keys** -- press 1-9 to freeze N columns.
- **Block selection** -- select rectangular regions (not just rows).
- **Clipboard export of selection**.
- **Built-in sort** by numeric column.

### 5.4 Terminal-Feasible Grid Features (Priority Ranking)

| Feature | Complexity | Impact | Notes |
|---------|-----------|--------|-------|
| Column sort (server-side) | Low | High | Re-run query with ORDER BY |
| Row filter (WHERE clause) | Low | High | Append WHERE to base query |
| Column freeze/pin | Medium | High | Split window + synced scroll |
| Pagination (OFFSET/LIMIT) | Low | High | Already have LIMIT; add page nav |
| Aggregate on selection | Medium | High | Sum/count/avg in status line |
| Local text search | Low | Medium | `/` to search within buffer |
| Conditional formatting | Medium | Medium | Color based on NULL, type, value range |
| Column resize | Medium | Medium | Adjust max_col_width per column |
| Column hide | Low | Medium | Toggle visibility of specific columns |
| Row numbers | Low | Low | Optional line number column |

---

## 6. Highest-Impact Features No Neovim Plugin Currently Offers

Based on the research across all categories, these are the features that would most differentiate dadbod-grip.nvim. Each is feasible in a terminal/Neovim context and none exist in any current Neovim database plugin.

### Tier 1: High Impact, Moderate Complexity

**1. Foreign Key Navigation (`gf`)**
- When cursor is on a cell that is a FK, press `gf` to open a new Grip grid showing the referenced row.
- Query the FK metadata from `information_schema.key_column_usage` (PG) or `PRAGMA foreign_key_list` (SQLite).
- Build a `SELECT * FROM referenced_table WHERE pk = cell_value` and open it.
- Breadcrumb trail in status line showing navigation path (e.g., `orders > users > addresses`).
- `<C-o>` to go back in the navigation stack.
- **No Neovim plugin does this.** DataGrip, DBeaver, Postico, TablePlus all do.

**2. Server-Side Sort (`s` / `S`)**
- Press `s` on a column header to sort ASC; press again for DESC; press again to remove sort.
- Multiple columns: `S` to add secondary sort (stacked sorting a la DataGrip).
- Re-runs the base query with `ORDER BY col ASC/DESC` appended.
- Visual indicator in column header (arrow up/down).

**3. Server-Side Filter (`f`)**
- Press `f` to open a filter input (float or cmdline).
- Type a WHERE clause fragment (e.g., `age > 25 AND name LIKE 'J%'`).
- Appends to the base query and re-runs.
- Filter indicator in status bar showing active filter.
- `F` to clear filter and return to unfiltered view.
- Quick filter: `ff` on a cell to filter by "column = this value".

**4. Pagination with Page Navigation**
- Display current page info: "Page 1 of 12 (rows 1-100 of 1,187)".
- `]p` / `[p` for next/previous page.
- `gp` to jump to a specific page number.
- Uses OFFSET/LIMIT queries.

### Tier 2: High Impact, Lower Complexity

**5. Aggregate Status Line**
- Select cells in visual mode (or visual block).
- Show in a virtual text line or floating window: count, sum, average, min, max.
- Like DataGrip's aggregate view, but displayed as a status line update.
- No other terminal DB tool does this.

**6. EXPLAIN Plan Viewer**
- `:GripExplain` on any query to run EXPLAIN ANALYZE.
- Render as indented tree in a new buffer with extmark coloring.
- Color code by relative cost (green/yellow/red).
- Show actual vs estimated rows, execution time per node.
- For PostgreSQL: parse `EXPLAIN (FORMAT JSON)` output.
- For SQLite: parse `EXPLAIN QUERY PLAN` output.

**7. Column Pinning/Freezing**
- Press `1`-`9` (like pspg) to freeze N leftmost columns.
- Implementation: render frozen columns in a narrow left split, sync vertical scrolling via autocmds.
- The frozen pane is narrow and non-scrollable horizontally; the main pane scrolls.

**8. Multiple Export Formats**
- Extend current CSV export with: JSON, SQL INSERT, SQL UPDATE, Markdown table, TSV.
- `gE` to open export format picker (using `vim.ui.select`).

### Tier 3: Differentiation Features

**9. Data Diff Between Tables/Queries**
- `:GripDiff query1 query2` -- opens two grids side by side with diff highlighting.
- Match rows by PK or specified columns.
- Highlight added (green), removed (red), and changed (yellow) cells.
- Generate sync SQL to make one match the other.

**10. Query Snippets / Saved Filters**
- Save frequently used filters/queries per table.
- `:GripSave name` to save current filter+sort state.
- `:GripLoad name` to restore.
- Stored in a JSON file per connection/database.

**11. Conditional Cell Formatting**
- NULL cells already styled differently.
- Add: negative numbers in red, dates in the past in dim, boolean true/false with color, long text truncated with ellipsis indicator.
- Type-aware formatting based on column metadata from `get_column_info`.

**12. Inline Column Statistics**
- Press `gs` on a column to see: count, distinct count, NULL count, min, max, avg (for numeric), most common values (top 5).
- Run a single aggregate query and display in a float.
- Uses `SELECT COUNT(*), COUNT(DISTINCT col), COUNT(*) FILTER (WHERE col IS NULL), MIN(col), MAX(col) FROM table`.

**13. Transaction Wrapper**
- Wrap all staged changes in `BEGIN ... COMMIT` with a `ROLLBACK` on any error.
- Show transaction status in status bar.
- Optional manual transaction mode: `BEGIN` when first change is staged, user explicitly commits or rolls back.

**14. Batch Edit (Visual Block)**
- Select a column of cells in visual block mode.
- Type a value to set all selected cells to that value.
- Or: `e` to edit, and the value applies to all selected cells.

---

## 7. Implementation Priority Recommendation

Given Grip's current architecture (adapter system, immutable state, pure SQL generation), here is a recommended implementation order:

### Phase 1: Table Navigation (v1.3.0 items -- already planned)

These align with the existing TODO.md roadmap:
1. **Sort by column** -- low complexity, high value
2. **Filter rows** -- low complexity, high value
3. **Pagination** -- low complexity, high value
4. **Search within grid** -- low complexity, medium value

### Phase 2: FK & Data Intelligence (new -- proposed v1.4.0)

5. **Foreign key navigation** -- medium complexity, highest differentiator
6. **Aggregate status line** -- medium complexity, unique in ecosystem
7. **Inline column statistics** -- low complexity, useful
8. **Additional export formats** (JSON, SQL INSERT) -- low complexity

### Phase 3: Advanced Visualization (proposed v2.0.0)

9. **Column pinning/freezing** -- medium complexity, solves real pain
10. **EXPLAIN plan viewer** -- medium complexity, unique feature
11. **Conditional cell formatting** -- medium complexity
12. **Transaction wrapper** -- medium complexity

### Phase 4: Power Features (proposed v2.1.0+)

13. **Data diff** -- high complexity, niche but powerful
14. **Batch edit** -- medium complexity
15. **Saved filters/snippets** -- low complexity
16. **Query builder** (interactive WHERE clause construction) -- high complexity

---

## 8. References

### Terminal/CLI Clients
- [pgcli GitHub](https://github.com/dbcli/pgcli)
- [pgcli Commands](https://www.pgcli.com/commands)
- [pgcli Configuration](https://www.pgcli.com/config)
- [pspg GitHub](https://github.com/okbob/pspg)
- [lazysql GitHub](https://github.com/jorgerojas26/lazysql)
- [sqlit GitHub](https://github.com/Maxteabag/sqlit)
- [usql GitHub](https://github.com/xo/usql)
- [gobang GitHub](https://github.com/TaKO8Ki/gobang)
- [dbcli GitHub org](https://github.com/dbcli)

### Desktop GUIs
- [DataGrip Features](https://www.jetbrains.com/datagrip/features/)
- [DataGrip Data Editor](https://www.jetbrains.com/datagrip/features/data_editor.html)
- [DataGrip Completion](https://www.jetbrains.com/datagrip/features/completion.html)
- [DataGrip EXPLAIN Plan](https://www.jetbrains.com/help/datagrip/query-execution-plan.html)
- [DataGrip Aggregate View](https://www.jetbrains.com/help/datagrip/explore-data-in-data-editor.html)
- [DBeaver Schema Compare](https://dbeaver.com/docs/dbeaver/Schema-compare/)
- [DBeaver Data Compare](https://dbeaver.com/docs/ug/comparing-data/)
- [DBeaver Visual Query Builder](https://dbeaver.com/docs/dbeaver/Visual-Query-Builder/)
- [TablePlus Documentation](https://docs.tableplus.com/)
- [Beekeeper Studio Features](https://www.beekeeperstudio.io/features)
- [Postico 2](https://eggerapps.at/postico2/)
- [DbVisualizer Features](https://www.dbvis.com/features/)
- [DbVisualizer Explain Plan](https://www.dbvis.com/feature/explain-plan/)

### Neovim Plugins
- [vim-dadbod GitHub](https://github.com/tpope/vim-dadbod)
- [vim-dadbod-ui GitHub](https://github.com/kristijanhusak/vim-dadbod-ui)
- [vim-dadbod-completion GitHub](https://github.com/kristijanhusak/vim-dadbod-completion)
- [nvim-dbee GitHub](https://github.com/kndndrj/nvim-dbee)
- [sqlua.nvim GitHub](https://github.com/Xemptuous/sqlua.nvim)
- [dbout.nvim GitHub](https://github.com/zongben/dbout.nvim)
- [dadbod-explorer.nvim GitHub](https://github.com/tkopets/dadbod-explorer.nvim)

### SQL Editors & Visualization
- [Supabase SQL Editor](https://supabase.com/features/sql-editor)
- [explain.dalibo.com](https://explain.dalibo.com/)
- [PEV2 GitHub](https://github.com/dalibo/pev2)
- [explain.depesz.com](https://explain.depesz.com/)
- [pgMustard Plan Visualization Tools](https://www.pgmustard.com/blog/postgres-query-plan-visualization-tools)
- [dbtree](http://vivekn.dev/dbtree/)
- [erd (BurntSushi)](https://github.com/BurntSushi/erd)

### Data Grids
- [AG Grid Column Pinning](https://www.ag-grid.com/javascript-data-grid/column-pinning/)
- [AG Grid Infinite Scroll](https://www.ag-grid.com/javascript-data-grid/infinite-scrolling/)
- [Handsontable](https://handsontable.com/)
- [Handsontable Conditional Formatting](https://handsontable.com/docs/javascript-data-grid/conditional-formatting/)
- [Ratatui (Rust TUI)](https://ratatui.rs/)
- [tview (Go TUI)](https://github.com/rivo/tview)

### Data Tools
- [Mockaroo](https://www.mockaroo.com)
- [DBeaver + Liquibase Integration](https://www.liquibase.com/blog/using-dbeaver-liquibase-to-easily-compare-databases-in-your-ci-cd-flow)
