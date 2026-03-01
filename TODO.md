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
- [ ] MySQL/MariaDB adapter (mysql CLI, information_schema)

## v1.2.0 — Edit Mode Improvements

- [ ] Consistent shortcut scheme across all edit operations
- [ ] Bulk edit (visual select multiple cells)
- [ ] Copy/paste between cells
- [ ] Undo history (multi-level, not just per-row)
- [ ] SQL template generation from table context (INSERT/SELECT/UPDATE/DELETE)

## v1.3.0 — Table Navigation

- [ ] Column resize / auto-fit
- [ ] Sort by column (toggle asc/desc)
- [ ] Filter rows (WHERE clause builder)
- [ ] Pagination for large tables (next/prev page)
- [ ] Jump to row by PK value
- [ ] Search within grid (/ to filter visible rows)

## v2.0.0 — Advanced Features

- [ ] Foreign key navigation (follow FK to related table)
- [ ] Telescope/fzf picker for tables and columns
- [ ] Schema browser (tree view of tables/views/indexes)
- [ ] Transaction support (BEGIN/COMMIT/ROLLBACK wrapper)
- [ ] Diff view (compare staged changes side-by-side)
- [ ] Connection profiles (project-level saved connections)

## Future — Schema Operations (DDL)

- [ ] Table properties view (columns, types, constraints, defaults)
- [ ] Column rename (ALTER TABLE ... RENAME COLUMN)
- [ ] Column add (ALTER TABLE ... ADD COLUMN with type/nullable/default)
- [ ] Column drop (ALTER TABLE ... DROP COLUMN with confirmation)
- [ ] Edit column properties (type, nullable, default) — adapter-aware DDL
- [ ] Create table wizard (interactive column definition)
- [ ] Drop table with confirmation

## Ongoing

- [ ] Automated tests and CI (GitHub Actions)
- [ ] Performance profiling on large tables (1000+ rows)
- [ ] Documentation (vimdoc help file)
- [ ] Update README comparison table for multi-DB support
