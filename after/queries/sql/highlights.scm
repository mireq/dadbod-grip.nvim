; extends
;
; dadbod-grip SQL highlight overrides.
;
; Two semantic improvements over nvim-treesitter's built-in SQL highlights:
;
;   1. Clause keywords -> @keyword.operator  (FROM, WHERE, JOIN, GROUP BY, ...)
;      Built-in maps ALL keywords to @keyword. DML verbs (SELECT, INSERT, UPDATE)
;      and structural clause keywords are semantically distinct. Clause keywords
;      already share the register with AND/OR/NOT/IN which are @keyword.operator.
;
;   2. Aggregate/window functions -> @function.builtin  (avg, count, sum, ...)
;      Built-in maps ALL invocations to @function.call. Well-known aggregate and
;      window functions are builtins, not user-defined calls.
;
; `after/queries/` guarantees this file loads after all `queries/` directories,
; so these patterns reliably extend nvim-treesitter's base queries.
; (#set! priority 105) on the invocation pattern provides explicit priority as a
; safety net for future nvim-treesitter versions that may change loading order.

; ── Clause keywords -> @tag ───────────────────────────────────────────────────
;
; Structural keywords that connect query parts: FROM table, JOIN table ON ...,
; GROUP BY col, ORDER BY col, RETURNING col, OVER (PARTITION BY ...), etc.
; Distinct from DML action verbs (SELECT, INSERT, UPDATE, DELETE) which remain @keyword.
;
; @tag (blue) is used instead of @keyword.operator because Catppuccin Mocha (and
; other popular themes) alias @keyword, @keyword.return, and @keyword.operator to
; the same color. @tag is a structurally analogous group (declarative structural
; delimiters, like HTML tags) that themes keep visually distinct.

[
  (keyword_from)
  (keyword_where)
  (keyword_join)
  (keyword_left)
  (keyword_right)
  (keyword_outer)
  (keyword_inner)
  (keyword_full)
  (keyword_cross)
  (keyword_lateral)
  (keyword_natural)
  (keyword_using)
  (keyword_having)
  (keyword_limit)
  (keyword_offset)
  (keyword_returning)
  (keyword_over)
  (keyword_partition)
  (keyword_window)
  (keyword_filter)
  (keyword_order)
  (keyword_group)
  (keyword_as)
] @tag

; ── Aggregate and window functions -> @function.builtin ──────────────────────
;
; Override @function.call for well-known SQL aggregate and window functions.
; Lowercase only: modern SQL style writes avg() not AVG().

((invocation
  (object_reference
    name: (identifier) @function.builtin))
  (#any-of? @function.builtin
    "avg" "count" "sum" "min" "max"
    "coalesce" "nullif"
    "date_trunc" "date_part" "extract"
    "row_number" "rank" "dense_rank" "cume_dist" "percent_rank"
    "lag" "lead" "first_value" "last_value" "nth_value" "ntile"
    "string_agg" "array_agg" "json_agg" "jsonb_agg"
    "upper" "lower" "trim" "ltrim" "rtrim" "length" "substr" "substring"
    "round" "ceil" "floor" "abs"
    "now" "current_timestamp" "current_date" "gen_random_uuid")
  (#set! priority 105))
