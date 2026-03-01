# dadbod-grip.nvim — Roadmap

## v1.0.0 — Done

- [x] DataGrip-style editable data grids with box-drawing UI
- [x] Inline cell editing via float editor (e, CR to save, Esc cancel)
- [x] Visual change staging (modified=blue, deleted=red, inserted=green)
- [x] Live SQL preview (gs=preview, gc=copy, gl=live toggle)
- [x] Immutable state management (deep_copy on every transition)
- [x] PostgreSQL support (psql CLI)
- [x] DBUI integration (smart context detection from query/dbout buffers)
- [x] Composite primary key support
- [x] Read-only auto-detection (views, no-PK tables)
- [x] Row view transpose (K), column type annotations (T)
- [x] CSV export (y=cell, Y=row, gY=table)
- [x] Cell explain (ge), table info (gi)
- [x] Paste (p), undo (u/U), insert (o), delete (d), apply (a)
- [x] Full navigation: j/k/h/l/w/b/Tab/S-Tab/gg/G/0/^/$/{/}
- [x] NULL handling with sentinel values
- [x] Help popup (?) with ASCII art

## v1.1.0 — Multi-Database (in progress)

- [x] Adapter system (db.lua facade + adapters/ registry)
- [x] SQLite adapter (sqlite3 CLI, PRAGMA metadata, changes())
- [x] RFC 4180 CSV parser (multiline quoted fields)
- [x] Multiline cell display (↵ indicator)
- [x] SQLite test fixtures (seed_sqlite.sql — mirrors PG seed)
- [ ] DuckDB adapter (duckdb CLI, information_schema, parquet/csv queries)
  - [ ] File-as-table querying: `:Grip /path/to/data.parquet` (CSV, JSON, Parquet, Excel via DuckDB)
- [ ] MySQL/MariaDB adapter (mysql CLI, information_schema)

## v1.2.0 — Sort, Filter, Paginate

Low complexity, high impact. Every desktop GUI has these; no Neovim plugin does.

- [ ] Sort by column — `s` toggles ASC/DESC/off, re-runs query with ORDER BY
- [ ] Stacked sort — `S` adds secondary sort column
- [ ] Filter rows — `f` opens WHERE clause input, appends to base query
- [ ] Quick filter — `ff` on a cell to filter by "column = this value"
- [ ] Clear filter — `F` removes filter and refreshes
- [ ] Pagination — `]p`/`[p` next/prev page, status line shows "Page 1 of N"
- [ ] Search within grid — `/` to search loaded buffer text locally

## v1.3.0 — Foreign Key Navigation & Data Intelligence

The single biggest gap in the Neovim database ecosystem. DataGrip, DBeaver, Postico, TablePlus all have FK navigation.

- [ ] FK navigation — `gf` on a FK cell opens referenced row in new grid
- [ ] FK metadata query per adapter (information_schema / PRAGMA foreign_key_list)
- [ ] Navigation stack with `<C-o>` to go back, breadcrumb in status line
- [ ] Aggregate on selection — visual select cells, show count/sum/avg/min/max
- [ ] Column statistics — `gS` on a column for count, distinct, nulls, min/max, top values (validated by MotherDuck's Column Explorer)
- [ ] Additional export formats — JSON, SQL INSERT, Markdown table (gE picker)

## v1.4.0 — Grid Enhancements

- [ ] Column pinning/freezing — number keys (1-9) to freeze N leftmost columns (pspg-style)
- [ ] Column resize / auto-fit
- [ ] Column hide/show toggle
- [ ] Conditional cell formatting — negatives red, booleans colored, dates dimmed if past
- [ ] Batch edit — visual block select, set all selected cells to same value
- [ ] Copy/paste between cells
- [ ] Undo history (multi-level, not just per-row)

## v2.0.0 — Advanced Features

- [ ] EXPLAIN plan viewer — `:GripExplain` renders query plan as color-coded tree
- [ ] Data diff — `:GripDiff` opens two grids side-by-side with diff highlighting
- [ ] Transaction wrapper — BEGIN/COMMIT/ROLLBACK around staged changes
- [ ] Telescope/fzf picker for tables and columns
- [ ] Schema browser (tree view of tables/views/indexes)
- [ ] Saved filters/queries per table (`:GripSave`/`:GripLoad`)
- [ ] Connection profiles (project-level saved connections)

## Future — Schema Operations (DDL)

- [ ] Table properties view (columns, types, constraints, defaults)
- [ ] Column rename (ALTER TABLE ... RENAME COLUMN)
- [ ] Column add/drop with type/nullable/default
- [ ] Edit column properties — adapter-aware DDL generation
- [ ] Create/drop table with confirmation

## Ongoing

- [ ] Automated tests and CI (GitHub Actions)
- [ ] Performance profiling on large tables (1000+ rows)
- [ ] Documentation (vimdoc help file)
